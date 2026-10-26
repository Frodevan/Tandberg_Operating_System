;//////////////////////////////////////////////////////////////////////////////
;//
;//     DCOPY - Duplicate floppy
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:[,:<Tn>:][,<option>]]
;//
;//                 Tn          Drive type and number, default :D0:,:D1:
;//                 option      User option, default I
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
;//                 Options:
;//                     I       Copy up to track 75 only, on IBM drive type
;//
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
;//         NOTE: The I option can only be used with any of the IBM drive types
;//
;//         NOTE: Deleted sectors are only copied on IBM type drive types. For TOS
;//               disk drive types, deleted sectors are treated as bad sectors.
;//
;//
;//         Changelog:
;//
;//             1.2: Entry at 0xC000
;//
;//                 -> First version I have
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> Adds a prompt to ask if more copies are needed at the end
;//
;//             1.5: Entry at 0x2000
;//
;//                 -> Fully rewritten to rely only on XMON API
;//                 -> Accepts lowercase input on the user choice prompt
;//                 -> Adds the S option to the user choice prompt
;//                 -> Will attempt to re-write track if verification fails
;//
;//             1.6a: Entry at 0x2000
;//
;//                 -> Version ID written to 0x2700
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
;//             1.8: Entry at 0x2000
;//
;//                 -> Will only make additional copies if Y is given for an answer
;//                    at the final prompt, and will re-use the initial option if
;//                    so. This is different from older versions, which would take
;//                    a new option to replace the previous choice here.
;//
;//             2.0a: Entry at 0x2800
;//
;//                 -> Command-line options formalized, using source-destination
;//                    drive designators instead of hardcoded drive numbers.
;//                 -> Will only accept the additional I option on the command-
;//                    line, the single-drive copy option is now set automatically
;//                    based on the source and target drive specified.
;//                 -> Handles different drive types differently
;//                 -> Double-sided drive types added
;//                 -> Reduces number of retries from 20 to 5
;//                 -> Fixes the verification bug from v1.6 for all other drive
;//                    types than the single-sided IBM drive type
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Constants
;
NOT         EQU     255

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
ERLIN       EQU     004H        ; Erase current line
BEL         EQU     007H        ; Bell short beep
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON constants
;
DISK_HEAD_1 EQU	    080H        ; Floppy disk sector number mask for disk head 1

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
DCALW       EQU     00070H      ; Reset disk drive with wait
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
DSDLW       EQU     00079H      ; Write deleted to disk with wait
DDSRDW      EQU     00097H      ; Read from double-sided disk with wait
DDSWRW      EQU     0009AH      ; Write to double-sided disk with wait
DDSDLW      EQU     0009DH      ; Write deleted to double-sided disk with wait

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
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_20    EQU     020H        ; DELETED DATA RECORD
ERROR_26    EQU     026H        ; IMPROPER PARAMETER


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DCOPY',NULL
        DB          '200'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Initialization
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02800H
start:
        ;
        ; Backup stack pointer, for breaking out of program
        ;
        LXI         H,0
        DAD         SP
        SHLD        saved_stack_ptr


;//////////////////////////////////////

        ;
        ; Check if CLI input is a buffered line-based file
        ;
        LHLD        CI_FCB
        MOV         A,M
        CPI         4
        JNZ         get_input_args
        ;
        ; Verify that there are CLI data pending in file
        ;
        INX         H
        INX         H
        MOV         E,M             ; CI_FCB + FCB_BUFIDX
        INX         H
        MOV         D,M
        PUSH        D
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; CI_FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        POP         H
        DAD         D
        MOV         A,M
        CPI         LF
        JZ          dual_drive_mode
        ;
        ; Get input arguments
        ;
get_input_args:
        LHLD        CI_FCB
        LXI         D,input_args_str_buffer
        CALL        GET
        RC


;//////////////////////////////////////

        ;
        ; Parse input arguments
        ;
        LXI         D,input_args_str_buffer
        ;
        ; Prune leading spaces and verify there's more args to parse
        ;
trim_arg_leading_spaces:
        LDAX        D
        INX         D
        CPI         ' '
        JZ          trim_arg_leading_spaces
        CPI         CR
        JZ          dual_drive_mode
        DCX         D
        ;
        ; Parse source drive designator
        ;
        CALL        parse_drive_designator
        MOV         A,B
        STA         welcome_prompt_str+11
        STA         source_drive_type
        MOV         A,C
        STA         welcome_prompt_str+12
        SUI         '0'
        STA         source_drive_nr
        ;
        ; Check for more args, I option or target drive designator
        ;
        LDAX        D
        CPI         ','
        JNZ         check_for_args_end
        INX         D
        LDAX        D
        CALL        to_uppercase
        CPI         'I'
        JZ          setup_for_i_option_arg
        ;
        ; Parse destination drive designator
        ;
        CALL        parse_drive_designator
        MOV         A,B
        STA         welcome_prompt_str+19
        STA         target_drive_type
        MOV         A,C
        STA         welcome_prompt_str+20
        SUI         '0'
        STA         target_drive_nr
        ;
        ; Check for more args, I option
        ;
        LDAX        D
        CPI         ','
        JNZ         check_for_args_end
        INX         D
        LDAX        D
        CALL        to_uppercase
        CPI         'I'
        JNZ         improper_param_err
        ;
        ; Verify no more args after I option
        ;
        INX         D
        LDAX        D
        CPI         CR
        JNZ         improper_param_err


