;//////////////////////////////////////////////////////////////////////////////
;//
;//     RESCUE - Recover recently deleted file
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<filename>
;//
;//                 Tn          Drive type and number, default :F0:
;//                 filename    File to undelete
;//
;//                 Drive type T:
;//                     F       Floppy (Intel ISIS)
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         Undeletes a file that has recently been deleted from a floppy. Some
;//         rudimentary checks are done to make sure the file is sound: That there
;//         is at least one deleted file-entry for the file, that the corresponding
;//         linking block structure for this deleted file points to valid sectors
;//         on the disk, and that none of the blocks to be undeleted are already
;//         marked as used in ISIS.MAP. If all requirements are met, the file is
;//         undeleted in its place and the directory table and mapfile are updated
;//         accordingly.
;//
;//         Should there be several deleted directory-entries for a file, the last
;//         occurence of such an entry will be used.
;//
;//         NOTE: There is a chance that parts of the file may have been written
;//               over by more recent files which has since been deleted. The tool
;//               will not check for this, so there is no guarantees if RESCUE is
;//               run on a file which is not recently deleted if the disk has
;//               been written to afterwards. File content should be verified by
;//               other means even in the case this tool reports a success.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the wrong error code is returned if the
;//                    command line arguments are invalid
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
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
LOCDIR      EQU     0FD85H      ; Look up filetable entry of filename on disk
FILENAME    EQU     0FDCDH      ; Input TOS filename

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_10    EQU     010H        ; NON-VALID DISKETTE COMMAND
ERROR_11    EQU     011H        ; IMPROPER UNIT SPECIFICATION
ERROR_13    EQU     013H        ; DRIVE NUMBER NOT 0-3
ERROR_1D    EQU     01DH        ; COMMAND UNIT NOT :FN: OR :MN:
ERROR_35    EQU     035H        ; TRACK NUMBER > 76
ERROR_36    EQU     036H        ; SECTOR NUMBER = 0 OR > 26

;
; TOS file attributes
;
ATTR_A      EQU     008H        ; Alias file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Check and parse filename to rescue, with drive designator if provided
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         drive_set
        CALL        INCHAR
        RC
        CPI         'F'
        JNZ         invalid_drive_type
        CALL        INCHAR
        RC
        SUI         '0'
        CPI         4
        JNC         invalid_drive_number
        STA         drive_number
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_args
        CALL        INCHAR
        RC
drive_set:
        LXI         D,filename_str
        CALL        FILENAME
        RC
        ;
        ; Verify that there are no more command line arguments
        ;
        CPI         CR
        JNZ         wrong_number_of_args
        ;
        ; Set and print drive designator of file to use
        ;
        LDA         drive_number
        ADI         '0'
        STA         drive_designator_str + 2
        LXI         D,drive_designator_str
        LHLD        CO_FCB
        CALL        PUTSTR
        ;
        ; Prepare filename for printing as string, and check for file extension
        ;
        MVI         A,CR
        STA         filename_str + 9
        LDA         filename_str + 6
        ORA         A
        LXI         D,filename_str
        JZ          filename_print_last_part
        ;
        ; Filename has an extension, so print name and ext deliminator first
        ;
        MOV         C,A
        MVI         A,CR
        STA         filename_str + 6
        CALL        PUTSTR
        MVI         A,'.'
        CALL        OUTCHAR
        RC
        MOV         A,C
        ;
        ; Then print file extension
        ;
        LXI         D,filename_str + 6
        STAX        D
filename_print_last_part:
        CALL        PUTSTR
        ;
        ; Load mapfile linking block
        ;
        LXI         H,mapfile_name
        CALL        get_file_linking_block
        RC
        ;
        ; Load mapfile into buffer, using data block refs from linking block
        ;
        LHLD        linking_block_buffer + 004H
        SHLD        mapfile_block_1_ref
        LXI         D,mapfile_data_buffer
        CALL        disk_read_ref_from_reg
        RC
        LHLD        linking_block_buffer + 006H
        SHLD        mapfile_block_2_ref
        LXI         D,mapfile_data_buffer + 128
        CALL        disk_read_ref_from_reg
        RC
        ;
        ; Load directory filetable file linking block
        ;
        LXI         H,dir_filename
        CALL        get_file_linking_block
        RC
        ;
        ; Scan through directory, looking for deleted file to be rescued
        ;
