;//////////////////////////////////////////////////////////////////////////////
;//
;//     ATTRIB - Change attributes of file
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<filename>,<op><attr>[,<op><attr>[,<op><attr>[...]]]
;//
;//                 Tn          Drive type and number, default :F0:
;//                 op          Attribute operation
;//                 attr        Attribute type
;//
;//                 Drive type T:
;//                     F       Floppy
;//
;//                 Drive number n:
;//                     0-3
;//
;//                 Operation op:
;//                     +       Add attribute
;//                     -       Remove attribute
;//
;//                 Attribute attr:
;//
;//                     I       Invisible
;//                     S       System
;//                     W       Write-protect
;//
;//
;//         Adds and/or removes attributes from a file, either on floppy disk or on
;//         tape. The Invisible attribute will hide a file from a regular directory
;//         listing, the Write-protect attribute prevents a file to be written to,
;//         while the System attribute will ensure the file is copied over if a new
;//         disk is initialized as a system disk.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Writes file-entry back once for each attribute-bit changed
;//                 -> Has a bug where the file-extension deliminer is printed even
;//                    if the file has no extension
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
TRK         EQU     02731H      ; Pointer to block address of next directory data block

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
FILENAME    EQU     0FDCDH      ; Input TOS filename

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS file attributes
;
ATTR_I      EQU     001H        ; Invisible file
ATTR_S      EQU     002H        ; System file
ATTR_W      EQU     004H        ; Write-protected file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

file_entry_ptr:
        DW          00000H

        DW          00000H

filename_drive_nr:
        DB          0
filename_str:
        DS          9
attribute_operation:
        DB          000H
file_entry_attribute_byte_ptr:
        DB          000H

not_found_str:
        DB          'NOT FOUND',CR
attributes_altered_str:
        DB          'ATTRIBUTES ALTERED',CR
improper_unit_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
improper_params_str:
        DB          'IMPROPER PARAMETER LIST',CR
unknown_attribute_str:
        DB          'ATTRIBUTE UNKNOWN',CR

drive_designator_str:
        DB          ':F*:',CR

        DS          128


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert character to uppercase
        ;
to_uppercase:
        CPI         'a'
        RM
        CPI         'z'+1
        RP
        ANI         0DFH
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Set default drive number
        ;
        SUB         A
        STA         filename_drive_nr
        ;
        ; Ignore leading spaces
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          beginning
        ;
        ; Parse potential drive designator
        ;
        CPI         CR
        RZ
        CPI         ':'
        JNZ         done_selecting_drive
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'F'
        JNZ         invalid_device
        CALL        INCHAR
        RC
        CPI         '0'
        JM          invalid_device
        CPI         '4'
        JP          invalid_device
        SUI         '0'
        STA         filename_drive_nr
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_device
        CALL        INCHAR
        RC
done_selecting_drive:
        ;
        ; Get filename, print it, and look it up
        ;
        LXI         D,filename_str
        CALL        FILENAME
        RC
        CPI         ','
        JNZ         invalid_parameters
        CALL        print_full_file_ref
        RC
        LXI         H,filename_str
        LDA         filename_drive_nr
        CALL        LOCDIR
        RC
        MOV         A,M
        CPI         000H
        JNZ         file_not_found
        ;
        ; Store pointers to file entry and its attribute byte
        ;
        SHLD        file_entry_ptr
        LXI         D,00AH
        DAD         D
        SHLD        file_entry_attribute_byte_ptr
        ;
        ; Parse attribute changes from command line arguments
        ;
parse_next_attribute_change:
        ;
        ; Verify attribute operation
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         '+'
        JZ          valid_attribute_operation
        CPI         '-'
        JNZ         invalid_parameters
valid_attribute_operation:
        STA         attribute_operation
        ;
        ; Verify attribute name, and select appropriate bitmask
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        MVI         B,ATTR_I
        CPI         'I'
        JZ          valid_attribute
        MVI         B,ATTR_S
        CPI         'S'
        JZ          valid_attribute
        MVI         B,ATTR_W
        CPI         'W'
        JNZ         invalid_attribute
valid_attribute:
        ;
        ; Check if we are adding or removing an attribute
        ;
        LDA         attribute_operation
        CPI         '+'
        JZ          add_attribute
        ;
        ; Remove attribute
        ;
        MOV         A,B
        XRI         0FFH
        LHLD        file_entry_attribute_byte_ptr
        ANA         M
        MOV         M,A
        JMP         attribute_changed

add_attribute:
        ;
        ; Add attribute
        ;
        LHLD        file_entry_attribute_byte_ptr
        MOV         A,B
        ORA         M
        MOV         M,A
attribute_changed:
        ;
        ; Write changes back to disk
        ;
        LHLD        TRK
        DCX         H
        MOV         B,M
        DCX         H
        MOV         C,M
        LXI         H,BUF2
        LDA         filename_drive_nr
        CALL        DSWRW
        RC
        ;
        ; Check if there are more attribute changes pending
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ','
        JZ          parse_next_attribute_change
        CPI         CR
        JNZ         invalid_parameters
        ;
        ; Print final status and exit
        ;
        LXI         D,attributes_altered_str
        JMP         print_string_and_quit


;//////////////////////////////////////

file_not_found:
        LXI         D,not_found_str

print_string_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

invalid_device:
        LXI         D,improper_unit_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

invalid_parameters:
        LXI         D,improper_params_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

invalid_attribute:
        LXI         D,unknown_attribute_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

        ;
        ; Print full filename
        ;
print_full_file_ref:
        ;
        ; Print file designator
        ;
        LHLD        CO_FCB
        LDA         filename_drive_nr
        ADI         '0'
        STA         drive_designator_str+2
        LXI         D,drive_designator_str
        CALL        PUTSTR
        ;
        ; print first part of filename
        ;
        LXI         D,filename_str
        MVI         B,6
print_file_name:
        LDAX        D
        CPI         NULL
        JZ          dont_pad_filename_tail
        CALL        OUTCHAR
        RC
dont_pad_filename_tail:
        INX         D
        DCR         B
        JNZ         print_file_name
        ;
        ; Print dot before extension
        ;
        MVI         A,'.'
        CALL        OUTCHAR
        RC
        ;
        ; Print file extension
        ;
        MVI         B,3
print_file_ext:
        LDAX        D
        CPI         NULL
        JNZ         print_next_file_ext_char
        MVI         A,' '
print_next_file_ext_char:
        CALL        OUTCHAR
        RC
        INX         D
        DCR         B
        JNZ         print_file_ext
        ;
        ; Add a space after full filename
        ;
        MVI         A,' '
        CALL        OUTCHAR
        RET
