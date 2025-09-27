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
;//                     A       Floppy (IBM 3740, ASCII)
;//                     F       Floppy (Intel ISIS)
;//                     I       Floppy (IBM 3740, EBCDIC)
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
;//             1.3: Entry at 0xC103
;//
;//                 -> First version I have
;//
;//             1.5a: Entry at 0xC000
;//
;//                 -> Flushes excess command line argument input on exit
;//                 -> Only prints file extension deliminer if filename has an
;//                    extension
;//
;//             1.5b: Entry at 0xC104
;//
;//                 -> Recognizes B and J as valid drive types
;//                 -> Introduces a bug where drive types B and J are reported to
;//                    the user as type A and I respectively
;//
;//             1.6a: Entry at 0xC0AA
;//
;//                 -> Reverts all changes from v1.5b
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
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; XMON system calls
;
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
DSRAW       EQU     0007CH      ; Read from disk with wait and translate EBCDIC to ASCII
DSWAW       EQU     0007FH      ; Translate ASCII to EBCDIC and write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
CCAL        EQU     00091H      ; Reset tape cartridge
CWT         EQU     000ACH      ; Wait for tape command complete
CLOCDIR     EQU     000C1H      ; Look up filetable entry of filename on tape

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SIGNATURE   EQU     02700H      ; Program signature
SSWITCH     EQU     0272CH      ; TOS system switch
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
IBFIL       EQU     0FDD0H      ; Input IBM-3740 filename

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_20    EQU     020H        ; DELETED DATA RECORD

;
; TOS file attributes
;
ATTR_S      EQU     002H        ; System file
ATTR_W      EQU     004H        ; Write-protected file
ATTR_F      EQU     080H        ; Format file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'RENAME'
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
old_file_dir_entry_ptr:
        DW          00000H

        DB          000H,000H

drive_nr:
        DB          0
ibm_read_call_ptr:
        DS          2
ibm_write_call_ptr:
        DS          2
input_char:
        DS          1
old_filename:
        DS          9
new_filename:
        DS          9

drive_designator_str:
        DB          ':F0:',CR

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

start:
        ;
        ; Scan for first character of mandatory command line argument
        ;
scan_for_first_char:
        SUB         A
        STA         drive_nr
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
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
        STA         input_char
        CPI         CR
        JZ          invalid_drive
        CALL        to_uppercase
        STA         drive_designator_str + 1
        CALL        INCHAR
        RC
        STA         input_char
        STA         drive_designator_str + 2
        SUI         '0'
        JC          invalid_drive
        CPI         4
        JNC         invalid_drive
        STA         drive_nr
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ':'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        STA         input_char
drive_set:
        ;
        ; Check device type for IBM disk
        ;
        PUSH        PSW
        LDA         drive_designator_str + 1
        CPI         'I'
        JZ          rename_ibm_ebcdic
        CPI         'A'
        JZ          rename_ibm_ascii
        POP         PSW
        ;
        ; Otherwise continue getting filename for Tape or Intel-formatted disk
        ;
        LXI         D,old_filename
        CALL        FILENAME
        RC
        STA         input_char
        CPI         ','
        JNZ         invalid_input
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
        STA         input_char
        CPI         CR
        JNZ         invalid_input
        ;
        ; Check device type for Tape or Intel disk
        ;
        LDA         drive_designator_str + 1
        CPI         'M'
        LXI         H,new_filename
        JZ          rename_tape
        CPI         'F'
        JNZ         invalid_drive


;//////////////////////////////////////

rename_intel:
        ;
        ; Get file entry of new filename, and verify it does not already exist
        ;
        LDA         drive_nr
        CALL        LOCDIR
        RC
        MOV         A,M
        ANA         A
        JZ          new_tos_file_exists
        ;
        ; Get file entry of old filename, and verify it does exist
        ;
        LXI         H,old_filename
        LDA         drive_nr
        CALL        LOCDIR
        RC
        MOV         A,M
        ANA         A
        JNZ         old_tos_file_not_found
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
tos_file_rename_done:
        LXI         D,old_filename
        CALL        print_filename
