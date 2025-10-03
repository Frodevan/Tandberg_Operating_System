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
;//                     A       Floppy (IBM 3740, ASCII), v1.7
;//                     B       Floppy (IBM 3740, ASCII), v1.7
;//                     F       Floppy (Intel ISIS)
;//                     I       Floppy (IBM 3740, EBCDIC), v1.7
;//                     J       Floppy (IBM 3740, EBCDIC), v1.7
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
;//         NOTE: If a file on an IBM-formatted floppy is recovered, no additional
;//               checks are done except for checking for the deleted status when
;//               reading the index record and then matching the filename. No
;//               further checks are done, and if a new data set has re-used parts
;//               of the deleted file's records, you may potentially end up with
;//               two active data-sets containing overlapping records.
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
;//             1.5: Entry at 0xC000
;//
;//                 -> Supports upper case input
;//                 -> Checks for end of directory linking block
;//                 -> Allows for recovery of aliases
;//
;//             1.6: Entry at 0xC000
;//
;//                 -> Version ID written to 0x2700
;//
;//             1.7: Entry at 0xC000
;//
;//                 -> Adds support for IBM formats
;//                 -> More general error reported if invalid drive type
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Flag values
;
TRUE        EQU     -1          ; Boolean True

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
DSRAW       EQU     0007CH      ; Read from disk with wait and translate EBCDIC to ASCII
DSWAW       EQU     0007FH      ; Translate ASCII to EBCDIC and write to disk with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature
ASCI        EQU     0277EH      ; EBCDIC to ASCII translation table reference

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
LOCDIR      EQU     0FD85H      ; Look up filetable entry of filename on disk
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
ERROR_10    EQU     010H        ; NON-VALID DISKETTE COMMAND
ERROR_11    EQU     011H        ; IMPROPER UNIT SPECIFICATION
ERROR_13    EQU     013H        ; DRIVE NUMBER NOT 0-3
ERROR_35    EQU     035H        ; TRACK NUMBER > 76
ERROR_36    EQU     036H        ; SECTOR NUMBER = 0 OR > 26


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'RESCUE'
        DB          '107'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Require command line arguments
        ;
        CALL        get_next_char
        RC
        STA         input_char
        CPI         CR
        JZ          wrong_number_of_args
        ;
        ; Check and parse filename to rescue, with drive designator if provided
        ;
        CPI         ':'
        JNZ         intel_drive_set
        CALL        get_next_char
        RC
        CALL        to_uppercase
        STA         drive_type
        CALL        get_next_char
        RC
        SUI         '0'
        CPI         4
        JNC         invalid_drive_number
        STA         drive_number
        CALL        get_next_char
        RC
        CPI         ':'
        JNZ         invalid_args
        ;
        ; Require a filename after the drive designator
        ;
        CALL        get_next_char
        RC
        CPI         CR
        JZ          wrong_number_of_args
        STA         input_char
        ;
        ; Verify drive type
        ;
        LDA         drive_type
        CPI         'F'
        JZ          intel_drive_set
        CPI         'I'
        JZ          ibm_ebcdic_drive_set
        CPI         'J'
        JZ          ibm_ebcdic_drive_set
        CPI         'A'
        JZ          ibm_ascii_drive_set
        CPI         'B'
        JZ          ibm_ascii_drive_set
        JMP         invalid_args

intel_drive_set:
        LDA         input_char
        LXI         D,filename_str
        CALL        FILENAME
        RC
        ;
        ; Verify that there are no more command line arguments
        ;
        CPI         CR
        JNZ         wrong_number_of_args
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
        CALL        read_from_disk
        RC
        LHLD        linking_block_buffer + 006H
        SHLD        mapfile_block_2_ref
        LXI         D,mapfile_data_buffer + 128
        CALL        read_from_disk
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
        LXI         D,004H
        DAD         D
        SHLD        dir_linking_block_ptr
        MVI         A,25
        STA         dir_block_count
scan_next_directory_block:
        ;
        ; Check if we are at the end of the directory
        ;
        LDA         dir_block_count
        ORA         A
        JZ          directory_scan_done
        ;
        ; Get next data block reference from directory linking block
        ;
        LHLD        dir_linking_block_ptr
        MOV         C,M
        INX         H
        MOV         B,M
        INX         H
        SHLD        dir_linking_block_ptr
        DCR         A
        STA         dir_block_count
        ;
        ; Check if data block reference is set
        ;
        MOV         A,C
        ORA         B
        JZ          directory_scan_done
        ;
        ; Read data block from disk
        ;
        LDA         drive_number
        LXI         H,dir_data_buffer
        CALL        DSRDW
        RC
        SHLD        dir_entry_data_ptr
        ;
        ; Prepare to check all file entries in directory block
        ;
        XRA         A
        STA         dir_entry_counter
        LDA         dir_entry_counter
