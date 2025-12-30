;//////////////////////////////////////////////////////////////////////////////
;//
;//     REMAP - Regenerate sector map file
;//
;//         Extra parameters:
;//
;//             [$:<Tn>:]
;//
;//                 Tn          Drive type and number, default :F0:
;//
;//                 Drive type T:
;//                     F       Floppy
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         Regenerates the ISIS.MAP file based on the blocks allocated to all the
;//         files currently present in the file directory. This tool will reverse
;//         any manual alteration to ISIS.MAP, for instances sector-reservations
;//         done by tools like DROP.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where a file entry with no linking block will skip
;//                    mapping the remaining entries of the current block of the
;//                    directory
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> Accepts lowercase input
;//                 -> Adds a status print after remapping is done
;//
;//             1.6: Entry at 0xC000
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
NULL        EQU     000H        ; Null character
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
LOCDIR      EQU     0FD85H      ; Look up filetable entry of filename on disk

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_11    EQU     011H        ; IMPROPER UNIT SPECIFICATION
ERROR_13    EQU     013H        ; DRIVE NUMBER NOT 0-3
ERROR_1D    EQU     01DH        ; COMMAND UNIT NOT :FN: OR :MN:
ERROR_35    EQU     035H        ; TRACK NUMBER > 76
ERROR_36    EQU     036H        ; SECTOR NUMBER = 0 OR > 26


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'REMAP',NULL
        DB          '106'


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
;//     Filenames
;//
;//////////////////////////////////////////////////////////////////////////////

dirfile_name_str:
        DB          'ISIS',NULL,NULL
        DB          'DIR'

mapfile_name_str:
        DB          'ISIS',NULL,NULL
        DB          'MAP'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Check if a drive designator has been provided as a command line arg
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JZ          use_default_drive
        ;
        ; Verify custom drive designator to be a valid Intel type device
        ;
        CPI         ':'
        JNZ         invalid_input
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'F'
        JNZ         invalid_drive_type
        CALL        INCHAR
        RC
        SUI         '0'
        CPI         4
        JNC         invalid_drive_nr
        STA         drive_number
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_input
        ;
        ; Flush any remaining command line arguments
        ;
flush_next_char:
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         flush_next_char
        JMP         start_remap

use_default_drive:
        ;
        ; Set drive to :F0:
        ;
        XRA         A
        STA         drive_number
        ;
        ; Main remap routine
        ;
start_remap:
        ;
        ; Get block addresses to disk mapfile data
        ;
        LXI         H,mapfile_name_str
        CALL        get_file_linking_block
        RC
        LHLD        linking_block_buffer + 004H
        SHLD        disk_mapfile_block_1_ref
        LHLD        linking_block_buffer + 006H
        SHLD        disk_mapfile_block_2_ref
        ;
        ; Clear RAM to be used as mapfile data buffer
        ;
        LXI         H,mapfile_data_buffer
        MVI         A,255
        MVI         M,000H
clear_next_byte:
        INX         H
        MVI         M,000H
        DCR         A
        JNZ         clear_next_byte
        ;
        ; Prepare to scan through all entries in the file directory
        ;
        LXI         H,dirfile_name_str
        CALL        get_file_linking_block
        RC
        LXI         D,004H
        DAD         D
        SHLD        dir_linking_block_ptr
        MVI         A,25
        STA         dir_block_count
        ;
        ; Scan through directory, marking used blocks in a new mapfile
        ;
scan_next_directory_block:
        ;
        ; Check if we are at the end of the directory
        ;
        LDA         dir_block_count
        ORA         A
        JZ          remap_files_done
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
        ; Check if data block reference is active
        ;
        MOV         A,C
        ORA         B
        JZ          remap_files_done
        ;
        ; Read data block of directory, based on reference from linking block
        ;
        LDA         drive_number
        LXI         H,dir_data_buffer
        CALL        DSRDW
        RC
        SHLD        file_entry_status_byte_ptr
        ;
        ; Point to linking block address of the first file entry in the block
        ;
        LXI         D,00EH
        DAD         D
        SHLD        file_entry_linking_block_ref_ptr
        ;
        ; Prepare to remap all files in the block
        ;
        MVI         A,8
        STA         file_entry_counter
check_next_file:
        ;
        ; Check for end of directory block
        ;
        LDA         file_entry_counter
        ORA         A
        JZ          scan_next_directory_block
        ;
        ; Get linking block reference of next file entry in the directory block
        ;
        LHLD        file_entry_linking_block_ref_ptr
        MOV         C,M
        INX         H
        MOV         B,M
        LXI         D,00FH
        DAD         D
        SHLD        file_entry_linking_block_ref_ptr
        DCR         A
        STA         file_entry_counter
        ;
        ; Check if file entry is an active file
        ;
        LHLD        file_entry_status_byte_ptr
        XRA         A
        ORA         M
        PUSH        PSW
        INX         D
        DAD         D
        SHLD        file_entry_status_byte_ptr
        POP         PSW
        JNZ         check_next_file
        ;
        ; Verify that linking block reference of file entry is active
        ;
        MOV         A,C
        ORA         B
        JZ          scan_next_directory_block
        ;
        ; Go through linking block chain of file, adding any blocks used to map
        ;
