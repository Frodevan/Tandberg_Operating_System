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
;//                     M       Tape
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
;//         NOTE: Tape operation uses the XMON API for some operations, and this
;//               API may not be present in all machines. The write itself on tape
;//               is done directly using low-level IO-calls, but as mentioned not
;//               the reading and tape-drive setup.
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
;//             1.5: Entry at 0xC000
;//
;//                 -> No longer allows adding the system attribute to aliases
;//                 -> Support for files on tape added
;//                 -> Flushes excess input on exit
;//                 -> Prints filename after attribute changed, not before
;//                 -> Accepts attribute arguments in lower-case
;//                 -> Single-instruction optimizations
;//                 -> Only writes file-entry back when all changes are made
;//                 -> Fixes file-extension deliminer bug from v1.3
;//
;//             1.6: Entry at 0xC09F
;//
;//                 -> Version ID written to 0x2700
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
CR          EQU     00DH        ; Cartridge Return

;
; IO ports
;
CBLKLG_IOH  EQU     021H        ; Tape block data length high byte
CBLKLG_IOL  EQU     022H        ; Tape block data length low byte
CBUF_IOH    EQU     023H        ; Tape block data address high byte
CBUF_IOL    EQU     024H        ; Tape block data address low byte
CCMD_IO     EQU     027H        ; Tape command (W) and status (R)

;
; XMON system calls
;
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
CWT         EQU     000ACH      ; Wait for tape command complete
CLOCDIR     EQU     000C1H      ; Look up filetable entry of filename on tape

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SIGNATURE   EQU     02700H      ; Program signature
TRK         EQU     02731H      ; Pointer to block address of next directory data block
CPROG       EQU     02741H      ; Tape prog status
CUNIT       EQU     02742H      ; Tape unit number
CCONT       EQU     02743H      ; Tape cont address
CBUF        EQU     02745H      ; Tape data buffer address
CTRK        EQU     02747H      ; Tape track nr
CRETRY      EQU     0274DH      ; Tape retry address
CBLKLG      EQU     02750H      ; Tape block length

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
ATTR_A      EQU     008H        ; Alias file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'ATTRIB'
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Legacy program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

file_entry_ptr:
        DW          00000H

        DW          00000H

filename_drive_nr:
        DB          0
filename_str:
        DS          9
input_char:
        DB          000H
file_entry_attribute_byte_ptr:
        DB          000H

drive_designator_str:
        DB          ':F0:',CR

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

start:
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
        STA         input_char
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
        STA         input_char
        STA         drive_designator_str+1
        CPI         'M'
        JZ          valid_device_type
        CPI         'F'
        JNZ         invalid_device
valid_device_type:
        CALL        INCHAR
        RC
        STA         input_char
        STA         drive_designator_str+2
        SUI         '0'
        JM          invalid_device
        CPI         4
        JP          invalid_device
        STA         filename_drive_nr
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ':'
        JNZ         invalid_device
        CALL        INCHAR
        RC
done_selecting_drive:
        ;
        ; Get filename and check that correct deliminer is used
        ;
        LXI         D,filename_str
        CALL        FILENAME
        RC
        STA         input_char
        CPI         ','
        JNZ         invalid_parameters
        ;
        ; Check drive type
        ;
        LXI         H,filename_str
        LDA         drive_designator_str+1
        CPI         'M'
        JZ          do_tape_file
        ;
        ; Look up file entry for floppy disk
        ;
        LDA         filename_drive_nr
        CALL        LOCDIR
        RC
        XRA         A
        ORA         M
        JNZ         file_not_found
        ;
        ; Store pointers to file entry and its attribute byte
        ;
        SHLD        file_entry_ptr
        LXI         D,00AH
        JMP         go_change_attributes

do_tape_file:
        ;
        ; Look up file entry for tape
        ;
        LDA         filename_drive_nr
        CALL        CLOCDIR
        RC
        XRA         A
        ORA         M
        JNZ         file_not_found
        ;
        ; Store pointers to file entry and its attribute byte
        ;
        SHLD        file_entry_ptr
        LXI         D,012H

go_change_attributes:
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
        STA         input_char
        CPI         '+'
        JZ          valid_attribute_operation
        CPI         '-'
        JNZ         invalid_parameters
valid_attribute_operation:
        MOV         C,A
        ;
        ; Verify attribute name, and select appropriate bitmask
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CALL        to_uppercase
        STA         input_char
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
        MOV         A,C
        CPI         '+'
        JZ          add_attribute
        ;
        ; Remove attribute
        ;
        MOV         A,B
        CMA
        LHLD        file_entry_attribute_byte_ptr
        ANA         M
        MOV         M,A
        JMP         attribute_changed

