;//////////////////////////////////////////////////////////////////////////////
;//
;//     ALLOC - Allocate a file record on a disk in IBM 3740 format
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:][<filename>]
;//
;//                 filename    Name of file target, default 'DATA'
;//                 Tn          Drive type and number, default :I0:
;//
;//                 Drive type T:
;//                     A       Floppy (IBM 3740, ASCII)
;//                     B       Floppy (IBM 3740, ASCII)
;//                     I       Floppy (IBM 3740, EBCDIC)
;//                     J       Floppy (IBM 3740, EBCDIC)
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//                 NOTE: Filename must be a new file, unless it's being replaced
;//                       with itself (updated in place).
;//
;//
;//         This program allocates a new file index record on a disk using the IBM
;//         3740 format, or alternatively updates an existing index with new info.
;//         Once a file has been created, it can be used by other programs. Please
;//         note that the IBM format requires files to be on consecutive sectors,
;//         so if EOE of a file does not allow for enough room on the disk then
;//         only extend it if you know it is the last file stored on the disk.
;//
;//
;//         Input:
;//
;//             New/Replace:
;//                 N                   New file, default
;//                 R <filename>        Name of file to update, file must exist
;//
;//             Record length:
;//                 <length>            File length in sectors (0-128)
;//
;//             Beginning of extent:
;//                 <track>/<sector>    First sector of file
;//
;//             End of extent:
;//                 <track>/<sector>    Last sector reserved by file
;//
;//             Remainder default:
;//                 Y                   Skip remaining prompts
;//                 N                   Prompt everything
;//
;//             Bypass file:
;//                 <space>             Process file on the IBM 3747
;//                 B                   Skip file on the IBM 3747
;//
;//             Accessibility:
;//                 <space>             Enable reading of file
;//                 <anything else>     Disable reading of file
;//
;//             Protect:
;//                 <space>             Enable writing to file
;//                 P                   Disable writing to file
;//
;//             Creation date:
;//                 <space>             Clear creation date of file
;//                 <YY><MM><DD>        Set new creation date of file
;//
;//             Expiration data:
;//                 <space>             Clear expiration date of file
;//                 <YY><MM><DD>        Set new expiration date of file
;//
;//             Verify:
;//                 <space>             File is unverified, default for new file
;//                 C                   File has been copy-veified
;//                 V                   File has been verified
;//
;//             End of Data:
;//                 <track>/<sector>    Next unused sector of file
;//
;//
;//             NOTE: Entering an empty line selects no change, or the default
;//                   option for a given prompt. Only a few prompts have any
;//                   particular default values.
;//
;//             NOTE: Track and sector entries can take a comma or a space as
;//                   deliminer, instead of the slash. In any way, track must be a
;//                   number between 1 and 73, while sector must be a number within
;//                   the range 1 to 26.
;//
;//             NOTE: During any point, it is possible to press the Home arrow-key
;//                   to discard any pending selections and return to the very
;//                   first prompt.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where software-autoscroll can trigger when not
;//                    supposed to
;//
;//             1.5a: Entry at 0xC000
;//
;//                 -> Accepts lowercase drive-type and input on prompts
;//                 -> Fixes software-autoscroll bug from v1.3
;//
;//             1.5b: Entry at 0xC000
;//
;//                 -> Recognizes B and J as valid drive types
;//                 -> Introduces a bug where drive types B and J are reported to
;//                    the user as type A and I respectively
;//
;//             1.6: Entry at 0xC000
;//
;//                 -> Version ID written to 0x2700
;//                 -> Check if target file already exist before and after prompts
;//                 -> Check if replace file exists at prompt as well
;//                 -> More verbose responses on invalid input
;//                 -> Minimum record lengt must be 1, as 0 is no longer allowed
;//                 -> Track numbers cannot be 0 or higher than 73
;//                 -> Checks that BOE is not to be after EOE
;//                 -> Checks that EOD is after or at BOE
;//                 -> Checks that EOD is not after EOE+1
;//                 -> Default EOD = BOE for new files
;//
;//             1.7: Entry at 0xC000
;//
;//                 -> Use TOS CO file instead of XMON API to print Ctrl-characters
;//                 -> Updates the no-autoscroll line counter when cursor is moved
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
ETX         EQU     003H        ; End of text
BEL         EQU     007H        ; Bell (short beep)
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return
ERPAG       EQU     019H        ; Clear screen
CURH        EQU     01DH        ; Cursor home

;
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; XMON system calls
;
TTO         EQU     00043H      ; Console output
CURSOR      EQU     00049H      ; Set console cursor position
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
DSRAW       EQU     0007CH      ; Read from disk with wait and translate EBCDIC to ASCII
DSWAW       EQU     0007FH      ; Translate ASCII to EBCDIC and write to disk with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature
ROLLSW      EQU     0271FH      ; Cursor line number if no hardware autoscroll
ASCI        EQU     0277EH      ; EBCDIC to ASCII translation table reference
KEYBUF      EQU     02780H      ; Console input buffer

;
; TOS system calls
;
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR

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
ERROR_20    EQU     020H        ; DELETED DATA RECORD


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'ALLOC',NULL
        DB          '107'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Save stack-pointer for breaking out of subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        sp_backup
        ;
        ; Get command line arguments into buffer
        ;
        LXI         D,input_line_buffer
        LHLD        CI_FCB
        CALL        GET
        RC
        ;
        ; Get drive from command line arguments, else use default
        ;
        LXI         H,drive_designator_str
        LXI         D,input_line_buffer
        LDAX        D
        CPI         ':'
        JNZ         drive_set
        MOV         M,A
        INX         H
        INX         D
        LDAX        D
        CALL        to_uppercase
        CPI         'J'
        JNZ         ibm_type_j_check_done
        DCR         A
