;//////////////////////////////////////////////////////////////////////////////
;//
;//     DELETE - Delete files and aliases
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<filename>[,[:<Tn>:]<filename>[,[:<Tn>:]<filename>[...]]]
;//
;//                 Tn          Drive type and number, default :D0:
;//                 filename    File to delete
;//
;//                 Drive type T:
;//                     D       Floppy, TOS double-sided double-density
;//                     F       Floppy, TOS single-sided single-density
;//                     I       Floppy, IBM 3740 double-sided double-density
;//                     J       Floppy, IBM 3740 single-sided single-density
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         This tool is used to delete files and aliases. If an alias is deleted,
;//         the file data will still be accessible through the original file and
;//         any eventual other aliases.
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
;//             1.5a: Entry at 0xC000
;//
;//                 -> Adds support for A and I drive types
;//                 -> Major rewrite in code for parsing and storing drive type
;//                 -> Fixes file-extension deliminer bug from v1.2
;//                 -> Fixes the v1.2 mapfile bug
;//                 -> Flushes excess input on exit
;//
;//             1.5b: Entry at 0xC111
;//
;//                 -> Recognizes B and J as valid drive types
;//                 -> Introduces a bug where drive types B and J are reported to
;//                    the user as type A and I respectively
;//
;//             1.6a: Entry at 0xC0AD
;//
;//                 -> Reverts all changes from v1.5b
;//                 -> Version ID written to 0x2700
;//
;//             1.6b: Entry at 0xC0AD
;//
;//                 -> Re-introduces support for the B and J drive types without
;//                    the bug in v1.5b
;//
;//             2.0a: Entry at 0x292D
;//
;//                 -> Removes support for tape drive
;//                 -> Adds support for double-sided drive types, allthough double-
;//                    sided IBM format is recognized but not implemented
;//                 -> Changes default drive to :D0:
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
; XMON system calls
;
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
DSDLW       EQU     00079H      ; Write deleted to disk with wait
DSRAW       EQU     0007CH      ; Read from disk with wait and translate EBCDIC to ASCII
DSWAW       EQU     0007FH      ; Translate ASCII to EBCDIC and write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
DDSRDW      EQU     00097H      ; Read from double-sided disk with wait
DDSWRW      EQU     0009AH      ; Write to double-sided disk with wait
DLOCDIR     EQU     000CDH      ; Look up filetable entry of filename on double-sided disk

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SIGNATURE   EQU     02700H      ; Program signature
SSWITCH     EQU     0272CH      ; TOS system switch
TRK         EQU     02731H      ; Pointer to block address of next directory data block
MAP1        EQU     02739H      ; Block address of first half of mapfile data
MAP2        EQU     0273BH      ; Block address of last half of mapfile data

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
DFILENAME   EQU     0FDBBH      ; Input TOS filename for double-sided disk
DRELN       EQU     0FDBEH      ; Release next N blocks from linking block on double-sided disk
DRELBLK     EQU     0FDC1H      ; Release a single block on current double-sided disk
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
ERROR_38    EQU     038H        ; ROUTINE NOT AVAILABLE
ERROR_5B    EQU     05BH        ; IMPROPER VOLUME FORMAT

;
; TOS file attributes
;
ATTR_S      EQU     002H        ; System file
ATTR_W      EQU     004H        ; Write-protected file
ATTR_F      EQU     080H        ; Format file

;
; TOS-II file attributes byte 1
;
ATTR_S_DSDD EQU     004H        ; System file
ATTR_W_DSDD EQU     040H        ; Write-protected file

;
; TOS-II file attributes byte 3
;
ATTR_F_DSDD EQU     020H        ; Format file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DELETE'
        DB          '200'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02800H
ibm_read_call_ptr:
        DW          00000H
ibm_write_call_ptr:
        DW          00000H
file_entry_data_ptr:
        DW          00000H
linking_block_track_sector:
        DW          00000H
drive_nr:
        DB          0
filename_str:
        DS          13
input_char:
        DB          NULL
tos_dsdd_signature:
        DB          'TANDBERG'
mapfile_name:
        DB          'ISIS',NULL,NULL
        DB          'MAP'

drive_designator:
        DB          ':D0:',CR

data_buffer:
        DS          256


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Initialization
;//
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
prune_leading_spaces_loop:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          prune_leading_spaces_loop
        ;
        ; Expect some arguments
        ;
        CPI         CR
        RZ
        STA         input_char
        ;
        ; Check for custom drive designator specified, and set up drive type
        ;
        CPI         ':'
        JNZ         delete_tos_dsdd_file
        CALL        INCHAR
        RC
        CALL        to_uppercase
        STA         input_char
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
        STA         input_char
        LDA         drive_designator+1
        CPI         'D'
        JZ          delete_tos_dsdd_file
        CPI         'F'
        JZ          delete_tos_sssd_file
        CPI         'I'
        JZ          delete_ibm_dsdd_file
        CPI         'J'
        JZ          delete_ibm_sssd_file
        JMP         invalid_drive


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Double-sided TOS disk file
;//
;//////////////////////////////////////////////////////////////////////////////

delete_tos_dsdd_file:
        ;
        ; Parse filename, and following line end or deliminer
        ;
        LDA         input_char
        LXI         D,filename_str
        CALL        DFILENAME
        RC
        STA         input_char
        CPI         CR
        JZ          d_valid_filename_input
        CPI         ','
        JNZ         invalid_input
d_valid_filename_input:
        ;
        ; Get TOS-II double-density disk format signature tag
        ;
        LXI         H,data_buffer
        LXI         B,1*DISK_TRACK + 26*DISK_SECTOR
        LDA         drive_nr
        CALL        DDSRDW
        RC
        LXI         D,data_buffer + 011H
        ;
        ; Verify format signature
        ;
        LXI         H,tos_dsdd_signature
        MVI         B,8
