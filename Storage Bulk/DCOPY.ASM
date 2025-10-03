;//////////////////////////////////////////////////////////////////////////////
;//
;//     DCOPY - Duplicate floppy
;//
;//         Extra parameters:
;//
;//             [$<option>]
;//
;//                 option      User option
;//
;//                 Options:
;//                     I       Copy up to track 75, from drive 0 to drive 1
;//                     N       Abort copy
;//                     S       Copy using drive 0 only
;//                     Y       Copy from drive 0 to drive 1
;//
;//         Duplicates an entire floppy-disk, track by track. Each track on the
;//         source disk is attempted to be read up to 20 times in the case of read-
;//         issues, while each track is only attempted re-written twice should
;//         there be write issues.
;//
;//         Input selection will be prompted for at program start, unless extra
;//         parameters are supported and provided. Not all versions of this tool
;//         supports the extra parameters feature.
;//
;//         If the S option is used, the user will be prompted to swap disk every
;//         once in a while. This prompt will take any keypress to continue, except
;//         for 'Q' which will immediately abort the copy and end the program.
;//
;//         NOTE: This version of the program uses TOS to find the start of RAM, and
;//               supports 54KB user memory. However, this in turn requires at least
;//               TOS v1.7 to run properly.
;//
;//         NOTE: The minor verification bug from v1.6 was never fixed.
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
;//                 -> Version ID written to 0x2700
;//                 -> Reverts all changes from v1.5b
;//
;//             1.6b: Entry at 0x2000
;//
;//                 -> Re-introduces support for deleted sectors without the buffer
;//                    overrun bug from v1.5b
;//                 -> Introduces a bug where the last 25 bytes of each track won't
;//                    be properly verified, neither will the sector type of the
;//                    very last sector in each track
;//
;//             1.7: Entry at 0x2000
;//
;//                 -> Uses TOS start-of-RAM variable instead of finding it using a
;//                    local algorithm. This adds support for 54k user memory.
;//                 -> Flushes excess extra parameters after first option
;//                 -> Uses TOS device-files for text I/O, instead of XMON API
;//                 -> Adds the I option
;//                 -> Typing Q at any prompt during the copy aborts the operation
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
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
DCALW       EQU     00070H      ; Reset disk drive with wait
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
DSDLW       EQU     00079H      ; Write deleted to disk with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature
BUFLIM      EQU     0272EH      ; Lowest address of current TOS buffers
KEYBUF      EQU     02780H      ; Console input buffer

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR

;
; TOS constants
;
RAMST       EQU     0FDFCH      ; Address to start of user-RAM

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_20    EQU     020H        ; DELETED DATA RECORD


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DCOPY',NULL
        DB          '107'


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
        LXI         D,welcome_prompt_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC
        ;
        ; Get highest possible start address of a track data buffer
        ;
        LHLD        BUFLIM
        LXI         D,-26*(128+1)
        DAD         D
        MOV         A,H
        INR         A
        STA         buffer_end_check_instr+1
        ;
        ; Scan for start of user-RAM to get start address of first track buffer
        ;
        LHLD        RAMST
        SHLD        track_buffer_list
        ;
        ; Prepare to set up a list of pointers to individual track data buffers
        ;
        LXI         D,26*(128+1)
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
        ; Get prompt input
        ;
        CALL        get_input_char
        MOV         C,A
        CPI         CR
        JZ          quit_program
        ;
        ; Flush remaining input chars
        ;
flush_user_input_prompt:
        CALL        get_input_char
        CPI         CR
        JNZ         flush_user_input_prompt
        MOV         A,C
        ;
        ; Convert input choice to uppercase
        ;
        CPI         'a'-1
        JC          char_is_uppercase
        SUI         'a'-'A'
char_is_uppercase:
        ;
        ; Check prompt input selection
        ;
        CPI         'Y'
        JZ          prepare_to_copy
        CPI         'I'
        JZ          prepare_to_copy
        CPI         'S'
        JNZ         quit_program
prepare_to_copy:
        ;
        ; Save prompt selection, and prepare to start copy
        ;
        STA         prompt_choice
        ;
        ; Reset source disk drive
        ;
reset_source_drive:
        XRA         A
        CALL        DCALW
        JNC         source_drive_ready
        LXI         D,drive_not_ready_str
        CALL        prompt_user
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
        LXI         D,drive_not_ready_str
        CALL        prompt_user
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
        LXI         D,read_error_str
        JMP         print_and_quit

track_read_success:
        ;
        ; Advance to next track
        ;
        LDA         current_track_nr
        INR         A
        STA         current_track_nr
        ;
        ; Check prompt for IBM disk, and end reading after track 74 if so
        ;
        LDA         prompt_choice
        CPI         'I'
        JNZ         advance_read_buffer
        LDA         current_track_nr
        CPI         75
        JNC         read_chunk_done
