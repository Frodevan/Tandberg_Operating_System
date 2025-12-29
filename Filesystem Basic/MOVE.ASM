;//////////////////////////////////////////////////////////////////////////////
;//
;//     MOVE - Move data between sources and destinations
;//
;//         Extra parameters:
;//
;//             :F0: filecopy   $<filename>
;//             :LP: output     [$[lines][H][EOF=<eof>][Q]]
;//             Otherwise       [$[H][EOF=<eof>]]
;//
;//
;//                 filename    Filename of input file
;//                 lines       Page-length of output print, default 0 (no paging)
;//                 H           Enables binary to ASCII hexadecimal conversion
;//                 eof         End-of-File char to end the move, default Ctrl-C
;//                 Q           Immediately abort transfer before starting
;//
;//
;//                 NOTE: [EOF=<eof>] is only applicable if SI is explicitly
;//                       assigned to a polling-device, such as the keyboard or
;//                       the serial port. Default is none, where a 'Q' needs to be
;//                       typed on the keyboard to end the move, except when the
;//                       console is chosen as the input source. In that case
;//                       Ctrl-C is the default keystroke to end the move.
;//
;//
;//         Moves data from SI to SO. This tool also has various operating modes,
;//         depending on what is chosen as input and output devices/files. In most
;//         cases, a move can be prematurely stopped by pressing the 'Q' key on the
;//         keyboard.
;//
;//         If CI or :CI: is chosen as input source, the user can type data
;//         directly into the output target, with console echo.
;//
;//         If the output destination equals CO, data will be printed to screen in
;//         full pages. If there is any non-ASCII in the first line in the input,
;//         or the first line is too long (more than 132 chars), then the user will
;//         be prompted if they wish to enable the hexadecimal option for the rest
;//         of the file.
;//
;//         Should :LP: be used as output, a custom page-length (0, or 24-127) will
;//         be asked for. If set to a non-zero value, each page will be padded with
;//         4 blank lines of margin both at the top and at the bottom.
;//
;//         There is a single-floppy diskswap copy mode, which is invoked by only
;//         assigning SO=:F0:<filename>. In this mode, the input file name will
;//         need to be provided by the user as an extra argument or on a prompt.
;//         This mode is purely a 1:1 file-copy mode, and does not combine with
;//         the hexadecimal argument or other modes.
;//
;//         The hexadecimal option will print the input data in paragraphs of 8
;//         lines, with 16 ASCII hexadecimal bytevalues per line. Each paragraph
;//         as such represents 128 bytes of data.
;//
;//         NOTE: If SO is not assigned, SL is used. If neither SO or SL are
;//               assigned, then CO is chosen as output as a last-resort.
;//
;//         NOTE: This version expects a gap of RAM between the XMON working area
;//               and TOS user RAM. As such, it will not work on machines equipped
;//               with the full 54KB of RAM.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//
;//             1.5a: Entry at 0x2000
;//
;//                 -> Completely rewritten to be more general purpose, replacing
;//                    the earlier more specialized HEXLST, TYPE and COPY tools
;//                 -> Has a bug where the wrong error code is reported if the user
;//                    has specified an invalid argument for the custom EOF
;//
;//             1.5b: Entry at 0x2000
;//
;//                 -> Handles END-OF-BLOCK status for IBM file types :Bn: and :Jn:
;//
;//             1.6a: Entry at 0xC000
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Flag values
;
FALSE       EQU     0           ; Boolean False
TRUE        EQU     1           ; Boolean True

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
ETX         EQU     003H        ; End of text
BEL         EQU     007H        ; Bell (short beep)
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return
ERPAG       EQU     019H        ; Clear screen

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
PRNT        EQU     00052H      ; Printer port output
DCALW       EQU     00070H      ; Reset disk drive with wait

;
; XMON and TOS system data
;
BUFLIM      EQU     0272EH      ; Lowest address of current TOS buffers
KEYBUF      EQU     02780H      ; Console input buffer

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
OPEN        EQU     0FD1EH      ; Open block device
EDBH        EQU     0FD2AH      ; Convert byte to 2-character ASCII hexadecimal
EDHB        EQU     0FD30H      ; Convert 2-character ASCII hexadecimal to byte
PHYSINT     EQU     0FDDFH      ; Initialize FCB from full file designator

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer

;
; TOS Errors
;
ERROR_0F    EQU     00FH        ; DISKETTE MAP MISSING
ERROR_19    EQU     019H        ; UNASSIGNED DEVICE
ERROR_5C    EQU     05CH        ; END-OF-BLOCK (B AND J FILES)

;
; TOS File Control Block, block device variables
;
FCB_DEVTYP  EQU     010H        ; Block-device type

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag
FM_BINARY   EQU     004H        ; Binary flag

;
; Output filetype enumerator
;
OT_ENUM_F0  EQU     1           ; First floppy disk drive file output
OT_ENUM_CO  EQU     2           ; Console output
OT_ENUM_LP  EQU     3           ; Line-printer output
OT_ENUM_OT  EQU     4           ; Other output


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Legacy program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02000H
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

