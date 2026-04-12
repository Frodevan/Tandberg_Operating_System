;//////////////////////////////////////////////////////////////////////////////
;//
;//     ASM - Tandberg 8080 Assembler
;//
;//         This program is a 2-pass absolute-address 8080 assembler. This has
;//         several modes of operation, depending on which input and output files
;//         are assigned. Typical output of this program is a hex-file with the
;//         assembled program, along with various listings.
;//
;//         To convert an output hex-file to a loadable program, use the HEX2BIN
;//         program on it from TOS, after ASM is complete.
;//
;//
;//         Input and output standard TOS-file assignments:
;//
;//             SI  Source code input (must be a block-device)
;//             SO  Hex file output
;//             SL  Code listing output
;//             AO  Source code output
;//             AL  Error listing output
;//
;//
;//         If SI is assigned, dual-pass assembler mode with hexadecimal output
;//         will be used. In this mode error-messages will be copied to console
;//         even if AL is assigned.
;//
;//         If SI is not assigned, input is taken from the keyboard in single-pass
;//         'interactive' assembler mode. If AO is also defined, any valid source
;//         code typed in will be written to this file with proper tabulaton. In
;//         this mode symbols can be used as single-part expressions before being
;//         defined, as long as the symbol is defined later at some point.
;//
;//         If neither SI or SO is assigned, the assembled output binary data will
;//         will be put directly into memory. This mode is meant to be used in
;//         conjunction with the XMON debugger in ROM to enter, run and eventually
;//         debug short programs.
;//
;//         If SL is not set, CO will be used for the code lising using a console-
;//         friendly layout. Error listing will also be copied to CO, even if AL
;//         is set.
;//
;//         If AL is not set, SL and/or CO will be used for error-listings.
;//
;//
;//         Assembly follows standard Intel 8080 syntax, with certain quirks:
;//
;//             * Individual numbers can only be up to 7 digits long
;//             * Only +/- arithmetic is supported for expressions, no parantheses
;//             * Symbols can't be more than 5 characters long
;//             * Input source-file must end with an END or EOF pseudo-instruction
;//
;//
;//         Extra control codes:
;//
;//             /               Dump next 3 bytes at current address to listing
;//             .X              Exit to TOS
;//             .G addr         Go run from address defined by expression addr
;//             .K name         Remove symbol name and any symbol defined after it
;//             .I [sta [end]]  Reinitialize assembler, with optional custom
;//                             symbol-table bounds ranging from addresses defined
;//                             by expressions sta (start) to end.
;//             .M              Invoke XMON ROM debug monitor
;//             .S              List all current defined symbols
;//             .U              List all current undefined symbols
;//
;//             NOTE: While it is intended that the extra control codes are meant
;//                   for interactive mode only, these are not being filtered out
;//                   in other operation modes. If a line in a source-code input
;//                   file starts with one of these, its action will be taken on
;//                   both passes. Not that this is much useful for most of these.
;//
;//
;//         NOTE: This program will determine the start of user-RAM in a way that
;//               is not compatible with systems having 54KB or more RAM. If this
;//               were to be run on a systeme like this, the TOS and XMON data area
;//               would be overwritten by the defined symbols table, unless the
;//               bounds for the symbol-tables are manually changed using the .I
;//               control code.
;//
;//         NOTE: Due to the size of this program, it will overwrite parts of TOS
;//               if run on TOS version v1.7 or later. Running this on v1.6x will
;//               work, however there will be limited room for complex assignement
;//               of input/output TOS standard files.
;//
;//         NOTE: This program takes keyboard input directly from the XMON API, and
;//               as such a batch-file can't be used with CI to emulate keyboard-
;//               input.
;//
;//
;//         Changelog:
;//
;//             Early: Entry at 0xC603
;//
;//                 -> First version I have
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Constant
;
NOT         EQU     255

;
; Flag values
;
FALSE       EQU     0           ; Boolean False
TRUE        EQU     -1          ; Boolean True

;
; ASCII control cHaracters
;
NULL        EQU     000H        ; Null character
HTAB        EQU     009H        ; Horizontal tabulation
LF          EQU     00AH        ; Line Feed
ROLUP       EQU     00CH        ; Scroll screen up one row
CR          EQU     00DH        ; Cartridge Return
CURR        EQU     018H        ; Cursor right
APOSTROPHE  EQU     027H        ; Aphostrophe
SEMICOLON   EQU     03BH        ; Semicolon
DEL         EQU     07FH        ; Delete

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
OPEN        EQU     0FD1EH      ; Open block device

;
; TOS standard files
;
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer
AO_FCB      EQU     0FF0CH      ; Auxilliary output abstract file FCB pointer
AL_FCB      EQU     0FF0EH      ; Auxilliary line-printer output abstract file FCB pointer

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag
FM_OUTPUT   EQU     002H        ; File open for writing flag
FM_BINARY   EQU     004H        ; Binary flag
FM_EOF_NEXT EQU     010H        ; Can detect End of File flag
FM_ASSIGNED EQU     020H        ; Assigned and opened by command line flag
FM_NO_CLOSE EQU     040H        ; Don't close file flag

;
; TOS Errors
;
ERROR_08    EQU     008H        ; DRIVE NOT READY
ERROR_18    EQU     018H        ; OUTPUT TO NON-OUTPUT FILE

;
; ASM assembly state
;
AS_LASTPASS EQU     00FH        ; Assembler in the second- or single-pass state
AS_DONE     EQU     0FFH        ; Assembler is done

;
; ASM Errors
;
II_FC_ERR   EQU     001H        ; Illegal instruction (first character)
II_LI_ERR   EQU     002H        ; Illegal instruction (last item)
II_FI_ERR   EQU     003H        ; Illegal instruction (first item)
PI_S_ERR    EQU     004H        ; Pseudo-instruction syntax error
DBLSYMB_ERR EQU     005H        ; Symbol defined multiple times
SYMBTAB_ERR EQU     006H        ; Symbol table full
EOS_ERR     EQU     007H        ; Unexpected end of string
EXPR_S_ERR  EQU     008H        ; Expression syntax error
IT_EXPR_ERR EQU     009H        ; Illegal terminator of expression
NO_OPER_ERR EQU     010H        ; Missing operand
NO_CONS_ERR EQU     011H        ; Missing constant (DB, DW)
US_EXPR_ERR EQU     012H        ; Undefined symbol in expression
EOF_ERR     EQU     013H        ; Unexpected end of file (END missing)
ILL_SL_ERR  EQU     052H        ; Illegal list device
ILL_CMD_ERR EQU     054H        ; Illegal assembly command
DEV_BSY_ERR EQU     056H        ; Disk or cartridge not ready
TOS_ERR     EQU     099H        ; TOS error

;
; Listing string binary data bitmap bits
;
LS_BDBMP_B3 EQU     001H        ; Binary data, byte 1 flag
LS_BDBMP_B2 EQU     002H        ; Binary data, byte 2 flag
LS_BDBMP_B1 EQU     004H        ; Binary data, byte 3 flag
LS_BDBMP_AD EQU     008H        ; Address of binary data flag
LS_BDBMP_B4 EQU     010H        ; Binary data, byte 4 flag

;
; Symbol character flags
;
SYM_CH_MASK EQU     03FH        ; Symbol character data mask
SYM_SF_BYTE EQU     000H        ; Symbol byte length flag
SYM_SF_WORD EQU     040H        ; Symbol word length flag
SYM_CF_LAST EQU     080H        ; Symbol last character flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Dynamic data-buffers
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
symbol_buffers:
        DS          00600H
symbol_buffers_end:


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program re-entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Manual re-entry from debugger
        ;
        JMP         reentry_point


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Initialization
;//
;//////////////////////////////////////////////////////////////////////////////

start:
        ;
        ; Save stack pointer for breaking out of program from subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        stack_backup


;//////////////////////////////////////

        ;
        ; Check if the SI standard file is set
        ;
        LHLD        SI_FCB
        MOV         A,L
        ORA         H
        JZ          si_checked
        MVI         A,TRUE
si_checked:
        MOV         B,A
        ;
        ; If not, activate single-pass interactive mode
        ;
        CMA
        STA         interactive_mode_flag
        ANI         AS_LASTPASS
        STA         assembler_pass_state
        ;
        ; Check if the SO standard file is set
        ;
        LHLD        SO_FCB
        MOV         A,L
        ORA         H
        JZ          so_checked
        MVI         A,TRUE
so_checked:
        MOV         C,A
        ORA         B
        ;
        ; If neither SI or SO are set, assemble directly to RAM
        ;
        CMA
        STA         asm_direct_to_ram_flag
        ;
        ; Check if the AL standard file is set
        ;
        LHLD        AL_FCB
        MOV         A,L
        ORA         H
        JZ          al_checked
        MVI         A,TRUE
al_checked:
        MOV         E,A
        ;
        ; Check if the SL standard file is set
        ;
        LHLD        SL_FCB
        MOV         A,L
        ORA         H
        JZ          sl_checked
        MVI         A,TRUE
sl_checked:
        ;
        ; If so, enable the final error-report on the listing output
        ;
        STA         final_error_report_flag
        MOV         D,A


;//////////////////////////////////////

        ;
        ; Determine standard-files to use for the varous outputs
        ;
        JZ          handle_sl_not_set
        ;
        ; Use SL for error-listing if AL is not set
        ;
        ANA         E
        JNZ         sl_set_listing_device_ready
        LHLD        SL_FCB
        SHLD        AL_FCB
sl_set_listing_device_ready:
        ;
        ; Copy error-listing to CO if SI is not set
        ;
        MOV         A,B
        ORA         A
        JZ          set_up_copy_err_listing_to_console
        JMP         err_listing_device_ready

handle_sl_not_set:
        ;
        ; Use CO for code-listing if SL is not set
        ;
        LHLD        CO_FCB
        SHLD        SL_FCB
        ;
        ; Copy error-listing to CO if AL was set
        ;
        ORA         E
        JNZ         set_up_copy_err_listing_to_console
        ;
        ; Use CO for error-listing if neither SL or AL were set
        ;
        LHLD        CO_FCB
        SHLD        AL_FCB
        JMP         err_listing_device_ready

set_up_copy_err_listing_to_console:
        ;
        ; Set up error-listing for dual-device output
        ;
        LHLD        AL_FCB
        SHLD        dual_err_listing_2nd_file_ptr
        LXI         H,dual_err_listing_fcb
        SHLD        AL_FCB
        LHLD        CO_FCB
        SHLD        dual_err_listing_1st_file_ptr
err_listing_device_ready:
        ;
        ; Make sure unused output files can receive data, assigning a null-file
        ;
        MOV         A,C
        ORA         A
        JNZ         output_device_ready
        LXI         H,null_output_fcb
        SHLD        SO_FCB
output_device_ready:
        LHLD        AO_FCB
        MOV         A,L
        ORA         H
        JNZ         src_output_device_ready
        LXI         H,null_output_fcb
        SHLD        AO_FCB
src_output_device_ready:
        ;
        ; Use CO for code-listing if neither SO, SL or AL, but SI were set
        ;
        ORA         C
        ORA         D
        ORA         E
        JNZ         listing_device_ready
        ORA         B
        JZ          listing_device_ready
        LHLD        CO_FCB
        SHLD        SL_FCB
listing_device_ready:


;//////////////////////////////////////

        ;
        ; Determine bounds of user-memory fo symbol-buffers
        ;
        LXI         H,symbol_buffers_end-1
        SHLD        symbol_buffers_last_byte_ptr
        LXI         H,symbol_buffers
memory_test_loop:
        ;
        ; Check next memory page
        ;
        DCR         H
        MOV         A,M
        CMA
        MOV         M,A
        CMP         M
        JZ          memory_test_loop
        INR         H
        ;
        ; Save pointer to start of RAM
        ;
        SHLD        symbol_buffers_first_byte_ptr
        CALL        setup_buffers


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Sanitize stack in case of re-entry from debugger
        ;
reentry_point:
        LHLD        stack_backup
        SPHL
        ;
        ; Print initial code-listing margin
        ;
        MVI         A,ROLUP
        CALL        print_char_to_code_listing
        MVI         C,3
listing_first_margin_loop:
        CALL        print_newline_to_code_listing
        DCR         C
        JNZ         listing_first_margin_loop
        ;
        ; Reset lines left on page countdown
        ;
        MVI         A,65
        STA         lines_left_on_page


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear unused main flag
        ;
        XRA         A
        STA         unused_outside_main_flag
        ;
        ; Print ASM program title to console
        ;
        LHLD        CO_FCB
        LXI         B,title_str
        CALL        print_string
        CALL        print_newline


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Sanitize stack after break from anywhere
        ;
break_to_main:
        LHLD        stack_backup
        SPHL


;//////////////////////////////////////

        ;
        ; Main routine
        ;
main:
        ;
        ; Blank and setup output strings
        ;
        LXI         B,list_output_str_buffer
        CALL        clear_str_buffer
        LXI         H,src_output_str_buffer
        SHLD        src_output_str_buffer_cursor
        ;
        ; Set listing address
        ;
        LHLD        current_address_ptr
        SHLD        listing_bindata_addr
        ;
        ; Go to next line on code-listing output if pass 2 or interactive mode
        ;
        LDA         assembler_pass_state
        ORA         A
        LHLD        SL_FCB
        CNZ         print_newline
        ;
        ; Print current address to code-listing as a prompt if interactive mode
        ;
        LDA         interactive_mode_flag
        ORA         A
        LXI         H,listing_bindata_bitmap
        MVI         M,LS_BDBMP_AD
        LHLD        SL_FCB
        CNZ         print_data_only_listing_line
        MVI         C,16
        CALL        move_to_position_if_possible
        ;
        ; Clear variables to be used for parsing of the next line
        ;
        XRA         A
        MOV         L,A
        MOV         H,A
        SHLD        current_line_bin_length
        STA         current_error_nr
        STA         current_tos_error_nr
        STA         immediate_datatype_len_plus_one
        ;
        ; Enable address to be printed to the code-listing
        ;
        MVI         A,LS_BDBMP_AD
        STA         listing_bindata_bitmap
        ;
        ; Parse line
        ;
        CALL        parse_operation_type
        JC          main_input_line_done
        CALL        parse_operation_name
        JC          main_input_line_done
        CALL        parse_instruction
        JC          main_input_line_done
        CALL        parse_pseudo_instruction