;//////////////////////////////////////

        ;
        ; I option selected on the command line
        ;
setup_for_i_option_arg:
        ;
        ; Verify that an IBM format is used as source drive for the I option
        ;
        LDA         welcome_prompt_str+11
        CPI         'I'
        JZ          is_ibm_format_source
        CPI         'J'
        JNZ         improper_param_err
is_ibm_format_source:
        MVI         A,'I'
        STA         ibm_format_flag
        JMP         verify_target_drive


;//////////////////////////////////////

        ;
        ; All args should have been parsed here
        ;
check_for_args_end:
        CPI         CR
        JNZ         improper_param_err
        ;
        ; Set up variables according to selection
        ;
verify_target_drive:
        ;
        ; Check for a particular target drive being specified
        ;
        LDA         target_drive_type
        ANA         A
        JZ          single_drive_mode
        ;
        ; Verify that the drive type of the source and target is the same
        ;
        LDA         welcome_prompt_str+11
        MOV         C,A
        LDA         welcome_prompt_str+19
        CMP         C
        JNZ         improper_param_err
        ;
        ; Check target drive number if single-drive mode needs to be enabled
        ;
        LDA         welcome_prompt_str+12
        MOV         C,A
        LDA         welcome_prompt_str+20
        CMP         C
        JNZ         dual_drive_mode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set up for single-drive copy mode
        ;
single_drive_mode:
        MVI         A,'S'
        STA         single_drive_flag
        LDA         source_drive_nr
        STA         target_drive_nr
        LDA         welcome_prompt_str+11
        STA         welcome_prompt_single_str+16
        LDA         welcome_prompt_str+12
        STA         welcome_prompt_single_str+17
        ;
        ; Print welcome prompt string
        ;
        LXI         D,welcome_prompt_single_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC
        JMP         drives_set


;//////////////////////////////////////

        ;
        ; Set up for dual-drive copy mode
        ;
dual_drive_mode:
        ;
        ; Print welcome prompt string
        ;
        LXI         D,welcome_prompt_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC


;//////////////////////////////////////

drives_set:
        LDA         welcome_prompt_str+11
        CPI         'D'
        JZ          copy_tos_dsdd_disk
        CPI         'F'
        JZ          copy_tos_sssd_disk
        CPI         'I'
        JZ          copy_ibm_dsdd_disk
        CPI         'J'
        JZ          copy_ibm_sssd_disk
        JMP         improper_param_err


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Double-sided TOS disk copy
;//
;//////////////////////////////////////////////////////////////////////////////

copy_tos_dsdd_disk:
        ;
        ; Get highest possible start address of a track data buffer
        ;
        LHLD        BUFLIM
        LXI         D,-26*256
        DAD         D
        MOV         A,H
        INR         A
        STA         d_buffer_end_check_instr+1
        ;
        ; Store start address of first track buffer
        ;
        LXI         H,data_buffer
        SHLD        track_buffer_list
        ;
        ; Prepare to set up a list of pointers to individual track data buffers
        ;
        LXI         D,26*256
        LXI         B,track_buffer_list+2
        XRA         A
        STA         track_buffer_count
d_add_next_track_data_buffer:
        ;
        ; Check if there's space for another track data buffer
        ;
        DAD         D
        MOV         A,H
d_buffer_end_check_instr:
        CPI         000H
        JNC         d_parse_prompt_input
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
        JMP         d_add_next_track_data_buffer

d_parse_prompt_input:
        ;
        ; Get prompt input
        ;
        CALL        get_input_char
        MOV         C,A
        CPI         CR
        JZ          quit_program
        ;
        ; Flush remaining prompt input after first character
        ;
d_flush_prompt_input_loop:
        CALL        get_input_char
        CPI         CR
        JNZ         d_flush_prompt_input_loop
        ;
        ; Convert input choice to uppercase
        ;
        MOV         A,C
        CALL        to_uppercase
        ;
        ; Check prompt input selection
        ;
        CPI         'Y'
        JNZ         quit_program
        ;
        ; Prepare to start copy, reset source disk drive
        ;
d_reset_source_drive:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         d_source_drive_ready
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         d_reset_source_drive

d_source_drive_ready:
        ;
        ; Reset destination disk drive, unless single-drive operation
        ;
        LDA         single_drive_flag
        CPI         'S'
        JZ          d_target_drive_ready
d_reset_target_drive:
        LDA         target_drive_nr
        CALL        DCALW
        JNC         d_target_drive_ready
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         d_reset_target_drive


;//////////////////////////////////////