check_file_entry:
        ;
        ; Check for end of directory block
        ;
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
        STA         dir_entry_counter
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
        MOV         B,H
        MOV         C,L
        LXI         H,dir_data_buffer
        LDA         drive_number
        CALL        DSRDW
        RC
        ;
        ; Determine pointer to entry of file to rescue
        ;
        LDA         file_entry_nr_in_dir_block
        ORA         A
        JZ          file_entry_ptr_ready
        LXI         D,010H
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
        LDA         drive_number
        LXI         H,file_linking_block_buffer
        CALL        DSRDW
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
        ; Check for end of linking block
        ;
        LDA         file_data_block_counter
        ORA         A
        JZ          reserve_next_linking_block
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
        JMP         reserve_next_data_block

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
        CALL        write_to_disk
        RC
        ;
        ; Save updated mapfile data back to disk
        ;
        LHLD        mapfile_block_1_ref
        LXI         D,mapfile_data_buffer
        CALL        write_to_disk
        RC
        LHLD        mapfile_block_2_ref
        LXI         D,mapfile_data_buffer + 128
        CALL        write_to_disk
        RC
        JMP         file_rescue_success


;//////////////////////////////////////////////////////////////////////////////

ibm_ebcdic_drive_set:
        ;
        ; Set up for EBCDIC disk API
        ;
        LXI         H,DSRAW
        SHLD        ibm_read_routine
        LXI         H,DSWAW
        MVI         A,TRUE
        JMP         ibm_mode_set

ibm_ascii_drive_set:
        ;
        ; Set up for regular (ASCII) disk API
        ;
        LXI         H,DSRDW
        SHLD        ibm_read_routine
        LXI         H,DSWRW
        XRA         A
ibm_mode_set:
        SHLD        ibm_write_routine
        STA         ebcdic_format_flag
        ;
        ; Get name of IBM file to recover, and verify no more arguments
        ;
        LDA         input_char
        LXI         D,filename_str
        CALL        IBFIL
        RC
        CPI         CR
        JNZ         wrong_number_of_args
        ;
        ; Start scanning through at start of directory table
        ;
        LXI         B,0*DISK_TRACK + 8*DISK_SECTOR
check_ibm_directory_record:
        ;
        ; Get file entry
        ;
        CALL        read_from_ibm_disk
        RC
        JZ          check_next_ibm_directory_record
        ;
        ; Compare file entry filename with filename of file to rescue
        ;
        LXI         D,filename_str
        LXI         H,dir_data_buffer + 5
        PUSH        B
        MVI         C,8
compare_next_ibm_filename_char:
        LDAX        D
        CMP         M
        JNZ         ibm_file_not_match
        INX         H
        INX         D
        DCR         C
        JNZ         compare_next_ibm_filename_char
        ;
        ; File found, undelete it right away
        ;
        LXI         H,dir_data_buffer
        MVI         M,'H'
        INX         H
        MVI         M,'D'
        INX         H
        MVI         M,'R'
        INX         H
        MVI         M,'1'
        POP         B
        ;
        ; Write changes to disk, and print status
        ;
        CALL        write_to_ibm_disk
        RC
        CALL        print_ibm_filename
        RC
        LXI         D,reclaimed_str
        JMP         print_and_quit

ibm_file_not_match:
        POP         B
check_next_ibm_directory_record:
        ;
        ; Check for end of directory, and advance to next record
        ;
        MOV         A,C
        CPI         26
        JNC         ibm_file_not_found
        INR         C
        JMP         check_ibm_directory_record

ibm_file_not_found:
        CALL        print_ibm_filename
        RC
        LXI         D,not_found_str
        JMP         print_and_quit


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
        MOV         C,M
        INX         H
        MOV         B,M
        LDA         drive_number
        LXI         H,linking_block_buffer
        CALL        DSRDW
        RET


;//////////////////////////////////////

        ;
        ; Read block HL from floppy to buffer at DE
        ;
read_from_disk:
        MOV         B,H
        MOV         C,L
        XCHG
        LDA         drive_number
        CALL        DSRDW
        RET


;//////////////////////////////////////

        ;
        ; Write buffer at DE to block HL on floppy
        ;
write_to_disk:
        MOV         B,H
        MOV         C,L
        XCHG
        LDA         drive_number
        CALL        DSWRW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read record from IBM disk, using previously selected read API call
        ;
read_from_ibm_disk:
        LHLD        ibm_read_routine
        CALL        do_ibm_disk_operation
        JC          check_ibm_read_status
        XRA         A
        RET