remap_next_linking_block_of_file:
        ;
        ; Mark next linking block of file as used in the mapfile
        ;
        CALL        verify_block_reference
        RC
        CALL        mark_block_in_mapfile
        ;
        ; Load linking block, saving the reference to the next block in chain
        ;
        LDA         drive_number
        LXI         H,file_entry_linking_block_buffer
        CALL        DSRDW
        RC
        INX         H
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        SHLD        file_entry_linking_block_ptr
        XCHG
        SHLD        file_entry_next_linking_block_ref
        ;
        ; Prepare to go through all data-blocks defined by linking block
        ;
        MVI         A,62
        STA         file_linking_block_count
check_next_data_block_ref:
        ;
        ; Check for end of linking block
        ;
        LDA         file_linking_block_count
        ORA         A
        JZ          advance_to_next_linking_block
        ;
        ; Get next data block reference from linking block
        ;
        LHLD        file_entry_linking_block_ptr
        MOV         C,M
        INX         H
        MOV         B,M
        INX         H
        SHLD        file_entry_linking_block_ptr
        DCR         A
        STA         file_linking_block_count
        ;
        ; Check if data block is in use
        ;
        MOV         A,C
        ORA         B
        JZ          advance_to_next_linking_block
        ;
        ; Mark data block in mapfile
        ;
        CALL        verify_block_reference
        RC
        CALL        mark_block_in_mapfile
        JMP         check_next_data_block_ref

advance_to_next_linking_block:
        ;
        ; Advance to next linking block in file linking-block chain
        ;
        LHLD        file_entry_next_linking_block_ref
        MOV         B,H
        MOV         C,L
        ;
        ; Check if last linking block
        ;
        MOV         A,L
        ORA         H
        JZ          check_next_file
        JMP         remap_next_linking_block_of_file

remap_files_done:
        ;
        ; Write newly generated mapfile back to disk
        ;
        LHLD        disk_mapfile_block_1_ref
        MOV         B,H
        MOV         C,L
        LXI         H,mapfile_data_buffer
        LDA         drive_number
        CALL        DSWRW
        RC
        LHLD        disk_mapfile_block_2_ref
        MOV         B,H
        MOV         C,L
        LXI         H,mapfile_data_buffer + 128
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Print status message
        ;
        LXI         D,remapping_done_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read linking block of file
        ;
get_file_linking_block:
        ;
        ; Get file entry of requested file
        ;
        LDA         drive_number
        CALL        LOCDIR
        RC
        ;
        ; Get linking block reference from file entry
        ;
        LXI         D,00EH
        DAD         D
        MOV         C,M
        INX         H
        MOV         B,M
        ;
        ; Read linking block into a buffer
        ;
        LDA         drive_number
        LXI         H,linking_block_buffer
        CALL        DSRDW
        RET


;//////////////////////////////////////////////////////////////////////////////

mark_block_in_mapfile:
        PUSH        B
        ;
        ; Reserve block in mapfile pt1: Multiply track nr with 26
        ;
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
        ; Reserve block in mapfile pt6: Mark block as reserved
        ;
        ORA         M
        MOV         M,A
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Verify that block ref is within the bounds of the geometry of a disk
        ;
verify_block_reference:
        ;
        ; Check track number of block reference
        ;
        MOV         A,B
        CPI         77
        CMC
        MVI         A,ERROR_35
        RC
        ;
        ; Check sector number of block reference
        ;
        MOV         A,C
        CPI         1
        MVI         A,ERROR_36
        RC
        MOV         A,C
        CPI         27
        CMC
        MVI         A,ERROR_36
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
;//
;//     Errors
;//
;//////////////////////////////////////////////////////////////////////////////

invalid_drive_nr:
        MVI         B,ERROR_13
        JMP         flush_input_after_error

invalid_input:
        MVI         B,ERROR_11
        JMP         flush_input_after_error

invalid_drive_type:
        MVI         B,ERROR_1D
flush_input_after_error:
        ;
        ; Flush remaining command line arguments
        ;
flush_next_char_after_error:
        CPI         CR
        JZ          quit_with_error
        CALL        INCHAR
        RC
        JMP         flush_next_char_after_error

quit_with_error:
        MOV         A,B
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

drive_number:
        DS          1
disk_mapfile_block_1_ref:
        DS          2
disk_mapfile_block_2_ref:
        DS          2
linking_block_buffer:
        DS          128
dir_linking_block_ptr:
        DS          2
dir_block_count:
        DS          1
dir_data_buffer:
        DS          128
file_entry_linking_block_ref_ptr:
        DS          2
file_entry_counter:
        DS          1
file_entry_linking_block_buffer:
        DS          128
file_entry_linking_block_ptr:
        DS          2
file_entry_next_linking_block_ref:
        DS          2
file_linking_block_count:
        DS          1
mapfile_data_buffer:
        DS          256
file_entry_status_byte_ptr:
        DS          2

remapping_done_str:
        DB          'DISKETTE MAP RE-ESTABLISHED',CR
