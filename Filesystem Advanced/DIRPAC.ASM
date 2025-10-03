;//////////////////////////////////////////////////////////////////////////////
;//
;//     DIRPAC - Pack remaining entries in directory table
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
;//         Scanns through the directory-table, and removes any entries previously
;//         marked as deleted. This way existing file-entries will potentially be
;//         packed closer to the start of the table, something which may save a
;//         little time when doing file operations.
;//
;//         This program uses the TOS aliases for the XMON API for doing disk-
;//         operations, instead of using the XMON API directly.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//
;//             1.6: Entry at 0xC10B
;//
;//                 -> Version ID written to 0x2700
;//
;//             1.7: Entry at 0xC10B
;//
;//                 -> Flushes excess input characters from the extra parameters
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
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
DCALW       EQU     0FD70H      ; Reset disk drive with wait
DSRDW       EQU     0FD73H      ; Read from disk with wait
DSWRW       EQU     0FD76H      ; Write to disk with wait

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DIRPAC'
        DB          '107'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
drive_number:
        DB          0
input_track_sector:
        DW          00000H
output_track_sector:
        DW          00000H
input_file_entry_countdown:
        DB          0
output_file_entry_countdown:
        DB          0
input_buffer_ptr:
        DW          00000H
output_buffer_ptr:
        DW          00000H

input_data_buffer:
        DS          128
output_data_buffer:
        DS          128


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

start:
beginning:
        ;
        ; Set default drive to floppy disk drive 0
        ;
        SUB         A
        STA         drive_number
        ;
        ; Clear leading whitespace
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          beginning
        ;
        ; Check if there are any command line arguments
        ;
        CPI         CR
        JZ          pack_directory
        ;
        ; Parse and verify drive designator argument
        ;
        CPI         ':'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'F'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        CPI         '0'
        JM          invalid_drive
        CPI         '4'
        JP          invalid_drive
        SUI         '0'
        STA         drive_number
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_drive
        ;
        ; Flush any remaining input chars
        ;
flush_next_input_char:
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         flush_next_input_char


;//////////////////////////////////////

pack_directory:
        ;
        ; Reset drive and set up initial addresses/pointers
        ;
        LDA         drive_number
        CALL        DCALW
        RC
        LXI         H,1*DISK_TRACK + 2*DISK_SECTOR
        SHLD        input_track_sector
        SHLD        output_track_sector
        LXI         H,output_data_buffer
        SHLD        output_buffer_ptr
        MVI         A,8
        STA         output_file_entry_countdown
        ;
        ; Pack next sector of the file directory
        ;
pack_next_dir_sector:
        ;
        ; Read sector from file table
        ;
        LHLD        input_track_sector
        MOV         B,H
        MOV         C,L
        LXI         H,input_data_buffer
        LDA         drive_number
        CALL        DSRDW
        RC
        ;
        ; Check each of the 8 file entries in sector
        ;
        LXI         H,input_data_buffer
        SHLD        input_buffer_ptr
        MVI         A,8
        STA         input_file_entry_countdown
check_file_entry:
        ;
        ; Keep file if active, otherwise advance to next entry with no action
        ;
        MOV         A,M
        CPI         000H
        JZ          keep_file_entry
        LXI         D,010H
        DAD         D
check_next_file_entry:
        ;
        ; Store new data pointer and advance counter of entries left in sector
        ;
        SHLD        input_buffer_ptr
        LDA         input_file_entry_countdown
        DCR         A
        STA         input_file_entry_countdown
        JNZ         check_file_entry
        ;
        ; Advance current filetable sector-address
        ;
        LHLD        input_track_sector
        INR         L
        MOV         A,L
        CPI         27
        SHLD        input_track_sector
        JNZ         pack_next_dir_sector
        ;
        ; Clear remaining file-entries of last sector with active files
        ;
        LHLD        output_buffer_ptr


;//////////////////////////////////////

clear_next_file_entry:
        MVI         M,07FH
        LXI         D,010H
        DAD         D
        LDA         output_file_entry_countdown
        DCR         A
        STA         output_file_entry_countdown
        JNZ         clear_next_file_entry
        ;
        ; Write sector with some or all cleared file entries
        ;
        LHLD        output_track_sector
        MOV         B,H
        MOV         C,L
        LXI         H,output_data_buffer
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Clear all file-entries in the rest of the file table sectors
        ;
        MVI         A,8
        STA         output_file_entry_countdown
        LHLD        output_track_sector
        INR         L
        SHLD        output_track_sector
        MOV         A,L
        LXI         H,output_data_buffer
        CPI         27
        JNZ         clear_next_file_entry
        ;
        ; Done packing the directory
        ;
        LXI         D,completed_ok_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

keep_file_entry:
        ;
        ; Copy file entry between input and output buffers
        ;
        XCHG
        LHLD        output_buffer_ptr
        XCHG
        MVI         B,010H
copy_next_file_entry_byte:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         copy_next_file_entry_byte
        ;
        ; Advance to next entry of output buffer
        ;
        XCHG
        SHLD        output_buffer_ptr
        XCHG
        LDA         output_file_entry_countdown
        DCR         A
        STA         output_file_entry_countdown
        JNZ         check_next_file_entry
        ;
        ; Output buffer is full, write sector to disk and reset pointers
        ;
        PUSH        H
        LHLD        output_track_sector
        INR         L
        SHLD        output_track_sector
        DCR         L
        MOV         B,H
        MOV         C,L
        LXI         H,output_data_buffer
        SHLD        output_buffer_ptr
        LDA         drive_number
        CALL        DSWRW
        POP         H
        RC
        MVI         A,8
        STA         output_file_entry_countdown
        JMP         check_next_file_entry


;//////////////////////////////////////

invalid_drive:
        LXI         D,invalid_drive_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII char in A to uppercase
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
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

completed_ok_str:
        DB          'DIRECTORY PACKED',CR
invalid_drive_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