d_target_drive_ready:
        ;
        ; Initialize variables to copy a new disk
        ;
        LDA         source_drive_nr
        STA         current_drive_nr
        XRA         A
        STA         tracks_copied_count
        ;
        ; Clear any data from the previous track in RAM
        ;
        LHLD        track_buffer_list
        LXI         D,26*256
        CALL        clear_data_buffer
        LHLD        track_buffer_list+2
        LXI         D,26*256
        CALL        clear_data_buffer
d_copy_next_chunk:
        ;
        ; Reset buffers in preparation for new copying chunk of tracks
        ;
        MVI         A,1
        STA         current_track_buffer_nr
        LDA         tracks_copied_count
        STA         current_track_nr
d_prepare_track_read:
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
        ; Try up to 5 times to read a new track
        ;
        XRA         A
        STA         retry_counter
d_read_current_track:
        LDA         current_track_nr
        MOV         B,A
        LHLD        current_track_buffer_ptr
        CALL        d_read_track
        JNC         d_track_read_success
        LDA         retry_counter
        INR         A
        STA         retry_counter
        CPI         5
        JC          d_read_current_track
        LXI         D,read_error_str
        JMP         print_and_quit

d_track_read_success:
        ;
        ; Check if all heads of the current track are done or not
        ;
        LDA         current_track_nr
        ANA         A
        JP          d_continue_read_head_1
        ;
        ; Advance to first head of next track
        ;
        ANI         NOT-DISK_HEAD_1
        INR         A
        JMP         d_contine_read_current_head

d_continue_read_head_1:
        ORI         DISK_HEAD_1
d_contine_read_current_head:
        STA         current_track_nr
        ;
        ; End reading after track 76 for a normal disk
        ;
        CPI         77 + DISK_HEAD_1
        JNC         d_read_chunk_done
        ;
        ; Point to next track data buffer
        ;
        LDA         current_track_buffer_nr
        INR         A
        STA         current_track_buffer_nr
        MOV         B,A
        LDA         track_buffer_count
        CMP         B
        JNC         d_prepare_track_read

d_read_chunk_done:
        ;
        ; Prompt for disk change if one-drive mode
        ;
        LDA         single_drive_flag
        CPI         'S'
        JNZ         d_write_next_chunk_dual_drive
        LXI         D,change_to_copy_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
d_reset_drive_after_read:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         d_write_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         d_reset_drive_after_read


;//////////////////////////////////////

d_write_next_chunk_dual_drive:
        ;
        ; Make sure to write to second drive if multi-drive operation
        ;
        LDA         target_drive_nr
        STA         current_drive_nr
d_write_next_chunk:
        ;
        ; Start writing from first track buffer in chunk
        ;
        MVI         A,1
        STA         current_track_buffer_nr
        LDA         tracks_copied_count
        STA         current_track_nr
d_prepare_track_write:
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
d_write_current_track:
        LDA         current_track_nr
        MOV         B,A
        LHLD        current_track_buffer_ptr
        CALL        d_write_track
        JNC         d_verify_current_track
d_retry_writing_track:
        LDA         retry_counter
        INR         A
        STA         retry_counter
        CPI         5
        JC          d_write_current_track
        LXI         D,write_error_str
        JMP         print_and_quit

d_verify_current_track:
        ;
        ; Read back track data to buffer zero for verification
        ;
        LHLD        track_buffer_list
        CALL        d_read_track
        JC          d_retry_writing_track
        ;
        ; Compare readback track data with original track buffer
        ;
        LHLD        track_buffer_list
        XCHG
        LHLD        current_track_buffer_ptr
        LXI         B,26*256
d_verify_next_byte:
        LDAX        D
        CMP         M
        JNZ         d_retry_writing_track
        INX         D
        INX         H
        DCR         C
        JNZ         d_verify_next_byte
        DCR         B
        JNZ         d_verify_next_byte
        ;
        ; Check if all heads of the current track are done or not
        ;
        LDA         current_track_nr
        ANA         A
        JP          d_continue_write_head_1
        ;
        ; Advance to first head of next track
        ;
        ANI         NOT-DISK_HEAD_1
        INR         A
        JMP         d_contine_write_current_head

d_continue_write_head_1:
        ORI         DISK_HEAD_1
d_contine_write_current_head:
        STA         current_track_nr
        ;
        ; End writing after track 76 for a normal disk
        ;
        CPI         77 + DISK_HEAD_1
        JNC         d_copy_successful
        LDA         current_track_buffer_nr
        INR         A
        STA         current_track_buffer_nr
        ;
        ; Check if all track buffers have been written
        ;
        MOV         B,A
        LDA         track_buffer_count
        CMP         B
        JNC         d_prepare_track_write
        ;
        ; If so, prompt to change disk if single-disk mode
        ;
        LDA         single_drive_flag
        CPI         'S'
        JNZ         d_prepare_to_copy_next_chunk
        LXI         D,change_to_original_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
d_reset_drive_after_write:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         d_prepare_to_copy_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         d_reset_drive_after_write

