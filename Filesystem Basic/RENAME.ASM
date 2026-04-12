;//////////////////////////////////////////////////////////////////////////////
;//
;//     RENAME - Rename a file
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<old>,<new>
;//
;//                 Tn          Drive type and number, default :F0:
;//                 old         File to rename
;//                 new         New name to give file
;//
;//                 Drive type T:
;//                     F       Floppy
;//                     M       Tape
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         Renames a file. Some things are checked, for instance that the file
;//         exists and that no file with the new name exists. Write-protected,
;//         system- and format-files will typically be reserved from renaming,
;//         unless the system-flag is set to S using the SYS command in advance.
;//         Though, be adviced that changing the name of the format files may break
;//         the file-system of a disk.
;//
;//         NOTE: Uses XMON calls to load the file-directory, including for tapes.
;//               Not all machines have the tape API, as this was optional. The
;//               program may as such not work for tape if this is the case.
;//               Writing back to tape is done by using bare-metal I/O calls.
;//
;//
;//         Changelog:
;//
;//             1.2: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the file-extension deliminer is printed even
;//                    if the file has no extension
;//                 -> Has a bug where it assumes mapfile will be loaded when file
;//                    is looked up. Depending on XMON version, this may not always
;//                    be the case.
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
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; IO ports
;
CBLKLG_IOH  EQU     021H        ; Tape block data length high byte
CBLKLG_IOL  EQU     022H        ; Tape block data length low byte
CBUF_IOH    EQU     023H        ; Tape block data address high byte
CBUF_IOL    EQU     024H        ; Tape block data address low byte
CCMD_IO     EQU     027H        ; Tape command (W) and status (R)

;
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; XMON system calls
;
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
CCAL        EQU     00091H      ; Reset tape cartridge
CWT         EQU     000ACH      ; Wait for tape command complete
CLOCDIR     EQU     000C1H      ; Look up filetable entry of filename on tape

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SSWITCH     EQU     0272CH      ; TOS system switch
TRK         EQU     02731H      ; Pointer to block address of next directory data block
MAP1        EQU     02739H      ; Block address of first half of mapfile data
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
DSWRW       EQU     0FD76H      ; Write to disk with wait
FILENAME    EQU     0FDCDH      ; Input TOS filename

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS file attributes
;
ATTR_S      EQU     002H        ; System file
ATTR_W      EQU     004H        ; Write-protected file
ATTR_F      EQU     080H        ; Format file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Call LOCDIR, forcing MAP1 to point to first half of ISIS.MAP
        ;
look_up_intel_file:
        PUSH        H
        LXI         H,2*DISK_TRACK + 2*DISK_SECTOR
        SHLD        MAP1
        POP         H
        JMP         LOCDIR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

old_file_dir_entry_ptr:
        DW          00000H

        DB          000H,000H

drive_nr:
        DB          0
old_filename:
        DS          9
new_filename:
        DS          9

not_found_str:
        DB          'NOT FOUND',CR
renamed_str:
        DB          'RENAMED',CR
protected_str:
        DB          'PROTECTED',CR
exists_str:
        DB          'EXISTS',CR
invalid_drive_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
invalid_args_str:
        DB          'IMPROPER PARAMETER LIST',CR
drive_designator_str:
        DB          ':F*:',CR

        DS          128


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII character in A to uppercase
        ;
to_uppercase:
        CPI         'a'
        RM
        CPI         'z'+1
        RP
        ANI         0DFH
        RET


;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Scan for first character of mandatory command line argument
        ;
scan_for_first_char:
        SUB         A
        STA         drive_nr
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          scan_for_first_char
        CPI         CR
        RZ
        ;
        ; Parse optional drive designator before filename
        ;
        CPI         ':'
        JNZ         drive_set
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'F'
        JNZ         potentially_invalid_drive
valid_drive_type:
        ;
        ; Parse drive number
        ;
        CALL        INCHAR
        RC
        CPI         '0'
        JM          potentially_invalid_drive
        CPI         '4'
        JP          potentially_invalid_drive
        SUI         '0'
        ;
        ; Add drive number to base offset (nr 4-7 is tape drive 0-3)
        ;
        MOV         B,A
        LDA         drive_nr
        ADD         B
        STA         drive_nr
        ;
        ; Check drive designator closure
        ;
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         potentially_invalid_drive
        CALL        INCHAR
        RC
drive_set:
        ;
        ; Get filename for Tape or Intel-formatted disk
        ;
        LXI         D,old_filename
        CALL        FILENAME
        RC
        CPI         ','
        JNZ         invalid_input
        ;
        ; Set up drive designator string
        ;
        MVI         B,'F'
        LDA         drive_nr
        CPI         4
        JM          drive_type_char_ready
        MVI         B,'M'
drive_type_char_ready:
        MOV         A,B
        STA         drive_designator_str+1
        ;
        ; Print full filename with drive designator
        ;
        CALL        print_filename
        RC
        ;
        ; Skip whitespaces between deliminator and new filename
        ;
scan_for_tos_new_filename:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          scan_for_tos_new_filename
        ;
        ; Get new filename and verify end of command line arguments
        ;
        LXI         D,new_filename
        CALL        FILENAME
        RC
        CPI         CR
        JNZ         invalid_input
        LXI         D,new_filename
        ;
        ; Check device type for Tape or Intel disk
        ;
        LDA         drive_nr
        CPI         4
        JP          rename_tape