main:
        ;
        ; Fill buffer with data from input file
        ;
        CALL        read_data_from_input
        ;
        ; Put top margin on first page in printer output mode, if needed
        ;
        LDA         printer_paged_output_flag
        ORA         A
        JZ          initial_page_margin_done
        LDA         lines_text_per_page
        ORA         A
        JZ          initial_page_margin_done
        MVI         B,4
        CALL        write_newlines_to_output
initial_page_margin_done:
        ;
        ; Clear screen if console is output
        ;
        LDA         console_paged_output_flag
        ORA         A
        JZ          main_move_loop
        MVI         A,ERPAG
        CALL        TTO
        ;
        ; Move all data from input to output file
        ;
main_move_loop:
        XRA         A
        STA         first_read_flag
        CALL        write_data_to_output
        LDA         finished_flag
        ORA         A
        JNZ         move_done
        CALL        read_data_from_input
        JMP         main_move_loop

move_done:
        ;
        ; Add final newline if hexadecimal output mode
        ;
        LDA         hex_output_mode_flag
        ORA         A
        JZ          cleanup_and_quit
        CALL        write_newline_to_output
        XRA         A


;//////////////////////////////////////

        ;
        ; Clean up state of program and quit to TOS
        ;
cleanup_and_quit:
        ;
        ; Unnasign SI file if single-disk drive copy mode
        ;
        PUSH        PSW
        LDA         f0_diskswap_filecopy_flag
        ORA         A
        JZ          unassignements_done
        LXI         H,00000H
        SHLD        SI_FCB
        JMP         restore_keyboard_buffer

unassignements_done:
        ;
        ; Put end margin on last page in printer output mode, if needed
        ;
        LDA         printer_paged_output_flag
        ORA         A
        JZ          end_page_margin_done
        LDA         lines_text_per_page
        ORA         A
        JZ          end_page_margin_done
        ;
        ; Add any remaining lines that were not printed on page to end margin
        ;
        MOV         B,A
        LDA         current_line_on_page
        SUB         B
        CMA
        ADI         5
        MOV         B,A
        CALL        write_newlines_to_output
end_page_margin_done:
        ;
        ; Make sure to expect an input keystroke at last page if console output
        ;
        LDA         console_paged_output_flag
        ORA         A
        JZ          restore_keyboard_buffer
        CALL        TTI
        ;
        ; Restore any captured pending keyboard input
        ;
restore_keyboard_buffer:
        LXI         D,saved_kbd_input_fifo
        LXI         H,KEYBUF
        MVI         B,32
restore_next_kbd_char:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         restore_next_kbd_char
        ;
        ; Restore potential error status
        ;
        POP         PSW
hard_break_exit:
        ;
        ; Restore stack pointer and exit program
        ;
        LHLD        stack_pointer_backup
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines for main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Try to fill entire buffer with data read from input file
        ;
read_data_from_input:
        ;
        ; Prompt user to swap to input disk if diskswap :F0: filecopy mode
        ;
        LDA         f0_diskswap_filecopy_flag
        ORA         A
        JZ          ready_for_input
        LXI         D,input_disk_str
        CALL        diskswap_prompt
        ;
        ; Open input file first if first time data is read
        ;
        LDA         first_read_flag
        ORA         A
        JZ          ready_for_input
        LHLD        SI_FCB
        MVI         A,FM_INPUT
        CALL        OPEN
        JC          cleanup_and_quit
ready_for_input:
        ;
        ; Get buffer pointer, buffer size and FCB pointer ready
        ;
        LHLD        data_buffer_size
        MOV         B,H
        MOV         C,L
        LHLD        data_buffer_ptr
        XCHG
        LHLD        SI_FCB
input_loop:
        ;
        ; Check for modes that have their own (or no) keyboard handling
        ;
        LDA         f0_diskswap_filecopy_flag
        ORA         A
        JNZ         read_next_input_byte
        LDA         console_input_mode_flag
        ORA         A
        JNZ         read_next_input_byte
        LDA         console_paged_output_flag
        ORA         A
        JNZ         read_next_input_byte
        ;
        ; Check for pending keyboard input
        ;
        LDA         KEYBUF
        ORA         A
        JZ          read_next_input_byte
        ;
        ; If so, cache it for later, and also check if user wants to abort move
        ;
        CALL        save_pending_kbd_input
        CPI         'Q'
        JZ          cleanup_and_quit
        JMP         input_loop

read_next_input_byte:
        ;
        ; Get next input byte
        ;
        CALL        INCHAR
        JC          error_reading_input
        ;
        ; Check if input data needs to be echoed to console
        ;
        PUSH        B
        MOV         B,A
        LDA         echo_input_mode_flag
        ORA         A
        JZ          echo_input_done
        MOV         A,B
        ;
        ; Don't echo most control chars, except cartridge-return and newline
        ;
        CPI         ' '
        JNC         echo_input
        CPI         CR
        JZ          echo_input
        CPI         LF
        JNZ         echo_input_done
echo_input:
        PUSH        H
        LHLD        CO_FCB
        CALL        write_byte_to_file
        POP         H
echo_input_done:
        ;
        ; Check if EOF character is set, and if it has been encountered
        ;
        LDA         custom_eof_flag
        ORA         A
        JZ          no_custom_eof
        LDA         custom_eof
        CMP         B
        MOV         A,B
        POP         B
        JZ          end_of_input
        JMP         save_input_to_buffer