d_prepare_to_copy_next_chunk:
        ;
        ; Reads are always from the primary drive
        ;
        LDA         source_drive_nr
        STA         current_drive_nr
        ;
        ; Add recently copied tracks to total count
        ;
        LDA         track_buffer_count
        MOV         C,A
        LDA         tracks_copied_count
d_tally_next_track_head:
        ANA         A
        JP          d_tally_head_1
        ;
        ; Only count each cylinder once
        ;
        ANI         NOT-DISK_HEAD_1
        INR         A
        JMP         d_track_head_tallied

d_tally_head_1:
        ORI         DISK_HEAD_1
d_track_head_tallied:
        DCR         C
        JNZ         d_tally_next_track_head
        STA         tracks_copied_count
        JMP         d_copy_next_chunk


;//////////////////////////////////////

d_copy_successful:
        ;
        ; Print status and take a new user choice
        ;
        LXI         D,verification_ok_str
        LHLD        CO_FCB
        CALL        PUTSTR
        JC          quit_with_error_code
        JMP         d_parse_prompt_input


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read a whole track into buffer pointed to by HL
        ;
d_read_track:
        MVI         C,1
d_read_next_sector:
        ;
        ; Read sector
        ;
        LDA         current_drive_nr
        CALL        DDSRDW
        RC
        ;
        ; Advance to next sector
        ;
        LXI         D,256
        DAD         D
        INR         C
        MOV         A,C
        CPI         27
        JC          d_read_next_sector
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write a whole track from buffer pointed to by HL
        ;
d_write_track:
        MVI         C,1
d_write_next_sector:
        LDA         current_drive_nr
        ;
        ; Write normal sector
        ;
        CALL        DDSWRW
        RC
        ;
        ; Advance to next sector
        ;
        LXI         D,256
        DAD         D
        INR         C
        MOV         A,C
        CPI         27
        JC          d_write_next_sector
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Single-sided TOS disk copy
;//
;//////////////////////////////////////////////////////////////////////////////

copy_tos_sssd_disk:
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
        ; Store start address of first track buffer
        ;
        LXI         H,data_buffer
        SHLD        track_buffer_list
        ;
        ; Prepare to set up a list of pointers to individual track data buffers
        ;
        LXI         D,26*128
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
        ; Flush remaining prompt input after first character
        ;
flush_prompt_input_loop:
        CALL        get_input_char
        CPI         CR
        JNZ         flush_prompt_input_loop
        ;
        ; Convert input choice to uppercase
        ;
        MOV         A,C
        CALL        to_uppercase
        ;
        ; Check prompt input selection
        ;
        CPI         'Y'
        JNZ         quit_program
        ;
        ; Prepare to start copy, reset source disk drive
        ;
reset_source_drive:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         source_drive_ready
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         reset_source_drive

source_drive_ready:
        ;
        ; Reset destination disk drive, unless single-drive operation
        ;
        LDA         single_drive_flag
        CPI         'S'
        JZ          target_drive_ready
reset_target_drive:
        LDA         target_drive_nr
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
        LDA         source_drive_nr
        STA         current_drive_nr
        XRA         A
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
        ; Try up to 5 times to read a new track
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
        CPI         5
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
        ; End reading after track 76 for a normal disk
        ;
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
        LDA         single_drive_flag
        CPI         'S'
        JNZ         write_next_chunk_dual_drive
        LXI         D,change_to_copy_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
reset_drive_after_read:
        LDA         source_drive_nr
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
        LDA         target_drive_nr
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
        CPI         5
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
        ; End writing after track 76 for a normal disk
        ;
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
        LDA         single_drive_flag
        CPI         'S'
        JNZ         prepare_to_copy_next_chunk
        LXI         D,change_to_original_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
reset_drive_after_write:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         prepare_to_copy_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         reset_drive_after_write

prepare_to_copy_next_chunk:
        ;
        ; Reads are always from the primary drive
        ;
        LDA         source_drive_nr
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
        RC
        ;
        ; Advance to next sector
        ;
        LXI         D,128
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
        LDA         current_drive_nr
        ;
        ; Write normal sector
        ;
        CALL        DSWRW
        RC
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
;//
;//     Main program: Double-sided IBM disk copy
;//
;//////////////////////////////////////////////////////////////////////////////

copy_ibm_dsdd_disk:
        ;
        ; Get highest possible start address of a track data buffer
        ;
        LHLD        BUFLIM
        LXI         D,-26*(256+1)
        DAD         D
        MOV         A,H
        INR         A
        STA         i_buffer_end_check_instr+1
        ;
        ; Store start address of first track buffer
        ;
        LXI         H,data_buffer
        SHLD        track_buffer_list
        ;
        ; Prepare to set up a list of pointers to individual track data buffers
        ;
        LXI         D,26*(256+1)
        LXI         B,track_buffer_list+2
        XRA         A
        STA         track_buffer_count
i_add_next_track_data_buffer:
        ;
        ; Check if there's space for another track data buffer
        ;
        DAD         D
        MOV         A,H
i_buffer_end_check_instr:
        CPI         000H
        JNC         i_parse_prompt_input
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
        JMP         i_add_next_track_data_buffer