add_attribute:
        ;
        ; Check new attribute combination before adding an attribute
        ;
        LHLD        file_entry_attribute_byte_ptr
        MOV         A,B
        ANI         ATTR_S
        JZ          valid_attribute_combination
        MOV         A,M
        ANI         ATTR_A
        JZ          valid_attribute_combination
        LXI         D,system_alias_error_str
        JMP         print_string_and_quit

valid_attribute_combination:
        ;
        ; Add attribute in loaded file entry
        ;
        MOV         A,B
        ORA         M
        MOV         M,A
attribute_changed:
        ;
        ; Check if there are more attribute changes pending
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ','
        JZ          parse_next_attribute_change
        CPI         CR
        JNZ         invalid_parameters
        ;
        ; All attribute changes done, print filename
        ;
        CALL        print_full_file_ref
        RC
        ;
        ; Check drive type for writing file entry back
        ;
        LDA         drive_designator_str+1
        CPI         'M'
        JZ          write_updates_to_tape
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

attribute_changes_written:
        ;
        ; Print final status and exit
        ;
        LXI         D,attributes_altered_str
        JMP         print_string_and_quit

write_updates_to_tape:
        ;
        ; Wait for tape to be ready to take new commands
        ;
        CALL        CWT
        RC
        ;
        ; Set up tape control block and prepare controller for write
        ;
        LDA         filename_drive_nr
        STA         CUNIT
        LHLD        file_entry_ptr
        SHLD        CBUF
        CALL        wait_for_tape_ready
        MOV         A,H
        OUT         CBUF_IOH
        MOV         A,L
        OUT         CBUF_IOL
        MVI         A,0FFH
        STA         CPROG
        LXI         H,32
        SHLD        CBLKLG
        MOV         A,H
        OUT         CBLKLG_IOH
        MOV         A,L
        OUT         CBLKLG_IOL
        XRA         A
        STA         CTRK
        LXI         H,000H
        SHLD        CCONT
        SHLD        CRETRY
        ;
        ; Send write command to tape controller
        ;
        LXI         H,CUNIT
        MOV         A,M
        ORI         030H
        OUT         CCMD_IO
        CALL        CWT
        RC
        JMP         attribute_changes_written


;//////////////////////////////////////

file_not_found:
        LXI         D,not_found_str

print_string_and_quit:
        ;
        ; Print final message
        ;
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Flush excess input from CI and quit
        ;
        LDA         input_char
flush_remaining_input_loop:
        CPI         CR
        RZ
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         flush_remaining_input_loop


;//////////////////////////////////////

invalid_device:
        LXI         D,improper_unit_str
        JMP         print_string_and_quit


;//////////////////////////////////////

invalid_parameters:
        LXI         D,improper_params_str
        JMP         print_string_and_quit


;//////////////////////////////////////

invalid_attribute:
        LXI         D,unknown_attribute_str
        JMP         print_string_and_quit


;//////////////////////////////////////

        ;
        ; Print full filename
        ;
print_full_file_ref:
        ;
        ; Print file designator
        ;
        LHLD        CO_FCB
        LXI         D,drive_designator_str
        CALL        PUTSTR
        RC
        ;
        ; print first part of filename
        ;
        LXI         D,filename_str
        MVI         B,6
print_file_name:
        LDAX        D
        ORA         A
        JZ          dont_pad_filename_tail
        CALL        OUTCHAR
        RC
dont_pad_filename_tail:
        INX         D
        DCR         B
        JNZ         print_file_name
        ;
        ; Print dot before extension, but only if file has one
        ;
        LDAX        D
        ORA         A
        JZ          go_print_file_ext
        MVI         A,'.'
        CALL        OUTCHAR
        RC
go_print_file_ext:
        ;
        ; Print file extension
        ;
        MVI         B,3
print_file_ext:
        LDAX        D
        ORA         A
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


;//////////////////////////////////////

        ;
        ; Wait for tape ready status bit
        ;
wait_for_tape_ready:
        PUSH        PSW
wait_for_ready_bit:
        IN          CCMD_IO
        ANI         001H
        JNZ         wait_for_ready_bit
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

not_found_str:
        DB          'NOT FOUND',CR
attributes_altered_str:
        DB          'ATTRIBUTES ALTERED',CR
system_alias_error_str:
        DB          'SYSTEM ATTRIBUTE ON ALIAS FILE NOT ALLOWED',CR
improper_unit_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
improper_params_str:
        DB          'IMPROPER PARAMETER LIST',CR
unknown_attribute_str:
        DB          'ATTRIBUTE UNKNOWN',CR