main_input_line_done:
        ;
        ; Flush remaining parts of line after parsing
        ;
        CALL        flush_input_line
        ;
        ; Handle interactive mode main-routine stuff if active
        ;
        LDA         interactive_mode_flag
        ORA         A
        JNZ         interactive_mode_main
        ;
        ; Skip printing code-listing stuff if first pass
        ;
        LDA         assembler_pass_state
        ORA         A
        JZ          first_pass_main
        ;
        ; Second pass main:
        ; Cut code-listing output string at current cursor
        ;
        LDA         last_used_list_output_cursor_pos
        INR         A
        LXI         B,list_output_str_buffer
        STAX        B
        ;
        ; Point to end of code-listing string
        ;
        ADD         C
        MOV         C,A
        JNC         code_listing_str_end_ready
        INR         B
code_listing_str_end_ready:
        ;
        ; Add CR,LF to code-listing string and print it
        ;
        MVI         A,LF
        STAX        B
        DCX         B
        MVI         A,CR
        STAX        B
        LHLD        SL_FCB
        CALL        finalize_listing_line_and_print
        ;
        ; Increase code-listing linecount and check for end of page
        ;
        LDA         lines_left_on_page
        DCR         A
        JNZ         code_listing_line_number_ready
        ;
        ; If so, print margin of linebreak on code-listing
        ;
        MVI         C,7
print_code_listing_margin_loop:
        CALL        print_newline_to_code_listing
        DCR         C
        JNZ         print_code_listing_margin_loop
        ;
        ; Reset code-listing available linecount
        ;
        MVI         A,65
code_listing_line_number_ready:
        STA         lines_left_on_page
first_pass_main:
        ;
        ; Clear unused main flag
        ;
        XRA         A
        STA         unused_outside_main_flag
        ;
        ; Escalate any error that may have happened
        ;
        LDA         current_tos_error_nr
        MOV         B,A
        LDA         current_error_nr
        ORA         A
        MOV         C,A
        CNZ         raise_error
        JMP         main_loop_cleanup


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print newline to code-listing
        ;
print_newline_to_code_listing:
        MVI         A,CR
        CALL        print_char_to_code_listing
        MVI         A,LF


;//////////////////////////////////////

        ;
        ; Print a single character to code-listing
        ;
print_char_to_code_listing:
        LHLD        SL_FCB
        CALL        OUTCHAR
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Special handling for interactive mode main teardown
        ;
interactive_mode_main:
        ;
        ; Escalate any potential errors that may have happened
        ;
        LDA         current_error_nr
        ORA         A
        JZ          main_loop_cleanup
        MOV         C,A
        LDA         current_tos_error_nr
        MOV         B,A
        CALL        raise_error
        ;
        ; don't add anything to output files if error
        ;
        JMP         main


;//////////////////////////////////////

main_loop_cleanup:
        ;
        ; Generate source-code output from code-listing if interactive mode
        ;
        LDA         interactive_mode_flag
        ORA         A
        CNZ         copy_src_from_code_listing
        ;
        ; Write source-code to output if second pass or interactive mode
        ;
        LHLD        AO_FCB
        LXI         D,src_output_str_buffer
        LDA         assembler_pass_state
        ORA         A
        CNZ         PUT
        ;
        ; Check for end of second pass
        ;
        LDA         assembler_pass_state
        ORA         A
        JM          build_done      ; AS_DONE
        ;
        ; Advance current assembler address
        ;
        LHLD        current_line_bin_length
        XCHG
        LHLD        current_address_ptr
        DAD         D
        SHLD        current_address_ptr
        ;
        ; Continue next iteration of main loop
        ;
        JMP         main


;//////////////////////////////////////

        ;
        ; Handle teardown after end of second pass
        ;
build_done:
        ;
        ; Go to next line and print status on console
        ;
        LHLD        CO_FCB
        CALL        print_newline
        LXI         B,build_done_str
        CALL        print_string
        CALL        print_newline
        ;
        ; Check if errors
        ;
        LDA         error_counter
        ORA         A
        JZ          build_errors_report_ready
        ;
        ; If errors, update final error-report line
        ;
        LXI         B,build_errors_report_str + 1
        LXI         D,error_counter
        CALL        byte_to_hex
build_errors_report_ready:
        ;
        ; Print final error-report to console
        ;
        LHLD        CO_FCB
        LXI         B,build_errors_report_str
        CALL        print_string
        CALL        print_newline
        ;
        ; Print final error-report to code-listing if needed
        ;
        LDA         final_error_report_flag
        ORA         A
        LHLD        SL_FCB
        JZ          build_errors_report_done
        CALL        print_newline
        LXI         B,build_errors_report_str
        CALL        print_string
build_errors_report_done:
        ;
        ; Print final symbols reference to code-listing
        ;
        CALL        list_defined_symbols
        LHLD        SL_FCB
        CALL        list_undefined_symbols
        ;
        ; Quit to TOS
        ;
        JMP         exit_to_tos


;//////////////////////////////////////

title_str:
        DB          29
        DB          'TANDBERG TDV 2100 ASSEMBLER',CR,LF
build_errors_report_str:
        DB          18
        DB          'NO SYNTAX ERRORS',CR,LF
build_done_str:
        DB          19
        DB          'ASSEMBLY COMPLETE',CR,LF


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assembler core, instruction database
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; All 8080-opcode names
        ;
opcode_database:
        ;
        ; Opcodes without operands (1 byte)
        ;
        DB          008H,00CH,094H          ;  1: HLT
        HLT
        DB          012H,00CH,083H          ;  2: RLC
        RLC
        DB          012H,012H,083H          ;  3: RRC
        RRC
        DB          012H,001H,08CH          ;  4: RAL
        RAL
        DB          012H,001H,092H          ;  5: RAR
        RAR
        DB          012H,00EH,09AH          ;  6: RNZ
        RNZ
        DB          012H,09AH               ;  7: RZ
        RZ
        DB          012H,00EH,083H          ;  8: RNC
        RNC
        DB          012H,083H               ;  9: RC
        RC
        DB          012H,010H,08FH          ; 10: RPO
        RPO
        DB          012H,010H,085H          ; 11: RPE
        RPE
        DB          012H,090H               ; 12: RP
        RP
        DB          012H,08DH               ; 13: RM
        RM
        DB          018H,003H,008H,087H     ; 14: XCHG
        XCHG
        DB          018H,014H,008H,08CH     ; 15: XTHL
        XTHL
        DB          013H,010H,008H,08CH     ; 16: SPHL
        SPHL
        DB          010H,003H,008H,08CH     ; 17: PCHL
        PCHL
        DB          003H,00DH,081H          ; 18: CMA
        CMA
        DB          013H,014H,083H          ; 19: STC
        STC
        DB          003H,00DH,083H          ; 20: CMC
        CMC
        DB          004H,001H,081H          ; 21 :DAA
        DAA
        DB          005H,089H               ; 22: EI
        EI
        DB          004H,089H               ; 23: DI
        DI
        DB          00EH,00FH,090H          ; 24: NOP
        NOP
        DB          012H,005H,094H          ; 25: RET
        RET
        ;
        ; Immediate-byte argument opcodes (2 bytes)
        ;
        DB          009H,08EH               ; 26: IN    b
        DB          0DBH
        DB          00FH,015H,094H          ; 27: OUT   b
        DB          0D3H
        DB          001H,004H,089H          ; 28: ADI   b
        DB          0C6H
        DB          001H,003H,089H          ; 29: ACI   b
        DB          0CEH
        DB          013H,015H,089H          ; 30: SUI   b
        DB          0D6H
        DB          013H,002H,089H          ; 31: SBI   b
        DB          0DEH
        DB          001H,00EH,089H          ; 32: ANI   b
        DB          0E6H
        DB          018H,012H,089H          ; 33: XRI   b
        DB          0EEH
        DB          00FH,012H,089H          ; 34: ORI   b
        DB          0F6H
        DB          003H,010H,089H          ; 35: CPI   b
        DB          0FEH
        ;
        ; Immediate-word argument opcodes (3 bytes)
        ;
        DB          00CH,004H,081H          ; 36: LDA   w
        DB          03AH
        DB          013H,014H,081H          ; 37: STA   w
        DB          032H
        DB          003H,001H,00CH,08CH     ; 38: CALL  w
        DB          0CDH
        DB          00AH,00DH,090H          ; 39: JMP   w
        DB          0C3H
        DB          013H,008H,00CH,084H     ; 40: SHLD  w
        DB          022H
        DB          00CH,008H,00CH,084H     ; 41: LHLD  w
        DB          02AH
        DB          00AH,00EH,09AH          ; 42: JNZ   w
        DB          0C2H
        DB          00AH,09AH               ; 43: JZ    w
        DB          0CAH
        DB          00AH,00EH,083H          ; 44: JNC   w
        DB          0D2H
        DB          00AH,083H               ; 45: JC    w
        DB          0DAH
        DB          00AH,010H,08FH          ; 46: JPO   w
        DB          0E2H
        DB          00AH,010H,085H          ; 47: JPE   w
        DB          0EAH
        DB          00AH,090H               ; 48: JP    w
        DB          0F2H
        DB          00AH,08DH               ; 49: JM    w
        DB          0FAH
        DB          003H,00EH,09AH          ; 50: CNZ   w
        DB          0C4H
        DB          003H,09AH               ; 51: CZ    w
        DB          0CCH
        DB          003H,00EH,083H          ; 52: CNC   w
        DB          0D4H
        DB          003H,083H               ; 53: CC    w
        DB          0DCH
        DB          003H,010H,08FH          ; 54: CPO   w
        DB          0E4H
        DB          003H,010H,085H          ; 55: CPE   w
        DB          0ECH
        DB          003H,090H               ; 56: CP    w
        DB          0F4H
        DB          003H,08DH               ; 57: CM    w
        DB          0FCH
        ;
        ; Dual 8-bit register argument opcode (1 byte)
        ;
        DB          00DH,00FH,096H          ; 58: MOV   r8,r8
        MOV         B,B
        ;
        ; 8-bit register with immediate argument opcode (2 bytes)
        ;
        DB          00DH,016H,089H          ; 59: MVI   r8,b
        DB          006H
        ;
        ; Single 8-bit register argument opcodes (1 byte)
        ;
        DB          004H,003H,092H          ; 60: DCR   r8
        DCR         B
        DB          009H,00EH,092H          ; 61: INR   r8
        INR         B
        DB          001H,004H,084H          ; 62: ADD   r8
        ADD         B
        DB          001H,004H,083H          ; 63: ADC   r8
        ADC         B
        DB          013H,015H,082H          ; 64: SUB   r8
        SUB         B
        DB          013H,002H,082H          ; 65: SBB   r8
        SBB         B
        DB          001H,00EH,081H          ; 66: ANA   r8
        ANA         B
        DB          018H,012H,081H          ; 67: XRA   r8
        XRA         B
        DB          00FH,012H,081H          ; 68: ORA   r8
        ORA         B
        DB          003H,00DH,090H          ; 69: CMP   r8
        CMP         B
        ;
        ; opcodes with an enumerated argument (1 byte)
        ;
        DB          012H,013H,094H          ; 70: RST   n
        RST         0
        ;
        ; 16-bit register argument opcodes (1 byte)
        ;
        DB          010H,015H,013H,088H     ; 71: PUSH  r16
        PUSH        B
        DB          010H,00FH,090H          ; 72: POP   r16
        POP         B
        DB          013H,014H,001H,098H     ; 73: STAX  r16
        STAX        B
        DB          00CH,004H,001H,098H     ; 74: LDAX  r16
        LDAX        B
        DB          004H,001H,084H          ; 75: DAD   r16
        DAD         B
        DB          009H,00EH,098H          ; 76: INX   r16
        INX         B
        DB          004H,003H,098H          ; 77: DCX   r16
        DCX         B
        ;
        ; 16-bit register with immediate arguments opcodes (3 bytes)
        ;
        DB          00CH,018H,089H          ; 78: LXI   r16,w
        DB          001H
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; General pseudo-instruction names (except EQU)
        ;
pseudo_instr_database:
        DB          005H,00EH,084H          ; 1: END
        DB          005H,00FH,086H          ; 2: EOF
        DB          004H,082H               ; 3: DB    [b]
        DB          004H,097H               ; 4: DW    [w]
        DB          004H,093H               ; 5: DS    n
        DB          00FH,012H,087H          ; 6: ORG   w
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assembler core, meta-instructions and definitions
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse first character of line to catch and handle meta-instructions
        ;
parse_operation_type:
        ;
        ; Get character
        ;
        CALL        get_next_input_char
        ;
        ; Check for meta-instruction
        ;
        CPI         '/'
        JZ          dump_next_memory_instr
        CPI         '.'
        JZ          command_instr
        ;
        ; Check for comment or line-end
        ;
        CPI         CR
        JZ          skip_entire_input_line
        CPI         SEMICOLON
        JZ          skip_entire_input_line
        ;
        ; Assume normal assembly-instruction, so sanity-check if valid
        ;
        CALL        is_alphabetic
        RNC
        ;
        ; Otherwise raise error
        ;
instruction_first_char_error:
        MVI         A,II_FC_ERR
        STA         current_error_nr
        ;
        ; Set carry flag to signal that the line is to be skipped
        ;
skip_entire_input_line:
        STC
        RET


;//////////////////////////////////////

        ;
        ; Go handle command
        ;
command_instr:
        CALL        parse_input_command
        JMP         instrcution_done


;//////////////////////////////////////

        ;
        ; Dump the next three bytes of memory to list device
        ;