i_parse_prompt_input:
        ;
        ; Get prompt input
        ;
        CALL        get_input_char
        MOV         C,A
        CPI         CR
        JZ          quit_program
        ;
        ; Flush remaining prompt input after first character
        ;
i_flush_prompt_input_loop:
        CALL        get_input_char
        CPI         CR
        JNZ         i_flush_prompt_input_loop
        ;
        ; Convert input choice to uppercase
        ;
        MOV         A,C
        CALL        to_uppercase
        ;
        ; Check prompt input selection
        ;
        CPI         'Y'
        JNZ         quit_program
        ;
        ; Prepare to start copy, reset source disk drive
        ;
i_reset_source_drive:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         i_source_drive_ready
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         i_reset_source_drive

i_source_drive_ready:
        ;
        ; Reset destination disk drive, unless single-drive operation
        ;
        LDA         single_drive_flag
        CPI         'S'
        JZ          i_target_drive_ready
i_reset_target_drive:
        LDA         target_drive_nr
        CALL        DCALW
        JNC         i_target_drive_ready
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         i_reset_target_drive


;//////////////////////////////////////

i_target_drive_ready:
        ;
        ; Initialize variables to copy a new disk
        ;
        LDA         source_drive_nr
        STA         current_drive_nr
        XRA         A
        STA         tracks_copied_count
        ;
        ; Clear any data from the previous track in RAM
        ;
        LHLD        track_buffer_list
        LXI         D,26*(256+1)
        CALL        clear_data_buffer
        LHLD        track_buffer_list+2
        LXI         D,26*(256+1)
        CALL        clear_data_buffer
i_copy_next_chunk:
        ;
        ; Reset buffers in preparation for new copying chunk of tracks
        ;
        MVI         A,1
        STA         current_track_buffer_nr
        LDA         tracks_copied_count
        STA         current_track_nr
i_prepare_track_read:
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
        ; Try up to 5 times to read a new track
        ;
        XRA         A
        STA         retry_counter
i_read_current_track:
        LDA         current_track_nr
        MOV         B,A
        LHLD        current_track_buffer_ptr
        CALL        i_read_track
        JNC         i_track_read_success
        LDA         retry_counter
        INR         A
        STA         retry_counter
        CPI         5
        JC          i_read_current_track
        LXI         D,read_error_str
        JMP         print_and_quit

i_track_read_success:
        ;
        ; Check if all heads of the current track are done or not
        ;
        LDA         current_track_nr
        ANA         A
        JP          i_continue_read_head_1
        ;
        ; Advance to first head of next track
        ;
        ANI         NOT-DISK_HEAD_1
        INR         A
        JMP         i_contine_read_current_head

i_continue_read_head_1:
        ORI         DISK_HEAD_1
i_contine_read_current_head:
        STA         current_track_nr
        ;
        ; Check args for IBM disk option, and end reading after track 74 if so
        ;
        LDA         ibm_format_flag
        CPI         'I'
        JNZ         i_advance_read_buffer
        LDA         current_track_nr
        CPI         75 + DISK_HEAD_1
        JNC         i_read_chunk_done
i_advance_read_buffer:
        ;
        ; End reading after track 76 for a normal disk
        ;
        LDA         current_track_nr
        CPI         77 + DISK_HEAD_1
        JNC         i_read_chunk_done
        ;
        ; Point to next track data buffer
        ;
        LDA         current_track_buffer_nr
        INR         A
        STA         current_track_buffer_nr
        MOV         B,A
        LDA         track_buffer_count
        CMP         B
        JNC         i_prepare_track_read

i_read_chunk_done:
        ;
        ; Prompt for disk change if one-drive mode
        ;
        LDA         single_drive_flag
        CPI         'S'
        JNZ         i_write_next_chunk_dual_drive
        LXI         D,change_to_copy_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
i_reset_drive_after_read:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         i_write_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         i_reset_drive_after_read


;//////////////////////////////////////

i_write_next_chunk_dual_drive:
        ;
        ; Make sure to write to second drive if multi-drive operation
        ;
        LDA         target_drive_nr
        STA         current_drive_nr
i_write_next_chunk:
        ;
        ; Start writing from first track buffer in chunk
        ;
        MVI         A,1
        STA         current_track_buffer_nr
        LDA         tracks_copied_count
        STA         current_track_nr
i_prepare_track_write:
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
i_write_current_track:
        LDA         current_track_nr
        MOV         B,A
        LHLD        current_track_buffer_ptr
        CALL        i_write_track
        JNC         i_verify_current_track
i_retry_writing_track:
        LDA         retry_counter
        INR         A
        STA         retry_counter
        CPI         5
        JC          i_write_current_track
        LXI         D,write_error_str
        JMP         print_and_quit

i_verify_current_track:
        ;
        ; Read back track data to buffer zero for verification
        ;
        LHLD        track_buffer_list
        CALL        i_read_track
        JC          i_retry_writing_track
        ;
        ; Compare readback track data with original track buffer
        ;
        LHLD        track_buffer_list
        XCHG
        LHLD        current_track_buffer_ptr
        LXI         B,26*(256+1)
