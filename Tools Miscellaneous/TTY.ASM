;//////////////////////////////////////////////////////////////////////////////
;//
;//     TTY - Operate like a dumb-terminal
;//
;//         This tool will make the computer behave like a basic TDV-2114L dumb-
;//         terminal. To go back to TOS, a reset using the physical hardware reset-
;//         button will be needed. There is no key-sequence from the keyboard to do
;//         this, and the program will run forever on its own.
;//
;//         Intended to be used with the terminal module set to auto-linefeed, and
;//         will not work as intended unless the DIP-switch setting allows for
;//         this. Otherwise, the program will work in any of the roll modes.
;//
;//         NOTE: Correct operation is very dependent on XMON version, and in
;//               particular the location of the UART Rx buffer. If using the wrong
;//               combination of versions, there will be no input from the UART.
;//
;//
;//         Changelog:
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Hardcoded to use Rx buffer at 0x25E0
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
ROLUP       EQU     00CH        ; Scroll screen up one row
ERPAG       EQU     019H        ; Clear screen
CURH        EQU     01DH        ; Cursor home

;
; XMON constants
;
CURSOR_ROW  EQU     00100H      ; Multiplier for cursor row
CURSOR_COL  EQU     00001H      ; Multiplier for cursor column

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
CURSOR      EQU     00049H      ; Set console cursor position
INDISP      EQU     0006AH      ; Read character at console cursor
RCVI        EQU     00082H      ; Main UART input
XMIO        EQU     000CAH      ; Main UART output

;
; XMON and TOS system data
;
RCVBUF      EQU     025E0H      ; Main UART input buffer
KEYBUF      EQU     02780H      ; Console input buffer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Clear screen
        ;
        MVI         A,ERPAG
        CALL        TTO
        ;
        ; Try to trigger autoscroll, if active
        ;
        LXI         H,24*CURSOR_ROW + 79*CURSOR_COL
        CALL        CURSOR
        MVI         A,'A'
        CALL        TTO
        ;
        ; Read back same cursor position to check if autoscroll activated
        ;
        CALL        CURSOR
        MVI         A,' '
        CALL        INDISP
        CPI         'A'
        JZ          scroll_mode_found
        XRA         A
scroll_mode_found:
        STA         no_autoscroll_flag
        MVI         A,ERPAG
        CALL        TTO


;//////////////////////////////////////

        ;
        ; Set position to start of page
        ;
start_of_page:
        XRA         A
        STA         current_row
        ;
        ; Set position to start of row
        ;
start_of_row:
        XRA         A
        STA         current_column
        ;
        ; Main loop
        ;
main:
        ;
        ; Get input character and use it as the index in a jump table
        ;
        CALL        get_next_char
        LXI         H,char_action_jumptable
        MOV         E,A
        MVI         D,000H
        DAD         D
        DAD         D
        ;
        ; Get entry from jump-table, then do the jump
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        PCHL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Update cursor shadow position variables for normal cursor advance
        ;
cursor_advance:
        ;
        ; Cursor moved one position to the right
        ;
        LXI         H,current_column
        INR         M
        ;
        ; Check for end of row
        ;
        MOV         A,M
        CPI         80
        JC          main
        ;
        ; If so, assume auto newline and check for end of page
        ;
        LXI         H,current_row
        MOV         A,M
        CPI         24
        JNC         cursor_advance_scroll
        ;
        ; Just update shadow position if not end of page
        ;
        INR         M
        JMP         start_of_row

cursor_advance_scroll:
        ;
        ; On end of page, force scroll if no autoscroll
        ;
        LDA         no_autoscroll_flag
        ANA         A
        JZ          start_of_row
        MVI         A,ROLUP
        CALL        TTO
        JMP         start_of_row


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Update cursor shadow position variables for cursor up
        ;
cursor_up:
        ;
        ; Cursor moved one position to the left
        ;
        LDA         current_row
        ANA         A
        JZ          main
        DCR         A
        STA         current_row
        JMP         main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Update cursor shadow position variables for cursor down
        ;
cursor_down:
        LDA         current_row
        CPI         24
        JNC         main
        INR         A
        STA         current_row
        JMP         main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Update cursor shadow position variables for cursor left
        ;
cursor_left:
        ;
        ; Cursor moved one position to the left
        ;
        LDA         current_column
        ANA         A
        JZ          main
        DCR         A
        STA         current_column
        JMP         main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Update cursor shadow position variables for cursor right
        ;
cursor_right:
        ;
        ; Cursor moved one position to the right
        ;
        LDA         current_column
        INR         A
        STA         current_column
        ;
        ; Check for end of row
        ;
        CPI         80
        JC          main
        ;
        ; If so, assume auto newline
        ;
        XRA         A
        STA         current_column


;//////////////////////////////////////

        ;
        ; Update cursor shadow position variables for linefeed
        ;
linefeed:
        ;
        ; Check for end of page
        ;
        LDA         current_row
        CPI         24
        JNC         linefeed_scroll
        ;
        ; Just update shadow position if not end of page
        ;
        INR         A
        STA         current_row
        JMP         main

linefeed_scroll:
        ;
        ; On end of page, force scroll if no autoscroll
        ;
        LDA         no_autoscroll_flag
        ANA         A
        JZ          main
        MVI         A,ROLUP
        CALL        TTO
        JMP         main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Update cursor shadow position variables for custom cursor position
        ;
set_cursor_position:
        ;
        ; Get and verify row number
        ;
        CALL        get_next_char
        CPI         25
        JC          valid_cursor_row
        ;
        ; Invalid row, flush pending column
        ;
        CALL        get_next_char
invalid_cursor_row:
        ;
        ; Clear screen on illegal cursor position
        ;
        MVI         A,CURH
        CALL        TTO
        JMP         start_of_page

valid_cursor_row:
        ;
        ; Save updated cursor row shadow position variable
        ;
        STA         current_row
        ;
        ; Get and verify column number
        ;
        CALL        get_next_char
        CPI         80
        JNC         invalid_cursor_row
        ;
        ; Save updated cursor column shadow position variable
        ;
        STA         current_column
        JMP         main


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Check keyboard and serial port, forwarding data as fit
        ;
get_next_char:
        ;
        ; Check for pending keyboard input
        ;
        LDA         KEYBUF
        ANA         A
        JZ          check_serial_in
        ;
        ; Transmit keyboard input over serial port
        ;
        CALL        TTI
        CALL        XMIO
check_serial_in:
        ;
        ; Check for pending serial port input
        ;
        LDA         RCVBUF
        ANA         A
        JZ          get_next_char
        ;
        ; Print serial port input to the screen
        ;
        CALL        RCVI
        ANI         07FH
        CALL        TTO
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

char_action_jumptable:
        DW          main
        DW          main
        DW          main
        DW          main
        DW          start_of_row
        DW          main
        DW          main
        DW          main
        DW          cursor_left
        DW          main
        DW          linefeed
        DW          cursor_down
        DW          main
        DW          start_of_row
        DW          main
        DW          main
        DW          set_cursor_position
        DW          main
        DW          main
        DW          main
        DW          main
        DW          main
        DW          main
        DW          main
        DW          cursor_right
        DW          start_of_page
        DW          main
        DW          main
        DW          cursor_up
        DW          start_of_page
        DW          main
        DW          main
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          cursor_advance
        DW          main

no_autoscroll_flag:
        DS          1
current_column:
        DS          1
current_row:
        DS          1