compare_next_signature_char:
        LDAX        D
        CMP         M
        MVI         A,ERROR_5B
        STC
        RNZ
        INX         H
        INX         D
        DCR         B
        JNZ         compare_next_signature_char
        ;
        ; Print full filename with drive designator
        ;
        CALL        print_filename
        RC
        ;
        ; Store track and sector of mapfile data blocks
        ;
        LXI         H,1*DISK_TRACK + 1*DISK_SECTOR
        SHLD        MAP1
        LXI         H,1*DISK_TRACK + 2*DISK_SECTOR
        SHLD        MAP2
        ;
        ; try to look up file
        ;
        LXI         H,filename_str
        LDA         drive_nr
        CALL        DLOCDIR
        RC
        MOV         A,M
        ANA         A
        JNZ         file_not_found
        SHLD        file_entry_data_ptr
        ;
        ; Check attributes of file for delete protection
        ;
        LXI         D,00EH
        DAD         D
        LDA         SSWITCH
        CPI         'S'
        JZ          d_commit_to_delete_intel_file
        MOV         A,M
        ANI         ATTR_W_DSDD + ATTR_S_DSDD
        JNZ         d_protected_file
        INX         H
        INX         H
        MOV         A,M
        ANI         ATTR_F_DSDD
        JNZ         d_protected_file
d_commit_to_delete_intel_file:
        ;
        ; Delete normal file: Mark file as inactive and get linking block
        ;
        LHLD        file_entry_data_ptr
        MVI         M,0FFH
        LXI         D,01EH
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
        CALL        DDSWRW
        RC
        ;
        ; Free up all blocks previously reserved by the deleted file
        ;
d_free_next_linking_block:
        ;
        ; Read next linking block in chain
        ;
        MOV         B,D
        MOV         C,E
        LDA         drive_nr
        LXI         H,data_buffer
        CALL        DDSRDW
        RC
        ;
        ; Release the linking block itself
        ;
        CALL        DRELBLK
        RC
        ;
        ; Release all blocks in the linking block
        ;
        LXI         H,data_buffer+4
        MVI         A,62
        CALL        DRELN
        RC
        ;
        ; Get track and sector of the next linking block
        ;
        LHLD        data_buffer+2
        MOV         A,H
        ORA         L
        XCHG
        JNZ         d_free_next_linking_block
        ;
        ; Print status after deletion
        ;
        JMP         file_deleted


;//////////////////////////////////////

d_protected_file:
        LXI         D,protected_str
        JMP         file_done


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Single-sided TOS disk file
;//
;//////////////////////////////////////////////////////////////////////////////

delete_tos_sssd_file:
        ;
        ; Parse filename, and following line end or deliminer
        ;
        LDA         input_char
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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Double-sided IBM disk file
;//
;//////////////////////////////////////////////////////////////////////////////

delete_ibm_dsdd_file:
        MVI         A,ERROR_38
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Single-sided IBM disk file
;//
;//////////////////////////////////////////////////////////////////////////////

delete_ibm_sssd_file:
        ;
        ; Parse IBM filename, and following line end or deliminer
        ;
        LDA         input_char
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
        LDA         drive_nr
        LXI         H,BUF2
        CALL        DSRAW
        JNC         active_ibm_file
        CPI         ERROR_20
        STC
        RNZ
        JMP         inactive_ibm_file

active_ibm_file:
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
        LDA         drive_nr
        LXI         H,BUF2
        CALL        DSWAW
        RC
        ;
        ; Convert to deleted sector type
        ;
        LDA         drive_nr
        LXI         H,BUF2
        CALL        DSRDW
        JNC         ibm_mark_deleted
        CPI         ERROR_20
        STC
        RNZ
ibm_mark_deleted:
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
        ; Go delete next file if more
        ;
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
        JZ          filename_chars_done
        CALL        OUTCHAR
        RC
        ;
        ; Advance to next filename character
        ;
        INX         D
        DCR         B
        JNZ         print_next_filename_char
filename_chars_done:
        ;
        ; Point to start of file extension
        ;
        MOV         C,B
        MVI         B,3
        LXI         D,filename_str+6
        LDA         drive_designator+1
        CPI         'D'
        JNZ         print_file_extension
        INX         D
        INX         D
print_file_extension:
        ;
        ; Skip filename extension delimer if no extension
        ;
        LDAX        D
        ORA         A
        JZ          file_extension_done
        ;
        ; Print filename extension
        ;
        MVI         A,'.'
        CALL        OUTCHAR
        RC
print_next_file_ext_char:
        LDAX        D
        ORA         A
        JZ          file_extension_done
        CALL        OUTCHAR
        RC
        ;
        ; Advance to next filename extension character
        ;
        INX         D
        DCR         B
        JNZ         print_next_file_ext_char
file_extension_done:
        ;
        ; Pad out the rest of the filename print with spaces
        ;
        MOV         A,C
        ADD         B
        INR         A
        MOV         B,A
pad_filename_print_loop:
        MVI         A,' '
        CALL        OUTCHAR
        RC
        DCR         B
        JNZ         pad_filename_print_loop
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


;//////////////////////////////////////////////////////////////////////////////

to_uppercase:
        CPI         'a'
        RM
        CPI         'z'+1
        RP
        ANI         0DFH
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

not_found_str:
        DB          'NOT FOUND',CR
deleted_str:
        DB          'DELETED',CR
protected_str:
        DB          'PROTECTED',CR
improper_unit_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
improper_params_str:
        DB          'IMPROPER PARAMETER LIST',CR
