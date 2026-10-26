;//////////////////////////////////////////////////////////////////////////////
;//
;//     ATTRIB - Change attributes of file
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<filename>,<op><attr>[,<op><attr>[,<op><attr>[...]]]
;//
;//                 Tn          Drive type and number, default :D0:
;//                 op          Attribute operation
;//                 attr        Attribute type
;//
;//                 Drive type T:
;//                     F       Floppy
;//                     D       Floppy, double-sided double-density
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
;//         Adds and/or removes attributes from a file. The Invisible attribute will
;//         hide a file from a regular directory listing, the Write-protect attribute
;//         prevents a file to be written to, while the System attribute will ensure
;//         the file is copied over if a new disk is initialized as a system disk.
;//
;//
;//         Changelog:
;//
;//             1.2: Entry at 0xC000
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
;//                 -> No longer allows adding the system attribute to direct-
;//                    access files
;//
;//             2.0a: Entry at 0x2818
;//
;//                 -> Tape is no longer supported
;//                 -> Alias attribute no longer checked
;//                 -> Now supports double-sided double-density floppy
;//                 -> Default changed to :D0:
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
; XMON system calls
;
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
DDSWRW      EQU     0009AH      ; Write to double-sided disk with wait
DLOCDIR     EQU     000CDH      ; Look up filetable entry of filename on double-sided disk

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SIGNATURE   EQU     02700H      ; Program signature
TRK         EQU     02731H      ; Pointer to block address of next directory data block

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
DFILENAME   EQU     0FDBBH      ; Input TOS filename for double-sided disk
FILENAME    EQU     0FDCDH      ; Input TOS filename

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS-II file attributes byte 1
;
ATTR_S_DSDD EQU     004H        ; System file
ATTR_W_DSDD EQU     040H        ; Write-protected file
ATTR_X_DSDD EQU     080H        ; Direct-access file

;
; TOS-II file attributes byte 2
;
ATTR_I_DSDD EQU     001H        ; Invisible file

;
; TOS-II file attributes
;
ATTR_I_DSDD EQU     001H        ; Invisible file
ATTR_S_DSDD EQU     004H        ; System file
ATTR_W_DSDD EQU     040H        ; Write-protected file
ATTR_X_DSDD EQU     080H        ; Direct-access file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'ATTRIB'
        DB          '200'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02800H
file_entry_ptr:
        DW          00000H

filename_drive_nr:
        DB          0
filename_str:
        DS          13
input_char:
        DB          000H
file_entry_attribute_byte_ptr:
        DW          00000H

drive_designator_str:
        DB          ':D0:',CR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Initialization
;//
;//////////////////////////////////////////////////////////////////////////////

start:
        ;
        ; Set default drive number
        ;
        SUB         A
        STA         filename_drive_nr
        ;
        ; Ignore leading spaces
        ;
prune_leading_spaces_loop:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ' '
        JZ          prune_leading_spaces_loop
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
        CPI         'D'
        JZ          valid_device_type
        CPI         'F'
        JNZ         invalid_device
valid_device_type:
        CALL        INCHAR
        RC
        STA         input_char
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
        ; Check drive type
        ;
        PUSH        PSW
        LDA         drive_designator_str+1
        CPI         'D'
        JZ          do_double_density_file
        POP         PSW


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Single-sided TOS disk file
;//
;//////////////////////////////////////////////////////////////////////////////

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
        ; Look up file entry for floppy disk
        ;
        LDA         filename_drive_nr
        LXI         H,filename_str
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
        ANI         ATTR_X
        JZ          valid_attribute_combination
        LXI         D,system_random_error_str
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
        ; Print final status and exit
        ;
        LXI         D,attributes_altered_str
        JMP         print_string_and_quit


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Double-sided TOS disk file
;//
;//////////////////////////////////////////////////////////////////////////////

do_double_density_file:
        POP         PSW
        ;
        ; Get filename and check that correct deliminer is used
        ;
        LXI         D,filename_str
        CALL        DFILENAME
        RC
        STA         input_char
        CPI         ','
        JNZ         invalid_parameters
        ;
        ; Look up file entry for double-sided floppy disk
        ;
        LDA         filename_drive_nr
        LXI         H,filename_str
        CALL        DLOCDIR
        RC
        XRA         A
        ORA         M
        JNZ         file_not_found
        ;
        ; Store pointers to file entry and its attribute byte
        ;
        SHLD        file_entry_ptr
        LXI         D,00EH
        DAD         D
        SHLD        file_entry_attribute_byte_ptr
        ;
        ; Parse attribute changes from command line arguments
        ;