dump_next_memory_instr:
        ;
        ; Get next three bytes into the listing binary data buffer
        ;
        LHLD        current_address_ptr
        MOV         D,H
        MOV         E,L
        LXI         B,listing_line_bindata
        MVI         L,3
        CALL        copy_buffer
        ;
        ; List the three bytes to listing output
        ;
        MVI         A,LS_BDBMP_B1 + LS_BDBMP_B2 + LS_BDBMP_B3
        CALL        print_listing_line_new_datasize
        CALL        print_newline
instrcution_done:
        JMP         break_to_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Determine operation name, and handle if it is a symbol definition
        ;
parse_operation_name:
        CALL        get_next_name
        JC          instruction_first_char_error
        LDA         current_char
        CPI         ':'
        JZ          handle_symbol_def
        ORA         A
        RET

handle_symbol_def:
        ;
        ; Move cursor in interactive mode, a symbol def makes no binary data
        ;
        PUSH        PSW
        MVI         C,24
        CALL        move_interactive_cursor_to_position
        POP         PSW
        ;
        ; Add symbol to defined table, remove from undefined if present there
        ;
        LHLD        current_address_ptr
        SHLD        expression_value
        CALL        define_new_symbol
        RC
        CALL        replace_undef_with_value
        ;
        ; Continue, since a new operation can follow on the same line
        ;
        CALL        get_next_input_char
        CALL        is_alphabetic
        RC
        JMP         parse_operation_name


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get the next name, of an instruction, symbol or expression
        ;
get_next_name:
        ;
        ; Set up pointer and character count
        ;
        LXI         H,current_name_buffer
        MVI         C,-5
save_name_char:
        ;
        ; Save in-name characters using lower 6-bit only
        ;
        ANI         SYM_CH_MASK
        MOV         M,A
get_next_name_char:
        ;
        ; Get and validate next character
        ;
        PUSH        B
        CALL        get_input_char
        POP         B
        CALL        is_alphabetic
        JNC         got_valid_name_char
        CALL        is_numeric
        JNC         got_valid_name_char
        CALL        is_instr_separator
        JZ          got_last_char_in_name
        CALL        is_arithmetic
        JZ          got_last_char_in_name
        STC
        RET

got_valid_name_char:
        ;
        ; Check if the name buffer is going to be full
        ;
        INR         C
        JM          got_char_in_name
        ;
        ; If so, skip the rest of the name except for the last character
        ;
        MVI         C,-1
        JMP         get_next_name_char

got_char_in_name:
        ;
        ; Otherwise, still space in buffer, so keep going
        ;
        INX         H
        JMP         save_name_char

got_last_char_in_name:
        ;
        ; Save the last character as 7-bit ASCII, with bit-8 set
        ;
        STA         current_char
        MVI         A,SYM_CF_LAST
        ORA         M
        MOV         M,A
        ;
        ; Keep length of name
        ;
        MVI         A,6
        ADD         C
        STA         current_name_len
        ORA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assembler core, opcodes
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Validate and parse 8080-opcode instruction
        ;
parse_instruction:
        ;
        ; Check first character of instruction
        ;
        LDA         current_char
        CALL        is_arithmetic
        JZ          instr_error_last_item
        ;
        ; Check that the length of the instruction name is 2-4 characters
        ;
        LDA         current_name_len
        CPI         1
        RZ
        CPI         5
        RZ
        ;
        ; Look up instruction name in database
        ;
        LXI         B,opcode_database
        CALL        scan_for_name_byte_data
        JNC         valid_instruction
        ORA         A
        RET

valid_instruction:
        ;
        ; Point to next byte-address of instruction
        ;
        MOV         A,L
        LHLD        current_address_ptr
        INX         H
        SHLD        instr_data_next_addr_ptr
        ;
        ; Prepare listing output line for opcode
        ;
        MOV         L,A
        LDAX        B
        STA         listing_line_bindata
        CALL        tab_output_to_opcode
        XRA         A
        STA         listing_line_bindata + 1
        STA         listing_line_bindata + 2
        CALL        print_listing_line_new_datasize
        MOV         A,L
        ;
        ; Save table-index of opcode, and check for no-argument opcode
        ;
        STA         opcode_list_index
        CPI         26
        JC          single_byte_opcode_ready
        ;
        ; Verify whitespace between opcode and arguments
        ;
        LDA         current_char
        CPI         HTAB
        JZ          parse_opcode_args
        CPI         ' '
        JNZ         instr_error_last_item
parse_opcode_args:
        ;
        ; Handle immediate-type argument opcodes
        ;
        MOV         A,L
        CPI         36
        JC          parse_immediate_byte_arg
        CPI         58
        JC          parse_immediate_word_arg
        ;
        ; Get name of first argument
        ;
        CALL        get_next_input_char
        CALL        is_instr_separator
        JZ          instr_error_last_item
        CALL        get_next_name
        JC          instr_error_last_item
        ;
        ; Handle register as first operand
        ;
        LDA         opcode_list_index
        CPI         70
        JNC         parse_16_bit_reg_args_or_rst
        CPI         62
        JNC         parse_secondary_8_bit_reg_arith_arg
        ;
        ; Parse 8-bit reg inc/dec, as well as 8-bit mov/mvi
        ; Set first register bitfield
        ;
        ORA         A
        CALL        set_opcode_8b_reg_bitfield_from_name
        JC          instr_error_last_item
        LDA         opcode_list_index
        CPI         60
        JNC         single_byte_opcode_ready
        ;
        ; Parse 8-bit mov/mvi, verify operand separator
        ;
        MOV         L,A
        LDA         current_char
        CPI         ','
        JNZ         instr_error_last_item
        MOV         A,L
        ;
        ; Handle second operand as immediate if mvi
        ;
        CPI         59
        JZ          parse_immediate_byte_arg
        ;
        ; Check for existence of a second operand and fetch it
        ;
        CALL        get_input_char
        CALL        is_instr_separator
        JZ          instr_error_last_item
        CALL        get_next_name
        JC          instr_error_last_item
parse_secondary_8_bit_reg_arith_arg:
        ;
        ; Set second register bitfield
        ;
        STC
        CALL        set_opcode_8b_reg_bitfield_from_name
        JC          instr_error_last_item
        JMP         single_byte_opcode_ready


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prepare output line for opcode
        ;
tab_output_to_opcode:
        ;
        ; Skip if not interacive mode
        ;
        LDA         interactive_mode_flag
        ORA         A
        RZ
        ;
        ; Check if cursor is not past position 24
        ;
        LDA         console_line_cursor_pos
        CPI         24
        JP          tab_output_to_opcode_done
        PUSH        H
        MOV         C,A
        PUSH        B
        ;
        ; Get remaining characters between cursor and position 24
        ;
        MVI         A,24
        SUB         C
        ;
        ; Point to output string at cursor position
        ;
        LXI         D,list_output_str_buffer
        POP         H
        PUSH        H
        MVI         H,000H
        DAD         D
        XCHG
        DCX         D
        PUSH        D
        ;
        ; Point to output string at position 24
        ;
        MVI         B,000H
        MVI         C,24
        DAD         B
        MOV         B,H
        MOV         C,L
        ;
        ; Move text at cursor position and onwards up to position 24
        ;
        MOV         L,A
        PUSH        PSW
        CALL        copy_buffer
        POP         PSW
        ;
        ; Clear from cursor and up until position 24
        ;
        POP         H
        MVI         A,24
        POP         B
        SUB         C
clear_margin_before_opcode_loop:
        MVI         M,' '
        INX         H
        DCR         A
        JNZ         clear_margin_before_opcode_loop
        POP         H
tab_output_to_opcode_done:
        ;
        ; Move cursor to position 32
        ;
        MVI         C,32
        JMP         move_to_position_if_possible


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set bitfield of reset opcode, or ones with a 16-bit register operand
        ;
parse_16_bit_reg_args_or_rst:
        ;
        ; Check if not RST
        ;
        JNZ         parse_16_bit_reg_args
        ;
        ; Get RST-opcode nr from name
        ;
        LXI         B,reset_nr_database
        CALL        scan_for_name_no_data
        JC          instr_error_last_item
        ;
        ; 0-index RST nr
        ;
        DCR         L
        MOV         A,L
        JMP         finalize_opcode_16b_reg_or_rst_bitfield


;//////////////////////////////////////

reset_nr_database:
        DB          0B0H                     ; 1: 0
        DB          0B1H                     ; 2: 1
        DB          0B2H                     ; 3: 2
        DB          0B3H                     ; 4: 3
        DB          0B4H                     ; 5: 4
        DB          0B5H                     ; 6: 5
        DB          0B6H                     ; 7: 6
        DB          0B7H                     ; 8: 7
        DB          NULL


;//////////////////////////////////////

        ;
        ; Set bitfield of opcode with a 16-bit register operand
        ;
parse_16_bit_reg_args:
        ;
        ; Check if arithmetic or lxi opcode
        ;
        CPI         75
        JNC         parse_16_bit_reg_arith_args
        ;
        ; Enumerate register from name
        ;
        LXI         B,stack_op_registers_database
        CALL        scan_for_name_no_data
        JC          instr_error_last_item
        ;
        ; Check for push/pop or stax/ldax
        ;
        LDA         opcode_list_index
        CPI         73
        JC          set_opcode_16b_reg_bitfield
        ;
        ; If stax/ldax, H and PSW are not valid
        ;
        MOV         A,L
        CPI         3
        JNC         instr_error_last_item
        JMP         set_opcode_16b_reg_bitfield


;//////////////////////////////////////

stack_op_registers_database:
        DB          082H                    ; 1: B
        DB          084H                    ; 2: D
        DB          088H                    ; 3: H
        DB          010H,013H,097H          ; 4: PSW
        DB          NULL


;//////////////////////////////////////

        ;
        ; Use other register names for dad/inx/dcx/lxi than for push/pop
        ;
parse_16_bit_reg_arith_args:
        ;
        ; Enumerate register from name
        ;
        LXI         B,word_registers_database
        CALL        scan_for_name_no_data
        JC          instr_error_last_item


;//////////////////////////////////////

        ;
        ; Set the correct register bitfields of opcode according to register
        ;
set_opcode_16b_reg_bitfield:
        ;
        ; 0-index 16-bit register enumeraion
        ;
        DCR         L
        ;
        ; Shift enumeration to match appropriate opcode bitfield
        ;
        MOV         A,L
        ORA         A
        RAL
finalize_opcode_16b_reg_or_rst_bitfield:
        RAL
        RAL
        RAL
        ;
        ; Set bitfield in opcode binary data
        ;
        LXI         H,listing_line_bindata
        ORA         M
        MOV         M,A
        ;
        ; Check for lxi opcode
        ;
        LDA         opcode_list_index
        CPI         78
        JNZ         single_byte_opcode_ready
        ;
        ; If so, expect opcode separator followed by a 16-bit immediate
        ;
        LDA         current_char
        CPI         ','
        JNZ         instr_error_last_item
        JMP         parse_immediate_word_arg


;//////////////////////////////////////

word_registers_database:
        DB          082H                    ; 1: B
        DB          084H                    ; 2: D
        DB          088H                    ; 3: H
        DB          013H,090H               ; 4: SP
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte opcode is now complete, so report it
        ;
single_byte_opcode_ready:
        ;
        ; Update listing line binary data size and print data
        ;
        MVI         A,LS_BDBMP_B1 + LS_BDBMP_AD
        CALL        print_listing_line_new_datasize
        ;
        ; Add singly-byte opcode data to assembled output
        ;
        LXI         H,1
        SHLD        current_line_bin_length
        LDA         listing_line_bindata
        LHLD        current_address_ptr
        JMP         final_instr_byte_ready


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Byte immediate, set up for 2-byte opcode
        ;
parse_immediate_byte_arg:
        MVI         A,LS_BDBMP_B1 + LS_BDBMP_B2 + LS_BDBMP_AD
        MVI         L,2
        ORA         A
        JMP         parse_immediate_arg


;//////////////////////////////////////

        ;
        ; Word immediate, set up for 3-byte opcode
        ;
parse_immediate_word_arg:
        MVI         A,LS_BDBMP_B1 + LS_BDBMP_B2 + LS_BDBMP_B3 + LS_BDBMP_AD
        MVI         L,3
        STC


;//////////////////////////////////////

        ;
        ; Parse immediate argument
        ;
parse_immediate_arg:
        ;
        ; Update code-listing line with first opcode byte
        ;
        PUSH        PSW
        ANI         LS_BDBMP_B1 + LS_BDBMP_AD
        CALL        print_listing_line_new_datasize
        POP         PSW
        ;
        ; Update opcode length variables
        ;
        PUSH        PSW
        STA         listing_bindata_bitmap
        MVI         H,000H
        SHLD        current_line_bin_length
        MOV         A,L
        STA         immediate_datatype_len_plus_one
        ;
        ; Add first opcode byte to assembled output
        ;
        LDA         listing_line_bindata
        LHLD        current_address_ptr
        CALL        add_byte_to_assembled_binary
        ;
        ; Get immediate expression and store to listing binary data
        ;
        PUSH        H
        CALL        parse_expression
        LDA         last_used_list_output_cursor_pos
        STA         list_output_line_cursor_pos
        LHLD        expression_value
        SHLD        listing_line_bindata + 1
        XCHG
        POP         H
        POP         PSW
        ;
        ; Update code-listing line with immediate data
        ;
        PUSH        PSW
        PUSH        D
        CALL        print_listing_line_new_datasize
        POP         D
        POP         PSW
        ;
        ; Check if byte-size or word-size immediate data
        ;
        MOV         A,E
        JNC         final_instr_byte_ready
        ;
        ; Add first byte of word-size immediate data
        ;
        PUSH        D
        CALL        add_byte_to_assembled_binary
        POP         D
        ;
        ; Add second byte of word-size immediate data
        ;
        MOV         A,D
final_instr_byte_ready:
        CALL        add_byte_to_assembled_binary
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Escalate syntax error if fault while parsing instruction
        ;