scan_next_directory_block:
        ;
        ; Check if we are at the end of the directory
        ;
        LDA         dir_block_count
        ORA         A
        JZ          directory_scan_done
        ;
        ; Get next data block of directory using block refs from linking block
        ;
        DCR         A
        STA         dir_block_count
        LHLD        dir_linking_block_ptr
        LXI         D,dir_data_buffer
        CALL        disk_read_ref_from_ptr
        RC
        SHLD        dir_entry_data_ptr
        XCHG
        SHLD        dir_linking_block_ptr
        ;
        ; Prepare to check all file entries in directory block
        ;
        XRA         A
check_file_entry:
        ;
        ; Check for end of directory block
        ;
        STA         dir_entry_counter
        CPI         8
        JZ          scan_next_directory_block
        ;
        ; Save variables and point to filename string and file entry
        ;
        PUSH        B
        MOV         C,A
        LXI         D,filename_str
        LHLD        dir_entry_data_ptr
        ;
        ; Check if file is marked as deleted
        ;
        MVI         A,0FFH
        CMP         M
        JNZ         file_check_verdict_found
        ;
        ; If so, compare filename with name of file to rescure
        ;
        INX         H
        MVI         B,9
compare_next_filename_char:
        LDAX        D
        CMP         M
        JNZ         file_check_verdict_found
        INX         H
        INX         D
        DCR         B
        JNZ         compare_next_filename_char
        ;
        ; Check attribute, don't rescue aliases
        ;
        MVI         A,ATTR_A
        ANA         M
file_check_verdict_found:
        ;
        ; Recover variables from previously and act on file-check verdict
        ;
        MOV         A,C
        POP         B
        JNZ         check_next_file_entry
        ;
        ; File to recover found, save info to get back to it later
        ;
        MOV         H,B
        MOV         L,C
        SHLD        file_entry_dir_block_ref
        STA         file_entry_nr_in_dir_block
check_next_file_entry:
        ;
        ; Advance to next directory entry
        ;
        LHLD        dir_entry_data_ptr
        LXI         D,010H
        DAD         D
        SHLD        dir_entry_data_ptr
        INR         A
        JMP         check_file_entry


;//////////////////////////////////////////////////////////////////////////////

directory_scan_done:
        ;
        ; Check if a file to rescue was found
        ;
        LHLD        file_entry_dir_block_ref
        MOV         A,L
        ORA         H
        JZ          no_file_to_rescue
        ;
        ; Read directory data-block with file to rescue
        ;
        LXI         D,dir_data_buffer
        CALL        disk_read_ref_from_reg
        RC
        ;
        ; Determine pointer to entry of file to rescue
        ;
        LDA         file_entry_nr_in_dir_block
        ORA         A
        LXI         D,010H
        JZ          file_entry_ptr_ready
point_to_next_entry:
        DAD         D
        DCR         A
        JNZ         point_to_next_entry
file_entry_ptr_ready:
        SHLD        dir_entry_data_ptr
        ;
        ; Set file status to active
        ;
        MVI         M,000H
        ;
        ; Get linking block reference of rescued file
        ;
        DCX         D
        DAD         D
        MOV         B,M
        DCX         H
        MOV         C,M
reserve_linking_block:
        ;
        ; Reserve linking block itself in mapfile
        ;
        CALL        mark_block_in_mapfile
        RC
        JNZ         file_rescue_failed
        ;
        ; Read current linking block from disk
        ;
        LXI         D,file_linking_block_buffer
        CALL        disk_read_ref_prepared
        RC
        ;
        ; Save ref to next linking block in chain, and current block pointer
        ;
        INX         H
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        SHLD        file_current_linking_block_ptr
        XCHG
        SHLD        file_next_linking_block_ref
        ;
        ; Prepare to reserve all data-blocks defined by current linking block
        ;
        MVI         A,62
        STA         file_data_block_counter