check_ibm_read_status:
        ;
        ; Check for deleted record status
        ;
        CPI         020H
        STC
        RNZ
        ;
        ; Check if deleted sector needs to be converted from EBCDIC to ASCII
        ;
        LDA         ebcdic_format_flag
        ANA         A
        JZ          ibm_deleted_sector_ready
        ;
        ; Locally translate deleted sector to ASCII if EBCDIC-format is assumed
        ;
        PUSH        B
        PUSH        D
        PUSH        H
        LXI         H,dir_data_buffer
        MVI         B,128
        MVI         D,000H
convert_deleted_sector:
        MOV         E,M
        PUSH        H
        LHLD        ASCI
        DAD         D
        MOV         A,M
        POP         H
        MOV         M,A
        INX         H
        DCR         B
        JNZ         convert_deleted_sector
        POP         H
        POP         D
        POP         B
        ;
        ; Data of deleted sector ready
        ;
ibm_deleted_sector_ready:
        MVI         A,020H
        ANA         A
        RET


;//////////////////////////////////////

        ;
        ; Write record to IBM disk, using previously selected write API call
        ;
write_to_ibm_disk:
        LHLD        ibm_write_routine
do_ibm_disk_operation:
        LDA         drive_number
        PUSH        H
        LXI         H,dir_data_buffer
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

        ;
        ; Returns the next character from console input in A
        ;
get_next_char:
        PUSH        H
        LHLD        CI_FCB
        CALL        INCHAR
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prints character in A to console output
        ;
print_char:
        PUSH        H
        LHLD        CO_FCB
        CALL        OUTCHAR
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Check if character in A is an uppercase letter
        ;
is_uppercase_letter:
        CPI         'A'
        RC
        CPI         'Z'+1
        CMC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clears B bytes starting at HL
        ;
clear_memory:
        PUSH        H
clear_next_byte:
        MVI         M,000H
        INX         H
        DCR         B
        JNZ         clear_next_byte
        POP         H
        RET


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

        ;
        ; Print the name of file to be rescued, with its drive designator
        ;
print_filename:
        ;
        ; Set and print drive designator of file to use
        ;
        LDA         drive_number
        ADI         '0'
        STA         drive_designator_str + 2
        LHLD        CO_FCB
        LXI         D,drive_designator_str
        CALL        PUTSTR
        ;
        ; Prepare filename for printing as string, and check for file extension
        ;
        MVI         A,CR
        STA         filename_str + 9
        LXI         H,filename_str + 6
        XRA         A
        ORA         M
        LXI         D,filename_str
        JZ          filename_print_last_part
        ;
        ; Filename has an extension, so print name and ext deliminator first
        ;
        MOV         C,M
        MVI         M,CR
        PUSH        H
        LHLD        CO_FCB
        CALL        PUTSTR
        POP         H
        MVI         A,'.'
        CALL        print_char
        RC
        MOV         M,C
        ;
        ; Then print file extension
        ;
        XCHG
filename_print_last_part:
        LHLD        CO_FCB
        CALL        PUTSTR
        RET


;//////////////////////////////////////////////////////////////////////////////

print_ibm_filename:
        ;
        ; Set and print drive designator of file
        ;
        MVI         A,CR
        STA         filename_str + 8
        LDA         drive_type
        STA         drive_designator_str + 1
        LDA         drive_number
        ADI         '0'
        STA         drive_designator_str + 2
        LXI         D,drive_designator_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC
        LXI         D,filename_str
        CALL        PUTSTR
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
flush_next_char:
        CPI         CR
        JZ          flush_done
        CALL        get_next_char
        RC
        JMP         flush_next_char

flush_done:
        MOV         A,B
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

no_file_to_rescue:
        CALL        print_filename
        LXI         D,not_found_str
        JMP         print_and_quit


;//////////////////////////////////////

file_rescue_failed:
        CALL        print_filename
        LXI         D,lost_str
        JMP         print_and_quit


;//////////////////////////////////////

file_rescue_success:
        CALL        print_filename
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

drive_number:
        DB          0
mapfile_block_1_ref:
        DS          2
mapfile_block_2_ref:
        DS          2
dir_linking_block_ptr:
        DS          2
dir_block_count:
        DS          1
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

        DS          2

drive_type:
        DS          1
input_char:
        DS          1
ibm_read_routine:
        DS          2
ibm_write_routine:
        DS          2
ebcdic_format_flag:
        DS          1

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

not_found_str:
        DB          '  NOT FOUND',CR
lost_str:
        DB          '  LOST',CR
reclaimed_str:
        DB          '  RECLAIMED',CR
