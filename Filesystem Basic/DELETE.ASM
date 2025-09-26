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
;//                     F       Floppy
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
LOCDIRX     EQU     00085H      ; Look up filetable entry of filename on disk
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
DSRDW       EQU     0FD73H      ; Read from disk with wait
DSWRW       EQU     0FD76H      ; Write to disk with wait
LOCDIR      EQU     0FD85H      ; Look up filetable entry of filename on disk
FILENAME    EQU     0FDCDH      ; Input TOS filename
RELN        EQU     0FDD3H      ; Release next N blocks from linking block
RELBLK      EQU     0FDD6H      ; Release a single block on current Intel disk

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
ATTR_A      EQU     008H        ; Alias file
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
        JMP         LOCDIRX


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

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

beginning:
        ;
        ; Reset drive number base offset, assume floppy as default
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
parse_filename:
        ;
        ; Parse filename, and following line end or deliminer
        ;
        LXI         D,filename_str
        CALL        FILENAME
        RC
        CPI         CR
        JZ          valid_filename_input
        CPI         ','
        JNZ         invalid_input
valid_filename_input:
        STA         input_char
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
        STA         drive_designator+1
        ;
        ; Print full filename with drive designator
        ;
        CALL        print_filename
        RC
        ;
        ; Check drive type for deletion algorithm
        ;
        LXI         H,filename_str
        LDA         drive_nr
        CPI         4
        JP          delete_tape_file
        ;
        ; Prepare to delete file on intel-type floppy disk, try to look up file
        ;
        CALL        look_up_intel_file
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
        LHLD        CO_FCB
file_deleted:
        LXI         D,deleted_str
        JMP         file_done
file_not_found:
        LXI         D,not_found_str
file_done:
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Reset tape drive, if used
        ;
        LDA         drive_nr
        CPI         4
        JM          ready_for_next_file
        SUI         4
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

potentially_invalid_drive:
        CPI         'M'
        JZ          setup_for_tape_file
        LXI         D,improper_unit_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

invalid_input:
        LXI         D,improper_params_str
        LHLD        CO_FCB
        CALL        PUT
        RET


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


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print filename of Intel or Tape file
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
        STA         drive_designator+2
        LXI         D,drive_designator
        CALL        PUTSTR
        ;
        ; Print main part of filename
        ;
        LXI         D,filename_str
        MVI         B,6
print_next_filename_char:
        LDAX        D
        CPI         NULL
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
        MVI         A,' '
        CALL        OUTCHAR
        RET


;//////////////////////////////////////////////////////////////////////////////

setup_for_tape_file:
        ;
        ; Drive IDs for tape starts at 4 here, so set base offset
        ;
        MVI         A,4
        STA         drive_nr
        JMP         valid_drive_type


;//////////////////////////////////////

delete_tape_file:
        ;
        ; Prepare to delete file on tape, try to look up file
        ;
        SUI         4
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
        SUI         4
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