instr_error_last_item:
        MVI         A,II_LI_ERR
        STA         current_error_nr
        ;
        ; Make sure to add as much data as possible to the listing line
        ;
        MVI         A,LS_BDBMP_B1 + LS_BDBMP_B2 + LS_BDBMP_B3 + LS_BDBMP_AD
        STA         listing_bindata_bitmap
        MVI         A,3
        STA         current_line_bin_length
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set register bitfield in opcode for 8-bit register operands
        ; If Carry is set, bit 0-2 of opcode is set, otherwise bit 3-5 is set
        ;
set_opcode_8b_reg_bitfield_from_name:
        ;
        ; Look up register name enumeration
        ;
        PUSH        PSW
        LXI         B,byte_registers_database
        CALL        scan_for_name_no_data
        JNC         opcode_8b_reg_name_found
        POP         B
        RET

opcode_8b_reg_name_found:
        ;
        ; Make enumeration 0-indexed
        ;
        DCR         L
        POP         PSW
        MOV         A,L
        ;
        ; Align register enumeration to opcode bitfield
        ;
        JC          opcode_8b_reg_bitfield_ready
        RAL
        RAL
        RAL
opcode_8b_reg_bitfield_ready:
        ;
        ; Add register to opcode bitfield
        ;
        LXI         H,listing_line_bindata
        ORA         M
        MOV         M,A
        RET


;//////////////////////////////////////

byte_registers_database:
        DB          082H                    ; 1: B
        DB          083H                    ; 2: C
        DB          084H                    ; 3: D
        DB          085H                    ; 4: E
        DB          088H                    ; 5: H
        DB          08CH                    ; 6: L
        DB          08DH                    ; 7: M
        DB          081H                    ; 8: A
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assembler core, pseudo-instructions
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Validate and parse pseudo-instruction
        ;
parse_pseudo_instruction:
        ;
        ; Set up address pointers
        ;
        LHLD        current_address_ptr
        SHLD        instr_data_next_addr_ptr
        ;
        ; Look up pseudo-instruction by name
        ;
        LXI         B,pseudo_instr_database
        CALL        scan_for_name_no_data
        JNC         valid_pseudo_instr
        ;
        ; No valid pseudo-instruction, assume equate if followed by whitespace
        ;
        LDA         current_char
        CPI         ' '
        JZ          parse_equate
        CPI         HTAB
        JZ          parse_equate
        ;
        ; Invalid pseudo-instruction
        ;
instr_error_first_item:
        MVI         A,II_FI_ERR
        STA         current_error_nr
        RET

valid_pseudo_instr:
        ;
        ; Prepare code-listing for pseudo-instruction line
        ;
        CALL        tab_output_to_opcode
        PUSH        PSW
        CALL        print_listing_line
        POP         PSW
        ;
        ; Check for end/eof
        ;
        MOV         A,L
        CPI         3
        JNC         parse_data_or_addr_pseudo_instr
        ;
        ; Source code file has reached it's end
        ;
source_file_end:
        ;
        ; Check if at end of first pass or second pass
        ;
        LDA         assembler_pass_state
        ORA         A
        JZ          end_first_pass
        ;
        ; Second pass end, wrap up any partally unfinished hex-file line
        ;
        LXI         D,hexfile_str_len
        LDAX        D
        ORA         A
        JZ          terminate_hexfile
        ADI         2
        STAX        D
        CALL        finalize_and_print_hex_string
terminate_hexfile:
        ;
        ; Print hex-file block termination line
        ;
        LHLD        SO_FCB
        LXI         B,hexfile_termination_str
        CALL        print_string
        JMP         end_second_pass


;//////////////////////////////////////

        ;
        ; Go from first to second pass
        ;
end_first_pass:
        LHLD        SI_FCB
        PUSH        H
        ;
        ; Reset mode of input file, by clearing appropriate file-mode flags
        ;
        INX         H
        MOV         A,M             ; SI_FCB + FCB_MODE
        ANI         FM_ASSIGNED
        MVI         A,FM_BINARY + FM_NO_CLOSE
        JZ          force_close_input_file
        MVI         A,FM_INPUT + FM_OUTPUT + FM_BINARY + FM_ASSIGNED + FM_NO_CLOSE
force_close_input_file:
        ANA         M
        MOV         M,A
        ;
        ; Reset buffer-length of input file
        ;
        INX         H
        INX         H
        INX         H
        MVI         M,128           ; SI_FCB + FCB_BUFLEN
        INX         H
        XRA         A
        MOV         M,A
        ;
        ; Reset state of program
        ;
        STA         unused_outside_main_flag
        STA         error_counter
        ;
        ; Attempt to re-open input file for reading
        ;
        INR         A
        POP         H
        CALL        OPEN
        JNC         input_file_reopened
        ;
        ; Handle any eventual error during attempt at re-opening file
        ;
        MVI         C,TOS_ERR
        MOV         B,A
        JMP         raise_error

        ;
        ; Set up for second pass
        ;
input_file_reopened:
        MVI         A,AS_LASTPASS
        STA         assembler_pass_state
        LXI         H,0
        SHLD        current_address_ptr
        JMP         break_to_main


;//////////////////////////////////////

        ;
        ; Mark second pass done
        ;
end_second_pass:
        MVI         A,AS_DONE
        STA         assembler_pass_state
        RET


;//////////////////////////////////////

hexfile_termination_str:
        DB          13
        DB          ':00000001FF',CR,LF


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse pseudo-instructions db/dw/ds/org
        ;
parse_data_or_addr_pseudo_instr:
        STA         opcode_list_index
        ;
        ; Verify whitespace after pseudo-instruction name
        ;
        LDA         current_char
        CPI         HTAB
        JZ          pseudo_inst_whitespace_found
        CPI         ' '
        JNZ         pseudo_inst_syntax_error
pseudo_inst_whitespace_found:
        ;
        ; Check for db/dw
        ;
        MOV         A,L
        CPI         5
        JNC         parse_non_preset_pseudo_inst
        ;
        ; If so, set length variables
        ;
        DCR         A
        STA         immediate_datatype_len_plus_one
        MOV         L,A
        DCR         L
        MVI         H,000H
        SHLD        current_line_bin_length
        ;
        ; Check if byte or word length
        ;
        CPI         2
        JZ          parse_define_byte_data


;//////////////////////////////////////

        ;
        ; Parse defined word data
        ; Update initial listing binary size
        ;
        MVI         A,LS_BDBMP_B1 + LS_BDBMP_B2 + LS_BDBMP_AD
        STA         listing_bindata_bitmap
        ;
        ; Get first value, add it to binary output, and update listing
        ;
        CALL        parse_expression
        LHLD        expression_value
        SHLD        listing_line_bindata
        PUSH        H
        MOV         A,L
        LHLD        current_address_ptr
        CALL        add_byte_to_assembled_binary
        POP         PSW
        CALL        add_byte_to_assembled_binary
        CALL        print_listing_line
        ;
        ; Advance to next word and check for more data
        ;
        LHLD        instr_data_next_addr_ptr
        INX         H
        INX         H
        SHLD        instr_data_next_addr_ptr
        CALL        check_if_more_defined_data
        RC
        ;
        ; If more data, list those as byte nr 3 and 4
        ;
        LDA         listing_bindata_bitmap
        ORI         LS_BDBMP_B3 + LS_BDBMP_B4
        STA         listing_bindata_bitmap
        ;
        ; Get second value, add it to binary output, and update listing
        ;
        CALL        parse_expression
        LHLD        expression_value
        SHLD        listing_line_bindata + 2
        PUSH        H
        MOV         A,L
        LHLD        current_address_ptr
        CALL        add_byte_to_assembled_binary
        POP         PSW
        CALL        add_byte_to_assembled_binary
        CALL        print_listing_line
        ;
        ; Advance to next word and check for more data
        ;
        LHLD        instr_data_next_addr_ptr
        INX         H
        INX         H
        SHLD        instr_data_next_addr_ptr
        CALL        check_if_more_defined_data
        RC
add_next_defined_word:
        ;
        ; Get additional value, and add it to binary output without listing
        ;
        CALL        parse_expression
        LHLD        expression_value
        PUSH        H
        MOV         A,L
        LHLD        current_address_ptr
        CALL        add_byte_to_assembled_binary
        POP         PSW
        CALL        add_byte_to_assembled_binary
        ;
        ; Advance to next word and check for more data
        ;
        LHLD        instr_data_next_addr_ptr
        INX         H
        INX         H
        SHLD        instr_data_next_addr_ptr
        CALL        check_if_more_defined_data
        JNC         add_next_defined_word
        RET


;//////////////////////////////////////

        ;
        ; Add defined bytes to assembled program
        ;
parse_define_byte_data:
        ;
        ; Prepare initial listing binary size
        ;
        LXI         D,(LS_BDBMP_AD + LS_BDBMP_B1)*256
        PUSH        D
parse_next_defined_byte:
        ;
        ; Get first character of next value
        ;
        CALL        get_next_input_char
parse_defined_byte:
        ;
        ; Check that there is an expression at all
        ;
        CALL        is_instr_separator
        POP         D
        JNZ         get_defined_byte
        ;
        ; If no expression, raise no constant error
        ;
        MVI         A,NO_CONS_ERR
        STA         current_error_nr
        RET

get_defined_byte:
        ;
        ; Update listing binary size
        ;
        PUSH        PSW
        LDA         listing_bindata_bitmap
        ORA         D
        STA         listing_bindata_bitmap
        POP         PSW
        ;
        ; Check if expression is the start of a string, if not get value
        ;
        PUSH        D
        CPI         APOSTROPHE
        JZ          get_next_string_data_byte
        CALL        parse_expression_direct
        POP         D
        ;
        ; Update listing with value and add to binary output
        ;
        PUSH        D
        CALL        try_listing_defined_byte
        LDA         expression_value
        LHLD        current_address_ptr
        CALL        add_byte_to_assembled_binary
        ;
        ; Advance to next byte and check for more data
        ;
        LHLD        instr_data_next_addr_ptr
        INX         H
        SHLD        instr_data_next_addr_ptr
        CALL        check_if_more_defined_data
        POP         D
        RC
        ;
        ; Increase number of bytes in listing
        ;
        INX         D
        ;
        ; Add next bit to listing binary data bitfield
        ;
        MOV         A,E
        MVI         D,LS_BDBMP_B2
        CPI         1
        JZ          db_data_listing_pos_ready
        DCR         D               ; LS_BDBMP_B3
        CPI         2
        JZ          db_data_listing_pos_ready
        MVI         D,LS_BDBMP_B4
db_data_listing_pos_ready:
        PUSH        D
        ;
        ; Get to next defined expression
        ;
        CALL        get_input_char
        JMP         parse_defined_byte


;//////////////////////////////////////

        ;
        ; Deploy updated listing binary data bitmap and info
        ;
db_string_listing_pos_ready:
        PUSH        D
        LDA         listing_bindata_bitmap
        ORA         D
        STA         listing_bindata_bitmap
get_next_string_data_byte:
        ;
        ; Check for end of string data
        ;
        CALL        get_input_char
        CPI         APOSTROPHE
        JNZ         verify_next_string_data
        ;
        ; Check for more data or end of instruction after string end
        ;
        CALL        get_input_char
        STA         current_char
        CPI         ','
        JZ          parse_next_defined_byte
        CALL        is_instr_separator
        JNZ         end_of_string_error
        ;
        ; Prepare for parsing next instruction
        ;
        XRA         A
        STA         current_line_bin_length
        POP         D
        RET

verify_next_string_data:
        ;
        ; Verify that the string does not cross onto a new line
        ;
        CPI         CR
        JNZ         defined_string_data_ready
        STA         current_char
end_of_string_error:
        MVI         A,EOS_ERR
        STA         current_error_nr
        POP         D
        RET

defined_string_data_ready:
        ;
        ; Add string data to assembled binary
        ;
        STA         expression_value
        POP         D
        PUSH        D
        CALL        try_listing_defined_byte
        LDA         expression_value
        LHLD        current_address_ptr
        CALL        add_byte_to_assembled_binary
        ;
        ; Advance to next byte and check for more data
        ;
        LHLD        instr_data_next_addr_ptr
        INX         H
        SHLD        instr_data_next_addr_ptr
        CALL        more_defined_data
        POP         D
        RC
        ;
        ; Increase number of bytes in listing
        ;
        INX         D
        ;
        ; Add next bit to listing binary data bitfield
        ;
        MOV         A,E
        MVI         D,LS_BDBMP_B2
        CPI         1
        JZ          db_string_listing_pos_ready
        DCR         D               ; LS_BDBMP_B3
        CPI         2
        JZ          db_string_listing_pos_ready
        MVI         D,LS_BDBMP_B4
        JMP         db_string_listing_pos_ready


;//////////////////////////////////////

        ;
        ; Update listing line with additional defined data, if space
        ;
try_listing_defined_byte:
        ;
        ; Check if 4 bytes have been listed already
        ;
        MOV         A,E
        CPI         4
        RP
        ;
        ; Otherwise add byte to listing
        ;
        LXI         H,listing_line_bindata
        MVI         D,000H
        DAD         D
        LDA         expression_value
        MOV         M,A
        JMP         print_listing_line


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Check if an additional data-element follows previous data-element
        ;
check_if_more_defined_data:
        ;
        ; Check for data-definition separator, or end of instruction
        ;
        LDA         current_char
        CPI         ','
        JZ          more_defined_data
        CALL        is_instr_separator
        JZ          end_of_defined_data
        ;
        ; If unexpected character, raise no constant error
        ;
        MVI         A,NO_CONS_ERR
        STA         current_error_nr
        JMP         end_of_defined_data

more_defined_data:
        ;
        ; Check for interactive mode
        ;
        LDA         interactive_mode_flag
        ORA         A
        LDA         current_error_nr
        JZ          def_data_check_soft_err
        ;
        ; Check if an error was set for escalation if interactive mode
        ;
        ORA         A
        MOV         C,A
        MVI         B,FALSE
        CNZ         raise_error
advance_current_addr:
        ;
        ; Advance current address after adding data or space
        ;
        LHLD        current_line_bin_length
        XCHG
        LHLD        current_address_ptr
        DAD         D
        SHLD        current_address_ptr
        ORA         A
        RET