i_verify_next_byte:
        LDAX        D
        CMP         M
        JNZ         i_retry_writing_track
        INX         D
        INX         H
        DCR         C
        JNZ         i_verify_next_byte
        DCR         B
        JNZ         i_verify_next_byte
        ;
        ; Check if all heads of the current track are done or not
        ;
        LDA         current_track_nr
        ANA         A
        JP          i_continue_write_head_1
        ;
        ; Advance to first head of next track
        ;
        ANI         NOT-DISK_HEAD_1
        INR         A
        JMP         i_contine_write_current_head

i_continue_write_head_1:
        ORI         DISK_HEAD_1
i_contine_write_current_head:
        STA         current_track_nr
        ;
        ; Check prompt for IBM disk, and end writing after track 74 if so
        ;
        LDA         ibm_format_flag
        CPI         'I'
        JNZ         i_advance_write_buffer
        LDA         current_track_nr
        CPI         75 + DISK_HEAD_1
        JNC         i_copy_successful
i_advance_write_buffer:
        ;
        ; End writing after track 76 for a normal disk
        ;
        LDA         current_track_nr
        CPI         77 + DISK_HEAD_1
        JNC         i_copy_successful
        LDA         current_track_buffer_nr
        INR         A
        STA         current_track_buffer_nr
        ;
        ; Check if all track buffers have been written
        ;
        MOV         B,A
        LDA         track_buffer_count
        CMP         B
        JNC         i_prepare_track_write
        ;
        ; If so, prompt to change disk if single-disk mode
        ;
        LDA         single_drive_flag
        CPI         'S'
        JNZ         i_prepare_to_copy_next_chunk
        LXI         D,change_to_original_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
i_reset_drive_after_write:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         i_prepare_to_copy_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         i_reset_drive_after_write

i_prepare_to_copy_next_chunk:
        ;
        ; Reads are always from the primary drive
        ;
        LDA         source_drive_nr
        STA         current_drive_nr
        ;
        ; Add recently copied tracks to total count
        ;
        LDA         track_buffer_count
        MOV         C,A
        LDA         tracks_copied_count
i_tally_next_track_head:
        ANA         A
        JP          i_tally_head_1
        ;
        ; Only count each cylinder once
        ;
        ANI         NOT-DISK_HEAD_1
        INR         A
        JMP         i_track_head_tallied

i_tally_head_1:
        ORI         DISK_HEAD_1
i_track_head_tallied:
        DCR         C
        JNZ         i_tally_next_track_head
        STA         tracks_copied_count
        JMP         i_copy_next_chunk


;//////////////////////////////////////

i_copy_successful:
        ;
        ; Print status and take a new user choice
        ;
        LXI         D,verification_ok_str
        LHLD        CO_FCB
        CALL        PUTSTR
        JC          quit_with_error_code
        JMP         i_parse_prompt_input


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read a whole track into buffer pointed to by HL
        ;
i_read_track:
        MVI         C,1
i_read_next_sector:
        ;
        ; Read sector
        ;
        LDA         current_drive_nr
        CALL        DDSRDW
        JC          i_check_read_status
        ;
        ; Mark normal sector after sector data and advance to next sector
        ;
        LXI         D,256
        DAD         D
        MVI         M,000H
i_read_sector_ok:
        INX         H
        INR         C
        MOV         A,C
        CPI         27
        JC          i_read_next_sector
        RET


;//////////////////////////////////////

i_check_read_status:
        ;
        ; Check sector for deleted status
        ;
        CPI         ERROR_20
        JZ          i_read_status_deleted
        STC
        RET

i_read_status_deleted:
        ;
        ; Mark deleted sector after sector data and advance to next sector
        ;
        LXI         D,256
        DAD         D
        MVI         M,ERROR_20
        JMP         i_read_sector_ok


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write a whole track from buffer pointed to by HL
        ;
i_write_track:
        MVI         C,1
i_write_next_sector:
        ;
        ; Check sector status
        ;
        LXI         D,256
        DAD         D
        MOV         A,M
        LXI         D,-256
        DAD         D
        CPI         ERROR_20
        JZ          i_write_deleted_sector
        ;
        ; Write normal sector
        ;
        LDA         current_drive_nr
        CALL        DDSWRW
        RC
i_write_sector_ok:
        ;
        ; Advance to next sector
        ;
        LXI         D,256+1
        DAD         D
        INR         C
        MOV         A,C
        CPI         27
        JC          i_write_next_sector
        RET

i_write_deleted_sector:
        ;
        ; Check for track 0, if so then only write single-sided single-density
        ;
        MOV         A,B
        ANI         NOT-DISK_HEAD_1
        LDA         current_drive_nr
        JNZ         i_write_deleted_dd_sector
        CALL        DSDLW
        JMP         i_deleted_sector_written

i_write_deleted_dd_sector:
        ;
        ; Write deleted sector
        ;
        CALL        DDSDLW