ibm_type_j_check_done:
        CPI         'B'
        JNZ         ibm_type_b_check_done
        DCR         A
ibm_type_b_check_done:
        CPI         'I'
        JZ          is_ibm_drive
        CPI         'A'
        JNZ         wrong_device_type
is_ibm_drive:
        MOV         M,A
        INX         H
        INX         D
        LDAX        D
        CPI         '4'
        JNC         wrong_device_number
        MOV         M,A
        SUI         '0'
        STA         drive_number
        INX         H
        INX         D
        LDAX        D
        CPI         ':'
        JNZ         wrong_device_type
        MOV         M,A
        INX         D
        LDAX        D
drive_set:
        ;
        ; Get target filename from command line arguments, if specified
        ;
        LXI         H,target_filename+4
        MVI         B,13
        CPI         CR
        JZ          prepare_filename
        LXI         H,target_filename
        MVI         B,17
prepare_filename:
        CALL        copy_valid_filename
        JC          filename_error
        ;
        ; Select XMON system-calls for disk read/write depending on drive type
        ;
        LDA         drive_designator_str+1
        CPI         'I'
        JNZ         prepare_ascii_disk_type
        LXI         H,DSRAW
        SHLD        read_call
        LXI         H,DSWAW
        JMP         ibm_disk_type_set
prepare_ascii_disk_type:
        LXI         H,DSRDW
        SHLD        read_call
        LXI         H,DSWRW
ibm_disk_type_set:
        SHLD        write_call
        ;
        ; Read first IBM data-label on disk (t0, s8), and check if it is valid
        ;
        LXI         B,0*DISK_TRACK + 8*DISK_SECTOR
        CALL        read_ibm_disk_sector
        RC
        LXI         H,input_data_buffer
        LXI         D,active_file_label_id
        MVI         A,4
        CALL        compare_memory
        JZ          valid_ibm_disk
        LXI         H,input_data_buffer
        LXI         D,deleted_file_label_id
        MVI         A,4
        CALL        compare_memory
        JNZ         unrecognized_file_label_found_error
valid_ibm_disk:
        ;
        ; Verify that target file does not exist
        ;
        LXI         H,target_filename
        SHLD        filename_ptr
        CALL        look_up_ibm_file
        RC
        JNZ         get_fresh_file_parameters
        LXI         D,drive_designator_str
        CALL        print_str
        LXI         D,target_filename
        CALL        print_ibm_filename
        LXI         D,already_exists_str
        CALL        print_str
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Start process of allocating IBM file
        ;
get_fresh_file_parameters:
        ;
        ; Reset TOS autoscroll if hardware autoscroll is disabled
        ;
        LDA         ROLLSW
        ORA         A
        JZ          autoscroll_prepared
        MVI         A,'A'
        STA         ROLLSW
autoscroll_prepared:
        ;
        ; Reset buffers related to IBM file-parameter prompts
        ;
        MVI         A,CR
        STA         replace_filename
        LXI         B,55
        LXI         D,replace_filename+1
clear_parameters_data_loop:
        MVI         A,' '
        STAX        D
        INX         D
        DCX         B
        MOV         A,C
        ORA         B
        JNZ         clear_parameters_data_loop
        MVI         A,CR
        STA         bypass_char
        STA         access_char
        STA         protect_char
        STA         creation_date_str
        STA         expiration_date_str
        STA         verify_char
        STA         eod_str
        ;
        ; Print text for file parameters prompts
        ;
        LXI         D,parameter_prompts_str
        CALL        print_str
        LXI         H,parameter_prompts_cursor_locations
        SHLD        cursor_location_ptr
        CALL        move_cursor_to_next_location
        LXI         D,drive_designator_str
        CALL        print_str
        LXI         D,target_filename
        CALL        print_ibm_filename


;//////////////////////////////////////

        ;
        ; New/Replace prompt
        ;
        CALL        prompt_next_line
parse_prompt_new_replace:
        ;
        ; Verify user choice
        ;
        CALL        to_uppercase
        STA         new_replace_choice
        CPI         CR
        JZ          choice_new_replace_complete
        CPI         'N'
        JZ          choice_new_replace_complete
        CPI         'R'
        JZ          choice_replace
        LXI         D,improper_parameter_str
        CALL        print_prompt_feedback_status
        JMP         choice_new_replace_invalid_input

choice_replace:
        ;
        ; Replace chosen, skip spaces between choice and filename
        ;
choice_replace_get_to_filename_loop:
        INX         D
        LDAX        D
        CPI         ' '
        JZ          choice_replace_get_to_filename_loop
        ;
        ; Copy filename, while checking for invalid characters
        ;
        LXI         H,replace_filename
        MVI         B,17
        CALL        copy_valid_filename
        JNC         choice_replace_check_filename
choice_new_replace_invalid_input:
        CALL        prompt_current_line_again
        JMP         parse_prompt_new_replace

choice_replace_check_filename:
        ;
        ; Check for non-empty filename
        ;
        LXI         H,replace_filename
        MOV         A,M
        CPI         ' '
        JZ          choice_new_replace_invalid_input
        ;
        ; Verify that replace filename does exist
        ;
        LXI         H,replace_filename
        SHLD        filename_ptr
        CALL        look_up_ibm_file
        RC
        JZ          choice_new_replace_complete
        ;
        ; Print status message at last line if replace file not found
        ;
        LHLD        cursor_location_ptr
        PUSH        H
        LXI         H,parameter_prompts_final_cursor_location
        SHLD        cursor_location_ptr
        CALL        move_cursor_to_next_location
        LXI         D,drive_designator_str
        CALL        print_str
        LXI         D,replace_filename
        CALL        print_ibm_filename
        LXI         D,not_found_str
        CALL        print_str
        POP         H
        SHLD        cursor_location_ptr
        JMP         choice_new_replace_invalid_input

choice_new_replace_complete:


;//////////////////////////////////////

        ;
        ; Record Length prompt
        ;
        CALL        prompt_next_line
parse_prompt_record_length:
        ;
        ; Check if input has been provided
        ;
        CPI         CR
        JZ          choice_record_length_no_change
        ;
        ; Get numerical input and convert to BCD
        ;
        MVI         B,4
        LXI         H,00000H
choice_record_length_parse_loop:
        LDAX        D
        CPI         CR
        JZ          choice_record_length_verify
        DCR         B
        JZ          choice_record_length_invalid_input
        CALL        is_numeric_ascii
        JC          choice_record_length_invalid_input
        CALL        ascii_to_bcd_digit
        INX         D
        JMP         choice_record_length_parse_loop

choice_record_length_no_change:
        ;
        ; Record lenght can only be ommitted if Replace is chosen
        ;
        LDA         new_replace_choice
        CPI         'R'
        JZ          choice_record_length_complete
        LXI         D,no_default_parameter_str
        JMP         choice_record_length_error

choice_record_length_invalid_input:
        LXI         D,improper_record_length_str

choice_record_length_error:
        CALL        print_prompt_feedback_status
        CALL        prompt_current_line_again
        JMP         parse_prompt_record_length

choice_record_length_verify:
        ;
        ; Verify that the record length (in BCD) is within the range [1, 128]
        ;
        MOV         A,L
        ORA         H
        JZ          choice_record_length_invalid_input
        LXI         D,-00129H
        XCHG
        DAD         D
        JC          choice_record_length_invalid_input
        XCHG
        ;
        ; Convert record length in BCD back to ASCII
        ;
        LXI         D,record_length_str
        MOV         A,H
        CALL        bcd_to_ascii_digit
        MOV         A,L
        CALL        bcd_to_ascii_byte
choice_record_length_complete:


;//////////////////////////////////////

        ;
        ; Beginning of Extent (BOE) prompt
        ;
        CALL        prompt_next_line_for_track_and_sector
choice_boe_parse:
        ;
        ; Verify that BOE is entered correctly
        ;
        CALL        check_track_sector_input
        JZ          choice_boe_parsed
        LXI         D,no_default_parameter_str

choice_boe_error:
        CALL        print_prompt_feedback_status
        CALL        prompt_current_line_again_for_track_and_sector
        JMP         choice_boe_parse

choice_boe_parsed:
        ;
        ; If replace, get BOE from existing file
        ;
        LXI         H,boe_str
        LDAX        D
        CPI         CR
        JNZ         choice_boe_finalize
        LXI         D,input_data_buffer+28
        MVI         B,5
choice_boe_finalize:
        CALL        copy_memory
        ;
        ; Check if BOE is within bounds
        ;
        LXI         H,end_sector_boe_str
        LXI         D,boe_str
        CALL        track_sector_compare_for_carry_flag
        JNC         choice_boe_valid
        LXI         D,boe_out_of_range_str
        JMP         choice_boe_error

choice_boe_valid:


;//////////////////////////////////////

        ;
        ; End of Extent (EOE) prompt
        ;
        CALL        prompt_next_line_for_track_and_sector
choice_eoe_parse:
        ;
        ; Verify that EOE is entered correctly
        ;
        CALL        check_track_sector_input
        JZ          choice_eoe_parsed
        LXI         D,no_default_parameter_str

choice_eoe_error:
        CALL        print_prompt_feedback_status
        CALL        prompt_current_line_again_for_track_and_sector
        JMP         choice_eoe_parse

choice_eoe_parsed:
        ;
        ; If replace, get EOE from existing file
        ;
        LXI         H,eoe_str
        LDAX        D
        CPI         CR
        JNZ         choice_eoe_finalize
        LXI         D,input_data_buffer+34
        MVI         B,5
choice_eoe_finalize:
        CALL        copy_memory
        ;
        ; Check if EOE is within bounds
        ;
        LXI         H,end_sector_eoe_str
        LXI         D,eoe_str
        CALL        track_sector_compare_for_carry_flag
        JNC         choice_eoe_compare_boe
        LXI         D,eoe_out_of_range_str
        JMP         choice_eoe_error

choice_eoe_compare_boe:
        ;
        ; Check that BOE is within EOE
        ;
        LXI         H,eoe_str
        LXI         D,boe_str
        CALL        track_sector_compare_for_carry_flag
        JNC         choice_eoe_valid
        LXI         D,boe_out_of_eoe_str
        JMP         choice_eoe_error

choice_eoe_valid:


;//////////////////////////////////////

        ;
        ; Use defaults for remaining parameters prompt
        ;
        CALL        prompt_next_line
parse_prompt_use_defaults:
        ;
        ; Verify user choice
        ;
        CALL        to_uppercase
        CPI         CR
        JZ          all_file_parameters_set
        CPI         'Y'
        JZ          all_file_parameters_set
        CPI         'N'
        JZ          choice_use_defaults_complete
        LXI         D,improper_parameter_str
        CALL        print_prompt_feedback_status
        CALL        prompt_current_line_again
        JMP         parse_prompt_use_defaults

choice_use_defaults_complete:


;//////////////////////////////////////

        ;
        ; Bypass character prompt
        ;
        CALL        prompt_next_line
parse_prompt_bypass:
        ;
        ; Verify user choice
        ;
        CALL        to_uppercase
        CPI         CR
        JZ          choice_bypass_valid
        CPI         ' '
        JZ          choice_bypass_valid
        CPI         'B'
        JZ          choice_bypass_valid
        LXI         D,improper_parameter_str
        CALL        print_prompt_feedback_status
        CALL        prompt_current_line_again
        JMP         parse_prompt_bypass

choice_bypass_valid:
        STA         bypass_char


;//////////////////////////////////////

        ;
        ; Access character prompt
        ;
        CALL        prompt_next_line
        STA         access_char


;//////////////////////////////////////

        ;
        ; Protect prompt
        ;
        CALL        prompt_next_line
parse_prompt_protect:
        ;
        ; Verify user choice
        ;
        CALL        to_uppercase
        CPI         CR
        JZ          choice_protect_valid
        CPI         ' '
        JZ          choice_protect_valid
        CPI         'P'
        JZ          choice_protect_valid
        LXI         D,improper_parameter_str
        CALL        print_prompt_feedback_status
        CALL        prompt_current_line_again
        JMP         parse_prompt_protect

choice_protect_valid:
        STA         protect_char


;//////////////////////////////////////

        ;
        ; Creation date prompt
        ;
        LXI         H,creation_date_str
        CALL        prompt_next_line_for_date


;//////////////////////////////////////

        ;
        ; Expiration date prompt
        ;
        LXI         H,expiration_date_str
        CALL        prompt_next_line_for_date


;//////////////////////////////////////

        ;
        ; Verify prompt
        ;
        CALL        prompt_next_line
parse_prompt_verify:
        ;
        ; Verify user choice
        ;
        CALL        to_uppercase
        CPI         CR
        JZ          choice_verify_valid
        CPI         'V'
        JZ          choice_verify_valid
        CPI         'C'
        JZ          choice_verify_valid
        CPI         ' '
        JZ          choice_verify_valid
        LXI         D,improper_parameter_str
        CALL        print_prompt_feedback_status
        CALL        prompt_current_line_again
        JMP         parse_prompt_verify

choice_verify_valid:
        STA         verify_char


;//////////////////////////////////////

        ;
        ; End of Data (EOD) prompt
        ;
        CALL        prompt_next_line_for_track_and_sector
choice_eod_parsed:
        ;
        ; If default EOD, use BOE for new file or EOD from replace file
        ;
        LXI         H,eod_str
        LDAX        D
        CPI         CR
        JNZ         choice_eod_finalize
        LXI         D,input_data_buffer+74
        LDA         new_replace_choice
        CPI         'R'
        JZ          choice_eod_default_decided
        LXI         D,boe_str
choice_eod_default_decided:
        MVI         B,5
choice_eod_finalize:
        CALL        copy_memory
        ;
        ; Check that EOD is above BOE
        ;
        LXI         D,boe_str
        LXI         H,eod_str
        CALL        track_sector_compare_for_carry_flag
        JNC         choice_eod_check
        LXI         D,boe_out_of_bounds_str

choice_eod_error:
        CALL        print_prompt_feedback_status
        CALL        prompt_current_line_again_for_track_and_sector
        JMP         choice_eod_parsed

choice_eod_check:
        ;
        ; Get EOE Track/Sector as BCD numbers
        ;
        LXI         H,00000H
        LDA         eoe_str
        CALL        ascii_to_bcd_digit
        LDA         eoe_str+1
        CALL        ascii_to_bcd_digit
        LDA         eoe_str+3
        CALL        ascii_to_bcd_digit
        LDA         eoe_str+4
        CALL        ascii_to_bcd_digit
        ;
        ; Increase EOE sector by 1 to get highest possible EOD
        ;
        XRA         A
        MOV         A,L
        INR         A
        DAA
        MOV         L,A
        ;
        ; Increase EOE track by 1 on overflow, this should never happen
        ;
        MOV         A,H
        ACI         0
        DAA
        MOV         H,A
        ;
        ; If sector is greater than 26, roll over to sector 1 of next track
        ;
        MOV         A,L
        CPI         027H
        JC          choice_eod_check_eoe
        MVI         L,1
        INR         H
        XRA         A
        MOV         A,H
        DAA
        MOV         H,A
choice_eod_check_eoe:
        ;
        ; Encode EOD high limit as a string
        ;
        LXI         D,max_eod_str
        MOV         A,H
        CALL        bcd_to_ascii_byte
        MVI         A,'0'
        STAX        D
        INX         D
        MOV         A,L
        CALL        bcd_to_ascii_byte
        ;
        ; Verify that file is within bounds
        ;
        LXI         D,eod_str
        LXI         H,max_eod_str
        CALL        track_sector_compare_for_carry_flag
        JNC         all_file_parameters_set
        LXI         D,eoe_out_of_bounds_str
        JMP         choice_eod_error


;//////////////////////////////////////////////////////////////////////////////

all_file_parameters_set:
        ;
        ; Make sure cursor is set right, in case prompts were skipped
        ;
        LXI         H,parameter_prompts_final_cursor_location
        SHLD        cursor_location_ptr
        CALL        move_cursor_to_next_location
        ;
        ; Check if target file to be allocated already exists
        ;
        LXI         H,target_filename
        SHLD        filename_ptr
        CALL        look_up_ibm_file
        RC
        LDA         new_replace_choice
        JZ          found_target_file
        CPI         'R'
        JNZ         allocate_new_file
        ;
        ; Replace file, target file does not exist, try to select replace file
        ;
        LXI         H,replace_filename
        SHLD        filename_ptr
        CALL        look_up_ibm_file
        JNZ         file_not_found_error
        JMP         allocate_current_file

found_target_file:
        CPI         'R'
        JNZ         target_file_already_exists_error
        ;
        ; Replace file, target file exists, verify that names match
        ;
        LXI         H,replace_filename
        LXI         D,target_filename
        MVI         A,17
        CALL        compare_memory
        JNZ         target_file_already_exists_error
        JMP         allocate_current_file

        ;
        ; New file, target file does not exist, all ok.
        ;
allocate_new_file:
        ;
        ; Scan for next deleted IBM file entry
        ;
        LXI         B,0*DISK_TRACK + 8*DISK_SECTOR
scan_for_free_file_entry_loop:
        CALL        read_ibm_disk_sector
        RC
        JNZ         allocate_current_file
        LXI         H,input_data_buffer
        LXI         D,deleted_file_label_id
        MVI         A,4
        CALL        compare_memory
        JZ          allocate_current_file
        MOV         A,C
        CPI         26
        JZ          directory_full_error
        INR         C
        JMP         scan_for_free_file_entry_loop


;//////////////////////////////////////

allocate_current_file:
        ;
        ; Change file signature from deleted to active
        ;
        LXI         H,input_data_buffer
        LXI         D,active_file_label_id
        MVI         B,4
        CALL        copy_memory
        ;
        ; Set new filename
        ;
        LXI         H,input_data_buffer+5
        LXI         D,target_filename
        MVI         B,17
        CALL        copy_memory
        ;
        ; Set new record length
        ;
        LXI         H,input_data_buffer+24
        LXI         D,record_length_str
        LDAX        D
        CPI         ' '
        JZ          record_length_set
        MVI         B,3
        CALL        copy_memory
record_length_set:
        ;
        ; Set new BOE
        ;
        LXI         H,input_data_buffer+28
        LXI         D,boe_str
        CALL        copy_5_bytes_if_nonzero
        ;
        ; Set new EOE
        ;
        LXI         H,input_data_buffer+34
        LXI         D,eoe_str
        CALL        copy_5_bytes_if_nonzero
        ;
        ; Set new bypass character
        ;
        LDA         bypass_char
        CPI         CR
        JZ          bypass_character_set
        STA         input_data_buffer+40
bypass_character_set:
        ;
        ; Set new access character
        ;
        LDA         access_char
        CPI         CR
        JZ          access_character_set
        STA         input_data_buffer+41
access_character_set:
        ;
        ; Set new protect character
        ;
        LDA         protect_char
        CPI         CR
        JZ          protect_character_set
        STA         input_data_buffer+42
protect_character_set:
        ;
        ; Set new creation date
        ;
        LXI         H,input_data_buffer+47
        LXI         D,creation_date_str
        LDAX        D
        CPI         CR
        JZ          creation_date_set
        MVI         B,6
        CALL        copy_memory
creation_date_set:
        ;
        ; Set new expiration date
        ;
        LXI         H,input_data_buffer+66
        LXI         D,expiration_date_str
        LDAX        D
        CPI         CR
        JZ          expiration_date_set
        MVI         B,6
        CALL        copy_memory
expiration_date_set:
        ;
        ; Set new verify character
        ;
        LDA         verify_char
        CPI         CR
        JZ          set_default_verify_character
        STA         input_data_buffer+72
        JMP         verify_character_set

set_default_verify_character:
        LDA         new_replace_choice
        CPI         'R'
        JZ          verify_character_set
        MVI         A,' '
        STA         input_data_buffer+72
verify_character_set:
        ;
        ; Set new EOD, force EOD to BOE if new file
        ;
        LXI         H,input_data_buffer+74
        LXI         D,eod_str
        CALL        copy_5_bytes_if_nonzero
        JC          write_updated_ibm_file_entry
        LDA         new_replace_choice
        CPI         'R'
        LXI         D,boe_str
        CNZ         copy_5_bytes_if_nonzero


;//////////////////////////////////////

        ;
        ; Write updated file-entry back to disk and exit program
        ;
write_updated_ibm_file_entry:
        CALL        write_ibm_disk_sector
        RC
        LXI         D,target_filename
        CALL        print_ibm_filename
        LXI         D,established_str
        CALL        print_str
        XRA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

wrong_device_type:
        MVI         A,ERROR_11
        STC
        RET


;//////////////////////////////////////

wrong_device_number:
        MVI         A,ERROR_13
        STC
        RET


;//////////////////////////////////////

filename_error:
        LXI         D,filename_error_str

print_error_and_exit:
        CALL        print_str
        XRA         A
        RET


;//////////////////////////////////////

unrecognized_file_label_found_error:
        LXI         D,unrecognized_file_label_found_id_str
        JMP         print_error_and_exit


;//////////////////////////////////////

target_file_already_exists_error:
        LXI         D,target_filename
        CALL        print_ibm_filename
        LXI         D,already_exists_str
        JMP         print_error_and_exit


;//////////////////////////////////////

directory_full_error:
        LXI         D,directory_packed_str
        JMP         print_error_and_exit


;//////////////////////////////////////

file_not_found_error:
        LXI         D,replace_filename
        CALL        print_ibm_filename
        LXI         D,not_found_str
        JMP         print_error_and_exit


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Exit program from any call level
        ;
fatal_error:
        LHLD        sp_backup
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print ETX-terminated string
        ;
print_str:
        LDAX        D
        CPI         ETX
        RZ
        CALL        print_char
        INX         D
        JMP         print_str


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print IBM filename
        ;
print_ibm_filename:
        PUSH        B
        MVI         B,8
print_ibm_filename_loop:
        LDAX        D
        CPI         ' '
        JZ          print_ibm_filename_end
        CALL        print_char
        INX         D
        DCR         B
        JNZ         print_ibm_filename_loop
print_ibm_filename_end:
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print a single character to console
        ;
print_char:
        ;
        ; Use XMON API for text and TOS API for control characters
        ;
        CPI         ' '
        JC          print_char_tos
        CALL        TTO
        RET


;//////////////////////////////////////

        ;
        ; Print a single characters to console using TOS
        ;
print_char_tos:
        PUSH        H
        LHLD        CO_FCB
        CALL        OUTCHAR
        JC          fatal_error
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy 5 bytes if first byte is nonzero, for track/sector string
        ;
copy_5_bytes_if_nonzero:
        LDAX        D
        CPI         CR
        RZ
        MVI         B,5
        CALL        copy_memory
        STC
        RET


;//////////////////////////////////////

        ;
        ; Verify results from track/sector prompt
        ;
check_track_sector_input:
        LDA         new_replace_choice
        CPI         'R'
        RZ
        MOV         A,B
        CPI         5
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Run next prompt
        ;
prompt_next_line:
        CALL        move_cursor_to_next_location
run_prompt:
        CALL        get_input_line
        JNC         check_for_home

        ;
        ; Retry on current prompt
        ;
prompt_current_line_again:
        CALL        reset_current_prompt
        JMP         run_prompt

        ;
        ; Restart parameter prompts from start if the Home-key was pressed
        ;
check_for_home:
        LXI         D,input_line_buffer
        LDAX        D
        CPI         CURH
        RNZ
        LHLD        sp_backup
        SPHL
        JMP         get_fresh_file_parameters


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prompt and parse for track and sector
        ;
prompt_next_line_for_track_and_sector:
        CALL        prompt_next_line
parse_prompt_track_sector:
        CPI         CR
        JNZ         choice_track_sector_has_input
        ;
        ; Update pointers and set length to 1 if no data
        ;
        LXI         D,input_line_buffer
        MVI         B,1
        RET

choice_track_sector_has_input:
        ;
        ; Decode track number and expect deliminer character
        ;
        CALL        ascii_to_bcd_byte_with_verify
        CPI         '/'
        JZ          track_number_decoded
        CPI         ','
        JZ          track_number_decoded
        CPI         ' '
        JZ          track_number_decoded

invalid_track_sector_format:
        LXI         D,improper_parameter_str
        JMP         choice_track_sector_error

invalid_track:
        LXI         D,improper_track_str
        JMP         choice_track_sector_error

invalid_sector:
        LXI         D,improper_sector_str

choice_track_sector_error:
        CALL        print_prompt_feedback_status

        ;
        ; Retry prompt after error
        ;
prompt_current_line_again_for_track_and_sector:
        CALL        prompt_current_line_again
        JMP         parse_prompt_track_sector

track_number_decoded:
        ;
        ; Decode sector number
        ;
        MOV         C,L
        INX         D
        CALL        ascii_to_bcd_byte_with_verify
        CPI         CR
        JNZ         invalid_track_sector_format
        ;
        ; Check that track number (in BCD format) is within range
        ;
        LXI         D,input_line_buffer
        MOV         A,C
        ANA         A
        JZ          invalid_track
        CPI         077H
        JNC         invalid_track
        ;
        ; Store track number and deliminer as expected by IBM
        ;
        CALL        bcd_to_ascii_byte
        MVI         A,'0'
        STAX        D
        INX         D
        ;
        ; Check that sector number (in BCD format) is within range
        ;
        MOV         A,L
        ORA         A
        JZ          invalid_sector
        CPI         027H
        JNC         invalid_sector
        ;
        ; Store sector number
        ;
        CALL        bcd_to_ascii_byte
        ;
        ; Update pointers and set length
        ;
        MVI         B,5
        LXI         D,input_line_buffer
        RET


;//////////////////////////////////////

        ;
        ; Verify and convert two ASCII characters to BCD byte
        ;
ascii_to_bcd_byte_with_verify:
        LXI         H,0
        CALL        ascii_to_bcd_digit_with_verify
        RC
        CALL        ascii_to_bcd_digit_with_verify
        RC
        LDAX        D
        RET


;//////////////////////////////////////

        ;
        ; Verify and convert ASCII character to BCD digit
        ;
ascii_to_bcd_digit_with_verify:
        LDAX        D
        CALL        is_numeric_ascii
        RC
        CALL        ascii_to_bcd_digit
        INX         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Compare two track-sector strings, carry cleared if (HL) > (DE)
        ;
track_sector_compare_for_carry_flag:
        CALL        compare_dual_digits_for_carry_flag
        RNZ
        INX         H
        INX         D
        CALL        compare_dual_digits_for_carry_flag
        RNZ
        ANA         A
        RET


;//////////////////////////////////////

        ;
        ; Compare two digits of two strings, carry cleared if (HL) > (DE)
        ;
compare_dual_digits_for_carry_flag:
        CALL        compare_digit_for_carry_flag
        RNZ

        ;
        ; Compare one digit of two strings, carry cleared if (HL) > (DE)
        ;
compare_digit_for_carry_flag:
        LDAX        D
        CMP         M
        CMC
        RNZ
        INX         H
        INX         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print status after a failed prompt, as feedback for the user
        ;
print_prompt_feedback_status:
        PUSH        H
        LHLD        cursor_location_ptr
        PUSH        H
        LXI         H,parameter_prompts_final_cursor_location
        SHLD        cursor_location_ptr
        CALL        move_cursor_to_next_location
        CALL        print_str
        POP         H
        SHLD        cursor_location_ptr
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prompt and parse for date
        ;
prompt_next_line_for_date:
        PUSH        H
        CALL        prompt_next_line
parse_prompt_date:
        ;
        ; Check if none or empty date entered
        ;
        CPI         CR
        JZ          choice_date_none
        MVI         B,6
        CPI         ' '
        JZ          choice_date_empty
        ;
        ; Validate date
        ;
validate_date_loop:
        LDAX        D
        CALL        is_numeric_ascii
        JC          choice_date_invalid
        INX         D
        DCR         B
        JNZ         validate_date_loop
        LDAX        D
        CPI         CR
        JZ          choice_date_valid
choice_date_invalid:
        CALL        prompt_current_line_again
        JMP         parse_prompt_date

        ;
        ; Return empty string
        ;
choice_date_none:
        POP         H
        MOV         M,A
        RET

        ;
        ; Fill the date string
        ;