file_rename_done:
        LXI         D,renamed_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////

rename_ibm_ebcdic:
        ;
        ; Set IBM disk interface to the EBCDIC API calls in XMON
        ;
        LXI         H,DSRAW
        SHLD        ibm_read_call_ptr
        LXI         H,DSWAW
        JMP         rename_ibm

rename_ibm_ascii:
        ;
        ; Set IBM disk interface to the ASCII API calls in XMON
        ;
        LXI         H,DSRDW
        SHLD        ibm_read_call_ptr
        LXI         H,DSWRW
rename_ibm:
        SHLD        ibm_write_call_ptr
        ;
        ; Get IBM filename of file to rename
        ;
        POP         PSW
        LXI         D,old_filename
        CALL        IBFIL
        RC
        STA         input_char
        CPI         ','
        JNZ         invalid_input
        ;
        ; Skip whitespaces between deliminator and new filename
        ;
scan_for_ibm_new_filename:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          scan_for_ibm_new_filename
        ;
        ; Get new filename and verify end of command line arguments
        ;
        LXI         D,new_filename
        CALL        IBFIL
        RC
        STA         input_char
        CPI         CR
        JNZ         invalid_input
        ;
        ; Scan throug IBM file records to verify new filename does not exist
        ;
        LXI         B,0*DISK_TRACK + 8*DISK_SECTOR
scan_next_ibm_record_for_new_file:
        ;
        ; Read file record
        ;
        CALL        read_ibm_sector
        RC
        JNZ         is_not_new_file
        ;
        ; Compare filename
        ;
        LXI         D,new_filename
        CALL        compare_ibm_filename
        JNZ         is_not_new_file
        ;
        ; New filename found, abort rename
        ;
        LXI         D,new_filename
        CALL        print_ibm_filename
        JMP         file_exists

is_not_new_file:
        ;
        ; Advance to next file record, checking for end of directory
        ;
        INX         B
        MOV         A,C
        CPI         27
        JC          scan_next_ibm_record_for_new_file
        ;
        ; Scan throug IBM file records to verify old filename does exist
        ;
        LXI         B,0*DISK_TRACK + 8*DISK_SECTOR
scan_next_ibm_record_for_old_file:
        ;
        ; Read file record
        ;
        CALL        read_ibm_sector
        RC
        JNZ         is_not_old_file
        ;
        ; Compare filename
        ;
        LXI         D,old_filename
        CALL        compare_ibm_filename
        JZ          ibm_file_found
is_not_old_file:
        ;
        ; Advance to next file record, checking for end of directory
        ;
        INX         B
        MOV         A,C
        CPI         27
        JC          scan_next_ibm_record_for_old_file
        ;
        ; Old file not found, abort rename
        ;
        LXI         D,old_filename
        CALL        print_ibm_filename
        JMP         file_not_found

ibm_file_found:
        ;
        ; Copy new filename into file record of old file
        ;
        PUSH        B
        LXI         D,new_filename
        LXI         H,BUF2+5
        MVI         B,8
copy_ibm_filename_loop:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         copy_ibm_filename_loop
        POP         B
        ;
        ; Write changes back to disk
        ;
        CALL        write_ibm_sector
        RC
        LXI         D,old_filename
        CALL        print_ibm_filename
        JMP         file_rename_done


;//////////////////////////////////////////////////////////////////////////////

old_tos_file_not_found:
        LXI         D,old_filename
        CALL        print_filename
file_not_found:
        LXI         D,not_found_str
        ;
        ; Print error status, cleanup, and quit
        ;
quit_with_error_print:
        LDA         drive_designator_str + 1
        CPI         'M'
        JNZ         print_and_quit
        CALL        CCAL
        RC
print_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Flush remaining command line arguments before exiting
        ;
        LDA         input_char
flush_next_char:
        CPI         CR
        RZ
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         flush_next_char


;//////////////////////////////////////

invalid_drive:
        LXI         D,invalid_drive_str
        JMP         quit_with_error_print