i_deleted_sector_written:
        JNC         i_write_sector_ok
        CPI         ERROR_20
        JZ          i_write_sector_ok
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Single-sided IBM disk copy
;//
;//////////////////////////////////////////////////////////////////////////////

copy_ibm_sssd_disk:
        ;
        ; Get highest possible start address of a track data buffer
        ;
        LHLD        BUFLIM
        LXI         D,-26*(128+1)
        DAD         D
        MOV         A,H
        INR         A
        STA         j_buffer_end_check_instr+1
        ;
        ; Store start address of first track buffer
        ;
        LXI         H,data_buffer
        SHLD        track_buffer_list
        ;
        ; Prepare to set up a list of pointers to individual track data buffers
        ;
        LXI         D,26*(128+1)
        LXI         B,track_buffer_list+2
        XRA         A
        STA         track_buffer_count
j_add_next_track_data_buffer:
        ;
        ; Check if there's space for another track data buffer
        ;
        DAD         D
        MOV         A,H
j_buffer_end_check_instr:
        CPI         000H
        JNC         j_parse_prompt_input
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
        JMP         j_add_next_track_data_buffer

j_parse_prompt_input:
        ;
        ; Get prompt input
        ;
        CALL        get_input_char
        MOV         C,A
        CPI         CR
        JZ          quit_program
        ;
        ; Flush remaining prompt input after first character
        ;
j_flush_prompt_input_loop:
        CALL        get_input_char
        CPI         CR
        JNZ         j_flush_prompt_input_loop
        ;
        ; Convert input choice to uppercase
        ;
        MOV         A,C
        CALL        to_uppercase
        ;
        ; Check prompt input selection
        ;
        CPI         'Y'
        JNZ         quit_program
        ;
        ; Prepare to start copy, reset source disk drive
        ;
j_reset_source_drive:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         j_source_drive_ready
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         j_reset_source_drive

j_source_drive_ready:
        ;
        ; Reset destination disk drive, unless single-drive operation
        ;
        LDA         single_drive_flag
        CPI         'S'
        JZ          j_target_drive_ready
j_reset_target_drive:
        LDA         target_drive_nr
        CALL        DCALW
        JNC         j_target_drive_ready
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         j_reset_target_drive


;//////////////////////////////////////

j_target_drive_ready:
        ;
        ; Initialize variables to copy a new disk
        ;
        LDA         source_drive_nr
        STA         current_drive_nr
        XRA         A
        STA         tracks_copied_count
j_copy_next_chunk:
        ;
        ; Reset buffers in preparation for new copying chunk of tracks
        ;
        MVI         A,1
        STA         current_track_buffer_nr
        LDA         tracks_copied_count
        STA         current_track_nr
j_prepare_track_read:
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
        ; Try up to 5 times to read a new track
        ;
        XRA         A
        STA         retry_counter
j_read_current_track:
        LDA         current_track_nr
        MOV         B,A
        LHLD        current_track_buffer_ptr
        CALL        j_read_track
        JNC         j_track_read_success
        LDA         retry_counter
        INR         A
        STA         retry_counter
        CPI         5
        JC          j_read_current_track
        LXI         D,read_error_str
        JMP         print_and_quit

j_track_read_success:
        ;
        ; Check if all heads of the current track are done or not
        ;
        LDA         current_track_nr
        INR         A
        STA         current_track_nr
        ;
        ; Check args for IBM disk option, and end reading after track 74 if so
        ;
        LDA         ibm_format_flag
        CPI         'I'
        JNZ         advance_read_buffer
        LDA         current_track_nr
        CPI         75
        JNC         j_read_chunk_done
advance_read_buffer:
        ;
        ; End reading after track 76 for a normal disk
        ;
        LDA         current_track_nr
        CPI         77
        JNC         j_read_chunk_done
        ;
        ; Point to next track data buffer
        ;
        LDA         current_track_buffer_nr
        INR         A
        STA         current_track_buffer_nr
        MOV         B,A
        LDA         track_buffer_count
        CMP         B
        JNC         j_prepare_track_read

j_read_chunk_done:
        ;
        ; Prompt for disk change if one-drive mode
        ;
        LDA         single_drive_flag
        CPI         'S'
        JNZ         j_write_next_chunk_dual_drive
        LXI         D,change_to_copy_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
j_reset_drive_after_read:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         j_write_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         j_reset_drive_after_read


;//////////////////////////////////////

j_write_next_chunk_dual_drive:
        ;
        ; Make sure to write to second drive if multi-drive operation
        ;
        LDA         target_drive_nr
        STA         current_drive_nr
j_write_next_chunk:
        ;
        ; Start writing from first track buffer in chunk
        ;
        MVI         A,1
        STA         current_track_buffer_nr
        LDA         tracks_copied_count
        STA         current_track_nr
j_prepare_track_write:
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
j_write_current_track:
        LDA         current_track_nr
        MOV         B,A
        LHLD        current_track_buffer_ptr
        CALL        j_write_track
        JNC         j_verify_current_track
