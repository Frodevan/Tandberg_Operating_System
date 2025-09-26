;//////////////////////////////////////////////////////////////////////////////
;//
;//     SEDIT - Line text-editor
;//
;//         A simple line-editor that iterates through lines in SI, and lets the
;//         user copy or modify these to SO. The lines are iterated in sequence,
;//         and when the program advances to the next line the previous line is no
;//         longer available for alteration during that session.
;//
;//         Editing a file is done using a set of built-in commands, one of which
;//         provides an insertion-mode where new lines of text can be inserted
;//         freely into the output file. After the end of the input file, this mode
;//         is also automatically triggered. To exit the insertion-mode in both
;//         cases, enter Ctrl-C as the first character of a new line.
;//
;//         Most operations operate with there being a cursor on both the current
;//         input and current output lines. New data is taken from the cursor of
;//         the input line, while data is inserted at the cursor of the output
;//         line. These are separate cursors, where the input cursor can be at any
;//         point inside the input line, whereas the output line is more of a stack
;//         where the cursor is always at the end of the line.
;//
;//         NOTE: In most cases, the output line will automatically be written to
;//               the output file when the next input line is fetched from the
;//               input file. The only command where this is not the case, is some
;//               variants of the S commands.
;//
;//         NOTE: Line-lengths are usually not checked. There is an expectancy that
;//               no line of the input or output files exceeds 80 characters, and
;//               any single line longer than about 130 characters will cause the
;//               program to misbehave.
;//
;//         NOTE: Numeric command-arguments are not checked for the value of 0. If
;//               a value of 0 is used, it will behave as if the value was 256.
;//
;//
;//         Commands:
;//
;//             B       Reset input line cursor and clear output line.
;//             BI      Reset input line cursor only.
;//             BO      Clear output line only.
;//
;//             C       Append rest of input line from cursor, to output line, then
;//                     write output to file and advance one line.
;//             C<n>    Similar to C, but writes and advances n (1-99) input lines.
;//             C+<n>   Appends n (1-99) characters from the current input line to
;//                     the output line. Behaves as C if the input line runs out.
;//             C"..."  Appends characters from input line cursor and onwards until
;//                     the next occurence of the given quote appears in the input
;//                     text. This will keep going and may append output data from
;//                     multiple lines.
;//
;//             DI      Display current input line, with Ctrl-character indicators
;//                     and an indicator for where the cursor is.
;//             DO      Display current output line.
;//
;//             H       Quit editor, but this command requires that the output line
;//                     is empty in advance. Either use the S, C or BO commands to
;//                     clear the output line if the H command complains.
;//
;//             I       Starts an insert-mode session before the end of the input
;//                     file is reached. To return, enter a new line starting with
;//                     the Ctrl-C character. This line will not be added to the
;//                     output file.
;//             I"..."  Appends quoted text to output line. If the output line
;//                     exceeds the length of 79 characters, it will be immediately
;//                     written to file with a linebreak added, and only remaining
;//                     text after this will reside in the output line when the
;//                     command is complete.
;//
;//             S       Skip current input line and write output line to file.
;//             S<n>    Similar to S, but skip n (1-99) input lines instead of one.
;//             S+<n>   Skip n (1-99) characters in current input line. Skips to
;//                     the next input line on end of line, without resetting or
;//                     writing the current output line to file.
;//             S"..."  Skips input until the next occurence of quoted text. This
;//                     search spans multiple lines, and will not write the current
;//                     output line to file.
;//
;//             X"..."  Inserts quoted text into output, while skipping the same
;//                     number of characters of the current input line. If the
;//                     input line runs out of characters, the program switches
;//                     over to Insert quote mode for the remainder of the quote.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
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
ETX         EQU     003H        ; End of text
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; TOS system calls
;
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer


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
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

welcome_title_str:
        DB          '*** TANDBERG LINE EDITOR VER. 1.1 ***',CR
command_prompt_str:
        DB          'COMMAND: ',CR
command_error_str:
        DB          'COMMAND ERROR',CR
ok_str:
        DB          'OK',CR
exit_str:
        DB          'END EDIT',CR
quote_inserted_str:
        DB          'QUOTE INSERTED',CR
eof_str:
        DB          'END-OF-FILE ON INPUT',CR
newline_str:
        DB          CR
insert_mode_str:
        DB          'INSERT MODE ENTERED',CR
insert_mode_exit_str:
        DB          'END EDIT',CR

input_buffer:
        DS          132
input_buffer_ptr:
        DW          input_buffer
input_buffer_index:
        DB          0

output_buffer:
        DS          132
output_buffer_ptr:
        DW          output_buffer
output_buffer_index:
        DB          0

cursor_mark_str:
        DS          132
user_input_buffer:
        DS          82
numerical_arg_value:
        DB          0
compare_pattern_ptr:
        DW          00000H
buffer_pattern_ptr:
        DW          00000H
end_of_input_file_flag:
        DB          FALSE


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Align a 2-character command to be parsed as an 1-character command
        ;
align_cmd_string:
        ;
        ; Shift command string index 2-4 right by one char
        ;
        LDA         user_input_buffer+2
        STA         user_input_buffer+1
        LDA         user_input_buffer+3
        STA         user_input_buffer+2
        LDA         user_input_buffer+4
        STA         user_input_buffer+3
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII digit in A to its value in binary
        ;
get_digit_value:
        CPI         '0'
        JM          not_numerical
        CPI         '9'+1
        JP          not_numerical
        SUI         '0'
        RET

not_numerical:
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse the numerical argument from the command string
        ;
parse_cmd_numerical_arg:
        ;
        ; Parse most significant digit of number
        ;
        LDA         user_input_buffer+1
        CALL        get_digit_value
        JC          error_parsing_numerical_arg
        MOV         B,A
        STA         numerical_arg_value
        ;
        ; Parse potential second digit of number
        ;
        LDA         user_input_buffer+2
        CALL        get_digit_value
        JC          check_lines_arg_end
        MOV         C,A
        ;
        ; If second digit is present, add to first digit multiplied by 10
        ;
        MOV         A,B
        ADD         A
        MOV         B,A
        ADD         A
        ADD         A
        ADD         B
        ADD         C
        STA         numerical_arg_value
        ;
        ; Fetch next character from command string
        ;
        LDA         user_input_buffer+3
check_lines_arg_end:
        ;
        ; Verify that there are no more digits or arguments in command string
        ;
        CPI         CR
        RZ
        JMP         error_parsing_numerical_arg


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read next line of text from input file
        ;
read_next_input_line:
        LHLD        SI_FCB
        LXI         D,input_buffer
        CALL        GET
        JC          error_reading_input
        ;
        ; Reset input line cursor
        ;
        SUB         A
        STA         input_buffer_index
        LXI         H,input_buffer
        SHLD        input_buffer_ptr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write pending line of text to output file
        ;
write_output_line:
        LHLD        SO_FCB
        LXI         D,output_buffer
        CALL        PUT
        JC          error_writing_output
        ;
        ; Reset output line cursor
        ;
        SUB         A
        STA         output_buffer_index
        LXI         H,output_buffer
        SHLD        output_buffer_ptr
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
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Print welcome message
        ;
        LXI         D,welcome_title_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        LXI         D,newline_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Get first line of input file
        ;
        LHLD        SI_FCB
        LXI         D,input_buffer
        CALL        GET
        JC          check_input_file_empty
        JMP         init_command_prompt


;//////////////////////////////////////////////////////////////////////////////

command_prompt:
        ;
        ; Prompt for next command
        ;
        LHLD        CO_FCB
        LXI         D,command_prompt_str
        CALL        PUTSTR
        RC
        LHLD        CI_FCB
        LXI         D,user_input_buffer
        CALL        GET
        RC
        LDA         user_input_buffer
        CALL        to_uppercase
        ;
        ; Check for valid command, first character
        ;
        CPI         'B'
        JZ          cmd_reset_cursors
        CPI         'C'
        JZ          cmd_copy
        CPI         'D'
        JZ          cmd_display_buffers
        CPI         'H'
        JZ          cmd_quit
        CPI         'I'
        JZ          cmd_insert
        CPI         'S'
        JZ          cmd_skip
        CPI         'X'
        JZ          cmd_replace
command_error:
        ;
        ; Invalid command, print status and run prompt again
        ;
        LHLD        CO_FCB
        LXI         D,command_error_str
        CALL        PUT
        RC
        JMP         command_prompt


;//////////////////////////////////////////////////////////////////////////////

error_parsing_numerical_arg:
        POP         H
        JMP         command_error


;//////////////////////////////////////

error_reading_input:
        POP         H
check_input_file_empty:
        ;
        ; Error reading input file, check if end of file
        ;
        ANA         A
        JZ          end_of_input_file
        RET


;//////////////////////////////////////

error_writing_output:
        POP         H
        RET


;//////////////////////////////////////

end_of_input_file:
        ;
        ; Print status, set end-of-file flag and enter insert mode
        ;
        LHLD        CO_FCB
        LXI         D,eof_str
        CALL        PUT
        RC
        LXI         D,insert_mode_str
        CALL        PUT
        RC
        MVI         A,TRUE
        STA         end_of_input_file_flag
        JMP         insert_mode_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print overview of input line before running command prompt
        ;
init_command_prompt:
        ;
        ; Print input line itself
        ;
        LHLD        CO_FCB
        LXI         D,input_buffer
        CALL        PUT
        RC
        ;
        ; Print input line control character marks on second line
        ;
        LXI         D,input_buffer
mark_input_ctrl_chars_loop:
        LDAX        D
        INX         D
        CPI         ' '
        JM          is_input_ctrl_char
        MVI         A,' '
        CALL        OUTCHAR
        RC
        JMP         mark_input_ctrl_chars_loop

is_input_ctrl_char:
        ;
        ; Check for end of input line
        ;
        CPI         CR
        JZ          input_ctrl_chars_marked
        ;
        ; Otherwise insert mark at control character
        ;
        MVI         A,'_'
        CALL        OUTCHAR
        RC
        JMP         mark_input_ctrl_chars_loop

input_ctrl_chars_marked:
        CALL        OUTCHAR
        RC
        MVI         A,LF
        CALL        OUTCHAR
        RC
        ;
        ; Prepare input line cursor position string
        ;
        LXI         H,cursor_mark_str
        LDA         input_buffer_index
        INR         A
scan_to_cursor_pos_loop:
        DCR         A
        JZ          mark_cursor_pos
        MVI         M,' '
        INX         H
        JMP         scan_to_cursor_pos_loop

mark_cursor_pos:
        MVI         M,'!'
        INX         H
        MVI         M,CR
        ;
        ; Print cursor position mark on third line
        ;
        LHLD        CO_FCB
        LXI         D,cursor_mark_str
        CALL        PUT
        RC
        JMP         command_prompt


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Command to reset one or both of the buffer cursors
        ;
cmd_reset_cursors:
        ;
        ; Check second character of command for course of action
        ;
        LDA         user_input_buffer+1
        CALL        to_uppercase
        CPI         CR
        JZ          reset_both_cursors
        CPI         'I'
        JZ          reset_input_cursor
        CPI         'O'
        JNZ         command_error


;//////////////////////////////////////

reset_output_cursor:
        LXI         H,output_buffer
        SHLD        output_buffer_ptr
        SUB         A
        STA         output_buffer_index


;//////////////////////////////////////

reset_cursors_done:
        LHLD        CO_FCB
        LXI         D,ok_str
        CALL        PUT
        RC
        JMP         command_prompt


;//////////////////////////////////////

reset_input_cursor:
        LXI         H,input_buffer
        SHLD        input_buffer_ptr
        SUB         A
        STA         input_buffer_index
        JMP         reset_cursors_done


;//////////////////////////////////////

reset_both_cursors:
        LXI         H,input_buffer
        SHLD        input_buffer_ptr
        SUB         A
        STA         input_buffer_index
        JMP         reset_output_cursor


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Command to copy data while advancing further into the input file
        ;
cmd_copy:
        ;
        ; Set default number of lines to copy
        ;
        MVI         A,1
        STA         numerical_arg_value
        ;
        ; Check second character of command for course of action
        ;
        LDA         user_input_buffer+1
        CPI         CR
        JZ          copy_lines
        CPI         '"'
        JZ          copy_until
        CPI         '+'
        JZ          copy_chars
        ;
        ; Check for custom number of lines to copy
        ;
        CALL        parse_cmd_numerical_arg
        JC          command_error


;//////////////////////////////////////

copy_lines:
        ;
        ; At first advance through the remainder of the current input line
        ;
next_char_copy_lines:
        ;
        ; Copy next character from input line to output line
        ;
        LHLD        input_buffer_ptr
        MOV         A,M
        INX         H
        SHLD        input_buffer_ptr
        LHLD        output_buffer_ptr
        MOV         M,A
        INX         H
        SHLD        output_buffer_ptr
        ;
        ; Check for end of input line
        ;
        CPI         CR
        JZ          line_end_copy_lines
        ;
        ; Otherwise, advance cursors and continue
        ;
        LDA         input_buffer_index
        INR         A
        STA         input_buffer_index
        LDA         output_buffer_index
        INR         A
        STA         output_buffer_index
        JMP         next_char_copy_lines

line_end_copy_lines:
        ;
        ; Write output line to file
        ;
        CALL        write_output_line
        ;
        ; Advance through the rest of the lines in whole strings
        ;
next_line_copy_lines:
        ;
        ; Read next line from input
        ;
        CALL        read_next_input_line
        ;
        ; Check if desired number of lines has been copied
        ;
        LDA         numerical_arg_value
        DCR         A
        STA         numerical_arg_value
        JZ          init_command_prompt
        ;
        ; Write entire line to output
        ;
        LXI         D,input_buffer
        LHLD        SO_FCB
        CALL        PUT
        RC
        ;
        ; Reset output cursor
        ;
        SUB         A
        STA         output_buffer_index
        LXI         H,output_buffer
        SHLD        output_buffer_ptr
        JMP         next_line_copy_lines


;//////////////////////////////////////

copy_until:
        ;
        ; Verify that a pattern is specified
        ;
        LDA         user_input_buffer+2
        CPI         CR
        JZ          command_error
        CPI         '"'
        JZ          command_error
        ;
        ; Scan through input lines until given pattern is found
        ;
next_char_copy_until:
        ;
        ; Check if next character in line equals first character of pattern
        ;
        LXI         H,user_input_buffer+2
        SHLD        compare_pattern_ptr
        MOV         A,M
        LHLD        input_buffer_ptr
        CMP         M
        JZ          check_match_copy_until
continue_copy_until:
        ;
        ; Copy next character from input line to output line
        ;
        MOV         A,M
        INX         H
        SHLD        input_buffer_ptr
        LHLD        output_buffer_ptr
        MOV         M,A
        INX         H
        SHLD        output_buffer_ptr
        ;
        ; Check for end of input line
        ;
        CPI         CR
        JZ          line_end_copy_until
        ;
        ; Otherwise, advance cursors and continue
        ;
        LDA         input_buffer_index
        INR         A
        STA         input_buffer_index
        LDA         output_buffer_index
        INR         A
        STA         output_buffer_index
        JMP         next_char_copy_until

line_end_copy_until:
        ;
        ; Advance to next line, and continue scanning for pattern
        ;
        CALL        write_output_line
        CALL        read_next_input_line
        JMP         next_char_copy_until

check_match_copy_until:
        INX         H
        SHLD        buffer_pattern_ptr
check_char_copy_until:
        ;
        ; Get next character of pattern
        ;
        LHLD        compare_pattern_ptr
        INX         H
        SHLD        compare_pattern_ptr
        MOV         A,M
        ;
        ; Check for end of pattern
        ;
        CPI         '"'
        JZ          init_command_prompt
        CPI         CR
        JZ          init_command_prompt
        ;
        ; Compare with proposed pattern in input buffer
        ;
        LHLD        buffer_pattern_ptr
        CMP         M
        JNZ         not_match_copy_until
        ;
        ; If equal, continue with checking next character
        ;
        INX         H
        SHLD        buffer_pattern_ptr
        JMP         check_char_copy_until

not_match_copy_until:
        ;
        ; Recover cursor position for input buffer, to continue in outer loop
        ;
        LHLD        input_buffer_ptr
        JMP         continue_copy_until


;//////////////////////////////////////

copy_chars:
        ;
        ; Parse number of characters to copy
        ;
        CALL        align_cmd_string
        CALL        parse_cmd_numerical_arg
        JC          command_error
        ;
        ; Get cursors and prepare to copy the exact number of characters
        ;
        LHLD        output_buffer_ptr
        XCHG
        LHLD        input_buffer_ptr
        LDA         numerical_arg_value
        MOV         B,A
        MOV         C,A
next_char_copy_chars:
        ;
        ; Copy next character from input line to output line
        ;
        MOV         A,M
        INX         H
        XCHG
        MOV         M,A
        INX         H
        XCHG
        ;
        ; Check for end of input line
        ;
        CPI         CR
        JZ          line_end_copy_chars
        ;
        ; Otherwise, advance to next character
        ;
        DCR         B
        JNZ         next_char_copy_chars
        ;
        ; Characters copied, update cursors
        ;
        SHLD        input_buffer_ptr
        XCHG
        SHLD        output_buffer_ptr
        LDA         input_buffer_index
        ADD         C
        STA         input_buffer_index
        LDA         output_buffer_index
        ADD         C
        STA         output_buffer_index
        JMP         init_command_prompt

line_end_copy_chars:
        ;
        ; Stop copying characters if end of line has been encountered
        ;
        CALL        write_output_line
        CALL        read_next_input_line
        JMP         init_command_prompt


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Command to display the status of the input and/or output line buffers
        ;
cmd_display_buffers:
        ;
        ; Check second character of command for course of action
        ;
        LDA         user_input_buffer+1
        CALL        to_uppercase
        CPI         'I'
        JZ          init_command_prompt
        CPI         'O'
        JNZ         command_error


;//////////////////////////////////////

        ;
        ; Print output line, with cursor marked as an asterisk
        ;
        LHLD        output_buffer_ptr
        MVI         M,'*'
        INX         H
        MVI         M,CR
        LHLD        CO_FCB
        LXI         D,output_buffer
        CALL        PUT
        RC
        JMP         init_command_prompt


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Command to quit to TOS
        ;
cmd_quit:
        ;
        ; Make sure nothing pending in the output line buffer before quitting
        ;
        LDA         output_buffer_index
        ANA         A
        JNZ         command_error
        ;
        ; Print exit string and return to TOS
        ;
        LHLD        CO_FCB
        LXI         D,exit_str
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Command to insert new data into the output file
        ;
cmd_insert:
        ;
        ; Check second character of command for course of action
        ;
        LDA         user_input_buffer+1
        CPI         CR
        JZ          insert_mode_start
        CPI         '"'
        JNZ         command_error


;//////////////////////////////////////

        ;
        ; Prepare to fetch new data from command quote argument
        ;
        LXI         D,user_input_buffer+2
        LHLD        output_buffer_ptr
        XCHG
next_char_insert_quote:
        ;
        ; Check for end of quote argument
        ;
        MOV         A,M
        CPI         CR
        JZ          line_end_insert_quote
        CPI         '"'
        JZ          init_command_prompt
        ;
        ; Append next character of quote into output line buffer
        ;
        INX         H
        XCHG
        MOV         M,A
        ;
        ; Advance output line cursor
        ;
        INX         H
        SHLD        output_buffer_ptr
        XCHG
        LDA         output_buffer_index
        INR         A
        STA         output_buffer_index
        ;
        ; Enforce max 80 characters line-length, forcing a newline if needed
        ;
        CPI         80
        JNZ         next_char_insert_quote
        XCHG
        MVI         M,CR
        PUSH        H
        PUSH        D
        CALL        write_output_line
        POP         D
        POP         H
        LHLD        output_buffer_ptr
        XCHG
        JMP         next_char_insert_quote

line_end_insert_quote:
        ;
        ; Print status if quote-argument was not closed with a quotation sign
        ;
        LHLD        CO_FCB
        LXI         D,quote_inserted_str
        CALL        PUT
        RC
        JMP         init_command_prompt


;//////////////////////////////////////

        ;
        ; Freetype insertion mode
        ;
insert_mode_start:
        ;
        ; Verify that the output line is empty before entering insertion mode
        ;
        LDA         output_buffer_index
        ANA         A
        JNZ         command_error
insert_mode_main:
        ;
        ; Get next input string from user
        ;
        LHLD        CI_FCB
        LXI         D,user_input_buffer
        CALL        GET
        RC
        ;
        ; Check for Ctrl-C, if user wants to return to normal mode
        ;
        LDA         user_input_buffer
        CPI         ETX
        JZ          insert_mode_end
        ;
        ; Copy line from input buffer to output buffer
        ;
        LXI         D,output_buffer
        LXI         H,user_input_buffer
insert_mode_next_char:
        MOV         A,M
        XCHG
        CPI         CR
        JZ          insert_mode_line_end
        MOV         M,A
        XCHG
        INX         D
        INX         H
        JMP         insert_mode_next_char

insert_mode_line_end:
        MOV         M,A
        ;
        ; Write line to output file
        ;
        CALL        write_output_line
        JMP         insert_mode_main

insert_mode_end:
        ;
        ; Check if there's more input available from input file
        ;
        LDA         end_of_input_file_flag
        ANA         A
        JZ          init_command_prompt
        ;
        ; If not, print status and quit to TOS
        ;
        LXI         D,insert_mode_exit_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Command to skip data while advancing further into the input file
        ;
cmd_skip:
        ;
        ; Set default number of lines to skip
        ;
        MVI         A,1
        STA         numerical_arg_value
        ;
        ; Check second character of command for course of action
        ;
        LDA         user_input_buffer+1
        CPI         CR
        JZ          skip_lines
        CPI         '"'
        JZ          skip_until
        CPI         '+'
        JZ          skip_chars
        ;
        ; Check for custom number of lines to skip
        ;
        CALL        parse_cmd_numerical_arg
        JC          command_error


;//////////////////////////////////////

skip_lines:
        ;
        ; Write any pending data in output line, if any, to file
        ;
        LDA         output_buffer_index
        CPI         0
        JZ          next_line_skip_lines
        LHLD        output_buffer_ptr
        MVI         M,CR
        CALL        write_output_line
        ;
        ; Advance through the rest of the lines in whole strings
        ;
next_line_skip_lines:
        LDA         numerical_arg_value
        DCR         A
        STA         numerical_arg_value
        JZ          line_end_skip_lines
        CALL        read_next_input_line
        JMP         next_line_skip_lines

line_end_skip_lines:
        CALL        read_next_input_line
        JMP         init_command_prompt


;//////////////////////////////////////

skip_until:
        ;
        ; Verify that a pattern is specified
        ;
        LDA         user_input_buffer+2
        CPI         CR
        JZ          command_error
        CPI         '"'
        JZ          command_error
        ;
        ; Scan through input lines until given pattern is found
        ;
next_char_skip_until:
        ;
        ; Check if next character in line equals first character of pattern
        ;
        LXI         H,user_input_buffer+2
        SHLD        compare_pattern_ptr
        MOV         A,M
        LHLD        input_buffer_ptr
        CMP         M
        JZ          check_match_skip_until