;//////////////////////////////////////

rename_intel:
        ;
        ; Get file entry of new filename, and verify it does not already exist
        ;
        CALL        look_up_intel_file
        RC
        MOV         A,M
        ANA         A
        JZ          file_exists
        ;
        ; Get file entry of old filename, and verify it does exist
        ;
        LXI         H,old_filename
        LDA         drive_nr
        CALL        look_up_intel_file
        RC
        MOV         A,M
        ANA         A
        JNZ         file_not_found
        ;
        ; Check if file is protected, unless system switch is set to S
        ;
        SHLD        old_file_dir_entry_ptr
        LDA         SSWITCH
        CPI         'S'
        JZ          commit_to_rename_floppy
        LXI         D,00AH
        DAD         D
        MOV         A,M
        ANI         ATTR_S + ATTR_W + ATTR_F
        JNZ         old_file_protected
commit_to_rename_floppy:
        ;
        ; Replace old filename with new in file entry
        ;
        LHLD        old_file_dir_entry_ptr
        INX         H
        MVI         B,9
        LXI         D,new_filename
copy_floppy_filename_loop:
        LDAX        D
        MOV         M,A
        INX         D
        INX         H
        DCR         B
        JNZ         copy_floppy_filename_loop
        ;
        ; Write changes in file table back to disk
        ;
        LHLD        TRK
        DCX         H
        MOV         B,M
        DCX         H
        MOV         C,M
        LXI         H,BUF2
        LDA         drive_nr
        CALL        DSWRW
        RC


;//////////////////////////////////////

        ;
        ; Print final status and quit after successful rename
        ;
file_rename_done:
        LXI         D,renamed_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////

file_not_found:
        LXI         D,not_found_str
        ;
        ; Print error status, cleanup, and quit
        ;
quit_with_error_print:
        LDA        drive_nr
        CPI         4
        JM          print_and_quit
        SUI         4
        CALL        CCAL
        RC
print_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

potentially_invalid_drive:
        CPI         'M'
        JZ          setup_for_tape_file
        LXI         D,invalid_drive_str
        JMP         quit_with_error_print


;//////////////////////////////////////

invalid_input:
        LXI         D,invalid_args_str
        JMP         quit_with_error_print


;//////////////////////////////////////

old_file_protected:
        LXI         D,protected_str
        JMP         quit_with_error_print


;//////////////////////////////////////

file_exists:
        LXI         D,exists_str
        JMP         quit_with_error_print


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print full filename
        ;
print_filename:
        ;
        ; Restore drive number for drive designator string and print it
        ;
        LHLD        CO_FCB
        LDA         drive_nr
        CPI         4
        JM          print_drive_designator
        SUI         4
print_drive_designator:
        ADI         '0'
        STA         drive_designator_str+2
        LXI         D,drive_designator_str
        CALL        PUTSTR
        ;
        ; print first part of filename
        ;
        LXI         D,old_filename
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
        ; Print filename extension
        ;
        MVI         A,'.'
        CALL        OUTCHAR
        RC
        MVI         B,3
print_next_file_ext_char:
        LDAX        D
        CPI         NULL
        JNZ         file_ext_char_ready
        MVI         A,' '
file_ext_char_ready:
        CALL        OUTCHAR
        RC
        ;
        ; Advance to next filename extension character
        ;
        INX         D
        DCR         B
        JNZ         print_next_file_ext_char
        ;
        ; Add a space after full filename
        ;
        MVI         A,' '
        CALL        OUTCHAR
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Drive IDs for tape starts at 4 here, so set base offset
        ;
setup_for_tape_file:
        MVI         A,4
        STA         drive_nr
        JMP         valid_drive_type


;//////////////////////////////////////

rename_tape:
        ;
        ; Check that new filename does not already exist on tape
        ;
        SUI         4
        CALL        CLOCDIR
        RC
        MOV         A,M
        ANA         A
        JZ          file_exists
        ;
        ; Check that old filename exist on tape
        ;
        LXI         H,old_filename
        LDA         drive_nr
        SUI         4
        CALL        CLOCDIR
        RC
        MOV         A,M
        ANA         A
        JNZ         file_not_found
        ;
        ; Check if file is protected, unless system switch is set to S
        ;
        SHLD        old_file_dir_entry_ptr
        LXI         D,012H
        DAD         D
        LDA         SSWITCH
        CPI         'S'
        JZ          commit_to_rename_tape
        MOV         A,M
        ANI         ATTR_S + ATTR_W + ATTR_F
        JNZ         old_file_protected
commit_to_rename_tape:
        ;
        ; Wait for tape to be ready to take new commands
        ;
        CALL        CWT
        ;
        ; Start setting up tape control block
        ;
        LDA         drive_nr
        SUI         4
        STA         CUNIT
        ;
        ; Replace old filename with new in file entry
        ;
        LHLD        old_file_dir_entry_ptr
        INX         H
        MVI         B,9
        LXI         D,new_filename
copy_tape_filename_loop:
        LDAX        D
        MOV         M,A
        INX         D
        INX         H
        DCR         B
        JNZ         copy_tape_filename_loop
        ;
        ; Set up rest of tape control block and prepare controller for write
        ;
        LHLD        old_file_dir_entry_ptr
        SHLD        CBUF
        MOV         A,H
        CALL        wait_for_tape_ready
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
        SUB         A
        STA         CTRK
        LXI         H,00000H
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
        JMP         file_rename_done


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

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