def_data_check_soft_err:
        ;
        ; Cut data short on error, rather than raising a hard error
        ;
        ORA         A
        JZ          advance_current_addr
end_of_defined_data:
        ;
        ; Mark end of data in data-definition sequence
        ;
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Handle single-operand pseudo-instruction, in effect ds and org
        ;
parse_non_preset_pseudo_inst:
        ;
        ; Get operand for Pseudo-instruction
        ;
        CALL        parse_expression
        JC          pseudo_inst_syntax_error
        ;
        ; Check for org pseudo-instruction
        ;
        LDA         opcode_list_index
        CPI         6
        JZ          set_new_origin
        ;
        ; For ds, bump the current address with the expression-value of bytes
        ;
        LHLD        expression_value
        SHLD        current_line_bin_length
        RET


;//////////////////////////////////////

        ;
        ; Handle org pseudo-instruction
        ;
set_new_origin:
        ;
        ; Negate current address
        ;
        LHLD        current_address_ptr
        MOV         A,L
        CMA
        MOV         E,A
        MOV         A,H
        CMA
        MOV         D,A
        INX         D
        ;
        ; Set listing address to the new origin to expression value
        ;
        LHLD        expression_value
        SHLD        listing_bindata_addr
        ;
        ; Get the difference between the target origin and the current address
        ;
        DAD         D
        ;
        ; Bump the current address with this difference to reach target origin
        ;
        SHLD        current_line_bin_length
        JMP         print_listing_line


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set syntax error
        ;
pseudo_inst_syntax_error:
        MVI         A,PI_S_ERR
        STA         current_error_nr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Validate and register equ pseudo-instruction
        ;
parse_equate:
        ;
        ; Copy name of symbol in equ instruction
        ;
        LXI         B,equ_symbol_name_backup
        LXI         D,current_name_buffer
        MVI         L,6
        CALL        copy_buffer
        ;
        ; Check for 'EQU' expression
        ;
        CALL        get_next_input_char
        CPI         'E'
        JNZ         invalid_equ_expression
        CALL        get_input_char
        CPI         'Q'
        JNZ         invalid_equ_expression
        CALL        get_input_char
        CPI         'U'
        JNZ         invalid_equ_expression
        ;
        ; Validate separator between EQU and associated expression
        ;
        CALL        get_input_char
        CPI         ' '
        JZ          add_interactive_mode_equ_tab
        CPI         HTAB
        JZ          get_equ_value
invalid_equ_expression:
        ;
        ; If separator is not found, raise error
        ;
        STA         current_char
        JMP         instr_error_first_item

        ;
        ; Convert space to tab in interactive mode
        ;
add_interactive_mode_equ_tab:
        CALL        move_interactive_cursor_to_position


;//////////////////////////////////////

        ;
        ; Get value and assign to symbol
        ;
get_equ_value:
        ;
        ; Parse expression and add to listing
        ;
        CALL        parse_expression
        JC          pseudo_inst_syntax_error
        LHLD        expression_value
        SHLD        listing_bindata_addr
        CALL        print_listing_line
        ;
        ; Restore symbol from equ instruction and assign expression-value to it
        ;
        LXI         B,current_name_buffer
        LXI         D,equ_symbol_name_backup
        MVI         L,6
        CALL        copy_buffer
        CALL        define_new_symbol
        RC
        JMP         replace_undef_with_value


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assembler core, assembled output
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add a byte A to the final assembled output at address HL
        ;
add_byte_to_assembled_binary:
        ;
        ; Save byte to be added
        ;
        MOV         C,A
        STA         current_asm_bin_byte
        ;
        ; Check if first pass or not
        ;
        LDA         assembler_pass_state
        ORA         A
        RZ
        ;
        ; Put byte directly into memory if assembling directly to RAM
        ;
        LDA         asm_direct_to_ram_flag
        ORA         A
        JZ          add_byte_to_hex_output
        MOV         M,C
add_byte_to_hex_output:
        ;
        ; Check if current hex-file line is empty
        ;
        LXI         D,hexfile_str_len
        LDAX        D
        ORA         A
        JNZ         append_byte_to_hex_line
        ;
        ; If so, set up misc header-fields
        ;
set_up_hex_line:
        PUSH        D
        PUSH        H
        SHLD        hex_file_next_cont_addr
        ;
        ; Initialize hex-line checksum
        ;
        MOV         A,L
        ADD         H
        STA         hexfile_str_checksum_value
        ;
        ; Add hex-line address
        ;
        LXI         B,hexfile_str_buffer + 4
        LXI         D,hex_file_next_cont_addr
        CALL        word_to_hex
        ;
        ; Initialize hex-line record type to 00
        ;
        MVI         A,'0'
        STAX        B
        INX         B
        STAX        B
        INX         B
        ;
        ; Initialize target pointer to hex-line checksum
        ;
        MOV         L,C
        MOV         H,B
        SHLD        hexfile_str_checksum_ptr
        POP         H
        POP         D
        ;
        ; Initialize hex-line length
        ;
        MVI         A,11
        STAX        D
        ;
        ; Append byte to current hex-line
        ;
append_byte_to_hex_line:
        ;
        ; Increase length of hex-line by 2 chars and check if line is full
        ;
        ADI         2
        STAX        D
        CPI         45
        JZ          start_next_hex_file_line
        ;
        ; Check if byte to append is a continuation of the current line
        ;
        LXI         D,hex_file_next_cont_addr
        LDAX        D
        CMP         L
        JNZ         start_next_hex_file_line
        INX         D
        LDAX        D
        CMP         H
        JNZ         start_next_hex_file_line
        ;
        ; If so, keep going on the same line, advancing next expected address
        ;
        INX         H
        SHLD        hex_file_next_cont_addr
        ;
        ; Update hex-line checksum value
        ;
        LXI         D,current_asm_bin_byte
        LDAX        D
        LXI         H,hexfile_str_checksum_value
        ADD         M
        MOV         M,A
        ;
        ; Update hex-line checksum string pointer
        ;
        LHLD        hexfile_str_checksum_ptr
        MOV         C,L
        MOV         B,H
        INX         H
        INX         H
        SHLD        hexfile_str_checksum_ptr
        ;
        ; Add of data-byte to hex-line string
        ;
        CALL        byte_to_hex
        LHLD        hex_file_next_cont_addr
        RET

        ;
        ; Print the current hex-line string and prepare for the next one
        ;
start_next_hex_file_line:
        PUSH        H
        CALL        finalize_and_print_hex_string
        POP         H
        LXI         D,hexfile_str_len
        JMP         set_up_hex_line


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print the current hex-file line, after setting up the final fields
        ;
finalize_and_print_hex_string:
        ;
        ; Setup string of upcoming line for the hex-file output
        ;
        LXI         B,hexfile_str_buffer
        PUSH        B
        LDA         hexfile_str_len
        STAX        B
        INX         B
        ;
        ; Set up initial colon
        ;
        MVI         A,':'
        STAX        B
        INX         B
        ;
        ; Compose data-length field of hex-file line, based on line length
        ;
        LXI         D,hexfile_str_len
        PUSH        D
        LDAX        D
        SUI         1 + 5*2 + 2     ; Length of ':' + header + CR + LF
        RAR
        STAX        D
        CALL        byte_to_hex
        ;
        ; Prepare to finalize checksum of hex-file line
        ;
        LHLD        hexfile_str_checksum_ptr
        MOV         C,L
        MOV         B,H
        LXI         D,hexfile_str_checksum_value
        LDAX        D
        POP         H
        ;
        ; Calculate and compose final checksum
        ;
        ADD         M
        MVI         M,000H
        CMA
        INR         A
        STAX        D
        CALL        byte_to_hex
        ;
        ; Terminate hex-file line
        ;
        MVI         A,CR
        STAX        B
        INX         B
        MVI         A,LF
        STAX        B
        ;
        ; Output finalized hex-file line
        ;
        POP         B
        LHLD        SO_FCB
        CALL        print_string
        ;
        ; Make sure length is reset before starting with next line
        ;
        XRA         A
        STA         hexfile_str_len
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear full 79-character string data-buffer pointed to by HL
        ;
clear_str_buffer:
        PUSH        B
        PUSH        PSW
        ;
        ; Set length of string
        ;
        MVI         A,79
        STAX        B
        INX         B
        ;
        ; Fill string data-buffer with spaces
        ;
        MOV         E,A
        MVI         A,' '
clear_str_buffer_loop:
        STAX        B
        INX         B
        DCR         E
        JNZ         clear_str_buffer_loop
        POP         PSW
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assembler core, symbol management
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add a new symbol to the defined symbols table
        ;
define_new_symbol:
        ;
        ; Check if either interactive mode, or if file SI is on its first pass
        ;
        LDA         assembler_pass_state
        LXI         H,interactive_mode_flag
        XRA         M
        ANI         AS_LASTPASS
        RNZ
        ;
        ; Verify that the symbol is not already defined
        ;
        LHLD        defined_symbols_start_ptr
        MOV         B,H
        MOV         C,L
        CALL        scan_for_name_word_data
        MVI         A,DBLSYMB_ERR
        JNC         error_adding_symbol
        ;
        ; Verify that there is space for another symbol
        ;
        CALL        is_more_space_in_symb_tables
        JC          symb_tables_full_error
        ;
        ; Copy symbol name onto the end of the table of defined symbols
        ;
        LDA         current_name_len
        MOV         C,A
        LHLD        defined_symbols_end_ptr
        XCHG
        LXI         H,current_name_buffer
set_def_symb_name_loop:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         C
        JNZ         set_def_symb_name_loop
        ;
        ; Append the symbol address to new symbol database entry
        ;
        LHLD        expression_value
        XCHG
        MOV         M,E
        INX         H
        MOV         M,D
        INX         H
        ;
        ; Mark new end of defined symbols table
        ;
        SHLD        defined_symbols_end_ptr
        MVI         M,NULL
        RET


;//////////////////////////////////////

        ;
        ; Raise error related to adding symbols to tables
        ;
symb_tables_full_error:
        MVI         A,SYMBTAB_ERR
error_adding_symbol:
        STA         current_error_nr
        STC
        RET


;//////////////////////////////////////

        ;
        ; Add symbol to the table of undefined symbols
        ;
add_undefined_symbol:
        ;
        ; Check if either interactive mode or if file SI is on its second pass
        ;
        LDA         assembler_pass_state
        ORA         A
        RZ
        ;
        ; If not interactive mode, ready undefined symbol error right away
        ;
        LDA         interactive_mode_flag
        CMA
        ANI         US_EXPR_ERR
        STA         current_error_nr
        ;
        ; Verify that there is space for another symbol
        ;
        CALL        is_more_space_in_symb_tables
        JC          symb_tables_full_error
        ;
        ; Get negative length of symbols table entry
        ;
        LDA         current_name_len
        MOV         E,A
        ADI         2
        CMA
        INR         A
        MOV         C,A
        MVI         B,0FFh
        ;
        ; Make space for new entry at the start of the undefined symbols table
        ;
        LHLD        undefined_symbols_start_ptr
        DAD         B
        SHLD        undefined_symbols_start_ptr
        ;
        ; Copy symbol name onto the newly reserved entry
        ;
        MOV         C,E
        XCHG
        LXI         H,current_name_buffer
        LDA         undef_symb_size_flag
        ORA         M
set_undef_symb_name_loop:
        STAX        D
        INX         D
        INX         H
        DCR         C
        JZ          undef_symb_name_set
        MOV         A,M
        JMP         set_undef_symb_name_loop

undef_symb_name_set:
        ;
        ; Set address of undefined symbol entry
        ;
        LHLD        instr_data_next_addr_ptr
        XCHG
        MOV         M,E
        INX         H
        MOV         M,D
        RET


;//////////////////////////////////////

        ;
        ; Check if there's space for one more entry in either of the tables
        ;
is_more_space_in_symb_tables:
        ;
        ; Get offset to next entry
        ;
        LDA         current_name_len
        ADI         3
        ;
        ; Check if defined symbols ends after start of undefined symbols
        ;
        LHLD        defined_symbols_end_ptr
        XCHG
        LHLD        undefined_symbols_start_ptr
        MOV         A,H
        CMP         D
        JZ          check_symb_table_addr_2nd_half
        RET

check_symb_table_addr_2nd_half:
        MOV         A,L
        CMP         E
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Remove symbol from undefined symbols and insert the now known value
        ;
replace_undef_with_value:
        ;
        ; Check if interactive mode
        ;
        LDA         interactive_mode_flag
        ORA         A
        RZ
        ;
        ; Find the next instance of the undefined name being used
        ;
        LHLD        undefined_symbols_start_ptr
        MOV         B,H
        MOV         C,L
        CALL        scan_for_name_word_data
        RC
        ;
        ; Fill in missing value in assembled program
        ;
backfill_symb_value:
        ;
        ; Get address of symbol usage instance
        ;
        LDAX        B
        MOV         E,A
        INX         B
        LDAX        B
        MOV         D,A
        ;
        ; Get negative length of symbol name
        ;
        LDA         current_name_len
        CMA
        INR         A
        MOV         L,A
        MVI         H,0FFH
        ;
        ; Point back at first character of undefined symbol entry
        ;
        DCX         H
        DAD         B
        ;
        ; Check byte/word flag in first character
        ;
        PUSH        H
        MOV         A,M
        ANI         SYM_SF_WORD
        ;
        ; Add the new symbol's value to where it was missing in the program
        ;
        LHLD        expression_value
        XCHG
        MOV         A,E
        JZ          backfill_symb_value_last_byte
        PUSH        D
        CALL        add_byte_to_assembled_binary
        POP         D
        MOV         A,D
backfill_symb_value_last_byte:
        CALL        add_byte_to_assembled_binary
        POP         H
        ;
        ; Null out instance of symbol in undefined symbols
        ;
        LDA         current_name_len
        MOV         B,A
        ADI         2
        MVI         C,NULL
clear_symb_entry_loop:
        MOV         M,C
        INX         H
        DCR         B
        JNZ         clear_symb_entry_loop
        ;
        ; Store length instead of address after nulled entry
        ;
        MOV         M,A
        INX         H
        MOV         M,C
        INX         H
        ;
        ; Keep scanning for more instances of symbol
        ;
        MOV         B,H
        MOV         C,L
        CALL        scan_for_name_word_data
        JNC         backfill_symb_value


;//////////////////////////////////////

        ;
        ; Remove nulled entries from undefined symbols table
        ; Point to bounds of table
        ;
        LHLD        undefined_symbols_start_ptr
        MOV         B,H
        MOV         C,L
        LHLD        undefined_symbols_end_ptr
        DCX         H
        MOV         D,H
        MOV         E,L
        ;
        ; Prepare to relocate next byte of undefined symbols table
        ;
move_next_undef_table_char:
        ;
        ; Check if at end of table yet
        ;
        MOV         A,D
        CMP         B
        JC          replace_undef_done
        JNZ         check_undef_table_char
        MOV         A,E
        CMP         C
        JC          replace_undef_done
check_undef_table_char:
        ;
        ; Check if potentially at start of a nulled out entry
        ;
        LDAX        D
        ORA         A
        JNZ         move_undef_table_char
        ;
        ; Check previous character for length of nulled entry
        ;
        PUSH        D
        DCX         D
        LDAX        D
        ORA         A
        JZ          move_undef_table_char_alt_1
        ;
        ; Check the char before that again for content
        ;
        PUSH        PSW
        DCX         D
        LDAX        D
        ORA         A
        JNZ         move_undef_table_char_alt_2
        POP         PSW
        POP         D
        ;
        ; Skip nulled out entry
        ;
skip_undef_table_char_loop:
        DCX         D
        DCR         A
        JNZ         skip_undef_table_char_loop
        JMP         move_next_undef_table_char

        ;
        ; Relocate the still active byte of the undefined symbols table
        ;
move_undef_table_char_alt_2:
        POP         PSW
move_undef_table_char_alt_1:
        POP         D
move_undef_table_char:
        LDAX        D
        MOV         M,A
        ;
        ; Advance to the next byte of the table
        ;
        DCX         H
        DCX         D
        JMP         move_next_undef_table_char


;//////////////////////////////////////

        ;
        ; Garbage-collection of undefined symbol table is complete, update size
        ;
replace_undef_done:
        INX         H
        SHLD        undefined_symbols_start_ptr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Scan for name in a table where there is no data between names
        ;
scan_for_name_no_data:
        MVI         E,1
        JMP         scan_for_name


;//////////////////////////////////////

        ;
        ; Scan for name in a table where each name is followed by a byte value
        ;
scan_for_name_byte_data:
        MVI         E,2
        JMP         scan_for_name


;//////////////////////////////////////

        ;
        ; Scan for name in a table where each name is followed by a word value
        ;
scan_for_name_word_data:
        MVI         E,3


;//////////////////////////////////////

        ;
        ; Scan for name in a table, with L bytes overhead per entry
        ;
scan_for_name:
        MVI         D,000H
        MOV         L,D
scan_compare_next_name:
        ;
        ; Check if next name may be a potential match
        ;
        PUSH        H
        LXI         H,current_name_buffer
        LDAX        B
        CMP         D
        JZ          scan_name_not_found
        PUSH        D
        ;
        ; Compare the rest of the name
        ;
        MOV         D,A
        LDA         current_name_len
        MOV         E,A
        MOV         A,D
scan_compare_next_char:
        ANI         SYM_CH_MASK + SYM_CF_LAST
        CMP         M
        JNZ         scan_skip_name_loop
        INX         B
        INX         H
        DCR         E
        JZ          scan_done
        LDAX        B
        JMP         scan_compare_next_char

        ;
        ; Skip the rest of the name, since it was not a match after all
        ;
scan_skip_name_loop:
        ANA         A
        JM          scan_name_no_match
        INX         B
        LDAX        B
        JMP         scan_skip_name_loop

        ;
        ; Skip the metadata too, not only the length of the name itself
        ;
scan_name_no_match:
        POP         D
        MOV         H,B
        MOV         L,C
        DAD         D
        MOV         B,H
        MOV         C,L
        POP         H
        INX         H
        JMP         scan_compare_next_name


;//////////////////////////////////////

        ;
        ; No match in the table, set Carry
        ;
scan_name_not_found:
        STC
        POP         H
        RET


;//////////////////////////////////////

        ;
        ; Name found in table, clear Carry
        ;
scan_done:
        POP         D
        ANA         A
        POP         H
        INX         H
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assembler core, expressions
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse an expression into a particular value
        ;
parse_expression:
        CALL        get_next_input_char
parse_expression_direct:
        ;
        ; Initialize parsed value
        ;
        PUSH        PSW
        LXI         H,0
        SHLD        expression_value
        XRA         A
        STA         negative_expr_part_flag
        POP         PSW
        ;
        ; Check that there is an expression at all
        ;
        CALL        is_instr_separator
        JNZ         parse_nexr_expr_char
        MVI         A,NO_OPER_ERR
        JMP         raise_expression_error

parse_nexr_expr_char:
        ;
        ; Check if this is an arithmetic operation between two parts
        ;
        CPI         '-'
        JZ          expr_has_sign
        CPI         '+'
        JNZ         expr_sign_flag_ready
        XRA         A
expr_has_sign:
        STA         negative_expr_part_flag
        CALL        get_input_char
expr_sign_flag_ready:
        ;
        ; Determine type of expression part
        ;
        CALL        is_alphabetic
        JNC         expr_symbol_part
        CALL        is_numeric
        JNC         expr_numeric_part
        CPI         APOSTROPHE
        JZ          expr_char_part
        ;
        ; Otherwise raise expression syntax error
        ;
expression_syntax_error:
        MVI         A,EXPR_S_ERR
raise_expression_error:
        STA         current_error_nr
void_expression:
        STC
        LXI         H,0
        SHLD        expression_value
        RET


;//////////////////////////////////////

        ;
        ; Parse expression part as a symbol
        ;
expr_symbol_part:
        ;
        ; Get name of symbol and look up in database of defined symbols
        ;
        CALL        get_next_name
        JC          expression_syntax_error
        LHLD        defined_symbols_start_ptr
        MOV         B,H
        MOV         C,L
        CALL        scan_for_name_word_data
        JNC         expression_symb_found
        ;
        ; Check if this expression is part of immediate data
        ;
        LDA         immediate_datatype_len_plus_one
        ORA         A
        JZ          void_expression
        ;
        ; If so, add symbol-usage instance to undefined symbols table
        ;
        LXI         H,undef_symb_size_flag
        MVI         M,SYM_SF_BYTE
        CPI         2
        JZ          expr_undef_symb_size_ready
        MVI         M,SYM_SF_WORD
expr_undef_symb_size_ready:
        CALL        add_undefined_symbol
        ;
        ; Check if the undefined symbol is alone or part of a longer expression
        ;
        LHLD        expression_value
        MOV         A,H
        ORA         L
        JNZ         undef_symbol_error
        LDA         current_char
        CALL        is_instr_separator
        JZ          expression_part_done
        ;
        ; If part of a longer expression, raise undefined expression error
        ;
undef_symbol_error:
        MVI         A,US_EXPR_ERR
        JMP         raise_expression_error

        ;
        ; Get expression part value from looked-up symbol entry
        ;
expression_symb_found:
        LDAX        B
        INX         B
        MOV         E,A
        LDAX        B
        MOV         D,A
        JMP         add_expression_part


;//////////////////////////////////////

        ;
        ; Parse expression part as a number
        ;
expr_numeric_part:
        CALL        parse_number
        JC          expression_syntax_error
        JMP         add_expression_part


;//////////////////////////////////////

        ;
        ; Parse expression part as a character
        ;
expr_char_part:
        ;
        ; Scan for ending apostrophe of character definition
        ;
scan_for_char_def_end_loop:
        STA         expression_char_value
        CALL        get_input_char
        CPI         APOSTROPHE
        JZ          expr_char_value_ready
        ;
        ; If unexpected end of string, raise end of string error
        ;
        CPI         CR
        JNZ         scan_for_char_def_end_loop
        MVI         A,EOS_ERR
        JMP         raise_expression_error

        ;
        ; Use char value as expression part value
        ;
expr_char_value_ready:
        CALL        get_input_char
        STA         current_char
        LDA         expression_char_value
        MVI         D,000H
        MOV         E,A


;//////////////////////////////////////

        ;
        ; Add expression part value to overall expression value
        ;
add_expression_part:
        ;
        ; Negate part if it had a negative sign
        ;
        LDA         negative_expr_part_flag
        ORA         A
        JZ          expression_part_ready
        MOV         A,E
        CMA
        MOV         E,A
        MOV         A,D
        CMA
        MOV         D,A
        INX         D
expression_part_ready:
        ;
        ; Add part to overall value
        ;
        LHLD        expression_value
        DAD         D
        SHLD        expression_value
expression_part_done:
        ;
        ; Check if more parts or end of instruction, else raise error
        ;
        LDA         current_char
        CALL        is_arithmetic
        JZ          parse_nexr_expr_char
        CALL        is_instr_separator
        MVI         A,IT_EXPR_ERR
        JNZ         raise_expression_error
        ORA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse a number, as it appears in an expression
        ;
parse_number:
        ;
        ; Save first digit of number to string buffer
        ;
        LXI         H,current_numeric_str
        MOV         M,A
        INX         H
        ;
        ; Set up to save up to 6 additional digits to the string buffer too
        ;
        MVI         C,7
get_next_number_char:
        PUSH        H
        PUSH        B
        CALL        get_input_char
        ;
        ; Check for number end, and in the case number type
        ;
        CALL        is_instr_separator
        JZ          decimal_number_ready
        CALL        is_arithmetic
        JZ          decimal_number_ready
        CPI         'H'
        JZ          hexadecimal_number_ready
        CPI         'O'
        JZ          octadecimal_number_ready
        CPI         'Q'
        JZ          octadecimal_number_ready
        ;
        ; Still inside number, so advance to next character
        ;
        POP         B
        POP         H
        MOV         M,A
        INX         H
        DCR         C
        JNZ         get_next_number_char
        ;
        ; If number is more than 8 digits, set Carry and abort parsing
        ;
        STC
        RET


;//////////////////////////////////////

        ;
        ; Expression part is a decimal number
        ;
decimal_number_ready:
        STA         current_char
        POP         B
        POP         H
        ;
        ; Set end of number in string buffer
        ;
        MVI         M,' '
        JMP         parse_decimal_number


;//////////////////////////////////////

hexadecimal_number_ready:
        POP         B
        POP         H
        ;
        ; Set end of number in string buffer, and get char after number type
        ;
        MVI         M,' '
        CALL        get_input_char
        STA         current_char
        JMP         parse_hexadecimal_number


;//////////////////////////////////////

octadecimal_number_ready:
        POP         B
        POP         H
        MVI         M,' '
        CALL        get_input_char
        STA         current_char
        JMP         parse_octadecimal_number


;//////////////////////////////////////

        ;
        ; Parse hexadecimal expression part from string buffer
        ;
parse_hexadecimal_number:
        LXI         H,current_numeric_str
        LXI         D,0
parse_next_hexadecimal_digit:
        ;
        ; Check for end of number
        ;
        MOV         A,M
        CPI         ' '
        RZ
        ;
        ; Convert digit from hex to binary
        ;
        MVI         C,16
        CALL        ascii_to_hex
        RC
        ;
        ; Add digit to current number * 16
        ;
        XCHG
        MOV         A,B
        DAD         H
        DAD         H
        DAD         H
        DAD         H
        ADD         L
        MOV         L,A
        XCHG
        ;
        ; Advance to the next digit
        ;
        INX         H
        JMP         parse_next_hexadecimal_digit


;//////////////////////////////////////

        ;
        ; Parse octadecimal expression part from string buffer
        ;
parse_octadecimal_number:
        LXI         H,current_numeric_str
        LXI         D,0
parse_next_octadecimal_digit:
        ;
        ; Check for end of number
        ;
        MOV         A,M
        CPI         ' '
        RZ
        ;
        ; Convert digit from octal to binary
        ;
        MVI         C,8
        CALL        ascii_to_hex
        RC
        ;
        ; Add digit to current number * 8
        ;
        XCHG
        MOV         A,B
        DAD         H
        DAD         H
        DAD         H
        ADD         L
        MOV         L,A
        XCHG
        ;
        ; Advance to the next digit
        ;
        INX         H
        JMP         parse_next_octadecimal_digit


;//////////////////////////////////////

        ;
        ; Parse decimal expression part from string buffer
        ;
parse_decimal_number:
        LXI         H,current_numeric_str
        LXI         D,0
parse_next_decimal_digit:
        ;
        ; Check for end of number
        ;
        MOV         A,M
        CPI         ' '
        RZ
        ;
        ; Convert digit from decimal to binary
        ;
        MVI         C,10
        CALL        ascii_to_hex
        RC
        ;
        ; Add digit to current number * 10
        ;
        XCHG
        MOV         A,B
        PUSH        H
        DAD         H
        DAD         H
        DAD         H
        POP         B
        DAD         B
        DAD         B
        MVI         B,000H
        MOV         C,A
        DAD         B
        XCHG
        ;
        ; Advance to the next digit
        ;
        INX         H
        JMP         parse_next_decimal_digit


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assembler core, subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII value in A to binary in B, with a maximum limit of C
        ;
ascii_to_hex:
        PUSH        H
        LXI         H,bin_to_hex_char_table
        MVI         B,0
ascii_to_hex_loop:
        ;
        ; Compare next character in look-up table
        ;
        CMP         M
        JZ          ascii_to_hex_done
        INX         H
        INR         B
        ;
        ; Check if the proposed value has passed maximum limit
        ;
        DCR         C
        JNZ         ascii_to_hex_loop
        STC
ascii_to_hex_done:
        POP         H
        RET


;//////////////////////////////////////

bin_to_hex_char_table:
        DB          '0123456789ABCDEF'


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Returns Zero if character is alphabetic
        ;
is_alphabetic:
        CPI         'A'
        RC
        CPI         'Z'+1
        CMC
        RET


;//////////////////////////////////////

        ;
        ; Returns Zero if character is numerical
        ;
is_numeric:
        CPI         '0'
        RC
        CPI         '9'+1
        CMC
        RET


;//////////////////////////////////////

        ;
        ; Returns Zero if character is a separating character
        ;
is_instr_separator:
        ;
        ; Check for any of the valid linguistic separators
        ;
        CPI         ','
        RZ
        CPI         ':'
        RZ
        CPI         HTAB
        RZ
        CPI         CR
        RZ
        CPI         SEMICOLON
        RZ
        ;
        ; If space, tabulate output string
        ;
        CPI         ' '
        RNZ
        PUSH        PSW
        LDA         interactive_mode_flag
        ORA         A
        CNZ         tabulate_output_string
        POP         PSW
        RET


;//////////////////////////////////////

        ;
        ; Returns Zero if character is an arithmetic operator
        ;
is_arithmetic:
        CPI         '+'
        RZ
        CPI         '-'
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get next non-whitespace character
        ;
get_next_input_char:
        CALL        get_input_char
        ;
        ; Make sure space moves the cursor in interactive mode
        ;
        CPI         ' '
        JNZ         check_for_whitespace
        CALL        move_interactive_cursor_to_position
        XRA         A
check_for_whitespace:
        ;
        ; Check for and skip whitespaces
        ;
        CPI         HTAB
        JZ          get_next_input_char
        CPI         NULL
        JZ          get_next_input_char
        CPI         LF
        JZ          get_next_input_char
        CPI         DEL
        JZ          get_next_input_char
        ;
        ; Save character and console cursor position
        ;
        STA         current_char
        PUSH        PSW
        LDA         list_output_line_cursor_pos
        STA         console_line_cursor_pos
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Terminal emulator for code listing
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Skip the remaining input of line
        ;
flush_input_line:
        LDA         current_char
flush_input:
        CPI         CR
        RZ
        CALL        get_input_char
        JMP         flush_input


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Move cursor to character nr C on console, only if interactive mode
        ;
move_interactive_cursor_to_position:
        ;
        ; Skip if not interactive mode
        ;
        LDA         interactive_mode_flag
        ORA         A
        RZ
        ;
        ; Calculate number of chars to move cursor rightwards
        ;
        LDA         list_output_line_cursor_pos
        SUB         C
        JM          move_cursor_right
        ;
        ; Otherwise wrap around to start of line...
        ;
        RZ
        PUSH        H
        LXI         H,retry_tab_from_start
        PUSH        H
        MVI         A,CR
        JMP         conditional_char_to_output_str

        ;
        ; ...and retry tab from there
        ;
retry_tab_from_start:
        ;
        ; Setup variables for cursor at start of line
        ;
        POP         H
        XRA         A
        STA         list_output_line_cursor_pos
move_to_position_if_possible:
        ;
        ; Calculate number of chars to move cursor rightwards
        ;
        LDA         list_output_line_cursor_pos
        SUB         C
        RP
move_cursor_right:
        ;
        ; Move cursor to the right untill target position reached
        ;
        MOV         C,A
        MVI         A,CURR
move_to_position_loop:
        CALL        add_char_to_output
        INR         C
        JM          move_to_position_loop
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Tabulate output cursor position
        ;
tabulate_output_string:
        PUSH        PSW
        PUSH        B
        ;
        ; Identify the next tabulation stop
        ;
        LDA         list_output_line_cursor_pos
        MVI         C,24
        CMP         C
        JM          next_tab_stop_found
        MVI         C,32
        CMP         C
        JM          next_tab_stop_found
        MVI         C,40
        CMP         C
next_tab_stop_found:
        ;
        ; Tabulate if a stop was found
        ;
        CM          move_to_position_if_possible
        POP         B
        POP         PSW
        RET


;//////////////////////////////////////

        ;
        ; Get input from console and prepare
        ;
get_console_input_char:
        CALL        TTI


;//////////////////////////////////////

        ;
        ; Prepare input character for processing and echo to various outputs
        ;
prepare_input_char:
        ;
        ; Make input char uppercase
        ;
        ANI         07FH
        CPI         'a'
        JM          input_casefold_done
        CPI         'z'+3+1
        JP          input_casefold_done
        ANI         05FH
input_casefold_done:
        ;
        ; Replace cursor-right with tabs
        ;
        CPI         CURR
        JNZ         input_cursor_right_check_done
        MVI         A,HTAB
input_cursor_right_check_done:
        ;
        ; Echo input to source-code output string buffer
        ;
        PUSH        H
        LHLD        src_output_str_buffer_cursor
        MOV         M,A
        INX         H
        SHLD        src_output_str_buffer_cursor
        POP         H
        ;
        ; Echo input to console
        ;
        CPI         HTAB
        JZ          tabulate_output_string


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Send char to emulated output terminal and advance cursor.
        ; In the case of interactive mode, also send a copy to console.
        ;
add_char_to_output:
        ;
        ; Set flag to ensure char is added to output string
        ;
        STC
conditional_char_to_output_str:
        ;
        ; If entry from here, only the console copy will print if no carry flag
        ;
        PUSH        PSW
        ;
        ; Always print copy to console on output if interactive mode
        ;
        PUSH        H
        PUSH        PSW
        LDA         interactive_mode_flag
        ORA         A
        JZ          skip_console_copy
        POP         PSW
        LHLD        CO_FCB
        CALL        OUTCHAR
        JNC         console_copy_done
        ;
        ; Handle error if fault during console copy print
        ;
        POP         H
        POP         H
        MOV         B,A
        MVI         C,TOS_ERR
        JMP         raise_error

skip_console_copy:
        POP         PSW
console_copy_done:
        POP         H
        ;
        ; Check for special control characters
        ;
        CPI         CURR
        JZ          advance_output_terminal_cursor_alt
        CPI         CR
        JNZ         print_char_normal
        ;
        ; Move cursor back to start of current line on cartridge-return
        ;
        MVI         A,1
        STA         list_output_line_cursor_pos
print_char_done:
        POP         PSW
        RET

print_char_normal:
        ;
        ; Ignore other ASCII control characters
        ;
        CPI         ' '
        JM          print_char_done
        ;
        ; Move terminal cursor
        ;
        CALL        advance_output_terminal_cursor
        POP         PSW
        RNC
        ;
        ; Add character to output string buffer
        ;
        PUSH        H
        PUSH        D
        PUSH        PSW
        LDA         list_output_line_cursor_pos
        DCR         A
        MOV         E,A
        MVI         D,000H
        LXI         H,list_output_str_buffer
        DAD         D
        POP         PSW
        MOV         M,A
        POP         D
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy source code from output listing line
        ;
copy_src_from_code_listing:
        ;
        ; Set up pointers and set active-code flag
        ;
        LXI         D,list_output_str_buffer + 1 + 15
        LXI         H,src_output_str_buffer
        LXI         B,TRUE
copy_next_src_char:
        ;
        ; Copy next character and advance cursor
        ;
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        ;
        ; Check for end of line
        ;
        CPI         CR
        RZ
        ;
        ; Clear active-code flag if start of comment found
        ;
        MOV         C,A
        CPI         SEMICOLON
        JNZ         copy_next_src_char
        MVI         B,FALSE
        JMP         copy_next_src_char


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Advance cursor position of output string if possible
        ;
advance_output_terminal_cursor:
        PUSH        PSW
advance_output_terminal_cursor_alt:
        ;
        ; Don't advance cursor if at end of line buffer
        ;
        LDA         list_output_line_cursor_pos
        CPI         80
        JP          advance_output_terminal_cursor_done
        ;
        ; Otherwise advance cursor
        ;
        INR         A
        STA         list_output_line_cursor_pos
        STA         last_used_list_output_cursor_pos
advance_output_terminal_cursor_done:
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print cartridge return to emulated terminal
        ;
print_cr:
        PUSH        PSW
        MVI         A,CR
        JMP         line_end_last_char


;//////////////////////////////////////

        ;
        ; Print newline to emulated terminal
        ;
print_newline:
        PUSH        PSW
        MVI         A,CR
        CALL        add_char_to_output
        MVI         A,LF
line_end_last_char:
        CALL        add_char_to_output
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get next input character and prepare it for processing
        ;
get_input_char:
        ;
        ; Get input from console if interactive mode
        ;
        LDA         interactive_mode_flag
        ORA         A
        JNZ         get_console_input_char
        ;
        ; Otherwise get input from SI
        ;
        PUSH        H
        LHLD        SI_FCB
        CALL        INCHAR
        POP         H
        JNC         prepare_input_char
        ;
        ; Handle eventual errors, in particular look for unexpected end of file
        ;
        JNZ         si_read_error
        LXI         B,EOF_ERR
        CALL        raise_error
        JMP         source_file_end

si_read_error:
        MOV         B,A
        MVI         C,TOS_ERR
        JMP         raise_error


;//////////////////////////////////////////////////////////////////////////////
;//
;//     String functions
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string ref BC to device ref HL, with error-checking
        ;
print_string:
        ;
        ; Point to start of string data
        ;
        PUSH        D
        MOV         D,B
        MOV         E,C
        INX         D
        ;
        ; get string length and point to end of string
        ;
        LDAX        B
        ADD         C
        MOV         C,A
        JNC         string_end_found
        INR         B
string_end_found:
        ;
        ; Check if fully terminated ASCII string
        ;
        LDAX        B
        CPI         LF
        JZ          print_ascii_string
        ;
        ; Print as TOS string (CR-terminated only) if not
        ;
        INX         B
        MVI         A,CR
        STAX        B
        CALL        PUTSTR
        JMP         string_printed

print_ascii_string:
        ;
        ; Print as ASCII string
        ;
        CALL        PUT
string_printed:
        POP         D
        ;
        ; Check if any error happened, make sure to break out of program if so
        ;
        RNC
        MVI         B,TRUE
        ;
        ; Use dedicated device busy error instead of raising a TOS error
        ;
        CPI         ERROR_08
        MVI         C,DEV_BSY_ERR
        JZ          raise_error
        ;
        ; Use SL-not-set error if TOS non-output file error
        ;
        CPI         ERROR_18
        MVI         C,ILL_SL_ERR
        JZ          raise_error
        ;
        ; Otherwise, report as general TOS error
        ;
        MVI         C,TOS_ERR
        JMP         raise_error


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert byte at D to hexadecimal string at BC
        ;
byte_to_hex:
        LDAX        D
        MOV         D,A
        JMP         convert_byte_to_hex


;//////////////////////////////////////

        ;
        ; Convert word at DE to hexadecimal string at BC
        ;
word_to_hex:
        LDAX        D
        MOV         L,A
        INX         D
        LDAX        D
        MOV         H,A
        XCHG
        CALL        convert_byte_to_hex
        MOV         D,E


;//////////////////////////////////////

        ;
        ; Convert byte in D to hexadecimal string at BC
        ;
convert_byte_to_hex:
        MOV         A,D
        RLC
        RLC
        RLC
        RLC
        CALL        convert_to_hex_char
        MOV         A,D


;//////////////////////////////////////

        ;
        ; Convert a single nibble in A to ASCII hexadecimal at BC
        ;
convert_to_hex_char:
        ;
        ; Mask and convert nibble by means of a lookup-table
        ;
        ANI         00FH
        PUSH        B
        LXI         H,bin_to_hex_char_table
        MVI         B,000H
        MOV         C,A
        DAD         B
        MOV         A,M
        POP         B
        ;
        ; Store in target string buffer and advance pointer
        ;
        STAX        B
        INX         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print an empty line with only binary data added
        ;
print_data_only_listing_line:
        ;
        ; Prepare string with max output linelength of console
        ;
        LXI         B,list_output_str_buffer
        MVI         A,79
        STAX        B
        INX         B
        ;
        ; Clear output string buffer
        ;
        MVI         E,79
        MVI         A,' '
clear_output_str_loop:
        STAX        B
        INX         B
        DCR         E
        JNZ         clear_output_str_loop


;//////////////////////////////////////

        ;
        ; Add code-listing binary data and print line
        ;
finalize_listing_line_and_print:
        PUSH        H
        LDA         listing_bindata_bitmap
        RRC
        PUSH        PSW
        CC          report_listing_bindata_byte_3
        POP         PSW
        RRC
        PUSH        PSW
        CC          report_listing_bindata_byte_2
        POP         PSW
        RRC
        PUSH        PSW
        CC          report_listing_bindata_byte_1
        POP         PSW
        RRC
        PUSH        PSW
        CC          report_listing_bindata_addr
        POP         PSW
        RRC
        CC          report_listing_bindata_byte_4
        POP         H
        LXI         B,list_output_str_buffer
        CALL        print_string
        JMP         print_cr


;//////////////////////////////////////

        ;
        ; Add address to listing string
        ;
report_listing_bindata_addr:
        LXI         B,list_output_str_buffer + 2
        LXI         D,listing_bindata_addr
        JMP         word_to_hex


;//////////////////////////////////////

        ;
        ; Add listing bindata byte 1 to listing string
        ;
report_listing_bindata_byte_1:
        LXI         B,list_output_str_buffer + 7
        LXI         D,listing_line_bindata
        JMP         byte_to_hex


;//////////////////////////////////////

        ;
        ; Add listing bindata byte 2 to listing string
        ;
report_listing_bindata_byte_2:
        LXI         B,list_output_str_buffer + 9
        LXI         D,listing_line_bindata + 1
        JMP         byte_to_hex


;//////////////////////////////////////

        ;
        ; Add listing bindata byte 3 to listing string
        ;
report_listing_bindata_byte_3:
        LXI         B,list_output_str_buffer + 11
        LXI         D,listing_line_bindata + 2
        JMP         byte_to_hex