no_custom_eof:
        MOV         A,B
        POP         B
        ;
        ; Add input byte to buffer and advance to next input byte
        ;
save_input_to_buffer:
        STAX        D
        INX         D
        DCX         B
        MOV         A,B
        ORA         C
        JNZ         input_loop
        JMP         buffer_full


;//////////////////////////////////////

error_reading_input:
        ;
        ; Check for end of file
        ;
        ORA         A
        JZ          end_of_input
        ;
        ; Check for end-of-block for IBM file type B and J
        ;
        CPI         ERROR_5C
        JZ          read_next_input_byte
        STC
        JMP         cleanup_and_quit

end_of_input:
        ;
        ; Set move-done flag
        ;
        MVI         A,TRUE
        STA         finished_flag
        ;
        ; Resize buffer to equal length of final block of bytes read
        ;
        LHLD        data_buffer_ptr
        MOV         A,H
        CMA
        INR         A
        MOV         B,A
        MVI         C,000H
        XCHG
        DAD         B
        SHLD        data_buffer_size
        ;
        ; Handle a full buffer
        ;
buffer_full:
        ;
        ; Prompt user to swap to output disk if diskswap :F0: filecopy mode
        ;
        LDA         f0_diskswap_filecopy_flag
        ORA         A
        JZ          assess_output_mode
        LXI         D,output_disk_str
        CALL        diskswap_prompt
        RET

        ;
        ; Evaluate if hexadecimal conversion should be turned on based on input
        ;
assess_output_mode:
        ;
        ; Only check for first read, and if hex conversion is initially off
        ;
        LDA         first_read_flag
        ORA         A
        RZ
        LDA         hex_output_mode_flag
        ORA         A
        RNZ
        ;
        ; Also only check in the case of console or printer output
        ;
        LDA         console_paged_output_flag
        LXI         H,printer_paged_output_flag
        ORA         M
        RZ
        ;
        ; Scan for potential non-ASCII data in first line of input
        ;
        LHLD        data_buffer_ptr
        MVI         B,132+1
check_input_char:
        ;
        ; Check if at line end
        ;
        MOV         A,M
        CPI         CR
        RZ
        ;
        ; Check if char is reasonable ASCII data
        ;
        CPI         ' '
        JNC         check_next_input_char
        CPI         LF-1
        JC          hex_or_ascii_prompt
        CPI         CR
        JNC         hex_or_ascii_prompt
check_next_input_char:
        ;
        ; Advance to next character
        ;
        INX         H
        DCR         B
        JNZ         check_input_char
        ;
        ; Line is not expected to be longer than 132 chars (excluding CR)
        ;
hex_or_ascii_prompt:
        ;
        ; Suspicion of non-ASCII data, prompt if user want hex conversion mode
        ;
        LXI         D,hex_or_ascii_prompt_str
        LHLD        CO_FCB
        CALL        PUTSTR
parse_hex_or_ascii_choice:
        ;
        ; Get choice and convert to uppercase
        ;
        CALL        TTI
        CPI         'a'-1
        JC          hex_or_ascii_choice_is_uppercase
        SUI         'a' - 'A'
hex_or_ascii_choice_is_uppercase:
        ;
        ; Verify choice against possible options
        ;
        LXI         D,option_a_str
        CPI         'A'
        JZ          hex_or_ascii_prompt_end
        LXI         D,option_q_str
        CPI         'Q'
        JZ          hex_or_ascii_prompt_end
        CPI         'H'
        JNZ         parse_hex_or_ascii_choice
        ;
        ; Hexadecimal conversion selected, update flags
        ;
        MVI         A,TRUE
        STA         hex_output_mode_flag
        LXI         D,option_h_str
hex_or_ascii_prompt_end:
        ;
        ; Print choice and check if user decided to abort move early
        ;
        PUSH        PSW
        CALL        PUT
        POP         PSW
        CPI         'Q'
        RNZ
        LDA         console_paged_output_flag
        ORA         A
        JZ          cleanup_and_quit
        JMP         hard_break_exit


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prompt user for disk-swap, with DE pointing to disk type string
        ;
diskswap_prompt:
        ;
        ; Print prompt message
        ;
        PUSH        D
        LXI         D,insert_disk_str
        LHLD        CO_FCB
        CALL        PUTSTR
        POP         D
        CALL        PUTSTR
        LXI         D,continue_prompt_str
        CALL        PUTSTR
        ;
        ; Flush keyboard input
        ;
        XRA         A
        STA         KEYBUF
parse_diskswap_choice:
        ;
        ; Get prompt input and verify choice
        ;
        CALL        TTI
        CPI         'Q'
        JZ          cleanup_and_quit
        CPI         'q'
        JZ          cleanup_and_quit
        CPI         'C'
        JZ          diskswap_choice_continue
        CPI         'c'
        JNZ         parse_diskswap_choice
diskswap_choice_continue:
        ;
        ; Print continue choice and reset disk
        ;
        LXI         D,option_c_str
        LHLD        CO_FCB
        CALL        PUT
        XRA         A
        CALL        DCALW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Save any pending keyboard input into a buffer for later use
        ;