j_retry_writing_track:
        LDA         retry_counter
        INR         A
        STA         retry_counter
        CPI         5
        JC          j_write_current_track
        LXI         D,write_error_str
        JMP         print_and_quit

j_verify_current_track:
        ;
        ; Read back track data to buffer zero for verification
        ;
        LHLD        track_buffer_list
        CALL        j_read_track
        JC          j_retry_writing_track
        ;
        ; Compare readback track data with original track buffer
        ;
        LHLD        track_buffer_list
        XCHG
        LHLD        current_track_buffer_ptr
        LXI         B,26*128
j_verify_next_byte:
        LDAX        D
        CMP         M
        JNZ         j_retry_writing_track
        INX         D
        INX         H
        DCR         C
        JNZ         j_verify_next_byte
        DCR         B
        JNZ         j_verify_next_byte
        ;
        ; Check if all heads of the current track are done or not
        ;
        LDA         current_track_nr
        INR         A
        STA         current_track_nr
        ;
        ; Check prompt for IBM disk, and end writing after track 74 if so
        ;
        LDA         ibm_format_flag
        CPI         'I'
        JNZ         advance_write_buffer
        LDA         current_track_nr
        CPI         75
        JNC         j_copy_successful
advance_write_buffer:
        ;
        ; End writing after track 76 for a normal disk
        ;
        LDA         current_track_nr
        CPI         77
        JNC         j_copy_successful
        LDA         current_track_buffer_nr
        INR         A
        STA         current_track_buffer_nr
        ;
        ; Check if all track buffers have been written
        ;
        MOV         B,A
        LDA         track_buffer_count
        CMP         B
        JNC         j_prepare_track_write
        ;
        ; If so, prompt to change disk if single-disk mode
        ;
        LDA         single_drive_flag
        CPI         'S'
        JNZ         j_prepare_to_copy_next_chunk
        LXI         D,change_to_original_str
        CALL        prompt_user
        ;
        ; Reset disk drive after disk change
        ;
j_reset_drive_after_write:
        LDA         source_drive_nr
        CALL        DCALW
        JNC         j_prepare_to_copy_next_chunk
        LXI         D,drive_not_ready_str
        CALL        prompt_user
        JMP         j_reset_drive_after_write

j_prepare_to_copy_next_chunk:
        ;
        ; Reads are always from the primary drive
        ;
        LDA         source_drive_nr
        STA         current_drive_nr
        ;
        ; Add recently copied tracks to total count
        ;
        LDA         tracks_copied_count
        MOV         B,A
        LDA         track_buffer_count
        ADD         B
        STA         tracks_copied_count
        JMP         j_copy_next_chunk


;//////////////////////////////////////

j_copy_successful:
        ;
        ; Print status and take a new user choice
        ;
        LXI         D,verification_ok_str
        LHLD        CO_FCB
        CALL        PUTSTR
        JC          quit_with_error_code
        JMP         j_parse_prompt_input


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read a whole track into buffer pointed to by HL
        ;
j_read_track:
        MVI         C,1
j_read_next_sector:
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
        JC          j_read_next_sector
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
j_write_track:
        MVI         C,1
j_write_next_sector:
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
        JC          j_write_next_sector
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
;//     Main program: Termination
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Raise improper parameter error and quit
        ;
improper_param_err:
        MVI         A,ERROR_26
        STC
        JMP         quit_with_error_code


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
        ; Convert a single ASCII character to uppercase
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
        ; Parse and verify valid drive designator
        ;
parse_drive_designator:
        LDAX        D
        CPI         ':'
        JNZ         improper_param_err
        INX         D
        LDAX        D
        CALL        to_uppercase
        MOV         B,A
        CPI         'D'
        JZ          valid_drive_type
        CPI         'F'
        JZ          valid_drive_type
        CPI         'I'
        JZ          valid_drive_type
        CPI         'J'
        JNZ         improper_param_err
valid_drive_type:
        INX         D
        LDAX        D
        MOV         C,A
        INX         D
        LDAX        D
        CPI         ':'
        JNZ         improper_param_err
        INX         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear databuffer at HL with length DE
        ;
clear_data_buffer:
clear_next_byte:
        MVI         M,NULL
        INX         H
        DCX         D
        MOV         A,E
        ORA         D
        JNZ         clear_next_byte
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
        DB          0
single_drive_flag:
        DB          NULL
ibm_format_flag:
        DB          NULL
current_drive_nr:
        DB          0
source_drive_nr:
        DB          0
target_drive_nr:
        DB          1
source_drive_type:
        DB          NULL
target_drive_type:
        DB          NULL
tracks_copied_count:
        DB          0
current_track_nr:
        DB          0
current_track_buffer_nr:
        DB          0
current_track_buffer_ptr:
        DW          00000H
retry_counter:
        DB          0

welcome_prompt_str:
        DB          'Copy from :D0: to :D1: - type Y: ',CR
welcome_prompt_single_str:
        DB          'Single copy on :D0: - type Y: ',CR
verification_ok_str:
        DB          'EQUAL. More ? (Y/N): ',CR
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

data_buffer:
input_args_str_buffer:
