;//////////////////////////////////////////////////////////////////////////////
;//
;//     DELETE - Delete files and aliases
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<filename>[,[:<Tn>:]<filename>[,[:<Tn>:]<filename>[...]]]
;//
;//                 Tn          Drive type and number, default :F0:
;//                 filename    File to delete
;//
;//                 Drive type T:
;//                     A       Floppy (IBM 3740, ASCII)
;//                     B       Floppy (IBM 3740, ASCII)
;//                     F       Floppy (Intel ISIS)
;//                     I       Floppy (IBM 3740, EBCDIC)
;//                     J       Floppy (IBM 3740, EBCDIC)
;//                     M       Tape
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         This tool is used to delete files and aliases. If an alias is deleted,
;//         the file data will still be accessible through the original file and
;//         any eventual other aliases. If a file has been recently deleted by
;//         mistake, it may be undeleted with RESCUE.
;//
;//         NOTE: Tape operations depends on the optional XMON API for tape drives.
;//               Not all machines have this installed, so care should be taken if
;//               this program is to be used with tape.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the file-extension deliminer is printed even
;//                    if the file has no extension
;//                 -> Has a bug where it assumes mapfile will be loaded when file
;//                    is looked up. Depending on XMON version, this may not always
;//                    be the case.
;//
;//             1.5a: Entry at 0xC000
;//
;//                 -> Adds support for A and I drive types
;//                 -> Major rewrite in code for parsing and storing drive type
;//                 -> Fixes file-extension deliminer bug from v1.3
;//                 -> Fixes the v1.3 mapfile bug
;//                 -> Flushes excess input on exit
;//
;//             1.5b: Entry at 0xC111
;//
;//                 -> Recognizes B and J as valid drive types
;//                 -> Introduces a bug where drive types B and J are reported to
;//                    the user as type A and I respectively
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
DSDLW       EQU     00079H      ; Write deleted to disk with wait
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
SSWITCH     EQU     0272CH      ; TOS system switch
TRK         EQU     02731H      ; Pointer to block address of next directory data block
MAP1        EQU     02739H      ; Block address of first half of mapfile data
MAP2        EQU     0273BH      ; Block address of last half of mapfile data
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
RELN        EQU     0FDD3H      ; Release next N blocks from linking block
RELBLK      EQU     0FDD6H      ; Release a single block on current Intel disk

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_0F    EQU     00FH        ; DISKETTE MAP MISSING
ERROR_20    EQU     020H        ; DELETED DATA RECORD

;
; TOS file attributes
;
ATTR_S      EQU     002H        ; System file
ATTR_W      EQU     004H        ; Write-protected file
ATTR_A      EQU     008H        ; Alias file
ATTR_F      EQU     080H        ; Format file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Legacy program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

ibm_read_call_ptr:
        DW          00000H
ibm_write_call_ptr:
        DW          00000H
file_entry_data_ptr:
        DW          00000H
linking_block_track_sector:
        DW          00000H
drive_nr:
        DB          000H
filename_str:
        DS          9
input_char:
        DB          000H

mapfile_name:
        DB          'ISIS',NULL,NULL
        DB          'MAP'

not_found_str:
        DB          'NOT FOUND',CR
deleted_str:
        DB          'DELETED',CR
protected_str:
        DB          'PROTECTED',CR
alias_str:
        DB          'ALIAS',CR
deleted_alias_str:
        DB          'DELETED ALIAS',CR
improper_unit_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
improper_params_str:
        DB          'IMPROPER PARAMETER LIST',CR
drive_designator:
        DB          ':F*:',CR

data_buffer:
        DS          128


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

to_uppercase:
        CPI         'a'
        RM
        CPI         'z'+1
        RP
        ANI         0DFH
        RET


;//////////////////////////////////////////////////////////////////////////////

start:
beginning:
        ;
        ; Reset drive number assume drive :F0: default
        ;
        SUB         A
        STA         drive_nr
        ;
        ; Ignore leading whitespace
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          beginning
        ;
        ; Expect some arguments
        ;
        CPI         CR
        RZ
        ;
        ; Check for custom drive designator specified, and set up drive type
        ;
        CPI         ':'
        JNZ         parse_filename
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'B'
        JNZ         ibm_type_b_check_done
        DCR         A
ibm_type_b_check_done:
        CPI         'J'
        JNZ         ibm_type_j_check_done
        DCR         A
ibm_type_j_check_done:
        STA         input_char
        CPI         'F'
        JZ          valid_drive_type
        CPI         'A'
        JZ          valid_drive_type
        CPI         'I'
        JZ          valid_drive_type
        CPI         'M'
        JNZ         invalid_drive