save_pending_kbd_input:
        ;
        ; Get pending keyboard data, check if user want to end move early
        ;
        CALL        TTI
        CPI         'Q'
        JZ          abort_move
        CPI         'q'
        JNZ         add_kbd_input_to_cache
abort_move:
        ;
        ; Clear pending keyboard input buffer if aborting move
        ;
        XRA         A
        STA         saved_kbd_input_fifo
        MVI         A,'Q'
        RET

add_kbd_input_to_cache:
        ;
        ; Get index of fifo buffer tail, and check if the buffer is full
        ;
        STA         current_kbd_char
        LDA         saved_kbd_input_fifo
        CPI         32-1
        RZ
        ;
        ; Append keyboard char to end of fifo buffer
        ;
        INR         A
        STA         saved_kbd_input_fifo
        PUSH        H
        PUSH        B
        LXI         H,saved_kbd_input_fifo
        MOV         C,A
        MVI         B,000H
        DAD         B
        LDA         current_kbd_char
        MOV         M,A
        POP         B
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write entire buffer to output file
        ;
write_data_to_output:
        ;
        ; Get size of buffer, pointer to buffer and pointer to output FCB
        ;
        LHLD        data_buffer_size
        MOV         B,H
        MOV         C,L
        LHLD        data_buffer_ptr
        XCHG
        LHLD        SO_FCB
write_output_byte:
        ;
        ; Check if we are through buffer
        ;
        MOV         A,B
        ORA         C
        RZ
        ;
        ; Check for hexadecimal conversion mode
        ;
        LDA         hex_output_mode_flag
        ORA         A
        JZ          write_byte_as_is
        ;
        ; If active, get next byte, convert to hexadecimal, and write to output
        ;
        LDAX        D
        LXI         H,converted_decimal_ascii
        CALL        EDBH
        LHLD        SO_FCB
        LDA         converted_decimal_ascii
        CALL        write_byte_to_file
        LDA         converted_decimal_ascii+1
        CALL        write_byte_to_file
        MVI         A,' '
        CALL        write_byte_to_file
        ;
        ; Advance hexbyte-per-line counter and check if line is full
        ;
        LDA         hex_byte_counter
        INR         A
        STA         hex_byte_counter
        CPI         16
        JNZ         write_byte_done
        ;
        ; If so, insert newline into output and reset counter
        ;
        CALL        write_newline_to_output
        CALL        advance_page_mode_line
        XRA         A
        STA         hex_byte_counter
        ;
        ; Advance lines-in-paragraph counter and check if paragraph is full
        ;
        LDA         line_in_paragraph_counter
        INR         A
        STA         line_in_paragraph_counter
        CPI         8
        JNZ         write_byte_done
        ;
        ; If so, insert an empty line into output and reset counter
        ;
        CALL        write_newline_to_output
        CALL        advance_page_mode_line
        XRA         A
        STA         line_in_paragraph_counter
        JMP         write_byte_done

write_byte_as_is:
        ;
        ; Write byte to output with no alteration
        ;
        LDAX        D
        CALL        write_byte_to_file
        ;
        ; Advance char counter and check for console output mode
        ;
        LDA         char_counter
        INR         A
        STA         char_counter
        LDA         console_paged_output_flag
        ORA         A
        JZ          not_console_page_mode
        ;
        ; If so, assume auto wrap-around is active and check for this
        ;
        LDA         char_counter
        CPI         80
        JNZ         check_for_page_mode_newline
        ;
        ; Handle line wrap-around
        ;
        XRA         A
        STA         char_counter
        CALL        advance_page_mode_line
        JMP         check_for_page_mode_newline

not_console_page_mode:
        ;
        ; Check for printer page mode
        ;
        LDA         printer_paged_output_flag
        ORA         A
        JZ          write_byte_done
        ;
        ; Check for and handle the occurences of newline in paged modes
        ;
check_for_page_mode_newline:
        ;
        ; Get back last output character and check for part of newline
        ;
        LDAX        D
        CPI         CR
        JNZ         line_feed_check
        XRA         A
        STA         char_counter
line_feed_check:
        CPI         LF
        CZ          advance_page_mode_line
        ;
        ; Write complete, maintain user input that happened in the meantime
        ;
write_byte_done:
        ;
        ; Check for modes that have their own (or no) keyboard handling
        ;
        LDA         console_paged_output_flag
        ORA         A
        JNZ         write_next_output_byte
        LDA         console_input_mode_flag
        ORA         A
        JNZ         write_next_output_byte
        ;
        ; Check for pending keyboard input
        ;
        LDA         KEYBUF
        ORA         A
        JZ          write_next_output_byte
        ;
        ; If so, cache it for later, and also check if user wants to abort move
        ;
        CALL        save_pending_kbd_input
        CPI         'Q'
        JZ          cleanup_and_quit
write_next_output_byte:
        ;
        ; Advance to next byte in buffer and continue write
        ;
        INX         D
        DCX         B
        JMP         write_output_byte


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write a byte A to the file with file control block pointed to by HL
        ;
write_byte_to_file:
        ;
        ; If console paged mode is active, write directly through XMON API
        ;
        PUSH        PSW
        LDA         console_paged_output_flag
        ORA         A
        JZ          write_byte_using_tos
        POP         PSW
        CALL        TTO
        JC          cleanup_and_quit
        RET

write_byte_using_tos:
        ;
        ; If not console paged mode, write byte through TOS API
        ;
        POP         PSW
        CALL        OUTCHAR
        JC          cleanup_and_quit
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Advance to next line in paged modes, catching and handling page ends
        ;
advance_page_mode_line:
        ;
        ; Advance to next line on page
        ;
        LDA         current_line_on_page
        INR         A
        STA         current_line_on_page
        ;
        ; Check if console page mode
        ;
        LDA         console_paged_output_flag
        ORA         A
        JZ          check_printer_page_end
        ;
        ; If so, check for page end after 24 lines
        ;
        LDA         current_line_on_page
        CPI         24
        RNZ
        ;
        ; Wait for keyboard keypress, to give user a chance of reading page
        ;
        XRA         A
        STA         current_line_on_page
        CALL        TTI
        ;
        ; Check if user wants to abort move with this keypress
        ;
        CPI         'Q'
        JZ          abort_move_from_page_end
        CPI         'q'
        JNZ         setup_next_console_page
abort_move_from_page_end:
        ;
        ; Put 'Q' character back into TTI buffer before exiting program
        ;
        MVI         A,1
        STA         KEYBUF
        JMP         cleanup_and_quit

setup_next_console_page:
        JZ          cleanup_and_quit
        CPI         'q'
        JZ          cleanup_and_quit
        ;
        ; Clear screen before starting to display next page
        ;
        MVI         A,ERPAG
        CALL        TTO
        RET

check_printer_page_end:
        ;
        ; Check if printer page mode is active, and page length is set
        ;
        LDA         printer_paged_output_flag
        ORA         A
        RZ
        LDA         lines_text_per_page
        ORA         A
        RZ
        ;
        ; If so, check for page end
        ;
        PUSH        B
        MOV         B,A
        LDA         current_line_on_page
        CMP         B
        JNZ         printer_page_check_done
        ;
        ; On page end, insert 8 empty lines: 4 lines bottom and top margin
        ;
        MVI         B,8
        CALL        write_newlines_to_output
        XRA         A
        STA         current_line_on_page
printer_page_check_done:
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write B number of newlines to output
        ;
write_newlines_to_output:
        PUSH        H
        PUSH        PSW
        LHLD        SO_FCB
write_next_newline:
        CALL        write_newline_to_output
        DCR         B
        JNZ         write_next_newline
        POP         PSW
        POP         H
        RET


;//////////////////////////////////////

        ;
        ; Write a single newline to output
        ;
write_newline_to_output:
        MVI         A,CR
        CALL        write_byte_to_file
        MVI         A,LF
        CALL        write_byte_to_file
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

data_area_start:
saved_kbd_input_fifo:
        DS          32
f0_diskswap_filecopy_flag:
        DS          1
console_paged_output_flag:
        DS          1
printer_paged_output_flag:
        DS          1
hex_output_mode_flag:
        DS          1
first_read_flag:
        DS          1
si_assigned_flag:
        DS          1
so_file_type:
        DS          1
console_input_mode_flag:
        DS          1
echo_input_mode_flag:
        DS          1
current_line_on_page:
        DS          1
char_counter:
        DS          1
hex_byte_counter:
        DS          1
line_in_paragraph_counter:
        DS          1
finished_flag:
        DS          1
custom_eof_flag:
        DS          1
custom_eof:
        DS          1
eof_arg_ptr:
        DS          2
current_kbd_char:
        DS          1
lines_text_per_page:
        DS          1
data_buffer_ptr:
        DS          2
data_buffer_size:
        DS          2
converted_decimal_ascii:
        DS          2
data_area_end:

stack_pointer_backup:
        DS          2
console_input_buffer:
        DS          12

input_disk_str:
        DB          'input',CR
output_disk_str:
        DB          'output',CR
insert_disk_str:
        DB          'Insert ',CR
continue_prompt_str:
        DB          ' diskette, type C: ',BEL,CR
option_a_str:
        DB          'A',CR
option_c_str:
        DB          'C',CR
option_h_str:
        DB          'H',CR
option_q_str:
        DB          'Q',CR
hex_or_ascii_prompt_str:
        DB          'ASCII? Type H or A: ',BEL,CR

eof_arg_str:
        DB          'EOF=',NULL
input_file_prompt_str:
        DB          'Input file ?',CR
page_ength_prompt_str:
        DB          'Page length ?',CR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Setup program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
default_data_buffer:
        ;
        ; This code is run once on program start, and is later overwritten
        ;
start:
beginning:
        ;
        ; Save stack pointer for breaking out of program from subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        stack_pointer_backup
        ;
        ; Clear all program variables
        ;
        LXI         H,data_area_start
        MVI         B,data_area_end - data_area_start
clear_next_byte:
        MVI         M,000H
        INX         H
        DCR         B
        JNZ         clear_next_byte
        ;
        ; Get and parse command line arguments, to set up output mode flags
        ;
        CALL        get_console_input
        CALL        set_operating_mode
        ;
        ; Check and set up for floppy zero disk-swap filecopy mode, if selected
        ;
        LDA         f0_diskswap_filecopy_flag
        ORA         A
        JZ          setup_general_mode
        CALL        parse_diskswap_filecopy_mode_args
        JMP         common_setup

setup_general_mode:
        ;
        ; Check and set up for output to printer, if selected
        ;
        LDA         printer_paged_output_flag
        ORA         A
        JNZ         setup_printer_out
        ;
        ; Otherwise check if hexadecimal mode is activated
        ;
        CALL        parse_general_mode_args
        JMP         common_setup

setup_printer_out:
        CALL        parse_printer_mode_args
common_setup:
        ;
        ; Setup main buffer, remaining flags and counters
        ;
        CALL        setup_main_buffer
        MVI         A,TRUE
        STA         first_read_flag
        XRA         A
        STA         current_line_on_page
        STA         char_counter
        STA         hex_byte_counter
        STA         line_in_paragraph_counter
        STA         finished_flag
        ;
        ; Jump to main routine in low memory
        ;
        JMP         main


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines for setup
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set up buffer boundaries depending on output type
        ;
setup_main_buffer:
        ;
        ; Use small buffer if moving data to a page-based output
        ;
        LDA         printer_paged_output_flag
        ORA         A
        JNZ         use_small_buffer
        LDA         console_paged_output_flag
        ORA         A
        JZ          use_big_buffer
use_small_buffer:
        ;
        ; Only reserve 1000 bytes for the main buffer
        ;
        LXI         H,default_data_buffer
        SHLD        data_buffer_ptr
        LXI         H,1000
        SHLD        data_buffer_size
        RET

use_big_buffer:
        ;
        ; Find start of user-memory to use as buffer address
        ;
        LXI         H,default_data_buffer
start_of_memory_scan:
        DCR         H
        MOV         A,M
        INR         M
        CMP         M
        JNZ         start_of_memory_scan
        INR         H
        SHLD        data_buffer_ptr
        ;
        ; Find size by subtracting buffer start from start of TOS buffers
        ;
        MOV         A,H
        CMA
        INR         A
        MOV         B,A
        MVI         C,000H
        LHLD        BUFLIM
        DAD         B
        SHLD        data_buffer_size
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get one line of input from console, or an empty line if none
        ;
get_console_input:
        ;
        ; Reset local input buffer
        ;
        LXI         H,console_input_buffer
        MVI         M,CR
        ;
        ; Check CI if being a buffered input type file
        ;
        LHLD        CI_FCB
        MOV         A,M
        CPI         4
        RNZ
        ;
        ; Peek at the next char of CI to see if there's pending data
        ;
        INX         H
        INX         H
        MOV         C,M             ; CI_FCB + FCB_BUFIDX
        INX         H
        MOV         B,M
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; CI_FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        DAD         B
        MOV         A,M
        CPI         LF
        RZ
        ;
        ; Get input data
        ;
        LXI         D,console_input_buffer
        LHLD        CI_FCB
        CALL        GET
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Find input output device types and set up most related flags
        ;
set_operating_mode:
        ;
        ; Check if SI is assigned, set FCB to binary mode if so
        ;
        LHLD        SI_FCB
        MOV         A,H
        ORA         L
        JZ          si_check_done
        CALL        set_fcb_to_binary
        MVI         A,TRUE
si_check_done:
        STA         si_assigned_flag
        ;
        ; Initialize custom EOF flag to FALSE
        ;
        XRA         A
        STA         custom_eof_flag
        ;
        ; Compare if CI and SI is the same
        ;
        LHLD        SI_FCB
        XCHG
        LHLD        CI_FCB
        MOV         A,H
        CMP         D
        JNZ         separate_console_input
        MOV         A,L
        CMP         E
        JNZ         separate_console_input
console_as_input:
        ;
        ; Set default EOF character and interactive mode
        ;
        MVI         A,ETX
        STA         custom_eof_flag
        STA         custom_eof
        STA         console_input_mode_flag
        JMP         parse_eof_from_args

separate_console_input:
        ;
        ; Check if SI is a polling-driven device
        ;
        LHLD        SI_FCB
        MOV         A,M
        CPI         2
        JNZ         get_output_type
        ;
        ; If so, check if it is TTI. Other cases needs EOF char specified
        ;
        INX         H
        INX         H
        MOV         A,M
        CPI         TTI
        JNZ         parse_eof_from_args
        ;
        ; Set console-in related flags
        ;
        MVI         A,TRUE
        STA         echo_input_mode_flag
        JMP         console_as_input


;//////////////////////////////////////

parse_eof_from_args:
        ;
        ; Scan through the whole of the input args buffer for the EOF arg
        ;
        LXI         D,console_input_buffer
scan_for_eof_arg:
        ;
        ; Check for end of line
        ;
        LXI         H,eof_arg_str
        LDAX        D
        CPI         CR
        JZ          get_output_type
        ;
        ; Convert char to uppercase
        ;
        CPI         'a'-1
        JC          eof_arg_scan_char_is_uppercase
        SUI         'a' - 'A'