advance_read_buffer:
        ;
        ; End reading after track 76 for a normal disk
        ;
        LDA         current_track_nr
        CPI         77
        JNC         read_chunk_done
        ;
        ; Point to next track data buffer
        ;
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
        CPI         'I'
        JZ          write_next_chunk_dual_drive
        LXI         D,change_to_copy_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
reset_drive_after_read:
        XRA         A
        CALL        DCALW
        JNC         write_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
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
        LXI         D,write_error_str
        JMP         print_and_quit

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
        LXI         B,26*128
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
        ;
        ; Check prompt for IBM disk, and end writing after track 74 if so
        ;
        LDA         prompt_choice
        CPI         'I'
        JNZ         advance_write_buffer
        LDA         current_track_nr
        CPI         75
        JNC         copy_successful
advance_write_buffer:
        ;
        ; End writing after track 76 for a normal disk
        ;
        LDA         current_track_nr
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
        CPI         'I'
        JZ          prepare_to_copy_next_chunk
        LXI         D,change_to_original_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
reset_drive_after_write:
        XRA         A
        CALL        DCALW
        JNC         prepare_to_copy_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
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
        LXI         D,verification_ok_str
        LHLD        CO_FCB
        CALL        PUTSTR
        JC          quit_with_error_code
        JMP         parse_prompt_input


;//////////////////////////////////////

print_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        JC          quit_with_error_code
quit_program:
        ;
        ; Cleanup and quit program
        ;
        XRA         A
quit_with_error_code:
        LHLD        saved_stack_ptr
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Run a prompt after printing the string pointed to by DE
        ;
prompt_user:
        LHLD        CO_FCB
        CALL        PUTSTR
        JC          quit_with_error_code
        ;
        ; Flush input and wait for user choice
        ;
        XRA         A
        STA         KEYBUF
        CALL        TTI
        ;
        ; Clear prompt after choice has been made
        ;
        PUSH        PSW
        MVI         A,ERLIN
        CALL        TTO
        POP         PSW
        ;
        ; Answering Q to the prompt will end the program immediately
        ;
        CPI         'Q'
        JZ          quit_with_error_code
        CPI         'q'
        JZ          quit_with_error_code
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Input a single character to A
        ;
get_input_char:
        PUSH        H
        LHLD        CI_FCB
        CALL        INCHAR
        JC          quit_with_error_code
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read a whole track into buffer pointed to by HL
        ;
read_track:
        MVI         C,1
read_next_sector:
        ;
        ; Read sector
        ;
        LDA         current_drive_nr
        CALL        DSRDW
        JC          check_read_status
        ;
        ; Mark normal sector after sector data and advance to next sector
        ;
        LXI         D,128
        DAD         D
        MVI         M,000H
read_sector_ok:
        INX         H
        INR         C
        MOV         A,C
        CPI         27
        JC          read_next_sector
        RET


;//////////////////////////////////////

check_read_status:
        ;
        ; Check sector for deleted status
        ;
        CPI         ERROR_20
        JZ          read_status_deleted
        STC
        RET

read_status_deleted:
        ;
        ; Mark deleted sector after sector data and advance to next sector
        ;
        LXI         D,128
        DAD         D
        MVI         M,ERROR_20
        JMP         read_sector_ok


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
        LXI         D,128
        DAD         D
        MOV         A,M
        LXI         D,-128
        DAD         D
        CPI         ERROR_20
        LDA         current_drive_nr
        JZ          write_deleted_sector
        ;
        ; Write normal sector
        ;
        CALL        DSWRW
        RC
write_sector_ok:
        ;
        ; Advance to next sector
        ;
        LXI         D,128+1
        DAD         D
        INR         C
        MOV         A,C
        CPI         27
        JC          write_next_sector
        RET

write_deleted_sector:
        ;
        ; Write deleted sector
        ;
        CALL        DSDLW
        JNC         write_sector_ok
        CPI         ERROR_20
        JZ          write_sector_ok
        STC
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
        DB          'Copy from 0 to 0 - type S, from 0 to 1 - type Y: ',CR
verification_ok_str:
        DB          'EQUAL. More ? (S/Y): ',CR
change_to_copy_str:
        DB          'Change to output diskette: ',BEL,CR
change_to_original_str:
        DB          'Change to input diskette: ',BEL,CR
drive_not_ready_str:
        DB          'Drive not ready: ',BEL,CR
read_error_str:
        DB          'Read error',BEL,CR
write_error_str:
        DB          'Write error',BEL,CR