reserve_next_data_block:
        ;
        ; Get next data-block reference from linking block
        ;
        LHLD        file_current_linking_block_ptr
        MOV         C,M
        INX         H
        MOV         B,M
        INX         H
        SHLD        file_current_linking_block_ptr
        DCR         A
        STA         file_data_block_counter
        ;
        ; Verify that data-block reference is in use
        ;
        MOV         A,C
        ORA         B
        JZ          reserve_next_linking_block
        ;
        ; If so, reserve data-block in mapfile
        ;
        CALL        mark_block_in_mapfile
        RC
        JNZ         file_rescue_failed
        ;
        ; Check for end of linking block
        ;
        LDA         file_data_block_counter
        ORA         A
        JNZ         reserve_next_data_block
reserve_next_linking_block:
        ;
        ; Advance to next linking block in chain
        ;
        LHLD        file_next_linking_block_ref
        MOV         B,H
        MOV         C,L
        ;
        ; Check for last linking block
        ;
        MOV         A,L
        ORA         H
        JNZ         reserve_linking_block
        ;
        ; If so, save updated file table entry back to disk
        ;
        LHLD        file_entry_dir_block_ref
        LXI         D,dir_data_buffer
        CALL        disk_write_ref_from_reg
        RC
        ;
        ; Save updated mapfile data back to disk
        ;
        LHLD        mapfile_block_1_ref
        LXI         D,mapfile_data_buffer
        CALL        disk_write_ref_from_reg
        RC
        LHLD        mapfile_block_2_ref
        LXI         D,mapfile_data_buffer + 128
        CALL        disk_write_ref_from_reg
        RC
        JMP         file_rescue_success


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read linking block of file with filename pointed to by DE into buffer
        ;
get_file_linking_block:
        LDA         drive_number
        CALL        LOCDIR
        RC
        LXI         D,00EH
        DAD         D
        LXI         D,linking_block_buffer


;//////////////////////////////////////

        ;
        ; Read block with reference at HL from floppy to buffer at DE
        ;
disk_read_ref_from_ptr:
        MOV         C,M
        INX         H
        MOV         B,M
        INX         H
        ;
        ; Read block BC from floppy to buffer at DE
        ;
disk_read_ref_prepared:
        CALL        get_drive_nr
disk_read_call:
        CALL        DSRDW
        RET


;//////////////////////////////////////

        ;
        ; Read block HL from floppy to buffer at DE
        ;
disk_read_ref_from_reg:
        CALL        prepare_disk_ref_from_reg
        JMP         disk_read_call


;//////////////////////////////////////

        ;
        ; Write buffer at DE to block HL on floppy
        ;
disk_write_ref_from_reg:
        CALL        prepare_disk_ref_from_reg
        CALL        DSWRW
        RET


;//////////////////////////////////////

        ;
        ; Translate register-use between local subroutines and XMON floppy API
        ;
prepare_disk_ref_from_reg:
        MOV         B,H
        MOV         C,L
get_drive_nr:
        XCHG
        LDA         drive_number
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Mark block as used in the mapfile, after verifying that it is free
        ;