continue_skip_until:
        ;
        ; Skip past next character from input line
        ;
        MOV         A,M
        INX         H
        SHLD        input_buffer_ptr
        ;
        ; Check for end of input line
        ;
        CPI         CR
        JZ          line_end_skip_until
        ;
        ; Otherwise, advance input cursor and continue
        ;
        LDA         input_buffer_index
        INR         A
        STA         input_buffer_index
        JMP         next_char_skip_until

line_end_skip_until:
        ;
        ; Advance to next input line, and continue scanning for pattern
        ;
        CALL        read_next_input_line
        JMP         next_char_skip_until

check_match_skip_until:
        INX         H
        SHLD        buffer_pattern_ptr
check_char_skip_until:
        ;
        ; Get next character of pattern
        ;
        LHLD        compare_pattern_ptr
        INX         H
        SHLD        compare_pattern_ptr
        MOV         A,M
        ;
        ; Check for end of pattern
        ;
        CPI         '"'
        JZ          init_command_prompt
        CPI         CR
        JZ          init_command_prompt
        ;
        ; Compare with proposed pattern in input buffer
        ;
        LHLD        buffer_pattern_ptr
        CMP         M
        JNZ         not_match_skip_until
        ;
        ; If equal, continue with checking next character
        ;
        INX         H
        SHLD        buffer_pattern_ptr
        JMP         check_char_skip_until

not_match_skip_until:
        ;
        ; Recover cursor position for input buffer, to continue in outer loop
        ;
        LHLD        input_buffer_ptr
        JMP         continue_skip_until


;//////////////////////////////////////

skip_chars:
        ;
        ; Parse number of characters to skip
        ;
        CALL        align_cmd_string
        CALL        parse_cmd_numerical_arg
        JC          command_error
        ;
        ; Get input cursor and prepare to skip the exact number of characters
        ;
        LHLD        input_buffer_ptr
        LDA         numerical_arg_value
        MOV         B,A
        MOV         C,A
next_char_skip_chars:
        ;
        ; Skip next character from input line
        ;
        MOV         A,M
        INX         H
        ;
        ; Check for end of input line
        ;
        CPI         CR
        JZ          line_end_skip_chars
        ;
        ; Otherwise, advance to next character
        ;
        DCR         B
        JNZ         next_char_skip_chars
        ;
        ; Characters skipped, update cursor
        ;
        SHLD        input_buffer_ptr
        LDA         input_buffer_index
        ADD         C
        STA         input_buffer_index
        JMP         init_command_prompt

line_end_skip_chars:
        ;
        ; Stop skipping characters if end of line has been encountered
        ;
        CALL        read_next_input_line
        JMP         init_command_prompt


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Command to replace data from input, with new data written to output
        ;
cmd_replace:
        ;
        ; Require quote argument
        ;
        LDA         user_input_buffer+1
        CPI         '"'
        JNZ         command_error


;//////////////////////////////////////

        ;
        ; Prepare to fetch new data from command quote argument
        ;
        LXI         D,user_input_buffer+2
next_char_replace_quote:
        ;
        ; Check for end of quote argument or end of input string
        ;
        LDAX        D
        CPI         '"'
        JZ          init_command_prompt
        CPI         CR
        JZ          line_end_insert_quote
        LHLD        input_buffer_ptr
        MOV         A,M
        CPI         CR
        JZ          line_end_replace_quote
        ;
        ; Skip the next character of the input line buffer
        ;
        INX         H
        SHLD        input_buffer_ptr
        LDA         input_buffer_index
        INR         A
        STA         input_buffer_index
        ;
        ; Append next character of quote into output line buffer
        ;
        LDAX        D
        LHLD        output_buffer_ptr
        MOV         M,A
        INX         H
        SHLD        output_buffer_ptr
        LDA         output_buffer_index
        INR         A
        STA         output_buffer_index
        INX         D
        JMP         next_char_replace_quote

line_end_replace_quote:
        ;
        ; Switch to insert mode if input line runs out of characters
        ;
        LHLD        output_buffer_ptr
        XCHG
        JMP         next_char_insert_quote