eof_arg_scan_char_is_uppercase:
        ;
        ; Check if first char in EOF arg string is found, else keep scanning
        ;
        CMP         M
        JZ          parse_eof_flag
        INX         D
        JMP         scan_for_eof_arg

parse_eof_flag:
        ;
        ; Save pointer to potential EOF argument
        ;
        XCHG
        SHLD        eof_arg_ptr
        XCHG
        ;
        ; Compare with arg string to verify if this truly is the right argument
        ;
check_next_eof_arg_char:
        INX         H
        INX         D
        MOV         A,M
        ORA         A
        JZ          eof_arg_found
        LDAX        D
        CPI         'a'-1
        JC          eof_arg_check_char_is_uppercase
        SUI         'a' - 'A'
eof_arg_check_char_is_uppercase:
        CMP         M
        JNZ         scan_for_eof_arg
        JMP         check_next_eof_arg_char

eof_arg_found:
        ;
        ; Convert EOF number from ASCII arg to binary and save if successfull
        ;
        XCHG
        CALL        EDHB
        JNC         eof_arg_parsed
        MVI         A,ERROR_0F
        STC
        JMP         cleanup_and_quit

eof_arg_parsed:
        STA         custom_eof
        MVI         A,TRUE
        STA         custom_eof_flag
        ;
        ; Cut parsed  (6 chars long) EOF argument out of the args string
        ;
        LHLD        eof_arg_ptr
        LXI         D,6
        XCHG
        DAD         D
move_next_args_char:
        MOV         A,M
        STAX        D
        CPI         CR
        JZ          get_output_type
        INX         H
        INX         D
        JMP         move_next_args_char


;//////////////////////////////////////

        ;
        ; Determine if output file type is one out of several relevant ones
        ;
get_output_type:
        ;
        ; Check if SO has been assigned
        ;
        LHLD        SO_FCB
        MOV         A,H
        ORA         L
        JNZ         output_file_set
        ;
        ; If not, try SL and eventually use CO as a last resort
        ;
        LHLD        SL_FCB
        MOV         A,H
        ORA         L
        JNZ         output_file_selected
        LHLD        CO_FCB
output_file_selected:
        ;
        ; Reassign selected file as SO
        ;
        SHLD        SO_FCB
        LXI         H,00000H
        SHLD        SL_FCB
output_file_set:
        ;
        ; Check output file type for block device and floppy disk drive 0
        ;
        LHLD        SO_FCB
        MOV         A,M
        CPI         5
        JNZ         console_output_check
        LXI         B,FCB_DEVTYP
        DAD         B
        MOV         A,M
        INX         H
        ORA         M               ; SO_FCB + FCB_DRVNR
        JNZ         other_output_device
        MVI         A,OT_ENUM_F0
        STA         so_file_type
        JMP         set_mode_flags

        ;
        ; Check if output device is to the console
        ;
console_output_check:
        XCHG
        LHLD        CO_FCB
        MOV         A,D
        CMP         H
        JNZ         printer_output_check
        MOV         A,E
        CMP         L
        JNZ         printer_output_check
        MVI         A,OT_ENUM_CO
        STA         so_file_type
        JMP         set_mode_flags

        ;
        ; Check if output device is to the printer
        ;
printer_output_check:
        ;
        ; Printer should be polling device type and use PRNT as output routine
        ;
        LDAX        D
        CPI         2
        JNZ         other_output_device
        LXI         H,004H
        DAD         D
        MOV         A,M
        CPI         PRNT
        JNZ         other_output_device
        MVI         A,OT_ENUM_LP
        STA         so_file_type
        JMP         set_mode_flags

        ;
        ; Set other file type (block devices on other drives and anything else)
        ;
other_output_device:
        MVI         A,OT_ENUM_OT
        STA         so_file_type


;//////////////////////////////////////

        ;
        ; Set up flags based on input/output device type combination
        ;
set_mode_flags:
        ;
        ; Floppy diskswap filecopy mode is chosen by using :F0: and omitting SI
        ;
        LDA         si_assigned_flag
        ORA         A
        JNZ         check_co_page_mode
        LDA         so_file_type
        CPI         OT_ENUM_F0
        JNZ         input_file_required_error
        STA         f0_diskswap_filecopy_flag
        RET

check_co_page_mode:
        ;
        ; Fullpage consol output is chosen by assigning SO to the same as CO
        ;
        LDA         so_file_type
        CPI         OT_ENUM_CO
        JNZ         check_lp_page_mode
        STA         console_paged_output_flag
        RET

check_lp_page_mode:
        ;
        ; Paged printer output is chosen by assigning SO to :LP:
        ;
        CPI         OT_ENUM_LP
        RNZ
        STA         printer_paged_output_flag
        RET

input_file_required_error:
        MVI         A,ERROR_19
        STC
        JMP         cleanup_and_quit


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse command line arguments for diskswap filecopy mode
        ;