;//////////////////////////////////////

invalid_input:
        LXI         D,invalid_args_str
        JMP         quit_with_error_print


;//////////////////////////////////////

old_file_protected:
        LXI         D,old_filename
        CALL        print_filename
        LXI         D,protected_str
        JMP         quit_with_error_print


;//////////////////////////////////////

new_tos_file_exists:
        LXI         D,new_filename
        CALL        print_filename
file_exists:
        LXI         D,exists_str
        JMP         quit_with_error_print


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print full filename
        ;
print_filename:
        ;
        ; Print file designator
        ;
        PUSH        D
        LHLD        CO_FCB
        LXI         D,drive_designator_str
        CALL        PUTSTR
        POP         D
        ;
        ; print first part of filename
        ;
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
        ; Skip filename extension delimer if no extension
        ;
        LDAX        D
        ORA         A
        JZ          print_file_extension
        ;
        ; Print filename extension
        ;
        MVI         A,'.'
        CALL        OUTCHAR
        RC
print_file_extension:
        MVI         B,3
print_next_file_ext_char:
        LDAX        D
        ORA         A
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

rename_tape:
        ;
        ; Check that new filename does not already exist on tape
        ;
        LDA         drive_nr
        CALL        CLOCDIR
        RC
        MOV         A,M
        ANA         A
        JZ          new_tos_file_exists
        ;
        ; Check that old filename exist on tape
        ;
        LXI         H,old_filename
        LDA         drive_nr
        CALL        CLOCDIR
        RC
        MOV         A,M
        ANA         A
        JNZ         old_tos_file_not_found
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
        RC
        JMP         tos_file_rename_done


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read IBM sector, allow for deleted sectors
        ;
read_ibm_sector:
        CALL        ibm_read_operation
        JC          ibm_check_deleted
        XRA         A
        RET

ibm_check_deleted:
        ;
        ; Deleted sectors are OK, other faults are not
        ;
        CPI         ERROR_20
        STC
        RNZ
        ANA         A
        RET


;//////////////////////////////////////

        ;
        ; Read IBM sector with the currently selected encoding type
        ;
ibm_read_operation:
        LHLD        ibm_read_call_ptr
ibm_disk_operation:
        LDA         drive_nr
        PUSH        H
        LXI         H,BUF2
        RET

        ;
        ; Write IBM sector with the currently selected encoding type
        ;
write_ibm_sector:
        LHLD        ibm_write_call_ptr
        JMP         ibm_disk_operation


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Compare current IBM file record against a filename
        ;
compare_ibm_filename:
        PUSH        H
        PUSH        B
        ;
        ; Replace any NULL-chars of input IBM filename with spaces
        ;
        PUSH        D
        MVI         B,8
prepare_ibm_filename_loop:
        LDAX        D
        ORA         A
        JNZ         ibm_filename_char_ready
        MVI         A,' '
        STAX        D
ibm_filename_char_ready:
        INX         D
        DCR         B
        JNZ         prepare_ibm_filename_loop
        POP         D
        ;
        ; Compare input IBM filename against filename in IBM file record
        ;
        MVI         B,8
        LXI         H,BUF2+5
compare_next_ibm_filename_char:
        LDAX        D
        CMP         M
        JNZ         compare_ibm_filename_done
        INX         H
        INX         D
        DCR         B
        JNZ         compare_next_ibm_filename_char
compare_ibm_filename_done:
        POP         B
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print filename of IBM-3740 file
        ;
print_ibm_filename:
        ;
        ; Print drive designator string
        ;
        PUSH        D
        LHLD        CO_FCB
        LXI         D,drive_designator_str
        CALL        PUTSTR
        POP         D
        ;
        ; Print IBM filename
        ;
        MVI         B,8
print_next_ibm_filename_char:
        LDAX        D
        CALL        OUTCHAR
        RC
        INX         D
        DCR         B
        JNZ         print_next_ibm_filename_char
        MVI         A,' '
        CALL        OUTCHAR
        RET


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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

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