choice_date_empty:
        LXI         D,input_line_buffer
empty_date_loop:
        MOV         M,A
        INX         D
        DCR         B
        JNZ         empty_date_loop

        ;
        ; Copy over valid date-string
        ;
choice_date_valid:
        POP         H
        LXI         D,input_line_buffer
        MVI         B,6
        CALL        copy_memory
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Verify if number in A is an ASCII number
        ;
is_numeric_ascii:
        CPI         '0'
        RC
        CPI         '9'+1
        CMC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII character to uppercase
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
        ; Convert ASCII number in A to BCD digit and append to BCD number in HL
        ;
ascii_to_bcd_digit:
        DAD         H
        DAD         H
        DAD         H
        DAD         H
        SUI         '0'
        ORA         L
        MOV         L,A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Validate and copy IBM filename
        ;
copy_valid_filename:
        ;
        ; Check each character in filename
        ;
verify_next_filename_char:
        LDAX        D
        CPI         CR
        JZ          pad_out_filename_buffer
        CPI         '0'
        JC          invalid_filename_char
        CPI         '9'+1
        JC          valid_filename_char
        CPI         'A'
        JC          invalid_filename_char
valid_filename_char:
        ;
        ; Copy character if everything is OK
        ;
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         verify_next_filename_char
invalid_filename_char:
        STC
        RET

        ;
        ; Make sure the tailing of the filename buffer is all spaces
        ;
pad_out_filename_buffer:
        MVI         M,' '
        INX         H
        DCR         B
        JNZ         pad_out_filename_buffer
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert BCD byte in A to two ASCII characters in string at (DE)
        ;
bcd_to_ascii_byte:
        PUSH        PSW
        RRC
        RRC
        RRC
        RRC
        CALL        bcd_to_ascii_digit
        POP         PSW

        ;
        ; Convert BCD digit in A to ASCII character in string at (DE)
        ;
bcd_to_ascii_digit:
        ANI         00FH
        ADI         '0'
        STAX        D
        INX         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Move cursor to next location in a list of column-row bytepairs
        ;
move_cursor_to_next_location:
        PUSH        H
        PUSH        D
        LHLD        cursor_location_ptr
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        SHLD        cursor_location_ptr
        XCHG
        CALL        CURSOR
        PUSH        PSW
        ;
        ; Set TOS autoscroll to new line if hardware autoscroll is disabled
        ;
        LDA         ROLLSW
        ANA         A
        JZ          autoscroll_updated
        MOV         A,H
        ADI         'A'
        STA         ROLLSW
autoscroll_updated:
        POP         PSW
        POP         D
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get a complete line from TOS console-input
        ;
get_input_line:
        ;
        ; Wait for any input at all
        ;
wait_for_keyboard_input:
        LDA         KEYBUF
        ORA         A
        JZ          wait_for_keyboard_input
        ;
        ; Clear previous status-printout
        ;
        LHLD        cursor_location_ptr
        PUSH        H
        LXI         H,parameter_prompts_final_cursor_location
        SHLD        cursor_location_ptr
        CALL        move_cursor_to_next_location
        MVI         A,' '
        MVI         L,50
clear_status_print_loop:
        CALL        TTO
        DCR         L
        JNZ         clear_status_print_loop
        POP         H
        DCX         H
        DCX         H
        SHLD        cursor_location_ptr
        CALL        move_cursor_to_next_location
        ;
        ; Get the line
        ;
        LXI         D,input_line_buffer
        LHLD        CI_FCB
        CALL        GET
        XCHG
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear and restart the currently active prompt
        ;
reset_current_prompt:
        MVI         A,BEL
        CALL        TTO
        CALL        set_cursor_to_current_location
        ;
        ; Clear previous answer, both buffer and console echo
        ;
        LXI         D,input_line_buffer
clear_previous_input_loop:
        LDAX        D
        CPI         CR
        JZ          set_cursor_to_current_location
        MVI         A,' '
        CALL        TTO
        INX         D
        JMP         clear_previous_input_loop


;//////////////////////////////////////

        ;
        ; Restore cursor back to previously set location
        ;
set_cursor_to_current_location:
        LHLD        cursor_location_ptr
        DCX         H
        DCX         H
        SHLD        cursor_location_ptr
        CALL        move_cursor_to_next_location
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy B bytes from (DE) to (HL)
        ;
copy_memory:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         copy_memory
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Try to find a particular data label on an IBM-3740 formatted disk
        ;
look_up_ibm_file:
        ;
        ; Start at start of file table, track 0 sector 8
        ;
        LXI         B,0*DISK_TRACK + 8*DISK_SECTOR
check_ibm_data_label:
        ;
        ; Read data-label from disk
        ;
        CALL        read_ibm_disk_sector
        RC
        JNZ         check_next_ibm_data_label
        ;
        ; Skip if deleted file
        ;
        LXI         D,deleted_file_label_id
        LXI         H,input_data_buffer
        MVI         A,4
        CALL        compare_memory
        JZ          check_next_ibm_data_label
        ;
        ; Check if filename matches what we are looking for
        ;
        LHLD        filename_ptr
        XCHG
        LXI         H,input_data_buffer+5
        MVI         A,17
        CALL        compare_memory
        RZ
        ;
        ; Go check next file until we reach the end of the file-table
        ;
check_next_ibm_data_label:
        MOV         A,C
        CPI         26
        INX         B
        JNZ         check_ibm_data_label
        ORA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read a sector from an IBM 3740-formatted disk
        ;
read_ibm_disk_sector:
        LDA         drive_number
        CALL        read_ibm_sector_call
        JC          handle_peculiar_sector
        XRA         A
        RET