d_parse_next_attribute_change:
        ;
        ; Verify attribute operation
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         '+'
        JZ          d_valid_attribute_operation
        CPI         '-'
        JNZ         invalid_parameters
d_valid_attribute_operation:
        MOV         C,A
        ;
        ; Verify attribute name, and select appropriate bitmask
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CALL        to_uppercase
        STA         input_char
        LHLD        file_entry_attribute_byte_ptr
        MVI         B,ATTR_S_DSDD
        CPI         'S'
        JZ          d_valid_attribute
        MVI         B,ATTR_W_DSDD
        CPI         'W'
        JZ          d_valid_attribute
        INX         H
        MVI         B,ATTR_I_DSDD
        CPI         'I'
        JNZ         invalid_attribute
d_valid_attribute:
        ;
        ; Check if we are adding or removing an attribute
        ;
        MOV         A,C
        CPI         '+'
        JZ          d_add_attribute
        ;
        ; Remove attribute
        ;
        MOV         A,B
        CMA
        ANA         M
        MOV         M,A
        JMP         d_attribute_changed

d_add_attribute:
        ;
        ; Check new attribute combination before adding an attribute
        ;
        MOV         A,B
        ANI         ATTR_S_DSDD
        JZ          d_valid_attribute_combination
        MOV         A,M
        ANI         ATTR_X_DSDD
        JZ          d_valid_attribute_combination
        LXI         D,system_random_error_str
        JMP         print_string_and_quit

d_valid_attribute_combination:
        ;
        ; Add attribute in loaded file entry
        ;
        MOV         A,B
        ORA         M
        MOV         M,A
d_attribute_changed:
        ;
        ; Check if there are more attribute changes pending
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ','
        JZ          d_parse_next_attribute_change
        CPI         CR
        JNZ         invalid_parameters
        ;
        ; All attribute changes done, print filename
        ;
        CALL        print_full_file_ref
        RC
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
        CALL        DDSWRW
        RC
        ;
        ; Print final status and exit
        ;
        LXI         D,attributes_altered_str
        JMP         print_string_and_quit


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Termination
;//
;//////////////////////////////////////////////////////////////////////////////

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

        ;
        ; Print full filename
        ;
print_full_file_ref:
        ;
        ; Print file designator
        ;
        LHLD        CO_FCB
        LXI         D,drive_designator_str
        LDA         filename_drive_nr
        ADI         '0'
        STA         drive_designator_str+2
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
        INX         D
        DCR         B
        JNZ         print_file_name
dont_pad_filename_tail:
        ;
        ; Prepare to print file extension
        ;
        MOV         C,B
        MVI         B,3
        LXI         D,filename_str+6
        ;
        ; Adjust for longer filename-field on double-sided disks
        ;
        LDA         drive_designator_str+1
        CPI         'D'
        JNZ         ready_to_print_file_ext
        INX         D
        INX         D
ready_to_print_file_ext:
        ;
        ; Print dot before extension, but only if file has one
        ;
        LDAX        D
        ORA         A
        JZ          done_printing_file_ext
        MVI         A,'.'
        CALL        OUTCHAR
        RC
        ;
        ; Print file extension
        ;
print_next_file_ext_char:
        LDAX        D
        ORA         A
        JZ          done_printing_file_ext
        CALL        OUTCHAR
        RC
        INX         D
        DCR         B
        JNZ         print_next_file_ext_char
done_printing_file_ext:
        ;
        ; Pad out remaining field with spaces after filename + ext
        ;
        MOV         A,C
        ADD         B
        INR         A
        MOV         B,A
pad_file_ext_loop:
        MVI         A,' '
        CALL        OUTCHAR
        RC
        DCR         B
        JNZ         pad_file_ext_loop
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
system_random_error_str:
        DB          'SYSTEM ATTRIBUTE ON RANDOM FILE NOT ALLOWED',CR
improper_unit_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
improper_params_str:
        DB          'IMPROPER PARAMETER LIST',CR
unknown_attribute_str:
        DB          'ATTRIBUTE UNKNOWN',CR