valid_drive_type:
        STA         drive_designator+1
        ;
        ; Parse drive number
        ;
        CALL        INCHAR
        RC
        STA         input_char
        SUI         '0'
        JM          invalid_drive
        CPI         4
        JP          invalid_drive
        STA         drive_nr
        ;
        ; Check drive designator closure
        ;
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ':'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        PUSH        PSW
        LDA         drive_designator+1
        CPI         'I'
        JZ          delete_ibm_ebcdic_file
        CPI         'A'
        JZ          delete_ibm_ascii_file
        POP         PSW
parse_filename:
        ;
        ; Parse filename, and following line end or deliminer
        ;
        LXI         D,filename_str
        CALL        FILENAME
        RC
        STA         input_char
        CPI         CR
        JZ          valid_filename_input
        CPI         ','
        JNZ         invalid_input
valid_filename_input:
        ;
        ; Print full filename with drive designator
        ;
        CALL        print_filename
        RC
        ;
        ; Check drive type for deletion algorithm
        ;
        LDA         drive_designator+1
        CPI         'M'
        JZ          delete_tape_file
        ;
        ; Prepare to delete file on intel-type floppy disk, look up mapfile
        ;
        LXI         H,mapfile_name
        LDA         drive_nr
        CALL        LOCDIR
        RC
        MOV         A,M
        ANA         A
        MVI         A,ERROR_0F
        STC
        RNZ
        ;
        ; Read mapfile linking block
        ;
        LXI         D,14
        DAD         D
        PUSH        B
        MOV         C,M
        INX         H
        MOV         B,M
        LXI         H,BUF2
        LDA         drive_nr
        CALL        DSRDW
        POP         B
        RC
        ;
        ; Store track and sector of mapfile data blocks
        ;
        LHLD        BUF2+4
        SHLD        MAP1
        LHLD        BUF2+6
        SHLD        MAP2
        ;
        ; try to look up file
        ;
        LXI         H,filename_str
        LDA         drive_nr
        CALL        LOCDIR
        RC
        MOV         A,M
        ANA         A
        JNZ         file_not_found
        SHLD        file_entry_data_ptr
        ;
        ; Check attributes of file for delete protection
        ;
        LXI         D,00AH
        DAD         D
        LDA         SSWITCH
        CPI         'S'
        JZ          commit_to_delete_intel_file
        MOV         A,M
        ANI         ATTR_F + ATTR_W + ATTR_S
        JNZ         protected_file
commit_to_delete_intel_file:
        ;
        ; Check attributes of file for alias
        ;
        MOV         A,M
        ANI         ATTR_A
        JNZ         delete_alias_file
        ;
        ; Delete normal file: Mark file as inactive and get linking block
        ;
        LHLD        file_entry_data_ptr
        MVI         M,0FFH
        LXI         D,00EH
        DAD         D
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        SHLD        linking_block_track_sector
        XCHG
        ;
        ; Write changes in file directory back to disk
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
        ;
        ; Free up all blocks previously reserved by the deleted file
        ;
free_next_linking_block:
        ;
        ; Read next linking block in chain
        ;
        MOV         B,D
        MOV         C,E
        LDA         drive_nr
        LXI         H,data_buffer
        CALL        DSRDW
        RC
        ;
        ; Release the linking block itself
        ;
        CALL        RELBLK
        RC
        ;
        ; Release all blocks in the linking block
        ;
        LXI         H,data_buffer+4
        MVI         A,62
        CALL        RELN
        RC
        ;
        ; Get track and sector of the next linking block
        ;
        LHLD        data_buffer+2
        MOV         A,H
        ORA         L
        XCHG
        JNZ         free_next_linking_block
        ;
        ; Print status after deletion
        ;
        JMP         file_deleted


;//////////////////////////////////////

protected_file:
        LXI         D,protected_str
        JMP         file_done


;//////////////////////////////////////

delete_alias_file:
        ;
        ; Just delete entry for alias file, don't free up any blocks
        ;
        LHLD        file_entry_data_ptr
        MVI         M,0FFH
        ;
        ; Write changes back to disk
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
        ;
        ; Print status
        ;
        LXI         D,alias_str
        JMP         file_done


;//////////////////////////////////////

file_not_found:
        LXI         D,not_found_str
        JMP         file_done


;//////////////////////////////////////

file_deleted:
        LXI         D,deleted_str
file_done:
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Reset tape drive, if used
        ;
        LDA         drive_designator+1
        CPI         'M'
        JNZ         ready_for_next_file
        LDA         drive_nr
        CALL        CCAL
        RC
        ;
        ; Go delete next file if more
        ;
ready_for_next_file:
        LDA         input_char
        CPI         ','
        JZ          beginning
        ANA         A
        RET


;//////////////////////////////////////

invalid_drive:
        LXI         D,improper_unit_str
        JMP         print_error


;//////////////////////////////////////

invalid_input:
        LXI         D,improper_params_str

print_error:
        ;
        ; Print error message
        ;
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Flush remaining input before ending program
        ;
        LDA         input_char
