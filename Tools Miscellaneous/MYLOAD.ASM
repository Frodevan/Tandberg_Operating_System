;//////////////////////////////////////////////////////////////////////////////
;//
;//     MYLOAD - Load and run a program from a disk in Mycron MYCRO-1 format
;//
;//         Extra parameters:
;//
;//             $<filename>
;//
;//                 filename    File to be loaded and run
;//
;//
;//         Loads and runs a particular file from a floppy-disk in unit 0, where
;//         the disk is formatted for the Mycron MYCRO-1. This tool is particulary
;//         usefull if a MYCRO-1 is being used to develop and compile software for
;//         Tandberg OS.
;//
;//         After the file is loaded, the program starting at the beginning of
;//         the file's load-block 1 is run (MYCRO-1 files are defined with up to
;//         two load-blocks, where the second block is optional).
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0x2095, 0x2000
;//
;//                 -> First version I have
;//
;//             1.6: Entry at 0x2000
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
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; XMON system calls
;
DCALW       EQU     00070H      ; Reset disk drive with wait
DSRDW       EQU     00073H      ; Read from disk with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer

;
; TOS Errors
;
ERROR_0B    EQU     00BH        ; PROGRAM NAME NOT FOUND


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02000H
start:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

mycrop_file_info:
disk_block_address:
        DW          00000H
part_1_load_address:
        DW          00000H
part_1_block_count:
        DB          0
part_2_load_address:
        DW          00000H
part_2_block_count:
        DB          0

filename_str:
        DB          '        '
auxiliary_pointer:
        DW          filename_str
data_buffer:
        DS          128


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Get filename of target MYCROP file from command line arguments
        ;
        MVI         B,8
get_next_filename_char:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JZ          search_for_file
        LHLD        auxiliary_pointer
        MOV         M,A
        INX         H
        SHLD        auxiliary_pointer
        DCR         B
        JNZ         get_next_filename_char
        ;
        ; Search through all file entries for given file on MYCROP disk
        ;
search_for_file:
        ;
        ; Reset block address and get disk drive to track zero
        ;
        LXI         H,0*DISK_TRACK + 7*DISK_SECTOR
        SHLD        disk_block_address
        SUB         A
        CALL        DCALW
        RC
scan_next_directory_block:
        ;
        ; Advance to next sector of file directory
        ;
        LHLD        disk_block_address
        INR         L
        SHLD        disk_block_address
        ;
        ; Check for directory end at end of track 0
        ;
        MOV         A,L
        CPI         27
        JZ          file_not_found
        ;
        ; Read sector of file directory
        ;
        MOV         C,L
        MOV         B,H
        SUB         A
        LXI         H,data_buffer
        CALL        DSRDW
        RC
        ;
        ; Point to first file entry in current directory block
        ;
        LXI         H,data_buffer
        SHLD        auxiliary_pointer
        MVI         C,8
check_dir_entry:
        ;
        ; Compare filename of current directory entry with requested filename
        ;
        LXI         D,filename_str
        MVI         B,8
compare_filename_loop:
        LDAX        D
        CMP         M
        JNZ         check_next_dir_entry
        INX         H
        INX         D
        DCR         B
        JNZ         compare_filename_loop
        ;
        ; File found, copy file info into to local datastructure
        ;
        LHLD        auxiliary_pointer
        LXI         D,8
        DAD         D
        LXI         D,mycrop_file_info
        MVI         B,8
copy_next_fileinfo_byte:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         B
        JNZ         copy_next_fileinfo_byte
        ;
        ; Prepare disk block address to same format as XMON call uses
        ;
        LHLD        disk_block_address
        MOV         A,L
        MOV         L,H
        MOV         H,A
        SHLD        disk_block_address
        ;
        ; Convert part 1 load address from big- to little-endian byte order
        ;
        LHLD        part_1_load_address
        MOV         A,L
        MOV         L,H
        MOV         H,A
        SHLD        part_1_load_address
        ;
        ; Store entry-pointer and prepare to load part 1
        ;
        SHLD        auxiliary_pointer
        LHLD        disk_block_address
        MOV         B,H
        MOV         C,L
        LDA         part_1_block_count
        MOV         E,A
        LHLD        part_1_load_address
        ;
        ; Load part 1 into RAM at it's target address
        ;
read_part_1_block:
        ;
        ; Read current block
        ;
        SUB         A
        CALL        DSRDW
        RC
        ;
        ; Advance to next block
        ;
        DCR         E
        JZ          check_part_2
        PUSH        D
        LXI         D,128
        DAD         D
        POP         D
        ;
        ; Advance to next disk sector, and check for track end
        ;
        INR         C
        MOV         A,C
        CPI         27
        JNZ         read_part_1_block
        ;
        ; Advance to next track
        ;
        INR         B
        MVI         C,1
        JMP         read_part_1_block

check_part_2:
        ;
        ; Check if part 2 exists
        ;
        LDA         part_2_block_count
        CPI         0
        JZ          load_complete
        MOV         E,A
        ;
        ; Convert part 2 load address from big- to little-endian byte order
        ;
        LHLD        part_2_load_address
        MOV         A,L
        MOV         L,H
        MOV         H,A
        JMP         read_next_part_2_block

read_part_2_block:
        ;
        ; Read current block
        ;
        SUB         A
        CALL        DSRDW
        RC
        ;
        ; Advance to next block
        ;
        DCR         E
        JZ          load_complete
        PUSH        D
        LXI         D,128
        DAD         D
        POP         D
read_next_part_2_block:
        ;
        ; Advance to next disk sector, and check for track end
        ;
        INR         C
        MOV         A,C
        CPI         27
        JNZ         read_part_2_block
        ;
        ; Advance to next track
        ;
        INR         B
        MVI         C,1
        JMP         read_part_2_block

load_complete:
        ;
        ; Jump to start of loaded part 1
        ;
        LHLD        auxiliary_pointer
        PCHL


;//////////////////////////////////////

file_not_found:
        MVI         A,ERROR_0B
        STC
        RET


;//////////////////////////////////////

check_next_dir_entry:
        ;
        ; Advance to next directory entry in sector
        ;
        LHLD        auxiliary_pointer
        LXI         D,010H
        DAD         D
        SHLD        auxiliary_pointer
        DCR         C
        JNZ         check_dir_entry
        JMP         scan_next_directory_block


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'MYLOAD'
        DB          '106'