mark_block_in_mapfile:
        ;
        ; Verify that track number of block reference is within range 0-76
        ;
        MOV         A,B
        CPI         77
        CMC
        MVI         A,ERROR_35
        RC
        ;
        ; Verify that sector number of block reference is within range 1-26
        ;
        MOV         A,C
        CPI         1
        MVI         A,ERROR_36
        RC
        MOV         A,C
        CPI         27
        CMC
        MVI         A,ERROR_36
        RC
        ;
        ; Reserve block in mapfile pt1: Multiply track nr with 26
        ;
        PUSH        B
        MVI         H,000H
        MOV         L,B
        DAD         H
        PUSH        H
        DAD         H
        DAD         H
        PUSH        H
        DAD         H
        POP         D
        DAD         D
        POP         D
        DAD         D
        ;
        ; Reserve block in mapfile pt2: Add sector nr - 1 to get map bit index
        ;
        MVI         D,000H
        MOV         E,C
        DAD         D
        DCX         H
        ;
        ; Reserve block in mapfile pt3: Modulus index by 8 to get bit nr
        ;
        MOV         A,L
        ANI         007H
        MOV         C,A
        ;
        ; Reserve block in mapfile pt4: Divide index by 8 to get byte nr
        ;
        MOV         A,H
        RLC
        RLC
        RLC
        RLC
        RLC
        ANI         0E0H
        MOV         B,A
        MOV         A,L
        RRC
        RRC
        RRC
        ANI         01FH
        ORA         B
        MOV         L,A
        MOV         A,H
        RRC
        RRC
        RRC
        ANI         01FH
        MOV         H,A
        ;
        ; Reserve block in mapfile pt5: Set up pointer and bit mask
        ;
        LXI         D,mapfile_data_buffer
        DAD         D
        INR         C
        MVI         A,080H
shift_bitmask_loop:
        DCR         C
        JZ          bitmask_ready
        RRC
        ANI         07FH
        JMP         shift_bitmask_loop

bitmask_ready:
        ;
        ; Reserve block in mapfile pt6a: Verify that the block is free
        ;
        MOV         C,A
        ANA         M
        MOV         A,C
        POP         B
        RNZ
        ;
        ; Reserve block in mapfile pt6b: Mark block as reserved
        ;
        ORA         M
        MOV         M,A
        XRA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

invalid_drive_number:
        MVI         B,ERROR_13
        JMP         quit_with_error


;//////////////////////////////////////

invalid_args:
        MVI         B,ERROR_11
        JMP         quit_with_error


;//////////////////////////////////////

invalid_drive_type:
        MVI         B,ERROR_1D
        JMP         quit_with_error


;//////////////////////////////////////

wrong_number_of_args:
        MVI         B,ERROR_10


;//////////////////////////////////////

        ;
        ; Exit with error code from parsing the command line arguments
        ;
quit_with_error:
        ;
        ; Flush remaining command line arguments
        ;
        LHLD        CI_FCB
flush_next_char:
        CPI         CR
        JZ          flush_done
        CALL        INCHAR
        RC
        JMP         flush_next_char

flush_done:
        MOV         A,B
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

no_file_to_rescue:
        LXI         D,not_found_str
        JMP         print_and_quit


;//////////////////////////////////////

file_rescue_failed:
        LXI         D,lost_str
        JMP         print_and_quit


;//////////////////////////////////////

file_rescue_success:
        LXI         D,reclaimed_str


;//////////////////////////////////////

print_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

drive_designator_str:
        DB          ':F0:',CR
not_found_str:
        DB          '  NOT FOUND',CR
lost_str:
        DB          '  LOST',CR
reclaimed_str:
        DB          '  RECLAIMED',CR
        DB          '  ALREADY EXISTS',CR

drive_number:
        DB          0
mapfile_block_1_ref:
        DS          2
mapfile_block_2_ref:
        DS          2
dir_linking_block_ptr:
        DW          linking_block_buffer + 004H
dir_block_count:
        DB          25
dir_entry_data_ptr:
        DS          2
dir_entry_counter:
        DS          1
file_current_linking_block_ptr:
        DS          2
file_next_linking_block_ref:
        DS          2
file_data_block_counter:
        DS          1
file_entry_dir_block_ref:
        DW          00000H
file_entry_nr_in_dir_block:
        DS          1

dir_filename:
        DB          'ISIS',NULL,NULL
        DB          'DIR'
mapfile_name:
        DB          'ISIS',NULL,NULL
        DB          'MAP'

linking_block_buffer:
        DS          128
dir_data_buffer:
        DS          128
file_linking_block_buffer:
        DS          128
mapfile_data_buffer:
        DS          256
filename_str:
        DS          9+1