parse_diskswap_filecopy_mode_args:
        ;
        ; Check if an output filename has been given in the command line args
        ;
        LXI         H,console_input_buffer
        MOV         A,M
        ORA         A
        JZ          prompt_for_input_file
        ;
        ; Prepare FCB for and input-file for reading
        ;
        MVI         A,0
        CALL        PHYSINT
        JC          cleanup_and_quit
        SHLD        SI_FCB
        CALL        set_fcb_to_binary
        RET

        ;
        ; Prompt for user to type an input-file name
        ;
prompt_for_input_file:
        LXI         D,input_file_prompt_str
        LHLD        CO_FCB
        CALL        PUT
        LXI         D,console_input_buffer
        LHLD        CI_FCB
        CALL        GET
        JMP         parse_diskswap_filecopy_mode_args


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set a FCB and any linked FCBs into binary read mode
        ;
set_fcb_to_binary:
        ;
        ; Add null-pointer to bottom of stack of pending branches, as a marker
        ;
        LXI         D,00000H
        PUSH        D
set_fcb_branch_to_binary:
        ;
        ; Check if "node" of current branch is a double FCB
        ;
        MOV         A,M
        CPI         6
        JNZ         is_single_fcb
        ;
        ; Set read mode to binary for double FCB itself
        ;
        INX         H
        MOV         A,M
        ORI         FM_BINARY
        MOV         M,A
        ;
        ; Save pointer to linked FCB "branch" nr 1 onto stack for later
        ;
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        PUSH        D
        ;
        ; Get pointer to linked FCB "branch" nr 2 and continue from there
        ;
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        JMP         set_fcb_branch_to_binary

is_single_fcb:
        ;
        ; Set "leaf" single FCB to binary read mode
        ;
        INX         H
        MOV         A,M
        ORI         FM_BINARY
        MOV         M,A
        ;
        ; Recover pointer to next FCB "branch" and continue if not empty-marker
        ;
        POP         H
        MOV         A,H
        ORA         L
        JNZ         set_fcb_branch_to_binary
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse command line arguments for normal move data mode
        ;
parse_general_mode_args:
        ;
        ; Check if ASCII Hexadecimal switch is provided in the arguments
        ;
        LDA         console_input_buffer
        CPI         'H'
        JZ          general_mode_hex_arg_found
        CPI         'h'
        RNZ
general_mode_hex_arg_found:
        MVI         A,TRUE
        STA         hex_output_mode_flag
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse command line arguments for printer page output mode
        ;
parse_printer_mode_args:
        ;
        ; Reset to default page length (no pages)
        ;
        XRA         A
        STA         lines_text_per_page
parse_printer_mode_arg_str:
        ;
        ; Reset pointer, number-found flag and parsed number (lines per page)
        ;
        LXI         D,console_input_buffer
        MVI         C,FALSE
        LXI         H,00000H
printer_args_parse_next_char:
        ;
        ; Get next char and check for end of args
        ;
        LDAX        D
        INX         D
        CPI         CR
        JZ          printer_args_end
        ;
        ; Check if ASCII Hexadecimal switch is provided in the arguments
        ;
        CPI         'H'
        JZ          printer_mode_hex_arg_found
        CPI         'h'
        JNZ         printer_args_not_hex_arg
printer_mode_hex_arg_found:
        MVI         A,TRUE
        STA         hex_output_mode_flag
        JMP         printer_args_parse_next_char

printer_args_not_hex_arg:
        ;
        ; Check if abort has been entered at the prompt
        ;
        CPI         'Q'
        JZ          cleanup_and_quit
        CPI         'q'
        JZ          cleanup_and_quit
        ;
        ; Check if a digit of the number is encountered
        ;
        CPI         '0'
        JC          printer_args_parse_next_char
        CPI         '9'+1
        JNC         printer_args_parse_next_char
        ;
        ; Set number-found flag and get BCD from ASCII digit
        ;
        MVI         C,TRUE
        SUI         '0'
        ;
        ; Multiply already parsed section of number by 10
        ;
        PUSH        H
        POP         B
        DAD         H
        DAD         H
        DAD         B
        DAD         H
        ;
        ; Add value of new digit to parsed number
        ;
        ADD         L
        MOV         L,A
        MOV         A,H
        ACI         0
        MOV         H,A
        JMP         printer_args_parse_next_char

printer_args_end:
        ;
        ; Check if no paging is implicitly selected (no length arg provided)
        ;
        MOV         A,C
        ORA         A
        RZ
        ;
        ; Check that page length argument is below 256 lines
        ;
        MOV         A,H
        ORA         A
        JNZ         prompt_for_page_length
        ;
        ; Check if no paging has been explicitly selected (length = 0 lines)
        ;
        MOV         A,L
        ORA         A
        JZ          valid_page_length
        ;
        ; Check that page length is between 24 and 128 lines
        ;
        ANI         080H
        JNZ         prompt_for_page_length
        MOV         A,L
        CPI         24
        JC          prompt_for_page_length
        SUI         8
valid_page_length:
        STA         lines_text_per_page
        RET

        ;
        ; Prompt for user to type a page-length
        ;
prompt_for_page_length:
        LXI         D,page_ength_prompt_str
        LHLD        CO_FCB
        CALL        PUT
        LXI         D,console_input_buffer
        LHLD        CI_FCB
        CALL        GET
        JMP         parse_printer_mode_arg_str
