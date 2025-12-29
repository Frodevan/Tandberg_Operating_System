;//////////////////////////////////////////////////////////////////////////////
;//
;//     DCOPY - Duplicate floppy
;//
;//         Duplicates an entire floppy-disk, track by track. Each track on the
;//         source disk is attempted to be read up to 20 times in the case of read-
;//         issues, while each track is only attempted re-written twice should
;//         there be write issues.
;//
;//         If the S option is used, the user will be prompted to swap disk every
;//         once in a while. This prompt will take any keypress to continue.
;//
;//         NOTE: This program derives the size of user-memory on its own, and the
;//               code used expects a gap between start of user-memory and XMON-
;//               memory. This is true for machines with 48k RAM or less, but not
;//               for systems with the full 54k of user RAM. Running the wrong
;//               version of this program on a 54k machine will cause the computer
;//               to crash, since the whole XMON working-RAM block (where the
;//               program itself resides) will be overwritten with floppy-data.
;//
;//
;//         User choice prompt input:
;//
;//             <option>
;//
;//                 option      User option
;//
;//                 Options:
;//                     N       Abort copy
;//                     S       Copy using drive 0 only
;//                     Y       Copy from drive 0 to drive 1
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0x2000
;//
;//                 -> First version I have
;//
;//             1.5a: Entry at 0x2000
;//
;//                 -> Fully rewritten to rely only on XMON API
;//                 -> Accepts lowercase input on the user choice prompt
;//                 -> Adds the S option to the user choice prompt
;//                 -> Will attempt to re-write track if verification fails
;//
;//             1.5b: Entry at 0x2000
;//
;//                 -> Adds support for deleted sectors
;//                 -> Introduces a bug where the track-buffer may overrun into TOS
;//                    by up to 26 bytes
;//
;//             1.6a: Entry at 0x2000
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
ERLIN       EQU     004H        ; Erase current line
BEL         EQU     007H        ; Bell short beep
LF          EQU     00AH        ; Line Feed
ROLUP       EQU     00CH        ; Roll text upwards one line
CR          EQU     00DH        ; Cartridge Return
CURUP       EQU     01CH        ; Move cursor up one line

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
INDISP      EQU     0006AH      ; Get character at console cursor
DCALW       EQU     00070H      ; Reset disk drive with wait
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
DSDLW       EQU     00079H      ; Write deleted to disk with wait

;
; XMON and TOS system data
;
BUFLIM      EQU     0272EH      ; Lowest address of current TOS buffers
KEYBUF      EQU     02780H      ; Console input buffer

;
; TOS Errors
;
ERROR_20    EQU     020H        ; DELETED DATA RECORD


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02000H
start:
        ;
        ; Backup stack pointer, for breaking out of program
        ;
        LXI         H,0
        DAD         SP
        SHLD        saved_stack_ptr
        ;
        ; Print welcome prompt string
        ;
        LXI         H,welcome_prompt_str
        CALL        print_str
        ;
        ; Get highest possible start address of a track data buffer
        ;
        LHLD        BUFLIM
        LXI         D,-26*128
        DAD         D
        MOV         A,H
        INR         A
        STA         buffer_end_check_instr+1
        ;
        ; Scan for start of user-RAM to get start address of first track buffer
        ;
        LXI         H,0C000H
ram_test_loop:
        DCR         H
        MOV         A,M
        INR         M
        CMP         M
        JNZ         ram_test_loop
        INR         H
        SHLD        track_buffer_list
        ;
        ; Prepare to set up a list of pointers to individual track data buffers
        ;
        LXI         D,26*(1+128)
        LXI         B,track_buffer_list+2
        XRA         A
        STA         track_buffer_count
add_next_track_data_buffer:
        ;
        ; Check if there's space for another track data buffer
        ;
        DAD         D
        MOV         A,H
buffer_end_check_instr:
        CPI         000H
        JNC         parse_prompt_input
        ;
        ; Add new data buffer to list
        ;
        LDA         track_buffer_count
        INR         A
        STA         track_buffer_count
        MOV         A,L
        STAX        B
        INX         B
        MOV         A,H
        STAX        B
        INX         B
        JMP         add_next_track_data_buffer

parse_prompt_input:
        ;
        ; Get prompt input and convert to uppercase
        ;
        CALL        TTI
        CPI         'a'-1
        JC          char_is_uppercase
        SUI         'a'-'A'
char_is_uppercase:
        ;
        ; Check prompt input selection
        ;
        CPI         'Y'
        JZ          prepare_to_copy
        CPI         'N'
        JZ          quit_program
        CPI         'S'
        JNZ         parse_prompt_input
prepare_to_copy:
        ;
        ; Echo and save prompt selection, and prepare to start copy
        ;
        CALL        TTO
        STA         prompt_choice
        CALL        print_clean_new_line
        ;
        ; Reset source disk drive
        ;