;//////////////////////////////////////

        ;
        ; Add listing bindata byte 4 to listing string
        ;
report_listing_bindata_byte_4:
        LXI         B,list_output_str_buffer + 13
        LXI         D,listing_line_bindata + 3
        JMP         byte_to_hex


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Misc functions
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print listing line, with a new listing binary data size
        ;
print_listing_line_new_datasize:
        STA         listing_bindata_bitmap


;//////////////////////////////////////

        ;
        ; Print listing line without returning cursor
        ;
print_listing_line:
        ;
        ; Skip if not interactive mode
        ;
        LDA         interactive_mode_flag
        ORA         A
        RZ
        ;
        ; Save current character number of line
        ;
        PUSH        H
        LDA         list_output_line_cursor_pos
        PUSH        PSW
        ;
        ; Start a new line on console output
        ;
        LHLD        CO_FCB
        CALL        print_cr
        CALL        finalize_listing_line_and_print
        ;
        ; Goto previous location in new line
        ;
        POP         PSW
        MOV         C,A
        POP         H
        JMP         move_interactive_cursor_to_position


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Raise error number C with flag for fatal-error (or TOS error nr) in B
        ;
raise_error:
        PUSH        H
        PUSH        D
        PUSH        B
        ;
        ; Record error number
        ;
        MOV         A,C
        STA         current_error_nr
        LXI         B,error_str+7
        LXI         D,current_error_nr
        CALL        byte_to_hex
        ;
        ; Record assembler address at which error happened
        ;
        LXI         B,error_str+14
        LXI         D,current_address_ptr
        CALL        word_to_hex
        ;
        ; Print ASM error to error-listing device
        ;
        LHLD        AL_FCB
        CALL        print_newline
        LXI         B,error_str
        CALL        print_string
        ;
        ; Check if TOS error
        ;
        POP         B
        MOV         A,C
        CPI         TOS_ERR
        MOV         A,B
        JNZ         error_done
        ;
        ; If so, record TOS error number
        ;
        STA         current_tos_error_nr
        LXI         B,tos_error_str + 14
        LXI         D,current_tos_error_nr
        CALL        byte_to_hex
        ;
        ; Print TOS error to error-listing device
        ;
        LHLD        AL_FCB
        CALL        print_newline
        LXI         B,tos_error_str
        CALL        print_string
        LDA         current_tos_error_nr
error_done:
        ;
        ; Increase overall error-count
        ;
        LXI         H,error_counter
        INR         M
        POP         D
        POP         H
        ;
        ; Break out of program if TOS-error number is set
        ;
        ORA         A
        JNZ         exit_to_tos
        RET


;//////////////////////////////////////

error_str:
        DB          19
        DB          'ERROR 00  LC=0000',CR,LF
tos_error_str:
        DB          17
        DB          'TOS ERROR NO 00',CR,LF


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Move L bytes from DE to BC, starting at the end
        ;
copy_buffer:
        ;
        ; Calculate end of block to move
        ;
        MOV         A,L
        MVI         H,000H
        PUSH        H
        DAD         B
        XTHL
        POP         B
        DAD         D
        XCHG
        MOV         L,A
        ;
        ; Copy the data-block
        ;
copy_next_byte:
        DCX         B
        DCX         D
        LDAX        D
        STAX        B
        DCR         L
        JNZ         copy_next_byte
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Command interpreter
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parses and executes one particular command
        ;
parse_input_command:
        ;
        ; Get next command
        ;
        CALL        get_input_char
        ;
        ; X for Exit ASM
        ;
        CPI         'X'
        JNZ         check_other_commands
exit_to_tos:
        ;
        ; Print newline and exit to TOS
        ;
        LHLD        CO_FCB
        CALL        print_newline
        LHLD        stack_backup
        SPHL
        RET

check_other_commands:
        ;
        ; G for Go execute program
        ;
        CPI         'G'
        JZ          go_run_program
        ;
        ; K for Kill symbol sequence
        ;
        CPI         'K'
        JZ          kill_symbol_sequence
        CALL        print_newline
        ;
        ; I for Initialize assembler
        ;
        CPI         'I'
        JZ          initialize_assembler
        ;
        ; M for Monitor
        ;
        CPI         'M'
        JNZ         check_output_commands
        RST         RST0
        RET

check_output_commands:
        LHLD        CO_FCB
        ;
        ; S for Symbols listing
        ;
        CPI         'S'
        JZ          list_defined_symbols
        ;
        ; U for Undefined symbols listing
        ;
        CPI         'U'
        JZ          list_undefined_symbols
command_error:
        LXI         B,ILL_CMD_ERR
        JMP         raise_error


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Run assembled program
        ;
go_run_program:
        ;
        ; Get entry address from expression and jump to it
        ;
        CALL        parse_expression
        JC          command_error
        LHLD        expression_value
        PCHL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Remove defined symbol along with all symbols defined after it
        ;
kill_symbol_sequence:
        ;
        ; Get name from command
        ;
        CALL        get_next_input_char
        CALL        is_alphabetic
        JC          command_error
        CALL        get_next_name
        JC          command_error
        ;
        ; Find name in defined symbols
        ;
        LHLD        defined_symbols_start_ptr
        MOV         B,H
        MOV         C,L
        CALL        scan_for_name_word_data
        JC          command_error
        ;
        ; Point to start of symbol-entry by adding negative length of name
        ;
        LDA         current_name_len
        CMA
        INR         A
        MOV         L,A
        MVI         H,0FFH
        DAD         B
        ;
        ; Set end of symbols table at symbol-entry
        ;
        MVI         M,000H
        SHLD        defined_symbols_end_ptr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Dummy output-routine for null-file
        ;
null_output_routine:
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Reset symbol table buffer and listing-related variables
        ;
initialize_assembler:
        LHLD        CO_FCB
        CALL        print_newline
retry_initialize_command:
        ;
        ; Print symbol table address string
        ;
        LXI         B,symbols_table_str
        LHLD        CO_FCB
        CALL        print_string
        ;
        ; Construct and print symbol table bounds string
        ;
        LXI         B,list_output_str_buffer
        MVI         A,14
        STAX        B
        INX         B
        LXI         D,symbol_buffers_first_byte_ptr
        CALL        word_to_hex
        MVI         A,'H'
        STAX        B
        INX         B
        MVI         A,'-'
        STAX        B
        INX         B
        LXI         D,symbol_buffers_last_byte_ptr
        CALL        word_to_hex
        MVI         A,'H'
        STAX        B
        INX         B
        MVI         A,' '
        STAX        B
        INX         B
        MVI         A,':'
        STAX        B
        INX         B
        MVI         A,' '
        STAX        B
        LXI         B,list_output_str_buffer
        LHLD        CO_FCB
        CALL        print_string
        ;
        ; Check for and handle symbols data-buffer start address expression
        ;
        CALL        get_next_input_char
        CPI         CR
        JZ          setup_buffers
        CALL        parse_expression_direct
        JC          retry_initialize_command
        LHLD        expression_value
        SHLD        symbol_buffers_first_byte_ptr
        ;
        ; Check for and handle symbols data-buffer end address expression
        ;
        LDA         current_char
        CPI         CR
        JZ          setup_buffers
        CALL        parse_expression
        JC          retry_initialize_command
        LHLD        expression_value
        SHLD        symbol_buffers_last_byte_ptr
        ;
        ; Reset variables and set new boundaries of symbol table area
        ;
setup_buffers:
        XRA         A
        STA         hexfile_str_len
        STA         error_counter
        LHLD        symbol_buffers_first_byte_ptr
        SHLD        defined_symbols_end_ptr
        MOV         M,A
        LHLD        symbol_buffers_last_byte_ptr
        SHLD        undefined_symbols_start_ptr
        MOV         M,A
        LXI         H,0
        SHLD        current_address_ptr
        RET


;//////////////////////////////////////

symbols_table_str:
        DB          20
        DB          'SYMBOL TABLE AREA : '


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; List the entire table of udefined symbols
        ;
list_undefined_symbols:
        PUSH        H
        LHLD        undefined_symbols_start_ptr
        ;
        ; Check if at end of table
        ;
        MOV         A,M
        ANI         SYM_CH_MASK + SYM_CF_LAST
        JZ          end_of_symbol_table_check
        ;
        ; Set header string to undefined symbols
        ;
        LXI         B,undefined_symbols_str
        JMP         list_symbols


;//////////////////////////////////////

        ;
        ; List the entire table of defined symbols
        ;
list_defined_symbols:
        PUSH        H
        ;
        ; Set header string to defined symbols
        ;
        LHLD        defined_symbols_start_ptr
        LXI         B,symbols_str


;//////////////////////////////////////

        ;
        ; Print an entire symbol table to file referenced by HL
        ;
list_symbols:
        ;
        ; Print list header
        ;
        XCHG
        POP         H
        PUSH        H
        CALL        print_newline
        CALL        print_string
        ;
        ; Prepare output string buffer
        ;
        LXI         B,list_output_str_buffer
        MVI         A,14
        STAX        B
        CALL        clear_output_buffer_start
        ;
        ; Print newline
        ;
        POP         H
        PUSH        H
        CALL        print_newline
        ;
        ; Add CR,LF to end of string buffer
        ;
        MVI         A,CR
        STAX        B
        INX         B
        MVI         A,LF
        STAX        B
        ;
        ; List next symbol in table
        ;
list_next_symbol:
        LXI         B,list_output_str_buffer + 2
        ;
        ; Check if at end of table
        ;
        LDAX        D
        ANI         SYM_CH_MASK + SYM_CF_LAST
end_of_symbol_table_check:
        POP         H
        RZ
        PUSH        H
        ;
        ; List symbol
        ;
list_next_symbol_char:
        ;
        ; Check if last character of symbol name, and convert to ASCII
        ;
        JM          symbols_listing_do_last_char
        CPI         ' '
        JNC         symbols_listing_char_ready
        ADI         'A'-1
symbols_listing_char_ready:
        ;
        ; Add symbol name character to the output string and advance pointers
        ;
        STAX        B
        INX         B
        INX         D
        ;
        ; Check if at end of table
        ;
        LDAX        D
        ANI         SYM_CH_MASK + SYM_CF_LAST
        JMP         list_next_symbol_char

        ;
        ; Last character of symbol table
        ;
symbols_listing_do_last_char:
        ;
        ; Convert to ASCII
        ;
        ANI         NOT-(SYM_CF_LAST)
        CPI         ' '
        JNC         symbols_listing_last_char_ready
        ADI         'A'-1
symbols_listing_last_char_ready:
        ;
        ; Add symbol name character to the output string and advance pointers
        ;
        STAX        B
        INX         D
        LXI         B,list_output_str_buffer + 9
        ;
        ; Add symbol address to output string
        ;
        PUSH        D
        CALL        word_to_hex
        POP         D
        ;
        ; Print output string and advcance pointers to next symbol
        ;
        POP         H
        LXI         B,list_output_str_buffer
        CALL        print_string
        INX         D
        INX         D
        PUSH        H
        ;
        ; Clear output string in preparation for the next symbol table entry
        ;
        CALL        clear_output_buffer_start
        JMP         list_next_symbol


;//////////////////////////////////////

        ;
        ; Clear output string for one symbols-table name listing
        ;
clear_output_buffer_start:
        LXI         B,list_output_str_buffer + 1
        MVI         A,' '
        MVI         L,12
clear_output_buffer_start_loop:
        STAX        B
        INX         B
        DCR         L
        JNZ         clear_output_buffer_start_loop
        RET


;//////////////////////////////////////

undefined_symbols_str:
        DB          20
        DB          'UNDEFINED SYMBOLS:',CR,LF
symbols_str:
        DB          15
        DB          'SYMBOL TABLE:',CR,LF


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

lines_left_on_page:
        DS          1
interactive_mode_flag:
        DS          1
final_error_report_flag:
        DS          1
error_counter:
        DS          1
asm_direct_to_ram_flag:
        DS          1
current_name_buffer:
        DS          5
current_name_len:
        DS          1
console_line_cursor_pos:
        DS          1
equ_symbol_name_backup:
        DS          5 + 1
current_char:
        DS          1
assembler_pass_state:
        DS          1
expression_value:
        DS          2
instr_data_next_addr_ptr:
        DS          2
current_address_ptr:
        DS          2
current_line_bin_length:
        DS          2
listing_bindata_addr:
        DS          2
listing_bindata_bitmap:
        DS          1
immediate_datatype_len_plus_one:
        DS          1
listing_line_bindata:
        DS          4
opcode_list_index:
        DS          1
current_numeric_str:
        DS          8
undef_symb_size_flag:
        DS          1
current_error_nr:
        DS          1
current_tos_error_nr:
        DS          1
list_output_line_cursor_pos:
        DS          1
last_used_list_output_cursor_pos:
        DS          1
expression_char_value:
        DS          1
negative_expr_part_flag:
        DS          1
symbol_buffers_first_byte_ptr:
defined_symbols_start_ptr:
        DS          2
defined_symbols_end_ptr:
        DS          2
undefined_symbols_start_ptr:
        DS          2
symbol_buffers_last_byte_ptr:
undefined_symbols_end_ptr:
        DS          2
src_output_str_buffer:
        DS          1+81
list_output_str_buffer:
        DS          1+81
src_output_str_buffer_cursor:
        DS          2
unused_outside_main_flag:
        DS          1
stack_backup:
        DS          2
hexfile_str_len:
        DS          1
hex_file_next_cont_addr:
        DS          2
hexfile_str_checksum_value:
        DS          1
hexfile_str_checksum_ptr:
        DS          2
current_asm_bin_byte:
        DS          1
hexfile_str_buffer:
        DS          1+64

dual_err_listing_fcb:
        DB          6
        DB          FM_OUTPUT + FM_BINARY + FM_EOF_NEXT
dual_err_listing_1st_file_ptr:
        DW          00000H
dual_err_listing_2nd_file_ptr:
        DW          00000H

null_output_fcb:
        DB          2
        DB          FM_OUTPUT + FM_NO_CLOSE
        DW          00000H
        DW          null_output_routine