flush_input:
        CPI         CR
        RZ
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         flush_input


;//////////////////////////////////////////////////////////////////////////////

delete_tape_file:
        ;
        ; Prepare to delete file on tape, try to look up file
        ;
        LXI         H,filename_str
        LDA         drive_nr
        CALL        CLOCDIR
        RC
        MOV         A,M
        ANA         A
        JNZ         file_not_found
        SHLD        file_entry_data_ptr
        ;
        ; Check attributes of file for delete protection
        ;
        LXI         D,012H
        DAD         D
        LDA         SSWITCH
        CPI         'S'
        JZ          commit_to_delete_tape_file
        MOV         A,M
        ANI         ATTR_F + ATTR_W + ATTR_S
        JNZ         protected_file
commit_to_delete_tape_file:
        ;
        ; Delete tape file: Mark file as inactive
        ;
        LHLD        file_entry_data_ptr
        MVI         M,0FFH
        ;
        ; Wait for tape to be ready to take new commands
        ;
        CALL        CWT
        ;
        ; Set up tape control block and prepare controller for write
        ;
        LDA         drive_nr
        STA         CUNIT
        LHLD        file_entry_data_ptr
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
        JMP         file_deleted


;//////////////////////////////////////////////////////////////////////////////


delete_ibm_ebcdic_file:
        ;
        ; Set read/write pointers to EDBDIC system calls
        ;
        LXI         H,DSRAW
        SHLD        ibm_read_call_ptr
        LXI         H,DSWAW
        JMP         delete_ibm_file


;//////////////////////////////////////

delete_ibm_ascii_file:
        ;
        ; Set read/write pointers to ASCII system calls
        ;
        LXI         H,DSRDW
        SHLD        ibm_read_call_ptr
        LXI         H,DSWRW
delete_ibm_file:
        SHLD        ibm_write_call_ptr
        ;
        ; Parse IBM filename, and following line end or deliminer
        ;
        POP         PSW
        LXI         D,filename_str
        CALL        IBFIL
        RC
        STA         input_char
        CPI         CR
        JZ          valid_ibm_file
        CPI         ','
        JNZ         invalid_input
valid_ibm_file:
        LXI         D,filename_str
        CALL        print_ibm_filename
        RC
        ;
        ; Look up IBM file
        ;
        LXI         B,0*DISK_TRACK + 8*DISK_SECTOR
check_next_ibm_file:
        CALL        read_ibm_sector
        RC
        JNZ         inactive_ibm_file
        LXI         D,filename_str
        CALL        compare_ibm_filename
        JZ          ibm_file_found
inactive_ibm_file:
        INX         B
        MOV         A,C
        CPI         27
        JC          check_next_ibm_file
        JMP         file_not_found

ibm_file_found:
        ;
        ; Set deleted tag and write back to disk
        ;
        LXI         H,BUF2
        MVI         M,'D'
        INX         H
        MVI         M,'D'
        INX         H
        MVI         M,'R'
        INX         H
        MVI         M,'1'
        CALL        write_ibm_sector
        RC
        ;
        ; Convert to deleted sector type
        ;
        LXI         H,DSRDW
        SHLD        ibm_read_call_ptr
        CALL        read_ibm_sector
        RC
        LXI         H,BUF2
        LDA         drive_nr
        CALL        DSDLW
        RC
        JMP         file_deleted


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
        JMP         ibm_disk_operation

        ;
        ; Write IBM sector with the currently selected encoding type
        ;
write_ibm_sector:
        LHLD        ibm_write_call_ptr
ibm_disk_operation:
        LDA         drive_nr
        PUSH        H
        LXI         H,BUF2
        RET


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
        ; Print filename of Intel or Tape file
        ;
print_filename:
        ;
        ; Add drive number to drive designator string and print it
        ;
        LHLD        CO_FCB
        LXI         D,drive_designator
        LDA         drive_nr
        ADI         '0'
        STA         drive_designator+2
        CALL        PUTSTR
        RC
        ;
        ; Print main part of filename
        ;
        LXI         D,filename_str
        MVI         B,6
print_next_filename_char:
        LDAX        D
        ORA         A
        JZ          filename_char_done
        CALL        OUTCHAR
        RC
filename_char_done:
        ;
        ; Advance to next filename character
        ;
        INX         D
        DCR         B
        JNZ         print_next_filename_char
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
        MVI         A,' '
        CALL        OUTCHAR
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print filename of IBM-3740 file
        ;
print_ibm_filename:
        ;
        ; Add drive number to drive designator string and print it
        ;
        PUSH        D
        LHLD        CO_FCB
        LXI         D,drive_designator
        LDA         drive_nr
        ADI         '0'
        STA         drive_designator+2
        CALL        PUTSTR
        POP         D
        RC
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