reset_source_drive:
        XRA         A
        CALL        DCALW
        JNC         source_drive_ready
        LXI         H,drive_not_ready_str
        CALL        print_str
        CALL        TTI
        JMP         reset_source_drive

source_drive_ready:
        ;
        ; Reset destination disk drive, unless single-drive operation
        ;
        LDA         prompt_choice
        CPI         'S'
        JZ          target_drive_ready
reset_target_drive:
        MVI         A,1
        CALL        DCALW
        JNC         target_drive_ready
        LXI         H,drive_not_ready_str
        CALL        print_str
        CALL        TTI
        JMP         reset_target_drive


;//////////////////////////////////////

target_drive_ready:
        ;
        ; Initialize variables to copy a new disk
        ;
        XRA         A
        STA         current_drive_nr
        STA         tracks_copied_count
copy_next_chunk:
        ;
        ; Reset buffers in preparation for new copying chunk of tracks
        ;
        MVI         A,1
        STA         current_track_buffer_nr
        LDA         tracks_copied_count
        STA         current_track_nr
prepare_track_read:
        ;
        ; Look up track buffer pointer in list of tracks
        ;
        LDA         current_track_buffer_nr
        ADD         A
        MOV         C,A
        MVI         B,000H
        LXI         H,track_buffer_list
        DAD         B
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        SHLD        current_track_buffer_ptr
        ;
        ; Try up to 20 times to read a new track
        ;
        XRA         A
        STA         retry_counter
read_current_track:
        LDA         current_track_nr
        MOV         B,A
        LHLD        current_track_buffer_ptr
        CALL        read_track
        JNC         track_read_success
        LDA         retry_counter
        INR         A
        STA         retry_counter
        CPI         20
        JC          read_current_track
        LXI         H,read_error_str
        JMP         print_str_and_quit

track_read_success:
        ;
        ; Advance to next track
        ;
        LDA         current_track_nr
        INR         A
        STA         current_track_nr
        CPI         77
        JNC         read_chunk_done
        LDA         current_track_buffer_nr
        INR         A
        STA         current_track_buffer_nr
        MOV         B,A
        LDA         track_buffer_count
        CMP         B
        JNC         prepare_track_read

read_chunk_done:
        ;
        ; Prompt for disk change if one-drive mode
        ;
        LDA         prompt_choice
        CPI         'Y'
        JZ          write_next_chunk_dual_drive
        LXI         H,change_to_copy_str
        CALL        print_str
        CALL        print_clean_new_line
        ;
        ; Flush keyboard input buffer and wait for new keystroke
        ;
        XRA         A
        STA         KEYBUF
        CALL        TTI
        ;
        ; Clear prompt text
        ;
        MVI         A,CURUP
        CALL        TTO
        MVI         A,ERLIN
        CALL        TTO
        ;
        ; Reset disk drive after disk change
        ;
reset_drive_after_read:
        XRA         A
        CALL        DCALW
        JNC         write_next_chunk
        LXI         H,drive_not_ready_str
        CALL        print_str
        CALL        TTI
        JMP         reset_drive_after_read


;//////////////////////////////////////

write_next_chunk_dual_drive:
        ;
        ; Make sure to write to second drive if multi-drive operation
        ;
        MVI         A,1
        STA         current_drive_nr
write_next_chunk:
        ;
        ; Start writing from first track buffer in chunk
        ;
        MVI         A,1
        STA         current_track_buffer_nr
        LDA         tracks_copied_count
        STA         current_track_nr
prepare_track_write:
        ;
        ; Look up track buffer pointer in list of tracks
        ;
        LDA         current_track_buffer_nr
        ADD         A
        MOV         C,A
        MVI         B,000H
        LXI         H,track_buffer_list
        DAD         B
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        SHLD        current_track_buffer_ptr
        ;
        ; Try up to 2 times to write track
        ;
        XRA         A
        STA         retry_counter
write_current_track:
        LDA         current_track_nr
        MOV         B,A
        LHLD        current_track_buffer_ptr
        CALL        write_track
        JNC         verify_current_track
retry_writing_track:
        LDA         retry_counter
        INR         A
        STA         retry_counter
        CPI         2
        JC          write_current_track
        LXI         H,write_error_str
        JMP         print_str_and_quit

verify_current_track:
        ;
        ; Read back track data to buffer zero for verification
        ;
        LHLD        track_buffer_list
        CALL        read_track
        JC          retry_writing_track
        ;
        ; Compare readback track data with original track buffer
        ;
        LHLD        track_buffer_list
        XCHG
        LHLD        current_track_buffer_ptr
        LXI         B,26*(1+128)