handle_peculiar_sector:
        ;
        ; Check if sector is deleted
        ;
        CPI         ERROR_20
        JNZ         error_reading_sector
        ORA         A
        PUSH        PSW
        ;
        ; Check if drive type indicates ASCII or EBCDIC formatted IBM disk
        ;
        LDA         drive_designator_str+1
        CPI         'I'
        JNZ         deleted_sector_ready
        ;
        ; Locally translate deleted sector to ASCII if EBCDIC-format is assumed
        ;
        PUSH        B
        MVI         B,000H
        LXI         D,input_data_buffer
        MVI         A,128
convert_deleted_sector:
        PUSH        PSW
        LHLD        ASCI
        LDAX        D
        MOV         C,A
        DAD         B
        MOV         A,M
        STAX        D
        INX         D
        POP         PSW
        DCR         A
        JNZ         convert_deleted_sector
        POP         B

        ;
        ; Data of deleted sector ready
        ;
deleted_sector_ready:
        POP         PSW
        RET

        ;
        ; Something went wrong reading sector
        ;
error_reading_sector:
        STC
        RET


;//////////////////////////////////////

        ;
        ; Do appropriate read-sector system call
        ;
read_ibm_sector_call:
        LHLD        read_call

        ;
        ; Do disk-based system call
        ;
ibm_sector_system_call:
        PUSH        H
        LXI         H,input_data_buffer
        RET


;//////////////////////////////////////

        ;
        ; Do appropriate write-sector system call
        ;
write_ibm_disk_sector:
        LDA         drive_number
        LHLD        write_call
        JMP         ibm_sector_system_call


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Compare C bytes of memory at (DE) with (HL)
        ;
compare_memory:
        PUSH        B
        MOV         C,A
compare_memory_loop:
        LDAX        D
        CMP         M
        JNZ         done_comparing_memory
        INX         H
        INX         D
        DCR         C
        JNZ         compare_memory_loop
done_comparing_memory:
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

parameter_prompts_cursor_locations:
        DB          00AH, 000H
        DB          00DH, 001H
        DB          00FH, 002H
        DB          00BH, 003H
        DB          00BH, 004H
        DB          019H, 006H
        DB          008H, 008H
        DB          00DH, 009H
        DB          009H, 00AH
        DB          00FH, 00BH
        DB          011H, 00CH
        DB          008H, 00DH
        DB          00BH, 00EH
parameter_prompts_final_cursor_location:
        DB          000H, 010H

drive_designator_str:
        DB          ':I0:',ETX
target_filename:
        DB          'DATA'
        DS          13

replace_filename:
        DB          CR
        DS          16
record_length_str:
        DS          3
boe_str:
        DS          5
eoe_str:
        DS          5
bypass_char:
        DS          1
access_char:
        DS          1
protect_char:
        DS          1
creation_date_str:
        DS          6
expiration_date_str:
        DS          6
verify_char:
        DS          1
eod_str:
        DS          5
max_eod_str:
        DS          5
        DB          '      '

filename_ptr:
        DS          2
cursor_location_ptr:
        DS          2
drive_number:
        DS          1
sp_backup:
        DS          2
new_replace_choice:
        DS          1
read_call:
        DS          2
write_call:
        DS          2

input_line_buffer:
        DS          128
input_data_buffer:
        DS          128

active_file_label_id:
        DB          'HDR1'
deleted_file_label_id:
        DB          'DDR1'

end_sector_boe_str:
        DB          '73026'
end_sector_eoe_str:
        DB          '73026'

parameter_prompts_str:
        DB          ERPAG
        DB          'FILENAME: ',CR,LF
        DB          'REPLACE/NEW: ',CR,LF
        DB          'RECORD LENGTH: ',CR,LF
        DB          'BOE (T/S): ',CR,LF
        DB          'EOE (T/S): ',CR,LF,LF
        DB          'REMAINDER DEFAULT (Y/N): ',CR,LF,LF
        DB          'BYPASS: ',CR,LF
        DB          'ACCESS CHAR: ',CR,LF
        DB          'PROTECT: ',CR,LF
        DB          'CREATION DATE: ',CR,LF
        DB          'EXPIRATION DATE: ',CR,LF
        DB          'VERIFY: ',CR,LF
        DB          'EOD (T/S): ',CR,LF,ETX

filename_error_str:
        DB          'FILENAME ERROR',CR,LF,ETX
unrecognized_file_label_found_id_str:
        DB          'UNRECOGNIZED LABEL ID',CR,LF,ETX
already_exists_str:
        DB          ', ALREADY EXISTS',CR,LF,ETX
directory_packed_str:
        DB          'DIRECTORY PACKED',CR,LF,ETX
not_found_str:
        DB          ', NOT FOUND',CR,LF,ETX
established_str:
        DB          ', ESTABLISHED',CR,LF,ETX
improper_record_length_str:
        DB          'IMPROPER RECORD LENGTH',CR,LF,ETX
no_default_parameter_str:
        DB          'DEFAULT PARAMETER NOT ALLOWED',CR,LF,ETX
improper_parameter_str:
        DB          'IMPROPER PARAMETER LIST',CR,LF,ETX
boe_out_of_range_str:
        DB          'BOE > 73/26 NOT ALLOWED',CR,LF,ETX
eoe_out_of_range_str:
        DB          'EOE > 73/26 NOT ALLOWED',CR,LF,ETX
boe_out_of_eoe_str:
        DB          'BOE > EOE NOT ALLOWED',CR,LF,ETX
boe_out_of_bounds_str:
        DB          'EOD < BOE NOT ALLOWED',CR,LF,ETX
eoe_out_of_bounds_str:
        DB          'EOD > EOE+1 NOT ALLOWED',CR,LF,ETX
improper_track_str:
        DB          'IMPROPER TRACK VALUE',CR,LF,ETX
improper_sector_str:
        DB          'IMPROPER SECTOR VALUE',CR,LF,ETX