verify_next_byte:
        LDAX        D
        CMP         M
        JNZ         retry_writing_track
        INX         D
        INX         H
        DCR         C
        JNZ         verify_next_byte
        DCR         B
        JNZ         verify_next_byte
        ;
        ; Advance to next track
        ;
        LDA         current_track_nr
        INR         A
        STA         current_track_nr
        CPI         77
        JNC         copy_successful
        LDA         current_track_buffer_nr
        INR         A
        STA         current_track_buffer_nr
        ;
        ; Check if all track buffers have been written
        ;
        MOV         B,A
        LDA         track_buffer_count
        CMP         B
        JNC         prepare_track_write
        ;
        ; If so, prompt to change disk if single-disk mode
        ;
        LDA         prompt_choice
        CPI         'Y'
        JZ          prepare_to_copy_next_chunk
        LXI         H,change_to_original_str
        CALL        print_str
        CALL        print_clean_new_line
        ;
        ; Flush keyboard input buffer and wait for new keystroke
        ;
        XRA         A
        STA         KEYBUF
        CALL        TTI
        ;
        ; Clear prompt text
        ;
        MVI         A,CURUP
        CALL        TTO
        MVI         A,ERLIN
        CALL        TTO
        ;
        ; Reset disk drive after disk change
        ;
reset_drive_after_write:
        XRA         A
        CALL        DCALW
        JNC         prepare_to_copy_next_chunk
        LXI         H,drive_not_ready_str
        CALL        print_str
        CALL        TTI
        JMP         reset_drive_after_write

prepare_to_copy_next_chunk:
        ;
        ; Reads are always from the primary drive
        ;
        XRA         A
        STA         current_drive_nr
        ;
        ; Add recently copied tracks to total count
        ;
        LDA         tracks_copied_count
        MOV         B,A
        LDA         track_buffer_count
        ADD         B
        STA         tracks_copied_count
        JMP         copy_next_chunk


;//////////////////////////////////////

copy_successful:
        ;
        ; Print status and take a new user choice
        ;
        LXI         H,verification_ok_str
        CALL        print_str
        JMP         parse_prompt_input


;//////////////////////////////////////

print_str_and_quit:
        CALL        print_str
quit_program:
        ;
        ; Cleanup and quit program
        ;
        CALL        print_clean_new_line
        XRA         A
        LHLD        saved_stack_ptr
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string pointed to by HL
        ;
print_str:
        MOV         A,M
        ORA         A
        RZ
        CALL        TTO
        INX         H
        JMP         print_str


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read a whole track into buffer pointed to by HL
        ;
read_track:
        MVI         C,1
read_next_sector:
        ;
        ; Read sector and append read status before first byte of sector data
        ;
        LDA         current_drive_nr
        INX         H
        CALL        DSRDW
        DCX         H
        MOV         M,A
        ;
        ; Check sector read status, allow for normal and deleted
        ;
        JNC         read_sector_ok
        CPI         ERROR_20
        RNZ
read_sector_ok:
        ;
        ; Advance to next sector
        ;
        LXI         D,1+128
        DAD         D
        INR         C
        MOV         A,C
        CPI         27
        JC          read_next_sector
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write a whole track from buffer pointed to by HL
        ;
write_track:
        MVI         C,1
write_next_sector:
        ;
        ; Check sector status
        ;
        MOV         A,M
        INX         H
        CPI         ERROR_20
        JNZ         write_normal_sector
        ;
        ; Write deleted sector
        ;
        LDA         current_drive_nr
        CALL        DSDLW
        RC
        JMP         write_sector_ok

write_normal_sector:
        ;
        ; Write normal sector
        ;
        LDA         current_drive_nr
        CALL        DSWRW
        RC
write_sector_ok:
        ;
        ; Advance to next sector
        ;
        LXI         D,128
        DAD         D
        INR         C
        MOV         A,C
        CPI         27
        JC          write_next_sector
        RET


;//////////////////////////////////////////////////////////////////////////////

print_clean_new_line:
        MVI         A,CR
        CALL        TTO
        MVI         A,LF
        CALL        TTO
        CALL        INDISP
        ORA         A
        JZ          line_already_clear
        MVI         A,ROLUP
        CALL        TTO
line_already_clear:
        MVI         A,CR
        CALL        TTO
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

saved_stack_ptr:
        DW          00000H

track_buffer_list:
        DW          00000H
        DS          13*2

track_buffer_count:
        DB          000H
prompt_choice:
        DB          000H
current_drive_nr:
        DB          000H
tracks_copied_count:
        DB          000H
current_track_nr:
        DB          000H
current_track_buffer_nr:
        DB          000H
current_track_buffer_ptr:
        DW          00000H
retry_counter:
        DB          000H

welcome_prompt_str:
        DB          'Copy from 0 to 1 - Type Y to start : ',NULL
verification_ok_str:
        DB          'EQUAL. More ? ',NULL
change_to_copy_str:
        DB          'Change to copy diskette',BEL,NULL
change_to_original_str:
        DB          'Change to original diskette',BEL,NULL
drive_not_ready_str:
        DB          'Drive not ready. ',BEL,NULL
read_error_str:
        DB          'Read error',BEL,NULL
write_error_str:
        DB          'Write error',BEL,NULL
