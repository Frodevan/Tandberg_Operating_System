;//////////////////////////////////////////////////////////////////////////////
;//
;//     RASM - Tandberg 8080 Relocatable Assembler
;//
;//         Extra parameters:
;//
;//             [$[[PL]<pl_nr>][PW<pw_nr>]]
;//
;//                 pl_nr       Force $PL argument, page length (64 - 132)
;//                 pw_nr       Force $PW argument, page width (12 - 255)
;//
;//
;//         This program is a 2-pass assembler that produces relocatable object-
;//         files rather than absolute-address assembled files. These object-files
;//         can then be linked together with the LINK program. See the source code
;//         for LINK for an overview of the file format of the relocatable object
;//         files.
;//
;//
;//         Input and output standard TOS-file assignments:
;//
;//             SI  Source code input (must be a, or a chain of, block-devices)
;//             SO  Relocatable object file output
;//             SL  Code and error listing output
;//
;//
;//         If SL is not assigned, AL will be used instead if assigned. Otherwise
;//         the console will be used. A full code-listing will only be produced
;//         when SL has been assigned, otherwise only errors will be listed. By
;//         default, the page width is 110 characters, and the default page length
;//         is 48 lines.
;//
;//
;//         Assembly follows standard Intel 8080 obj syntax, with certain quirks:
;//
;//             * $ can be used as an expression for the current address
;//             * Single-character strings can be used for any expression part
;//             * Double-character strings can be used for any word-expression part
;//             * A strng-expression in a DB overrides preceeding arithmetic parts
;//             * Arithmetic parts after a DB string applies to last character only
;//             * Only +/- arithmetic is supported for expressions, no parantheses
;//             * Symbols can't be more than 6 characters long
;//             * Input source-file must end with an END or EOF pseudo-instruction
;//
;//
;//         Layout codes for program listing:
;//
;//             $TITLE <title>  Set title of the program listing
;//             $PW <width>     Set new page width of program listing (64 - 132)
;//             $PL <length>    Set new page length of program listing (12 - 255)
;//             $E              Insert page-break in program listing
;//             $DB             Include all data in listing for DB expressions
;//
;//
;//         NOTE: This program will determine the start of user-RAM in a way that
;//               is not compatible with systems having 54KB or more RAM. If this
;//               were to be run on a systeme like this, the TOS and XMON data area
;//               would be overwritten by the defined symbols table.
;//
;//         NOTE: Due to the size of this program, it will overwrite parts of TOS
;//               if run on TOS version v1.8x. Running this on v1.6x will work,
;//               however there will be limited room for complex assignement of
;//               input/output TOS standard files.
;//
;//
;//         Changelog:
;//
;//             v2.2a: Entry at 0xBC00
;//
;//                 -> First version I have
;//                 -> Has a bug if there is an external reference in a dw with
;//                    multiple parts
;//                 -> Has a bug where the $E layout code may be off-by-one line
;//                 -> Has a bug where a symbol name in an expression may in some
;//                    edge-cases corrupt the current external symbol number
;//
;//             v2.2b: Entry at 0xBC00
;//
;//                 -> Fixes the dw external reference bug from v2.2a
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
FIRST_BYTE  EQU     00001H
SECOND_BYTE EQU     00100H
JMP_LEN     EQU     003H

;
; Flag values
;
FALSE       EQU     0           ; Boolean False
TRUE        EQU     1           ; Boolean True
TRUE_ALT    EQU     -1          ; Boolean True

;
; ASCII control cHaracters
;
NULL        EQU     000H        ; Null character
HTAB        EQU     009H        ; Horizontal tabulation
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return
CURR        EQU     018H        ; Cursor right
SPACE       EQU     020H        ; Space
APOSTROPHE  EQU     027H        ; Aphostrophe
SEMICOLON   EQU     03BH        ; Semicolon

;
; XMON and TOS system data
;
BUFLIM      EQU     0272EH      ; Lowest address of current TOS buffers

;
; TOS system calls
;
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
OPEN        EQU     0FD1EH      ; Open block device
EDBH        EQU     0FD2AH      ; Convert byte to 2-character ASCII hexadecimal
EDWH        EQU     0FD2DH      ; Convert word to 4-character ASCII hexadecimal

;
; TOS constants
;
DEV_BB_PTR  EQU     0FDF2H      ; Reference to byte-bucket (void) device file

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer
AL_FCB      EQU     0FF0EH      ; Auxilliary line-printer output abstract file FCB pointer

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag
FM_OUTPUT   EQU     002H        ; File open for writing flag
FM_BINARY   EQU     004H        ; Binary flag
FM_ASSIGNED EQU     020H        ; Assigned and opened by command line flag
FM_NO_CLOSE EQU     040H        ; Don't close file flag
FM_EOF      EQU     080H        ; End of file flag

;
; RASM error codes
;
SYNTAX_ERR  EQU     001H        ; Syntax error in source code
INV_INS_ERR EQU     002H        ; Invalid instruction
LONG_LN_ERR EQU     003H        ; Too many entries in line
SYMBTAB_ERR EQU     004H        ; Symbol table full
ORG_EXP_ERR EQU     005H        ; Invalid ORG expression (undefned symbol part)
EQU_EXP_ERR EQU     006H        ; Invalid EQU expression
SB_EXP_ERR  EQU     007H        ; Invalid single-byte expression
LBL_EXP_ERR EQU     008H        ; Invalid label expression (undefned symbol part)
INV_EXP_ERR EQU     009H        ; Invalid expression
NO_EXP_ERR  EQU     010H        ; Missing expression
UND_SYM_ERR EQU     011H        ; Undefined symbol
DBLSYMB_ERR EQU     012H        ; Symbol defined multiple times
INC_REG_ERR EQU     013H        ; Incorrect register

;
; RASM object file record types
;
REC_HEADER  EQU     001H        ; Header record
REC_PUB_LBL EQU     002H        ; Public label record
REC_EXT_LBL EQU     003H        ; External label record
REC_DATA    EQU     004H        ; Data record
REC_INT_REF EQU     005H        ; Internal reference record
REC_EXT_REF EQU     006H        ; External reference record
REC_ST_ADDR EQU     007H        ; Start address record
REC_END     EQU     0FFH        ; End record

;
; Base segment flags (common for both expressions and symbol types)
;
BASE_CSEG   EQU     001H        ; CSEG segment
BASE_DSEG   EQU     002H        ; DSEG segment
BASE_ABS    EQU     004H        ; Absolute
BASE_EXT    EQU     008H        ; Symbol/expression type is external

;
; Other expression flags
;
EXP_TP_END  EQU     010H        ; End of expressions, no value
EXP_TP_ERR  EQU     020H        ; Invalid expression value
EX_PRL_CONT EQU     EXP_TP_END  ; Preliminary flag, not end of expressions when parsing one

;
; Other symbol flags
;
SYM_TP_PUB  EQU     010H        ; Symbol type is public
SYM_TP_DUPL EQU     020H        ; Symbol type is duplicate
SYM_ERASED  EQU     0FFH        ; Symbol deleted entry, first name character

;
; Parse-expression operation classes
;
EXP_CL_DB   EQU     1           ; Next byte of data-bytes expression
EXP_CL_SB   EQU     2           ; Next single-byte expression

;
; Pseudo-instructions
;
P_INS_ORG   EQU     1           ; Continue from absolute address pseudo-instruction
P_INS_CSEG  EQU     2           ; Continue from code segment pseudo-instruction
P_INS_DSEG  EQU     3           ; Continue from data segment pseudo-instruction
P_INS_LAYOT EQU     4           ; Layout change code
P_INS_DW    EQU     5           ; Define words pseudo-instruction
P_INS_DB    EQU     6           ; Define bytes pseudo-instruction
P_INS_DS    EQU     7           ; Define space pseudo-instruction
P_INS_END   EQU     8           ; End of code pseudo-instruction
P_INS_EQU   EQU     9           ; Equate pseudo-instruction
P_INS_EXTRN EQU     10          ; List of external labels pseudo-instruction
P_INS_PUBLI EQU     11          ; List of public labels pseudo-instruction

;
; Instruction classes
;
IC_PSEUDO   EQU     1           ; Pseudo-instruction, special meaning to assembler
IC_NO_ARGS  EQU     2           ; Instruction without any arguments
IC_BR_COUNT EQU     3           ; Counter instruction, byte register argument
IC_BR_ARITH EQU     4           ; Arithmetic instruction, byte register argument
IC_BR_MOVE  EQU     5           ; Move instruction, two byte register arguments
IC_WR_DATA  EQU     6           ; Load/Store instruction, word register argument
IC_WR_STACK EQU     7           ; Stack instruction, word register argument
IC_WR_ARITH EQU     8           ; Arithmetic instuction, word register argument
IC_N_RESET  EQU     9           ; Reset instruction, enumerated argument
IC_BI_ARITH EQU     10          ; Arithmetic instruction, byte immediate argument
IC_BI_MOVE  EQU     11          ; Move instruction, byte register and immediate argument
IC_WI_BRNCH EQU     12          ; Branching instruction, word immediate argument
IC_WI_MOVE  EQU     13          ; Move instruction, word register and immediate argument


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02000H
stack_backup:
        DS          2


;//////////////////////////////////////

primary_listing_dev_flag:
        DS          1
listing_to_console_flag:
        DS          1
listing_page_length:
        DS          1
lines_left_on_page:
        DS          1
listing_page_width:
        DS          1
page_length_preset_flag:
        DS          1
page_width_preset_flag:
        DS          1
db_verbose_listing_flag:
        DS          1
db_first_listing_line_flag:
        DS          1


;//////////////////////////////////////

symbol_buffer_start_ptr:
        DS          2
symbol_buffer_end_ptr:
        DS          2


;//////////////////////////////////////

source_code_line_nr_bcd:
        DS          3
current_addr_offset:
        DS          2
current_cseg_head:
        DS          2
current_dseg_head:
        DS          2
last_abs_address:
        DS          2
current_addr_base_type:
        DS          1


;//////////////////////////////////////

nr_of_assigned_src_errors:
        DS          1
src_assigned_errors_buffer:
        DS          161
total_error_count:
        DS          1
current_error_nr:
        DS          1


;//////////////////////////////////////

symb_table_full_flag:
        DS          1
no_inst_in_line_flag:
        DS          1


;//////////////////////////////////////

page_nr_counter_bcd:
        DS          2
listing_line_page_nr_offset:
        DS          2
input_line_buffer:
        DS          81
listing_line_str_buffer:
        DS          133
listing_line_str_buffer_end:
listing_hdr_str_buffer:
        DS          133
listing_hdr_str_buffer_end:
listing_error_str_buffer:
        DS          18
output_file_record_data:
        DS          80
listing_line_title_end_ptr:
        DS          2


;//////////////////////////////////////

current_line_bin_data_index:
        DS          1
record_content_len:
        DS          1
current_data_rec_byte_offset:
        DS          2
current_data_rec_base_enum:
        DS          1


;//////////////////////////////////////

src_line_data_buffers:
symb_name_buffer:
        DS          7
instr_name_buffer:
        DS          21
instr_first_arg_buffer:
        DS          41
instr_second_arg_buffer:
        DS          41
src_line_data_buffers_end:


;//////////////////////////////////////

instr_next_char:
        DS          1
listing_started_flag:
        DS          1


;//////////////////////////////////////

current_line_bin_data:
        DS          4
;
; NOTE: List index is 1:1 mapped to offset of value in current_line_bin_data
;
bin_data_word_type_flags:
        DS          4

current_line_bin_data_len:
        DS          1
current_line_bin_data_ptr:
        DS          2
        DS          1


;//////////////////////////////////////

instr_str_first_arg_ptr:
        DS          2


;//////////////////////////////////////

current_symbol_addr:
expression_value:
        DS          2
current_symbol_type:
expression_flags:
        DS          1

expr_next_char:
        DS          1
in_byte_string_expr_flag:
        DS          1
parsed_expression_class:
        DS          1
negative_expr_part_flag:
        DS          1

expr_symb_name_buffer:
        DS          6

current_ext_symb_nr:
        DS          2
last_val_ext_symb_nr:
        DS          2
symbol_class_bitmap:
        DS          1
nr_of_names_per_listing_line:
        DS          1
symbol_candidate_ptr:
        DS          2
name_nr_in_line_count:
        DS          1


;//////////////////////////////////////

emergency_buffer_start:
        DS          611
emergency_buffer_end:


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0BC00H
start:
beginning:
        ;
        ; Save stack pointer to be able to break out to TOS from subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        stack_backup
        ;
        ; Print welcome title
        ;
        LXI         D,rasm_title_str
        LHLD        CO_FCB
        CALL        PUT
        ;
        ; Assemble input file
        ;
        CALL        init_first_pass
        CALL        run_first_pass
        CALL        init_second_pass
        CALL        run_second_pass
        CALL        finalize_assembly
        ;
        ; Return to TOS
        ;
        XRA         A
exit_to_tos:
        LHLD        stack_backup
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main: Initialization of pass 1
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Validate any preconditions needed
        ;
init_first_pass:
        ;
        ; Check if a source-file is assigned
        ;
        LHLD        SI_FCB
        MOV         A,L
        ORA         H
        JNZ         source_file_ready
        ;
        ; If not, report error to user
        ;
        LXI         D,source_file_missing_str
        LHLD        CO_FCB
        CALL        PUT
        JMP         exit_to_tos


;//////////////////////////////////////

source_file_missing_str:
        DB          'No source file',CR


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Check integrety of assigned files
        ;
source_file_ready:
        ;
        ; Check that program did not overwrite any dynamic TOS buffers
        ;
        LHLD        BUFLIM
        LXI         D,end_of_program - 1
        MOV         A,H
        CMP         D
        JNZ         check_buflim_addr_digit
        MOV         A,L
        CMP         E
check_buflim_addr_digit:
        JNC         tos_buffers_ok
        ;
        ; If so, report error to user and reboot to recover TOS
        ;
        LXI         D,buffer_conflict_str
        LHLD        CO_FCB
        CALL        PUT
        RST         RST0


;//////////////////////////////////////

buffer_conflict_str:
        DB          'Buffer conflict. Too many files assigned',CR


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Make sure output file can take data
        ;
tos_buffers_ok:
        ;
        ; Check if output file has been assigned
        ;
        LHLD        SO_FCB
        MOV         A,L
        ORA         H
        JNZ         validate_output_file
        ;
        ; If not, assign null-file
        ;
        LHLD        DEV_BB_PTR
        SHLD        SO_FCB
        JMP         output_file_ready

validate_output_file:
        ;
        ; Validate that assigned output file is a block-device file
        ;
        MOV         A,M
        CPI         5
        JZ          output_file_ready
        ;
        ; If not, report error to user
        ;
        LXI         D,invalid_output_file_str
        LHLD        CO_FCB
        CALL        PUT
        JMP         exit_to_tos


;//////////////////////////////////////

invalid_output_file_str:
        DB          'Illegal assignment on SO',CR


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Determine operating mode based on which files have been assigned
        ;
output_file_ready:
        ;
        ; Check if the primary listing device has been assigned
        ;
        MVI         A,TRUE
        STA         primary_listing_dev_flag
        LHLD        SL_FCB
        MOV         A,L
        ORA         H
        JNZ         listing_device_ready
        ;
        ; If not, check if the alternate listing device has been assigned
        ;
        XRA         A
        STA         primary_listing_dev_flag
        LHLD        AL_FCB
        MOV         A,L
        ORA         H
        JNZ         set_listing_device
        ;
        ; Otherwise use console as listing device
        ;
        LHLD        CO_FCB
set_listing_device:
        SHLD        SL_FCB
        ;
        ; Null out AL since it has now been moved to SL anyways if it was set
        ;
        PUSH        H
        LXI         H,NULL
        SHLD        AL_FCB
        POP         H
listing_device_ready:
        ;
        ; Determine if the listing device is the same as the console device
        ;
        XRA         A
        STA         listing_to_console_flag
        XCHG
        LHLD        CO_FCB
        MOV         A,H
        CMP         D
        JNZ         console_listing_check_done
        MOV         A,L
        CMP         E
        JNZ         console_listing_check_done
        MVI         A,TRUE
        STA         listing_to_console_flag
console_listing_check_done:


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Initalize variables and default settings
        ;
        XRA         A
        STA         listing_started_flag
        STA         page_length_preset_flag
        STA         page_width_preset_flag
        MVI         A,48
        STA         listing_page_length
        ;
        ; Set initial listing page width based on listing target
        ;
        MVI         A,79
        STA         listing_page_width
        LDA         listing_to_console_flag
        ORA         A
        JNZ         initial_page_size_ready
        MVI         A,110
        STA         listing_page_width
initial_page_size_ready:
        ;
        ; Change page size if set in command line arguments
        ;
        CALL        parse_command_line_args
        ;
        ; Set end of dynamic buffer area to start of RASM program
        ;
        LXI         H,beginning
        SHLD        symbol_buffer_end_ptr
        ;
        ; Check if there is any extra user-RAM available at all
        ;
        MVI         L,000H
        DCR         H
        MOV         A,M
        INR         M
        CMP         M
        JNZ         find_start_of_mem_loop
        ;
        ; If not, reserve a bit of system-RAM instead
        ;
        LXI         H,emergency_buffer_end
        SHLD        symbol_buffer_end_ptr
        LXI         H,emergency_buffer_start
        JMP         dynamic_buffer_bounds_ready

        ;
        ; Find start of user-RAM to use as dynamic buffer start
        ;
find_start_of_mem_loop:
        DCR         H
        MOV         A,M
        INR         M
        CMP         M
        JNZ         find_start_of_mem_loop
        INR         H
dynamic_buffer_bounds_ready:
        SHLD        symbol_buffer_start_ptr
        MVI         M,NULL
        ;
        ; Reset assembler variables for first pass
        ;
        LXI         H,00000H
        SHLD        source_code_line_nr_bcd
        SHLD        listing_line_title_end_ptr
        XRA         A
        STA         source_code_line_nr_bcd + 2
        SHLD        last_abs_address
        SHLD        current_cseg_head
        SHLD        current_dseg_head
        SHLD        current_addr_offset
        MVI         A,BASE_CSEG
        STA         current_addr_base_type
        XRA         A
        STA         nr_of_assigned_src_errors
        STA         symb_table_full_flag
        STA         db_verbose_listing_flag
        CALL        init_first_listing_page
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main: First pass, map out symbols in the source code
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Run the first pass of the assembler
        ;
run_first_pass:
        ;
        ; Parse the next line of assembler code for the first pass
        ;
first_pass_main:
        ;
        ; Get next source-code line and set up datastructures
        ;
        CALL        get_next_input_file_line
        LDA         no_inst_in_line_flag
        ORA         A
        JNZ         first_pass_main
        ;
        ; Do basic book-keeping of things in the most recent code line
        ;
        CALL        check_and_add_symbol
        CALL        check_and_look_up_instr
        JC          first_pass_main
        ;
        ; Determine binary length of instruction
        ;
        ORA         A
        JZ          p1_tripple_byte_instr
        CPI         IC_PSEUDO
        JZ          p1_handle_pseudo_instr
        CPI         IC_BI_ARITH
        JC          p1_single_byte_instr
        CPI         IC_WI_BRNCH
        JC          p1_double_byte_instr
p1_tripple_byte_instr:
        LXI         D,3
        JMP         p1_instr_len_ready

p1_single_byte_instr:
        LXI         D,1
        JMP         p1_instr_len_ready

p1_double_byte_instr:
        LXI         D,2
p1_instr_len_ready:
        ;
        ; Advance current CSEG offset
        ;
        LHLD        current_addr_offset
        DAD         D
        SHLD        current_addr_offset
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Handle Pseudo-instruction for first assembler pass
        ;
p1_handle_pseudo_instr:
        ;
        ; Look up handler for relevant pseudo-instruction in jump-table
        ;
        LXI         D,p1_pseudo_instr_jump_table
        LDA         current_line_bin_data
        MOV         L,A
        MVI         H,000H
        DAD         D
        ;
        ; Run pseudo-instruction handler
        ;
        PCHL


;//////////////////////////////////////

        ;
        ; Jump-table for assembler pass-1 pseudo-instruction handlers
        ;
p1_pseudo_instr_jump_table:
        JMP         first_pass_main
        JMP         p1_handle_org
        JMP         p1_handle_cseg
        JMP         p1_handle_dseg
        JMP         p1_handle_layout_change
        JMP         p1_handle_dw
        JMP         p1_handle_db
        JMP         p1_handle_ds
        JMP         p1_handle_end
        JMP         p1_handle_equ
        JMP         p1_handle_extrn
        JMP         p1_handle_publi


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; ORG, continue assemble from an absolute address
        ;
p1_handle_org:
        ;
        ; Save current segment address, before switching to absolute addressing
        ;
        LDA         current_addr_base_type
        LHLD        current_addr_offset
        CPI         BASE_DSEG
        JC          p1_org_from_cseg
        JNZ         p1_org_abs_mode_set
        SHLD        current_dseg_head
        JMP         p1_org_old_offset_saved

p1_org_from_cseg:
        SHLD        current_cseg_head
p1_org_old_offset_saved:
        ;
        ; Start absolute addressing
        ;
        MVI         A,BASE_ABS
        STA         current_addr_base_type
p1_org_abs_mode_set:
        LHLD        last_abs_address
        SHLD        current_addr_offset
        ;
        ; Parse expression, expect it to be in the form of an absolute number
        ;
        LXI         D,instr_first_arg_buffer
        CALL        parse_word_expression
        CPI         BASE_ABS
        JZ          p1_org_update_addr
        ;
        ; If not, mark line with an error to be picked up in the second pass
        ;
        MVI         A,ORG_EXP_ERR
        CALL        assign_error_to_src_line
        JMP         first_pass_main

        ;
        ; Update current address with absolute number
        ;
p1_org_update_addr:
        SHLD        current_addr_offset
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; CSEG, continue assemble from the head of the code segment
        ;
p1_handle_cseg:
        ;
        ; Check if already in code segment addressing mode
        ;
        LDA         current_addr_base_type
        LHLD        current_addr_offset
        CPI         BASE_DSEG
        JC          first_pass_main
        ;
        ; If not, save current segment offset before changing mode
        ;
        JNZ         p1_cseg_from_abs
        SHLD        current_dseg_head
        JMP         p1_cseg_old_offset_saved

p1_cseg_from_abs:
        SHLD        last_abs_address
p1_cseg_old_offset_saved:
        ;
        ; Continue in code segment relative addressing mode
        ;
        MVI         A,BASE_CSEG
        STA         current_addr_base_type
        LHLD        current_cseg_head
        SHLD        current_addr_offset
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; DSEG, continue assemble from the head of the data segment
        ;
p1_handle_dseg:
        ;
        ; Check if already in data segment addressing mode
        ;
        LDA         current_addr_base_type
        LHLD        current_addr_offset
        CPI         BASE_DSEG
        JZ          first_pass_main
        ;
        ; If not, save current segment offset before changing mode
        ;
        JC          p1_dseg_from_cseg
        SHLD        last_abs_address
        JMP         p1_dseg_old_offset_saved

p1_dseg_from_cseg:
        SHLD        current_cseg_head
p1_dseg_old_offset_saved:
        ;
        ; Continue in data segment relative addressing mode
        ;
        MVI         A,BASE_DSEG
        STA         current_addr_base_type
        LHLD        current_dseg_head
        SHLD        current_addr_offset
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; $, change layout parameter
        ;
p1_handle_layout_change:
        ;
        ; Get to the start of the parameter change command
        ;
        LXI         D,input_line_buffer
p1_layout_find_cmd_start:
        LDAX        D
        INX         D
        CPI         '$'
        JNZ         p1_layout_find_cmd_start
        ;
        ; Determine which layout-change command is specified
        ;
        LDAX        D
        INX         D
        CPI         'T'
        JZ          p1_handle_title_change
        CPI         'P'
        JNZ         p1_handle_other_layout_cmds
        ;
        ; Check which page size parameter to change
        ;
        LDAX        D
        INX         D
        CPI         'W'
        JZ          p1_handle_page_width_change
        CPI         'L'
        JNZ         first_pass_main


;//////////////////////////////////////

        ;
        ; Page length change command
        ; Ignore page-length change if preset as a command line argument
        ;
        LDA         page_length_preset_flag
        ORA         A
        JNZ         first_pass_main
        ;
        ; Otherwise update new page-length if 12 lines or longer
        ;
        CALL        get_to_and_parse_number
        CPI         12
        JC          first_pass_main
        STA         listing_page_length
        JMP         first_pass_main


;//////////////////////////////////////

        ;
        ; Page width change command
        ;
p1_handle_page_width_change:
        ;
        ; Ignore page-width change if preset as a command line argument
        ;
        LDA         page_width_preset_flag
        ORA         A
        JNZ         first_pass_main
        ;
        ; Otherwise update new page-width if between 64 and 132 characters
        ;
        CALL        get_to_and_parse_number
        CPI         64
        JC          first_pass_main
        CPI         132+1
        JNC         first_pass_main
        STA         listing_page_width
        JMP         first_pass_main


;//////////////////////////////////////

        ;
        ; Title change command
        ;
p1_handle_title_change:
        ;
        ; Verify the rest of the TITLE command name
        ;
        MVI         B,4
        LXI         H,p1_title_cmd_name_str
p1_verify_title_cmd_loop:
        LDAX        D
        CMP         M
        JNZ         first_pass_main
        INX         H
        INX         D
        DCR         B
        JNZ         p1_verify_title_cmd_loop
        ;
        ; Copy the rest of the line in as the new source listing title
        ;
        LDA         listing_hdr_str_buffer + 34
        CPI         ' '
        CZ          update_listing_title
        JMP         first_pass_main


;//////////////////////////////////////

p1_title_cmd_name_str:
        DB          'ITLE'


;//////////////////////////////////////

        ;
        ; Other layout commands
        ;
p1_handle_other_layout_cmds:
        ;
        ; Check for layout DB command
        ;
        CPI         'D'
        JNZ         first_pass_main
        LDAX        D
        INX         D
        CPI         'B'
        JNZ         first_pass_main
        ;
        ; If so, set flag
        ;
        STA         db_verbose_listing_flag
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; DW, define data words
        ;
p1_handle_dw:
p1_parse_next_wordval:
        ;
        ; Get next data word expression value
        ;
        LHLD        instr_str_first_arg_ptr
        XCHG
        CALL        parse_word_expression
        XCHG
        SHLD        instr_str_first_arg_ptr
        ;
        ; End dw on end of expressions flag
        ;
        ANI         EXP_TP_END
        JNZ         first_pass_main
        ;
        ; Advance current offset
        ;
        LHLD        current_addr_offset
        INX         H
        INX         H
        SHLD        current_addr_offset
        ;
        ; Check if there's more data defined
        ;
        LDA         expr_next_char
        CPI         ','
        JZ          p1_parse_next_wordval
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; DB, define data bytes
        ;
p1_handle_db:
        ;
        ; Ready parsing byte data expressions
        ;
        CALL        init_data_byte_expr_parser
p1_parse_next_byteval:
        ;
        ; Get next data byte expression value
        ;
        LHLD        instr_str_first_arg_ptr
        XCHG
        CALL        parse_data_byte_expression
        XCHG
        SHLD        instr_str_first_arg_ptr
        ;
        ; End db on end of expressions flag
        ;
        ANI         EXP_TP_END
        JNZ         first_pass_main
        ;
        ; Advance current offset if so
        ;
        LHLD        current_addr_offset
        INX         H
        SHLD        current_addr_offset
        ;
        ; Check if there's more data defined
        ;
        LDA         expr_next_char
        CPI         ','
        JZ          p1_parse_next_byteval
        ;
        ; Check if there's more string-data defined
        ;
        LDA         in_byte_string_expr_flag
        ORA         A
        JNZ         p1_parse_next_byteval
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; DS, define data space
        ;
p1_handle_ds:
        ;
        ; Get number of bytes to reserve from expression
        ;
        LXI         D,instr_first_arg_buffer
        CALL        parse_word_expression
        ;
        ; Validate that it's a constant and independent value
        ;
        ANI         BASE_CSEG + BASE_DSEG + BASE_EXT + EXP_TP_END + EXP_TP_ERR
        JZ          p1_ds_len_ready
        ;
        ; Otherwise mark error
        ;
        MVI         A,ORG_EXP_ERR
        CALL        assign_error_to_src_line
        JMP         first_pass_main

p1_ds_len_ready:
        ;
        ; Advance offset in current segment to reserve bytes
        ;
        XCHG
        LHLD        current_addr_offset
        DAD         D
        SHLD        current_addr_offset
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; END, end of the assembly module
        ;
p1_handle_end:
        ;
        ; Update final offset of current segment
        ;
        LDA         current_addr_base_type
        LHLD        current_addr_offset
        CPI         BASE_DSEG
        JC          p1_end_from_cseg
        RNZ
        SHLD        current_dseg_head
        RET

p1_end_from_cseg:
        SHLD        current_cseg_head
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; EQU, assign a fixed value to a new symbol
        ;
p1_handle_equ:
        ;
        ; Get value to assign from expression
        ;
        LXI         D,instr_second_arg_buffer
        CALL        parse_word_expression
        ;
        ; Validate that it's a local absolute value
        ;
        ANI         BASE_CSEG + BASE_DSEG + BASE_EXT + EXP_TP_END + EXP_TP_ERR
        JZ          p1_equ_update_symbol
        ;
        ; Otherwise mark error and make sure expression is not assigned a type
        ;
        MVI         A,EQU_EXP_ERR
        CALL        assign_error_to_src_line
        XRA         A
        STA         expression_flags
p1_equ_update_symbol:
        ;
        ; Look up symbol from list of symbols
        ;
        LXI         D,symb_name_buffer
        CALL        look_up_symbol
        JC          first_pass_main
        ;
        ; Retreive EQU expression value
        ;
        XCHG
        LHLD        expression_value
        XCHG
        ;
        ; Override symbol base to become the same as EQU expression
        ;
        MOV         A,M
        ANI         BASE_EXT + SYM_TP_PUB + SYM_TP_DUPL
        MOV         B,A
        LDA         expression_flags
        ORA         B
        MOV         M,A
        ;
        ; Set assigned symbol value
        ;
        DCX         H
        MOV         M,D
        DCX         H
        MOV         M,E
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; PUBLI, list of public symbols in object
        ;
p1_handle_publi:
        MVI         A,SYM_TP_PUB
        JMP         p1_classify_symbols


;//////////////////////////////////////

        ;
        ; EXTRN, list of symbols external to object
        ;
p1_handle_extrn:
        MVI         A,BASE_EXT


;//////////////////////////////////////

        ;
        ; Classify a list of symbols with a particular flag
        ;
p1_classify_symbols:
        STA         symbol_class_bitmap
p1_classify_next_symb:
        ;
        ; Clear symbol name buffer
        ;
        LXI         H,symb_name_buffer
        MVI         B,10
p1_clear_symb_name_loop:
        MVI         M,NULL
        INX         H
        DCR         B
        JNZ         p1_clear_symb_name_loop
        ;
        ; Get next name from list of symbols to classify, and advance pointer
        ;
        LHLD        instr_str_first_arg_ptr
        LXI         D,symb_name_buffer
        MVI         B,10
        CALL        copy_instruction_part
        MOV         A,M
        INX         H
        SHLD        instr_str_first_arg_ptr
        PUSH        PSW
        ;
        ; Look up symbol in list of symbols
        ;
        LXI         D,symb_name_buffer
        CALL        look_up_symbol
        JC          p1_register_classified_symb
        ;
        ; If symbol was defined before classified, mark as duplicate and skip
        ;
        LDA         symbol_class_bitmap
        ORA         M
        ORI         SYM_TP_DUPL
        MOV         M,A
        JMP         p1_symb_classification_done

p1_register_classified_symb:
        ;
        ; Temporarily set type of symbol to classify
        ;
        LDA         current_addr_base_type
        PUSH        PSW
        LDA         symbol_class_bitmap
        STA         current_addr_base_type
        ;
        ; Temporarily set offset of symbol to classify
        ;
        LHLD        current_addr_offset
        PUSH        H
        LXI         H,00000H
        SHLD        current_addr_offset
        ;
        ; Add symbol with given classification, and restore variables
        ;
        CALL        check_and_add_symbol
        POP         H
        SHLD        current_addr_offset
        POP         PSW
        STA         current_addr_base_type
p1_symb_classification_done:
        ;
        ; Check for more names in list of symbols to classify
        ;
        POP         PSW
        CPI         ','
        JZ          p1_classify_next_symb
        JMP         first_pass_main


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main: Initialization of pass 2
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prepare for the second pass
        ;
init_second_pass:
        ;
        ; Reset source code file
        ;
        CALL        end_first_pass
        ;
        ; Write header, public and external symbol records to object file
        ;
        CALL        write_header_to_obj_file
        CALL        write_pub_labels_to_obj_file
        CALL        write_ext_labels_to_obj_file
        ;
        ; Set up page-number text in listing string
        ;
        CALL        place_header_page_nr_substr
        ;
        ; Reset assembler variables for second pass
        ;
        LXI         H,00000H
        SHLD        current_addr_offset
        SHLD        current_cseg_head
        SHLD        current_dseg_head
        SHLD        last_abs_address
        SHLD        source_code_line_nr_bcd
        XRA         A
        STA         record_content_len
        STA         source_code_line_nr_bcd + 2
        STA         total_error_count
        MVI         A,BASE_CSEG
        STA         current_addr_base_type
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main: Second pass, add assembled records to output file
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Run the second pass of the assembler
        ;
run_second_pass:
        ;
        ; Parse the next line of assembler code for the second pass
        ;
second_pass_main:
        ;
        ; Get and prepare next source-code line
        ;
        CALL        get_next_input_file_line
        CALL        prepare_pass_2_outputs
        ;
        ; Check if there's anything relevant in the current source-code line
        ;
        LDA         no_inst_in_line_flag
        ORA         A
        JZ          assemble_src_code_line
        ;
        ; Else blank binary data from listing line and continue to next line
        ;
        CALL        clear_listing_line_address
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main

assemble_src_code_line:
        ;
        ; Check for pre-registered errors and sanity-check source-code line
        ;
        CALL        check_line_for_assigned_errors
        CALL        check_symbol_for_errors
        CALL        check_and_look_up_instr
        JNC         src_line_ready
        ;
        ; If error, skip to next line
        ;
        CALL        clear_listing_line_address
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main

src_line_ready:
        ;
        ; Check if the instruction lookup returned a valid instruction
        ;
        ORA         A
        JNZ         src_line_valid
        ;
        ; If not, raise error
        ;
        MVI         A,INV_INS_ERR
        STA         current_error_nr
        MVI         A,3
        JMP         add_data_to_obj


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Run handler for the current instruction
        ;
src_line_valid:
        ;
        ; Check for pseudo-instruction
        ;
        CPI         IC_PSEUDO
        JZ          p2_handle_pseudo_instr
        ;
        ; Look up handler for instruction class in jump-table
        ;
        MOV         E,A
        MVI         D,000H
        LXI         H,instr_jump_table - 2*JMP_LEN
        DAD         D
        DAD         D
        JMP         p2_run_instr_handler

p2_handle_pseudo_instr:
        ;
        ; Look up handler for relevant pseudo-instruction in jump-table
        ;
        LXI         D,p2_pseudo_instr_jump_table
        LDA         current_line_bin_data
        MOV         L,A
        MVI         H,000H
p2_run_instr_handler:
        DAD         D
        ;
        ; Run the chosen instruction handler
        ;
        PCHL


;//////////////////////////////////////

        ;
        ; Op-Code instruction class handler jump-table
        ; NOTE: Starts at instruction class nr. 2
        ;
instr_jump_table:
        JMP         handle_no_arg_instr
        JMP         handle_byte_reg_counting
        JMP         handle_byte_reg_arithmetic
        JMP         handle_byte_reg_move
        JMP         handle_word_reg_datapointer
        JMP         handle_word_reg_stack
        JMP         handle_word_reg_arithmetic
        JMP         handle_enumerated_instr
        JMP         handle_immediate_byte_arithmetic
        JMP         handle_immediate_byte_move
        JMP         handle_immediate_word_branching
        JMP         handle_immediate_word_move

        ;
        ; Jump-table for assembler pass-2 pseudo-instruction handlers
        ;
p2_pseudo_instr_jump_table:
        JMP         second_pass_main
        JMP         p2_handle_org
        JMP         p2_handle_cseg
        JMP         p2_handle_dseg
        JMP         p2_handle_layout_change
        JMP         p2_handle_dw
        JMP         p2_handle_db
        JMP         p2_handle_ds
        JMP         p2_handle_end
        JMP         p2_handle_equ
        JMP         p2_classify_symbols
        JMP         p2_classify_symbols


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte op-codes with no operands
        ;
handle_no_arg_instr:
        ;
        ; Add op-code byte as-is
        ;
        JMP         finalize_1_byte_no_arg_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte op-codes with one 8-bit register operand
        ;
handle_byte_reg_counting:
        ;
        ; Set register bitmap in op-code byte before adding it
        ;
        CALL        look_up_first_byte_reg
        RAL
        RAL
        RAL
        ANI         038H
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        JMP         finalize_1_byte_single_arg_opcode

;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte arithmetic op-codes with one 8-bit register operand
        ;
handle_byte_reg_arithmetic:
        ;
        ; Set register bitmap in op-code byte before adding it
        ;
        CALL        look_up_first_byte_reg
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        JMP         finalize_1_byte_single_arg_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte op-codes with two 8-bit register operands
        ;
handle_byte_reg_move:
        ;
        ; Set first register bitmap in op-code byte
        ;
        CALL        look_up_first_byte_reg
        RAL
        RAL
        RAL
        ANI         038H
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        ;
        ; Set second register bitmap in op-code byte
        ;
        CALL        look_up_second_byte_reg
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        ;
        ; Add op-code byte to binary object
        ;
        JMP         add_1_byte_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte op-codes with 16-bit register as pointer operand
        ;
handle_word_reg_datapointer:
        ;
        ; Set register bitmap in op-code byte before adding it
        ;
        CALL        look_up_data_ptr_reg
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        JMP         finalize_1_byte_single_arg_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte stack op-codes with 16-bit register operand
        ;
handle_word_reg_stack:
        ;
        ; Set register bitmap in op-code byte before adding it
        ;
        CALL        look_up_word_reg_stack_op
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        JMP         finalize_1_byte_single_arg_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte arithmetic op-codes with 16-bit register operand
        ;
handle_word_reg_arithmetic:
        ;
        ; Set register bitmap in op-code byte before adding it
        ;
        CALL        look_up_word_reg
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        JMP         finalize_1_byte_single_arg_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Single-byte op-codes with enumerated operand
        ;
handle_enumerated_instr:
        ;
        ; Get and verify operand's enumerated value
        ;
        LXI         D,instr_first_arg_buffer
        CALL        parse_single_byte_expression
        CPI         BASE_ABS
        JNZ         invalid_instr_enum_arg
        LDA         expression_value
        CPI         8
        JNC         invalid_instr_enum_arg
        ;
        ; Set register bitmap in op-code byte before adding it
        ;
        RAL
        RAL
        RAL
        ANI         038H
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        JMP         finalize_1_byte_single_arg_opcode

        ;
        ; Raise error if the operand expression is not right
        ;
invalid_instr_enum_arg:
        MVI         A,INV_EXP_ERR
        STA         current_error_nr
        JMP         finalize_1_byte_single_arg_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Dual-byte arithmetic op-codes with immediate byte operand
        ;
handle_immediate_byte_arithmetic:
        ;
        ; Get and validate immediate byte-value
        ;
        LXI         D,instr_first_arg_buffer
        CALL        parse_single_byte_expression
        CPI         BASE_ABS
        JZ          word_arith_arg_ready
        ;
        ; If expression is not valid, raise single-byte expression error
        ;
        MVI         A,SB_EXP_ERR
        STA         current_error_nr
word_arith_arg_ready:
        ;
        ; Add immediate byte to instruction data
        ;
        LDA         expression_value
        STA         current_line_bin_data + 1
        JMP         finalize_2_byte_single_arg_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Dual-byte op-codes with 8-bit register and immediate byte operand
        ;
handle_immediate_byte_move:
        ;
        ; Set register bitmap in op-code byte
        ;
        CALL        look_up_first_byte_reg
        RAL
        RAL
        RAL
        ANI         038H
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        ;
        ; Get and validate immediate byte-value
        ;
        LXI         D,instr_second_arg_buffer
        CALL        parse_single_byte_expression
        CPI         BASE_ABS
        JZ          byte_move_arg_ready
        ;
        ; If expression is not valid, raise single-byte expression error
        ;
        MVI         A,SB_EXP_ERR
        STA         current_error_nr
byte_move_arg_ready:
        ;
        ; Add immediate byte to instruction data
        ;
        LDA         expression_value
        STA         current_line_bin_data + 1
        JMP         add_2_byte_opcode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Tripple-byte branching op-codes with 16-bit address/offset operand
        ;
handle_immediate_word_branching:
        ;
        ; 16-bit expression is in the first operand of op-code
        ;
        LXI         D,instr_first_arg_buffer


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Tripple-byte op-codes with at least one 16-bit immediate operand
        ;
handle_immediate_word_instr:
        ;
        ; Get and validate immediate word-value
        ;
        CALL        parse_word_expression
        STA         bin_data_word_type_flags + 1
        ANI         EXP_TP_END + EXP_TP_ERR
        JZ          word_arg_ready
        ;
        ; If not already a pending error, raise invalid expression error
        ;
        LDA         current_error_nr
        ORA         A
        JNZ         word_arg_ready
        MVI         A,INV_EXP_ERR
        STA         current_error_nr
word_arg_ready:
        ;
        ; Add word operand value to instruction data
        ;
        SHLD        current_line_bin_data + 1
        MVI         A,3
        JMP         add_data_to_obj


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Tripple-byte op-codes with 16-bit register and immediate operand
        ;
handle_immediate_word_move:
        ;
        ; Set register bitmap in op-code byte
        ;
        CALL        look_up_word_reg
        LXI         H,current_line_bin_data
        ADD         M
        MOV         M,A
        ;
        ; 16-bit expression is in the second operand of op-code
        ;
        LXI         D,instr_second_arg_buffer
        JMP         handle_immediate_word_instr


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Finalize an 1-byte instruction with no operand arguments
        ;
finalize_1_byte_no_arg_opcode:
        ;
        ; Verify that there were no data in the operand arguments
        ;
        LXI         D,instr_first_arg_buffer
        CALL        assert_argument_end
        JMP         add_1_byte_opcode


;//////////////////////////////////////

        ;
        ; Finalize an 1-byte instruction with one operand argument
        ;
finalize_1_byte_single_arg_opcode:
        ;
        ; Verify that there were no data in the second operand argument
        ;
        LXI         D,instr_second_arg_buffer
        CALL        assert_argument_end
add_1_byte_opcode:
        ;
        ; Add final single-byte opcode to binary data
        ;
        MVI         A,1
        JMP         add_data_to_obj


;//////////////////////////////////////

        ;
        ; Finalize a 2-byte instruction with one operand argument
        ;
finalize_2_byte_single_arg_opcode:
        LXI         D,instr_second_arg_buffer
        CALL        assert_argument_end
add_2_byte_opcode:
        ;
        ; Add final dual-byte opcode to binary data
        ;
        MVI         A,2


;//////////////////////////////////////

        ;
        ; Add binary instruction data to object file
        ;
add_data_to_obj:
        STA         current_line_bin_data_len
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; ORG, continue assemble from an absolute address
        ;
p2_handle_org:
        ;
        ; Save current segment address, before switching to absolute addressing
        ;
        LDA         current_addr_base_type
        LHLD        current_addr_offset
        CPI         BASE_DSEG
        JC          p2_org_from_cseg
        JNZ         p2_org_abs_mode_set
        SHLD        current_dseg_head
        JMP         p2_org_old_offset_saved

p2_org_from_cseg:
        SHLD        current_cseg_head
p2_org_old_offset_saved:
        ;
        ; Start absolute addressing
        ;
        MVI         A,BASE_ABS
        STA         current_addr_base_type
p2_org_abs_mode_set:
        LHLD        last_abs_address
        SHLD        current_addr_offset
        ;
        ; Parse expression, expect it to be in the form of an absolute number
        ;
        LXI         D,instr_first_arg_buffer
        CALL        parse_word_expression
        CPI         BASE_ABS
        JZ          p2_org_update_addr
        ;
        ; If not, raise invalid expression error and skip updating address
        ;
        MVI         A,INV_EXP_ERR
        STA         current_error_nr
        JMP         p2_org_done

p2_org_update_addr:
        ;
        ; Update current address with absolute number
        ;
        SHLD        current_addr_offset
p2_org_done:
        ;
        ; Complete listing line and finalize pseudo-instruction handling
        ;
        CALL        prepare_pass_2_outputs
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; CSEG, continue assemble from the head of the code segment
        ;
p2_handle_cseg:
        ;
        ; Check if already in code segment addressing mode
        ;
        LDA         current_addr_base_type
        CPI         BASE_CSEG
        JZ          p2_seg_mode_change_done
        ;
        ; If not, prepare to change to code segment addressing
        ;
        MVI         B,BASE_CSEG
        LHLD        current_cseg_head
        JMP         p2_change_seg_addr_mode


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; DSEG, continue assemble from the head of the data segment
        ;
p2_handle_dseg:
        ;
        ; Check if already in data segment addressing mode
        ;
        LDA         current_addr_base_type
        CPI         BASE_DSEG
        JZ          p2_seg_mode_change_done
        ;
        ; If not, prepare to change to data segment addressing
        ;
        MVI         B,BASE_DSEG
        LHLD        current_dseg_head


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Change segment addressing mode
        ;
p2_change_seg_addr_mode:
        ;
        ; Save current segment address, before switching to new mode
        ;
        XCHG
        LDA         current_addr_base_type
        LHLD        current_addr_offset
        CPI         BASE_DSEG
        JC          p2_seg_from_cseg
        JNZ         p2_seg_from_abs
        SHLD        current_dseg_head
        JMP         p2_seg_old_offset_saved

p2_seg_from_cseg:
        SHLD        current_cseg_head
        JMP         p2_seg_old_offset_saved

p2_seg_from_abs:
        SHLD        last_abs_address
p2_seg_old_offset_saved:
        XCHG
        ;
        ; Change to new segment addressing mode
        ;
        SHLD        current_addr_offset
        MOV         A,B
        STA         current_addr_base_type


;//////////////////////////////////////

        ;
        ; Complete listing line and finalize pseudo-instruction handling
        ;
p2_seg_mode_change_done:
        CALL        clear_listing_line_address
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; $, change layout parameter
        ;
p2_handle_layout_change:
        ;
        ; Prepare listing line for layout change
        ;
        CALL        clear_listing_line_address
        ;
        ; Waiver long-line errors as these commands use a nonstandard structure
        ;
        LDA         current_error_nr
        SUI         LONG_LN_ERR
        JNZ         p2_layout_parse_cmd
        STA         current_error_nr


;//////////////////////////////////////

        ;
        ; Parse layout parameter change command
        ;
p2_layout_parse_cmd:
        ;
        ; Get to the start of the parameter change command
        ;
        LXI         D,input_line_buffer
p2_layout_find_cmd_start:
        LDAX        D
        INX         D
        CPI         '$'
        JNZ         p2_layout_find_cmd_start
        ;
        ; Check if this is a TITLE change
        ;
        LXI         H,p2_title_cmd_name_str
        MVI         B,5
p2_verify_title_cmd_loop:
        LDAX        D
        CMP         M
        JNZ         p2_layout_check_other_cmds
        INX         H
        INX         D
        DCR         B
        JNZ         p2_verify_title_cmd_loop
        ;
        ; Update title and immediately start a new page
        ;
        CALL        update_listing_title
        CALL        listing_start_new_page
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main

p2_layout_check_other_cmds:
        ;
        ; Check if this is the E command, eject and start a new page if so
        ;
        CPI         'E'
        PUSH        PSW
        CALL        finalize_and_print_listing_line
        POP         PSW
        CZ          listing_start_new_page
        JMP         second_pass_main


;//////////////////////////////////////

p2_title_cmd_name_str:
        DB          'TITLE'


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; DW, define data words
        ;
p2_handle_dw:
        ;
        ; Set default error if no arguments follow, waiver any earlier errors
        ;
        MVI         A,NO_EXP_ERR
        STA         current_error_nr
        ;
        ; Parse two arguments at a time, to fill out a listing line
        ;
p2_parse_next_wordvals:
        ;
        ; Get next argument value, and add to binary data for assembled object
        ;
        LHLD        instr_str_first_arg_ptr
        XCHG
        CALL        parse_word_expression
        SHLD        current_line_bin_data
        XCHG
        ;
        ; Update argument pointer and save type of first value
        ;
        SHLD        instr_str_first_arg_ptr
        STA         bin_data_word_type_flags
        ;
        ; Check for expression end flag, end parsing if so
        ;
        ANI         EXP_TP_END
        JZ          check_first_wordval
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main

check_first_wordval:
        ;
        ; Check if first expression is valid, else raise invalid expression
        ;
        LDA         bin_data_word_type_flags
        ANI         EXP_TP_ERR
        JZ          dw_err_check_done
        MVI         A,INV_EXP_ERR
        JMP         dw_first_val_done

dw_err_check_done:
        ;
        ; Clear default no-error if the first value on this line is valid
        ;
        XRA         A
dw_first_val_done:
        ;
        ; Book-keep variables that may be needed later
        ;
        STA         current_error_nr
        LHLD        current_ext_symb_nr
        SHLD        last_val_ext_symb_nr
        MVI         A,2
        STA         current_line_bin_data_len
        ;
        ; Check if there is a second expression for this listing line
        ;
        LDA         expr_next_char
        CPI         ','
        JNZ         dw_line_done
        ;
        ; Get next argument value, and add to binary data for assembled object
        ;
        LHLD        instr_str_first_arg_ptr
        XCHG
        CALL        parse_word_expression
        SHLD        current_line_bin_data + 2
        XCHG
        ;
        ; Update argument pointer and save type of second value
        ;
        SHLD        instr_str_first_arg_ptr
        STA         bin_data_word_type_flags + 2
        ;
        ; Check for expression end flag, second word has no data if so
        ;
        ANI         EXP_TP_END
        JNZ         dw_second_val_done
        ;
        ; If not, update length of pending object data to include second word
        ;
        MVI         A,4
        STA         current_line_bin_data_len
        ;
        ; Swap external symbol number slots for the two word expressions
        ;
        LHLD        current_ext_symb_nr
        PUSH        H
        LHLD        last_val_ext_symb_nr
        SHLD        current_ext_symb_nr
        POP         H
        SHLD        last_val_ext_symb_nr
        ;
        ; Raise error if any of the two expressions were invalid
        ;
        LDA         bin_data_word_type_flags + 2
        ANI         EXP_TP_END + EXP_TP_ERR
        JNZ         dw_error
dw_second_val_done:
        LDA         bin_data_word_type_flags
        ANI         EXP_TP_END + EXP_TP_ERR
        JZ          dw_line_done
dw_error:
        MVI         A,INV_EXP_ERR
        STA         current_error_nr
dw_line_done:
        ;
        ; Print listing line and check for more data to add
        ;
        CALL        finalize_and_print_listing_line
        LDA         expr_next_char
        CPI         ','
        JNZ         second_pass_main
        ;
        ; If so, start a new line to list the additional data
        ;
        CALL        flush_listing_line_buffer
        MVI         A,CR
        STA         listing_line_str_buffer + 19
        XRA         A
        STA         current_error_nr
        CALL        prepare_pass_2_outputs
        JMP         p2_parse_next_wordvals


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; DB, define data bytes
        ;
p2_handle_db:
        ;
        ; Make sure to include everything for the first listing line
        ;
        MVI         A,TRUE
        STA         db_first_listing_line_flag
        ;
        ; Waiver long-line error, since DB arguments can form a valid long line
        ;
        LDA         current_error_nr
        SUI         LONG_LN_ERR
        JNZ         p2_db_parse_args
        STA         current_error_nr


;//////////////////////////////////////

        ;
        ; Add defined data to output object from a list of expressions
        ;
p2_db_parse_args:
        ;
        ; Ready parsing byte data expressions
        ;
        CALL        init_data_byte_expr_parser
        LXI         H,current_line_bin_data
        SHLD        current_line_bin_data_ptr
p2_parse_next_byteval:
        ;
        ; Get next data byte expression value
        ;
        LHLD        instr_str_first_arg_ptr
        XCHG
        CALL        parse_data_byte_expression
        XCHG
        SHLD        instr_str_first_arg_ptr
        ;
        ; Check for valid data, raise invalid single-byte error if not
        ;
        MOV         B,A
        ANI         EXP_TP_ERR
        JZ          db_err_check_done
        MVI         A,SB_EXP_ERR
        STA         current_error_nr
        STA         expr_next_char
db_err_check_done:
        ;
        ; Start on a new line if multi-value definition is done
        ;
        MOV         A,B
        ANI         EXP_TP_END
        JNZ         db_new_listing_line
        ;
        ; Append expression byte-value to pending object data
        ;
        LHLD        current_line_bin_data_ptr
        MOV         M,E
        INX         H
        SHLD        current_line_bin_data_ptr
        LDA         current_line_bin_data_len
        INR         A
        STA         current_line_bin_data_len
        ;
        ; If pending object data is full, write to object file
        ;
        CPI         4
        JNZ         db_byte_value_added
db_new_listing_line:
        CALL        write_data_and_list_db_line
        ;
        ; Prepare for new db listing line, and reset pending data buffer
        ;
        CALL        flush_listing_line_buffer
        XRA         A
        STA         current_line_bin_data_len
        STA         current_error_nr
        STA         db_first_listing_line_flag
        CALL        prepare_pass_2_outputs
        LXI         H,current_line_bin_data
        SHLD        current_line_bin_data_ptr
        MVI         A,CR
        STA         listing_line_str_buffer + 16
db_byte_value_added:
        ;
        ; Keep going if more byte-value expressions in db
        ;
        LDA         expr_next_char
        CPI         ','
        JZ          p2_parse_next_byteval
        ;
        ; Keep going if still inside a string expression
        ;
        LDA         in_byte_string_expr_flag
        ORA         A
        JNZ         p2_parse_next_byteval
        ;
        ; Write final data to object file if there is any pending data
        ;
        LDA         current_line_bin_data_len
        ORA         A
        JZ          second_pass_main
        CALL        write_data_and_list_db_line
        JMP         second_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Wrapper to control multi-line db verbosity in the code-listing
        ;
write_data_and_list_db_line:
        ;
        ; Skip any verbose listing if primary listing device is not assigned
        ;
        LDA         primary_listing_dev_flag
        PUSH        PSW
        ORA         A
        JZ          db_verbosity_level_ready
        ;
        ; Otherwise, only force verbose listing on first line of db
        ;
        LDA         db_first_listing_line_flag
        LXI         H,db_verbose_listing_flag
        ORA         M
        STA         primary_listing_dev_flag
db_verbosity_level_ready:
        ;
        ; Write pending data and add partial db line to listing
        ;
        CALL        finalize_and_print_listing_line
        POP         PSW
        STA         primary_listing_dev_flag
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; DS, define data space
        ;
p2_handle_ds:
        ;
        ; Get number of bytes to reserve from expression
        ;
        LXI         D,instr_first_arg_buffer
        CALL        parse_word_expression
        ;
        ; Validate that it's a constant and independent value
        ;
        ANI         BASE_CSEG + BASE_DSEG + BASE_EXT + EXP_TP_END + EXP_TP_ERR
        JZ          p2_ds_len_ready
        ;
        ; Else raise invalid expression error
        ;
        MVI         A,INV_EXP_ERR
        STA         current_error_nr
        JMP         ds_done

p2_ds_len_ready:
        ;
        ; Advance offset in current segment to reserve bytes
        ;
        XCHG
        LHLD        current_addr_offset
        DAD         D
        SHLD        current_addr_offset
ds_done:
        ;
        ; List ds line in listing
        ;
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; END, end of the assembly module
        ;
p2_handle_end:
        ;
        ; Prepare to write and list end record
        ;
        CALL        clear_listing_line_address
        CALL        finalize_and_write_current_rec
        ;
        ; Check if there is an argument to the end pseudo-instruction
        ;
        LXI         D,instr_first_arg_buffer
        LDAX        D
        ORA         A
        JZ          finalize_and_print_listing_line
        ;
        ; If so, add a start-address record with argument value if valid
        ;
        CALL        parse_word_expression
        STA         output_file_record_data + 2
        ANI         EXP_TP_END + EXP_TP_ERR
        JZ          write_st_addr_to_obj_file
        ;
        ; Otherwise raise invalid expression error
        ;
        MVI         A,INV_EXP_ERR
        STA         current_error_nr
        JMP         finalize_and_print_listing_line


;//////////////////////////////////////

        ;
        ; Write start-address record to object file, then finalize listing line
        ;
write_st_addr_to_obj_file:
        SHLD        output_file_record_data + 3
        LXI         H,FIRST_BYTE*REC_ST_ADDR + SECOND_BYTE*3
        SHLD        output_file_record_data
        CALL        write_record_to_obj_file
        JMP         finalize_and_print_listing_line


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; EQU, list fixed value which was assigned to a new symbol in pass 1
        ;
p2_handle_equ:
        ;
        ; Prepare to list EQU instruction
        ;
        CALL        clear_listing_line_address
        ;
        ; Waiver label error, since EQU instructions have an unuque structure
        ;
        LDA         current_error_nr
        SUI         LBL_EXP_ERR
        JNZ         equ_get_value
        STA         current_error_nr
equ_get_value:
        ;
        ; Get EQU expression value and raise error if invalid
        ;
        LXI         D,instr_second_arg_buffer
        CALL        parse_word_expression
        ANI         EXP_TP_END + EXP_TP_ERR
        JZ          equ_list_value
        MVI         A,INV_EXP_ERR
        STA         current_error_nr
equ_list_value:
        ;
        ; List EQU with value from expression
        ;
        XCHG
        LXI         H,listing_line_str_buffer
        CALL        EDWH
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Check list of symbols that were classified in pass 1 for issues
        ;
p2_classify_symbols:
        ;
        ; Prepare code listing line for symbol list
        ;
        CALL        clear_listing_line_address
        ;
        ; Waiver long line error, since symbol lists uses a unique form
        ;
        LDA         current_error_nr
        SUI         LONG_LN_ERR
        JNZ         check_next_symb_list_name
        STA         current_error_nr
check_next_symb_list_name:
        ;
        ; Clear symbol name buffer
        ;
        LXI         H,symb_name_buffer
        MVI         B,10
clear_symb_list_name_loop:
        MVI         M,NULL
        INX         H
        DCR         B
        JNZ         clear_symb_list_name_loop
        ;
        ; Copy the next name from symbol list to symbol name buffer
        ;
        LHLD        instr_str_first_arg_ptr
        LXI         D,symb_name_buffer
        MVI         B,10
        CALL        copy_instruction_part
        ;
        ; Advance to list deliminator character following name
        ;
        MOV         A,M
        INX         H
        SHLD        instr_str_first_arg_ptr
        PUSH        PSW
        ;
        ; Look up symbol in database
        ;
        LXI         D,symb_name_buffer
        CALL        look_up_symbol
        JC          undefined_symb_err
        ;
        ; Verify that symbol is not a duplicate, and that it has a base
        ;
        MOV         A,M
        ANI         SYM_TP_DUPL
        JNZ         duplicate_symb_err
        MOV         A,M
        ANI         BASE_CSEG + BASE_DSEG + BASE_ABS + BASE_EXT
        JNZ         symbol_check_done
undefined_symb_err:
        ;
        ; Otherwise raise undefined symbol error...
        ;
        MVI         A,UND_SYM_ERR
        STA         current_error_nr
        JMP         symbol_check_done

duplicate_symb_err:
        ;
        ; ...or eventually double symbol error
        ;
        MVI         A,DBLSYMB_ERR
        STA         current_error_nr
symbol_check_done:
        ;
        ; Check if there are more symbols in the list to check
        ;
        POP         PSW
        CPI         ','
        JZ          check_next_symb_list_name
        CALL        finalize_and_print_listing_line
        JMP         second_pass_main


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main: Finalize assembly
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Finalize assembled object file and list final error/symbol summary
        ;
finalize_assembly:
        ;
        ; Write end record to object file
        ;
        LXI         H,FIRST_BYTE*REC_END + SECOND_BYTE*0
        SHLD        output_file_record_data
        CALL        write_record_to_obj_file
        ;
        ; List total number of errors
        ;
        LDA         total_error_count
        ORA         A
        JZ          final_error_report_ready
        LXI         H,final_err_report_str
        CALL        EDBH
final_error_report_ready:
        LXI         D,final_err_report_str
        XRA         A
        CALL        add_str_to_listing
        ;
        ; Also print total number of errors to console if needed
        ;
        LDA         listing_to_console_flag
        ORA         A
        JNZ         list_symb_table
        LHLD        CO_FCB
        LXI         D,final_err_report_str
        CALL        PUT
        JMP         list_symb_table


;//////////////////////////////////////

final_err_report_str:
        DB          'NO ERROR MESSAGES',CR


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; List symbol-table, but skip if not primary listing device
        ;
list_symb_table:
        LDA         primary_listing_dev_flag
        ORA         A
        JZ          listing_feedpage
        ;
        ; Determine how many names can fit per listing line
        ;
        LDA         listing_page_width
        ADI         3
        MVI         B,0
symb_per_line_div_loop:
        SUI         16
        JM          symb_per_line_ready
        INR         B
        JMP         symb_per_line_div_loop
symb_per_line_ready:
        MOV         A,B
        STA         nr_of_names_per_listing_line
        ;
        ; Prepare to list symbol table on new page
        ;
        CALL        listing_start_new_page
list_next_line_of_names:
        ;
        ; Prepare to list new line in symbol table
        ;
        CALL        flush_listing_line_buffer
        XRA         A
        STA         name_nr_in_line_count
list_next_symbol_entry:
        ;
        ; Get next symbol to list and check if at the end of the table
        ;
        CALL        get_next_symbol_alphabetically
        JC          list_current_line_and_endpage
        ;
        ; Get offset in line of where to list symbol
        ;
        LDA         name_nr_in_line_count
        ADD         A
        ADD         A
        ADD         A
        ADD         A
        ;
        ; Point to where in listing line to list symbol
        ;
        MOV         C,A
        MVI         B,000H
        LXI         H,listing_line_str_buffer
        DAD         B
        ;
        ; Check for external symbols without an associated address
        ;
        LDA         current_symbol_type
        CPI         BASE_EXT
        JNZ         list_addressed_symb_type
        ;
        ; In this case, skip the address and just include the name
        ;
        LXI         B,5
        DAD         B
        MVI         M,'X'
        JMP         listing_symbol_type_ready

        ;
        ; Check for symbol types with an associated address
        ;
list_addressed_symb_type:
        ;
        ; Add address to symbol listing line
        ;
        XCHG
        LHLD        current_symbol_addr
        XCHG
        CALL        EDWH
        INX         H
        ;
        ; Check for valid symbol types
        ;
        LDA         current_symbol_type
        ANI         BASE_CSEG + BASE_DSEG + BASE_ABS + BASE_EXT + SYM_TP_DUPL
        MOV         B,A
        MVI         M,'C'
        CPI         BASE_CSEG
        JZ          listing_symbol_type_ready
        MVI         M,'D'
        CPI         BASE_DSEG
        JZ          listing_symbol_type_ready
        MVI         M,' '
        CPI         BASE_ABS
        JZ          listing_symbol_type_ready
        ;
        ; Check for errorneous symbol types
        ;
        MVI         M,'U'
        ANI         BASE_CSEG + BASE_DSEG + BASE_ABS + BASE_EXT
        JZ          listing_symbol_type_ready
        MVI         M,'*'
        MOV         A,B
        ANI         SYM_TP_DUPL
        JNZ         listing_symbol_type_ready
        ;
        ; If invalid symbol type, mark this too
        ;
        MVI         M,'?'
listing_symbol_type_ready:
        ;
        ; List public symbols with an asterisk right at the start of the name
        ;
        INX         H
        LDA         current_symbol_type
        ANI         SYM_TP_PUB
        JZ          list_symbol_name
        MVI         M,'*'
list_symbol_name:
        ;
        ; Copy symbol name to listing line
        ;
        INX         H
        LXI         D,symb_name_buffer
        MVI         B,6
list_symbol_name_loop:
        LDAX        D
        ORA         A
        JZ          list_symbol_name_done
        MOV         M,A
        INX         D
        INX         H
        DCR         B
        JNZ         list_symbol_name_loop
list_symbol_name_done:
        ;
        ; Advance to next name and check if there's more space in listing line
        ;
        LXI         H,name_nr_in_line_count
        INR         M
        LDA         nr_of_names_per_listing_line
        CMP         M
        JNZ         list_next_symbol_entry
        ;
        ; If not, advance to the next line of the listing
        ;
        CALL        terminate_listing_line_buffer
        CALL        print_listing_line
        JMP         list_next_line_of_names


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add current line to listing and feed out the rest of the page
        ;
list_current_line_and_endpage:
        CALL        terminate_listing_line_buffer
        CALL        print_listing_line


;//////////////////////////////////////

        ;
        ; Feed out the current page of the listing without starting a new page
        ;
listing_feedpage:
        CALL        feed_rest_of_listing_page
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines: Symbol listing
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Terminate listing line string just after its last character
        ;
terminate_listing_line_buffer:
        LXI         H,listing_line_str_buffer +131
scan_for_listing_line_end_loop:
        MOV         A,M
        CPI         ' '
        JNZ         listing_line_end_found
        DCX         H
        JMP         scan_for_listing_line_end_loop

listing_line_end_found:
        INX         H
        MVI         M,CR
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get next symbol from symbols table, in alphabetical order
        ;
get_next_symbol_alphabetically:
        ;
        ; Scan from start of the symbol list for the first candidate symbol
        ;
        LHLD        symbol_buffer_start_ptr
check_next_symbol:
        ;
        ; Check for end of symbols list
        ;
        PUSH        H
        MOV         A,M
        ORA         A
        JNZ         check_symbol_state
        POP         H
        STC
        RET

check_symbol_state:
        ;
        ; Check if symbol is deleted
        ;
        CPI         SYM_ERASED
        JNZ         propose_candidate_symbol
        POP         H
        LXI         D,9
        DAD         D
        JMP         check_next_symbol


;//////////////////////////////////////

        ;
        ; Change the proposed candidate for the next symbol to the current one
        ;
propose_candidate_symbol:
        ;
        ; Copy proposed symbol name to temporary buffer
        ;
        LXI         D,symb_name_buffer
        MVI         B,6
        SHLD        symbol_candidate_ptr
get_proposed_symb_name_loop:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         B
        JNZ         get_proposed_symb_name_loop
        ;
        ; Get symbol info
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        MOV         A,M
        STA         current_symbol_type
        XCHG
        SHLD        current_symbol_addr
        ;
        ; Advance scanning pointer to the next symbol in the table
        ;
        POP         H
        LXI         D,9
        DAD         D
scan_new_symb_for_candidate:
        PUSH        H
        ;
        ; Check if there are any remaining symbols in table
        ;
        MOV         A,M
        ORA         A
        JNZ         scan_for_better_candidate
        ;
        ; If not, use candidate symbol after erasing it from the table
        ;
        LHLD        symbol_candidate_ptr
        MVI         M,SYM_ERASED
        POP         H
        RET


;//////////////////////////////////////

        ;
        ; Check remaining symbol entries for a better candidate for next name
        ;
scan_for_better_candidate:
        ;
        ; Check if next candidate is erased
        ;
        CPI         SYM_ERASED
        JNZ         evaluate_symb_for_candidate
        ;
        ; If so ...
        ;
scan_next_symb_for_candidate:
        ;
        ; ... move on to next entry
        ;
        POP         H
        LXI         D,9
        DAD         D
        JMP         scan_new_symb_for_candidate

evaluate_symb_for_candidate:
        ;
        ; Check if current name is before proposed name in the alphabet
        ;
        MVI         B,6
        LXI         D,symb_name_buffer
compare_symb_char:
        LDAX        D
        CMP         M
        JC          scan_next_symb_for_candidate
        JZ          compare_symb_next_char
        POP         H
        PUSH        H
        JMP         propose_candidate_symbol

        ;
        ; Check the next character of current scanned name
        ;
compare_symb_next_char:
        INX         H
        INX         D
        DCR         B
        JNZ         compare_symb_char
        JMP         scan_next_symb_for_candidate


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines: First pass initialization
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse extra arguments from the command line
        ;
parse_command_line_args:
        ;
        ; Point to next pending character from the console input
        ;
        LHLD        CI_FCB
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
        ;
        ; Check if there is any pending data
        ;
        MOV         A,M
        CPI         LF
        RZ
        ;
        ; If so, get all pending command-line arguments into local buffer
        ;
        LXI         D,input_line_buffer
        LHLD        CI_FCB
        CALL        GET
        JC          exit_to_tos
        LXI         D,input_line_buffer - 1
        ;
        ; Make command line arguments uppercase
        ;
        LXI         H,input_line_buffer
args_to_uppercase_loop:
        MOV         A,M
        CPI         CR
        JZ          parse_next_arg
        CPI         'a'-1
        JC          arg_char_is_uppercase
        SUI         'a' - 'A'
        MOV         M,A
arg_char_is_uppercase:
        INX         H
        JMP         args_to_uppercase_loop


;//////////////////////////////////////

        ;
        ; Parse next command line argument
        ;
parse_next_arg:
        ;
        ; Get first character in next argument
        ;
        INX         D
parse_new_arg:
        LDAX        D
        ;
        ; Check for end of command line arguments
        ;
        CPI         CR
        RZ
        ;
        ; Check for page size arguments, if
        ;
        CPI         'P'
        JNZ         check_implied_pl_arg
        ;
        ; Check for page length or width update
        ;
        INX         D
        LDAX        D
        CPI         'L'
        JZ          preset_page_length
        CPI         'W'
        JNZ         parse_new_arg
        ;
        ; Prest and lock page width, if within 64 and 132 characters inclusive
        ;
        CALL        get_to_and_parse_number
        CPI         64
        JC          parse_new_arg
        CPI         132+1
        JNC         parse_new_arg
        STA         listing_page_width
        STA         page_width_preset_flag
        JMP         parse_new_arg

check_implied_pl_arg:
        ;
        ; Check for implied preset page length
        ;
        CPI         '0'
        JC          parse_next_arg
        CPI         '9'+1
        JNC         parse_next_arg
preset_page_length:
        ;
        ; Preset and lock page length if 12 lines or more
        ;
        CALL        get_to_and_parse_number
        CPI         12
        JC          parse_new_arg
        STA         listing_page_length
        STA         page_length_preset_flag
        JMP         parse_new_arg


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines: First pass runtime
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Verify symbol name and add to database
        ;
check_and_add_symbol:
        ;
        ; Check that a symbol name is provided
        ;
        LXI         D,symb_name_buffer
        LDAX        D
        ORA         A
        RZ
        MOV         H,D
        MOV         L,E
        ;
        ; Verify that symbol name is valid, first character can't be numerical
        ;
add_symb_check_char_alpha:
        ;
        ; Check for alphabetic character
        ;
        CPI         'A'
        RC
        CPI         'Z'+1
        RNC
add_symb_check_next_char:
        ;
        ; Advance to the next character and check for end of symbol name
        ;
        INX         H
        MOV         A,M
        ORA         M
        JZ          add_symb_valid_name
        ;
        ; Check for numeric character
        ;
        CPI         '0'
        RC
        CPI         '9'+1
        JC          add_symb_check_next_char
        JMP         add_symb_check_char_alpha

add_symb_valid_name:
        ;
        ; Check if symbol already exist
        ;
        CALL        look_up_symbol
        JC          add_new_symbol
        ;
        ; If so, check if symbol belongs to an address base
        ;
        MOV         A,M
        ANI         BASE_CSEG + BASE_DSEG + BASE_ABS + BASE_EXT
        JNZ         mark_symb_duplicate
        ;
        ; If not, reclaim symbol with the current address
        ;
        LDA         current_addr_base_type
        ORA         M
        MOV         M,A
        XCHG
        LHLD        current_addr_offset
        XCHG
        DCX         H
        MOV         M,D
        DCX         H
        MOV         M,E
        RET

        ;
        ; Symbol is a duplicate
        ;
mark_symb_duplicate:
        MOV         A,M
        MOV         A,M
        ORI         SYM_TP_DUPL
        MOV         M,A
        RET


;//////////////////////////////////////

        ;
        ; Add brand new symbol to symbol table
        ;
add_new_symbol:
        ;
        ; Check if symbol table is already full
        ;
        LDA         symb_table_full_flag
        ORA         A
        RNZ
        ;
        ; Check if adding the new symbol will overfill the symbol table
        ;
        XCHG
        LHLD        symbol_buffer_end_ptr
        XCHG
        MOV         A,H
        CMP         D
        JNZ         symb_table_space_check
        MOV         A,L
        CMP         E
symb_table_space_check:
        JC          symb_table_space_ok
        ;
        ; If so, raise symbol table error and mark table as full
        ;
        MVI         A,SYMBTAB_ERR
        STA         symb_table_full_flag
        CALL        assign_error_to_src_line
        RET

symb_table_space_ok:
        ;
        ; Copy symbol name to new entry in table
        ;
        MVI         B,6
        LXI         D,symb_name_buffer
add_symb_copy_name_loop:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         add_symb_copy_name_loop
        ;
        ; Set address of new symbol entry
        ;
        XCHG
        LHLD        current_addr_offset
        XCHG
        MOV         M,E
        INX         H
        MOV         M,D
        INX         H
        LDA         current_addr_base_type
        MOV         M,A
        ;
        ; Set new end of symbols table
        ;
        INX         H
        MVI         M,NULL
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Mark a line in the source code with a particular error
        ;
assign_error_to_src_line:
        ;
        ; Check if there is space for more entries in the list
        ;
        PUSH        PSW
        LDA         nr_of_assigned_src_errors
        CPI         40
        JNZ         add_assigned_error
        POP         PSW
        RET

add_assigned_error:
        ;
        ; Increase counter of errors saved
        ;
        MOV         B,A
        INR         A
        STA         nr_of_assigned_src_errors
        MOV         A,B
        ;
        ; Point to the next free slot in the list of assigned errors
        ;
        ADD         A
        ADD         A
        MOV         C,A
        MVI         B,000H
        LXI         H,src_assigned_errors_buffer
        DAD         B
        ;
        ; Copy the current source code line number into buffer slot index
        ;
        LXI         D,source_code_line_nr_bcd
        MVI         B,3
copy_src_line_nr_loop:
        LDAX        D
        MOV         M,A
        INX         D
        INX         H
        DCR         B
        JNZ         copy_src_line_nr_loop
        ;
        ; Add assigned error nr to buffer slot value
        ;
        POP         PSW
        MOV         M,A
        ;
        ; Mark new end of list
        ;
        INX         H
        MVI         M,NULL
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines: Second pass initialization
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Go from first to second pass
        ;
end_first_pass:
        ;
        ; Prepare to reset a chain of input files on SI
        ;
        LXI         H,NULL
        PUSH        H
        LHLD        SI_FCB
reset_next_chained_file:
        ;
        ; Check if the current file is a chained file
        ;
        MOV         A,M
        CPI         6
        JNZ         reset_block_device_file
        ;
        ; Clear End of File bit from the mode in the current chained file
        ;
        INX         H               ; FCB + FCB_MODE
        MVI         A,NOT-(FM_EOF)
        ANA         M
        MOV         M,A
        ;
        ; Add the first chained file to still pending files to reset on stack
        ;
        INX         H
        MOV         E,M             ; FCB + reference to first chained file
        INX         H
        MOV         D,M
        PUSH        D
        ;
        ; Reset the second chained file recursively
        ;
        INX         H
        MOV         E,M             ; FCB + reference to second chained file
        INX         H
        MOV         D,M
        XCHG
        JMP         reset_next_chained_file

reset_block_device_file:
        ;
        ; Reset non-chained file and continue with next pending file if any
        ;
        CALL        reset_file_state
        POP         H
        MOV         A,H
        ORA         L
        JNZ         reset_next_chained_file
        ;
        ; Attempt to re-open input file for reading
        ;
        MVI         A,FM_INPUT
        LHLD        SI_FCB
        CALL        OPEN
        JC          exit_to_tos
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Reset mode of input file, by clearing appropriate file-mode flags
        ;
reset_file_state:
        INX         H
        MOV         A,M
        ANI         FM_ASSIGNED
        MVI         A,FM_BINARY + FM_NO_CLOSE
        JZ          file_mode_mask_ready
        MVI         A,FM_INPUT + FM_OUTPUT + FM_BINARY + FM_ASSIGNED + FM_NO_CLOSE
file_mode_mask_ready:
        ANA         M
        MOV         M,A
        ;
        ; Reset buffer-length of input file
        ;
        INX         H
        INX         H
        INX         H
        MVI         M,128           ; FCB + FCB_BUFLEN
        INX         H
        MVI         M,000H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set header fields of object file record datastructure
        ;
write_header_to_obj_file:
        LXI         H,FIRST_BYTE*REC_HEADER + SECOND_BYTE*4
        SHLD        output_file_record_data
        LHLD        current_cseg_head
        SHLD        output_file_record_data + 2
        LHLD        current_dseg_head
        SHLD        output_file_record_data + 4
        CALL        write_record_to_obj_file
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write records of public labels to object file
        ;
write_pub_labels_to_obj_file:
        ;
        ; Set up to write records of type public label
        ;
        LXI         H,output_file_record_data
        MVI         M,REC_PUB_LBL
        ;
        ; Prepare to scan table of symbols for public labels
        ;
        LHLD        symbol_buffer_start_ptr
symb_scan_pub_labels_loop:
        ;
        ; Check for end of symbols table
        ;
        MOV         A,M
        ORA         A
        RZ
        ;
        ; Point to type of symbol entry
        ;
        PUSH        H
        LXI         D,8
        DAD         D
        ;
        ; Check for public symbol
        ;
        MOV         A,M
        ANI         SYM_TP_PUB
        JZ          symb_scan_next_for_pub_label
        ;
        ; If so, check for not duplicate or external symbol
        ;
        MOV         A,M
        ANI         BASE_EXT + SYM_TP_DUPL
        JNZ         symb_scan_next_for_pub_label
        ;
        ; If so, check for local address base
        ;
        MOV         A,M
        ANI         BASE_CSEG + BASE_DSEG + BASE_ABS
        JZ          symb_scan_next_for_pub_label
        ;
        ; If label base is absolute, enumerate list entry as 0 in object file
        ;
        CPI         BASE_CSEG + BASE_DSEG
        JC          pub_label_rec_type_ready
        CPI         BASE_ABS
        JNZ         symb_scan_next_for_pub_label
        XRA         A
pub_label_rec_type_ready:
        STA         output_file_record_data + 2
        ;
        ; Add label address offset to public label record
        ;
        DCX         H
        MOV         D,M
        DCX         H
        MOV         E,M
        XCHG
        SHLD        output_file_record_data + 3
        ;
        ; Prepare to copy name of public label into record
        ;
        POP         H
        PUSH        H
        LXI         D,output_file_record_data + 5
        ;
        ; Set initial public record data-size
        ;
        MVI         A,3
        STA         output_file_record_data + 1
        ;
        ; Copy name into record
        ;
        MVI         B,6
pub_label_copy_name_loop:
        MOV         A,M
        ORA         A
        JZ          pub_label_rec_ready
        STAX        D
        ;
        ; Advance to next character and increase data length field of record
        ;
        INX         D
        INX         H
        LDA         output_file_record_data + 1
        INR         A
        STA         output_file_record_data + 1
        DCR         B
        JNZ         pub_label_copy_name_loop
pub_label_rec_ready:
        ;
        ; Write public label record to object file
        ;
        CALL        write_record_to_obj_file
symb_scan_next_for_pub_label:
        ;
        ; Continue scanning next symbol in symbols table
        ;
        POP         H
        LXI         D,9
        DAD         D
        JMP         symb_scan_pub_labels_loop


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write records of external labels to object file
        ;
write_ext_labels_to_obj_file:
        ;
        ; Set up to write records of type external label
        ;
        LXI         H,output_file_record_data
        MVI         M,REC_EXT_LBL
        ;
        ; Prepare to scan table of symbols for external labels
        ;
        LHLD        symbol_buffer_start_ptr
symb_scan_ext_labels_loop:
        ;
        ; Check for end of symbols table
        ;
        MOV         A,M
        ORA         A
        RZ
        ;
        ; Point to type of symbol entry
        ;
        PUSH        H
        LXI         D,8
        DAD         D
        ;
        ; Check for external symbol
        ;
        MOV         A,M
        ANI         BASE_EXT
        JZ          symb_scan_next_for_ext_label
        ;
        ; Prepare to copy name of external label into record
        ;
        POP         H
        PUSH        H
        LXI         D,output_file_record_data + 2
        ;
        ; Set initial external record data-size
        ;
        XRA         A
        STA         output_file_record_data + 1
        ;
        ; Copy name into record
        ;
        MVI         B,6
ext_label_copy_name_loop:
        MOV         A,M
        ORA         A
        JZ          ext_label_rec_ready
        STAX        D
        ;
        ; Advance to next character and increase data length field of record
        ;
        INX         D
        INX         H
        LDA         output_file_record_data + 1
        INR         A
        STA         output_file_record_data + 1
        DCR         B
        JNZ         ext_label_copy_name_loop
ext_label_rec_ready:
        ;
        ; Write external label record to object file
        ;
        CALL        write_record_to_obj_file
symb_scan_next_for_ext_label:
        ;
        ; Continue scanning next symbol in symbols table
        ;
        POP         H
        LXI         D,9
        DAD         D
        JMP         symb_scan_ext_labels_loop


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add the static portions of the page number to the listing header
        ;
place_header_page_nr_substr:
        ;
        ; Point to start of the page number substring in listing line string
        ;
        LDA         listing_page_width
        MOV         E,A
        MVI         D,000H
        LXI         H,listing_hdr_str_buffer - ((page_str_end-page_str)+3+1)
        DAD         D
        ;
        ; Copy page number descriptive substring into header string
        ;
        LXI         D,page_str
copy_page_substr_loop:
        LDAX        D
        ORA         A
        JZ          page_substr_copied
        MOV         M,A
        INX         D
        INX         H
        JMP         copy_page_substr_loop

page_substr_copied:
        ;
        ; Store pointer to page number numeral substring in listing header
        ;
        SHLD        listing_line_page_nr_offset
        LXI         D,4
        DAD         D
        MVI         M,CR
        RET


;//////////////////////////////////////

page_str:
        DB          'PAGE'
page_str_end:
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines: Second pass runtime
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Validate a particular symbol, if one has been provided
        ;
check_symbol_for_errors:
        ;
        ; If an error has already been raised, give that priority
        ;
        LDA         current_error_nr
        ORA         A
        RNZ
        ;
        ; Check if a symbol has been provided at all
        ;
        LXI         D,symb_name_buffer
        LDAX        D
        ORA         A
        RZ
        ;
        ; Validate name of symbol, first character can't be numerical
        ;
        MOV         H,D
        MOV         L,E
chk_symb_check_char_alpha:
        ;
        ; Check for alphabetic character
        ;
        CPI         'A'
        JC          chk_symb_invalid_name
        CPI         'Z'+1
        JNC         chk_symb_invalid_name
chk_symb_check_next_char:
        ;
        ; Advance to the next character and check for end of symbol name
        ;
        INX         H
        MOV         A,M
        ORA         A
        JZ          chk_symb_check_flags
        ;
        ; Check for alphabetic character
        ;
        CPI         '0'
        JC          chk_symb_invalid_name
        CPI         '9'+1
        JC          chk_symb_check_next_char
        JMP         chk_symb_check_char_alpha

        ;
        ; Raise syntax error on invalid symbol name
        ;
chk_symb_invalid_name:
        MVI         A,SYNTAX_ERR
        STA         current_error_nr
        RET


;//////////////////////////////////////

        ;
        ; Validate an eventual symbol-definition from current source-code line
        ;
chk_symb_check_flags:
        ;
        ; Get symbol data from symbol table, raise undefined error if not found
        ;
        CALL        look_up_symbol
        JNC         chk_symb_check_dupe
        MVI         A,UND_SYM_ERR
        STA         current_error_nr
        RET

chk_symb_check_dupe:
        ;
        ; Check symbol flags, raise double symbol error if marked as duplicate
        ;
        MOV         A,M
        ANI         SYM_TP_DUPL
        JZ          chk_symb_check_offset
        MVI         A,DBLSYMB_ERR
        STA         current_error_nr
        RET

chk_symb_check_offset:
        ;
        ; Check that current symbol offset matches value in table from pass 1
        ;
        DCX         H
        MOV         A,M
        DCX         H
        MOV         E,M
        LHLD        current_addr_offset
        CMP         H
        JNZ         label_expr_error
        MOV         A,E
        CMP         L
        RZ

        ;
        ; Raise label expression error if symbol offset does not match pass 1
        ;
label_expr_error:
        MVI         A,LBL_EXP_ERR
        STA         current_error_nr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Retreive any previously saved errors for current source-code line
        ;
check_line_for_assigned_errors:
        ;
        ; Check if any errors have been saved from pass 1 at all
        ;
        LDA         nr_of_assigned_src_errors
        ORA         A
        RZ
        ;
        ; Scan through list of saved errors for current line number
        ;
        LXI         H,src_assigned_errors_buffer - 4
        PUSH        H
        MOV         B,A
scan_saved_errors_loop:
        ;
        ; Point to line number of the next saved error entry in the list
        ;
        POP         H
        LXI         D,4
        DAD         D
        PUSH        H
        ;
        ; Compare the current line-number to entry in list
        ;
        LXI         D,source_code_line_nr_bcd
        MVI         C,3
check_saved_err_line_nr_loop:
        LDAX        D
        CMP         M
        JNZ         check_next_saved_err
        INX         D
        INX         H
        DCR         C
        JNZ         check_saved_err_line_nr_loop
        ;
        ; An entry for the current lne was found, recover and raise the error
        ;
        MOV         A,M
        STA         current_error_nr
        POP         H
        RET

check_next_saved_err:
        ;
        ; Advance to next saved error entry in list if not at end of list
        ;
        DCR         B
        JNZ         scan_saved_errors_loop
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prepare listing line with current offset and clear output data buffer
        ;
prepare_pass_2_outputs:
        ;
        ; Insert current address to listing line
        ;
        LHLD        current_addr_offset
        XCHG
        LXI         H,listing_line_str_buffer
        CALL        EDWH
        INX         H
        ;
        ; Mark address with the appropriate base type in listing line
        ;
        MVI         M,' '
        LDA         current_addr_base_type
        CPI         BASE_CSEG
        JNZ         add_addr_cseg_check_done
        MVI         M,'C'
add_addr_cseg_check_done:
        CPI         BASE_DSEG
        JNZ         add_addr_dseg_check_done
        MVI         M,'D'
add_addr_dseg_check_done:
        ;
        ; Clear binary data for current line
        ;
        LXI         H,current_line_bin_data
        MVI         A,9
clear_bin_data_buffer_loop:
        MVI         M,NULL
        INX         H
        DCR         A
        JNZ         clear_bin_data_buffer_loop
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear the address and binary data dump from the current listing line
        ;
clear_listing_line_address:
        LXI         H,FIRST_BYTE*SPACE + SECOND_BYTE*SPACE
        SHLD        listing_line_str_buffer
        SHLD        listing_line_str_buffer + 2
        SHLD        listing_line_str_buffer + 4
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Finalize listing line and write any reference records to object file
        ;
finalize_and_print_listing_line:
        ;
        ; Check if there's any binary data associated with the current line
        ;
        LDA         current_line_bin_data_len
        ORA         A
        JZ          listing_line_ready
        ;
        ; If so, dump binary data to listing line
        ;
        LXI         H,listing_line_str_buffer + 8
        MOV         B,A
        LXI         D,current_line_bin_data
dump_line_bin_data_loop:
        LDAX        D
        CALL        EDBH
        INX         D
        DCR         B
        JNZ         dump_line_bin_data_loop
        ;
        ; Mark type of any symbol references that may be in the current line
        ;
        LXI         H,listing_line_str_buffer + 17
        LDA         bin_data_word_type_flags
        CALL        mark_listing_ref_value_type
        LDA         bin_data_word_type_flags + 1
        CALL        mark_listing_ref_value_type
        INX         H
        LDA         bin_data_word_type_flags + 2
        CALL        mark_listing_ref_value_type
        ;
        ; Write any relevant symbol reference records to object file
        ;
        CALL        render_asm_bin_to_obj_records
listing_line_ready:
        ;
        ; Print listing line, and an error if any errors were raised
        ;
        CALL        print_listing_line
        CALL        list_error_if_any
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add relevant letter to character at HL to mark reference type from A
        ;
mark_listing_ref_value_type:
        ANI         BASE_CSEG + BASE_DSEG + BASE_EXT
        CPI         BASE_CSEG
        JNZ         lst_ref_type_cseg_check_done
        MVI         M,'C'
lst_ref_type_cseg_check_done:
        CPI         BASE_DSEG
        JNZ         lst_ref_type_dseg_check_done
        MVI         M,'D'
lst_ref_type_dseg_check_done:
        CPI         BASE_EXT
        RNZ
        MVI         M,'X'
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert current line assembled bin data to object-file records
        ;
render_asm_bin_to_obj_records:
        ;
        ; Prepare to check types of all possible word expressions on a line
        ;
        XRA         A
        STA         current_line_bin_data_index
check_bin_index_for_refs:
        ;
        ; Determine if at end of code line assembled binary data
        ;
        LDA         current_line_bin_data_index
        LXI         H,current_line_bin_data_len
        CMP         M
        RNC
        ;
        ; Get any potential word value type of current position in binary data
        ;
        MOV         C,A
        MVI         B,000H
        LXI         H,bin_data_word_type_flags
        DAD         B
        MOV         A,M
        ;
        ; Check if reference, and if internal or external
        ;
        ANI         BASE_CSEG + BASE_DSEG + BASE_EXT
        CPI         BASE_CSEG
        JZ          internal_ref_at_index
        CPI         BASE_DSEG
        JZ          internal_ref_at_index
        CPI         BASE_EXT
        JNZ         no_ref_at_index
        ;
        ; Write external reference record to object file
        ;
        CALL        write_ext_ref_to_obj_file
        JMP         done_writing_ref

internal_ref_at_index:
        ;
        ; Write internal reference record to object file
        ;
        CALL        write_int_ref_to_obj_file
done_writing_ref:
        ;
        ; Advance one word ahead in the binary data to write
        ;
        LDA         current_line_bin_data_index
        ADI         2
        STA         current_line_bin_data_index
        LHLD        current_addr_offset
        INX         H
refs_chk_advance_bin_index:
        INX         H
        SHLD        current_addr_offset
        ;
        ; Book-keep external symbol number, just in case it is needed later
        ;
        LDA         current_line_bin_data_index
        CPI         2
        JNZ         check_bin_index_for_refs
        LHLD        last_val_ext_symb_nr
        SHLD        current_ext_symb_nr
        JMP         check_bin_index_for_refs

no_ref_at_index:
        ;
        ; Add byte to data record queue
        ;
        CALL        add_byte_to_obj_data
        ;
        ; Advance one byte ahead in the binary data to write
        ;
        LDA         current_line_bin_data_index
        INR         A
        STA         current_line_bin_data_index
        LHLD        current_addr_offset
        JMP         refs_chk_advance_bin_index


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write an internal reference record to object file
        ;
write_int_ref_to_obj_file:
        ;
        ; Set up header for internal reference record
        ;
        PUSH        PSW
        CALL        finalize_and_write_current_rec
        LXI         H,FIRST_BYTE*REC_INT_REF + SECOND_BYTE*6
        SHLD        output_file_record_data
        ;
        ; If current base is absolute, enumerate as 0 in object file
        ;
        LDA         current_addr_base_type
        CPI         BASE_ABS
        JNZ         int_ref_rec_type_ready
        XRA         A
int_ref_rec_type_ready:
        STA         output_file_record_data + 2
        ;
        ; Add current address offset to internal reference record
        ;
        LHLD        current_addr_offset
        SHLD        output_file_record_data + 3
        ;
        ; Add reference base to internal reference record
        ;
        POP         PSW
        STA         output_file_record_data + 5
        ;
        ; Point to reference offset data in assembled binary data of current line
        ;
        LDA         current_line_bin_data_index
        MOV         C,A
        MVI         B,000H
        LXI         H,current_line_bin_data
        DAD         B
        ;
        ; Add reference offset to internal reference record
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        SHLD        output_file_record_data + 6
        ;
        ; Write final internal reference record to object file
        ;
        CALL        write_record_to_obj_file
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write an external reference record to object file
        ;
write_ext_ref_to_obj_file:
        ;
        ; Set up header for external reference record
        ;
        CALL        finalize_and_write_current_rec
        LXI         H,FIRST_BYTE*REC_EXT_REF + SECOND_BYTE*7
        SHLD        output_file_record_data
        ;
        ; If reference base is absolute, enumerate as 0 in object file
        ;
        LDA         current_addr_base_type
        CPI         BASE_ABS
        JNZ         ext_ref_rec_type_ready
        XRA         A
ext_ref_rec_type_ready:
        STA         output_file_record_data + 2
        ;
        ; Add current address offset to external reference record
        ;
        LHLD        current_addr_offset
        SHLD        output_file_record_data + 3
        ;
        ; Get index to external reference data in assembled binary data
        ;
        LDA         current_line_bin_data_index
        MOV         C,A
        MVI         B,000H
        ;
        ; Add appropriate previously saved external reference number to record
        ;
        LHLD        current_ext_symb_nr
        SHLD        output_file_record_data + 5
        ;
        ; Point to reference offset data in assembled binary data of current line
        ;
        LXI         H,current_line_bin_data
        DAD         B
        ;
        ; Add reference offset to external reference record
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        SHLD        output_file_record_data + 7
        ;
        ; Write final external reference record to object file
        ;
        CALL        write_record_to_obj_file
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add a byte to next data record for object file
        ;
add_byte_to_obj_data:
        ;
        ; Initialize object data record if one has not been started already
        ;
        LDA         record_content_len
        ORA         A
        JZ          init_new_data_rec
        ;
        ; Write data now if there is no more space in the record data buffer
        ;
        CPI         35
        JNC         start_next_data_rec
        ;
        ; Convert current base flag to enumerator used by object file
        ;
        LDA         current_addr_base_type
        CPI         BASE_ABS
        JNZ         ready_for_byte_base_chk
        XRA         A
ready_for_byte_base_chk:
        ;
        ; Write data now if this data has a different base
        ;
        LXI         H,current_data_rec_base_enum
        CMP         M
        JNZ         start_next_data_rec
        ;
        ; Write pending data now if this data has a different offset
        ;
        LHLD        current_addr_offset
        XCHG
        LHLD        current_data_rec_byte_offset
        MOV         A,E
        CMP         L
        JNZ         start_next_data_rec
        MOV         A,D
        CMP         H
        JNZ         start_next_data_rec


;//////////////////////////////////////

        ;
        ; Add the byte to the initialized data record
        ;
append_byte_to_data_rec:
        ;
        ; Advance current data byte offset
        ;
        INX         H
        SHLD        current_data_rec_byte_offset
        ;
        ; Increase size of data record
        ;
        LDA         record_content_len
        MOV         C,A
        MVI         B,000H
        INR         A
        STA         record_content_len
        ;
        ; Point to destination-byte in data record buffer
        ;
        LXI         H,output_file_record_data + 5
        DAD         B
        PUSH        H
        ;
        ; Get byte from assembled binary data line
        ;
        LDA         current_line_bin_data_index
        MOV         C,A
        LXI         H,current_line_bin_data
        DAD         B
        MOV         A,M
        ;
        ; Store byte that is added in record datastructure
        ;
        POP         H
        MOV         M,A
        RET


;//////////////////////////////////////

        ;
        ; Start a new data record
        ;
start_next_data_rec:
        ;
        ; Write the current data record to object file first
        ;
        CALL        finalize_and_write_current_rec
init_new_data_rec:
        ;
        ; Prepare new record type to be a data record
        ;
        MVI         A,REC_DATA
        STA         output_file_record_data
        ;
        ; If current base is absolute, enumerate as 0 in object file
        ;
        LDA         current_addr_base_type
        CPI         BASE_ABS
        JNZ         data_rec_type_ready
        XRA         A
data_rec_type_ready:
        STA         current_data_rec_base_enum
        ;
        ; Prepare new record address base and offset
        ;
        STA         output_file_record_data + 2
        LHLD        current_addr_offset
        SHLD        output_file_record_data + 3
        JMP         append_byte_to_data_rec


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set record data length and write to object file
        ;
finalize_and_write_current_rec:
        ;
        ; Check if there is any record queued at all
        ;
        LDA         record_content_len
        ORA         A
        RZ
        ;
        ; Add general address offset info to record size
        ;
        ADI         3
        STA         output_file_record_data + 1
        ;
        ; write record and flush record buffer
        ;
        CALL        write_record_to_obj_file
        XRA         A
        STA         record_content_len
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; write finalized record to object file
        ;
write_record_to_obj_file:
        ;
        ; Add general record header to record size
        ;
        LDA         output_file_record_data + 1
        ADI         2
        ;
        ; Write entire record to object file
        ;
        MOV         B,A
        LXI         D,output_file_record_data
        LHLD        SO_FCB
write_record_to_file_loop:
        LDAX        D
        CALL        OUTCHAR
        INX         D
        DCR         B
        JNZ         write_record_to_file_loop
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Look up 8-bit register from first opcode argument
        ;
look_up_first_byte_reg:
        LXI         H,instr_first_arg_buffer
        JMP         look_up_byte_reg


;//////////////////////////////////////

        ;
        ; Look up 8-bit register from second opcode argument
        ;
look_up_second_byte_reg:
        LXI         H,instr_second_arg_buffer


;//////////////////////////////////////

        ;
        ; Look up 8-bit register from string pointed to by HL
        ;
look_up_byte_reg:
        ;
        ; Find name of 8-bit register in database
        ;
        MOV         B,M
        LXI         D,byte_register_db
compare_next_byte_reg_name:
        LDAX        D
        INX         D
        INX         D
        ORA         A
        JZ          invalid_reg_err
        CMP         B
        JNZ         compare_next_byte_reg_name
        ;
        ; Verify that name is only one chatacter long
        ;
        INX         H
        MOV         A,M
        ORA         A
        JNZ         invalid_reg_err
        ;
        ; Get value from matching database entry
        ;
        DCX         D
        LDAX        D
        RET


;//////////////////////////////////////

        ;
        ; Raise invalid register error
        ;
invalid_reg_err:
        MVI         A,INC_REG_ERR
        STA         current_error_nr
        XRA         A
        RET


;//////////////////////////////////////

        ;
        ; Database of 8-bit registers
        ;
byte_register_db:
        DB          'B',000H
        DB          'C',001H
        DB          'D',002H
        DB          'E',003H
        DB          'H',004H
        DB          'L',005H
        DB          'M',006H
        DB          'A',007H
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Look up 16-bit data-pointer register operand for LDAX/STAX
        ;
look_up_data_ptr_reg:
        ;
        ; Verify that name is only one chatacter long
        ;
        LDA         instr_first_arg_buffer + 1
        ORA         A
        JNZ         invalid_reg_err
        ;
        ; Check whenever one of the compatible registers have been specified
        ;
        LDA         instr_first_arg_buffer
        CPI         'D'
        JZ          data_ptr_reg_de
        CPI         'B'
        JNZ         invalid_reg_err
        ;
        ; Return appropriate register-bitmap values for LDAX/STAX opcodes
        ;
        XRA         A
        RET

data_ptr_reg_de:
        MVI         A,010H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Look up 16-bit register from first operand, for use with PUSH/POP
        ;
look_up_word_reg_stack_op:
        LXI         H,stack_op_word_register_db
        JMP         look_up_word_reg_loop


;//////////////////////////////////////

        ;
        ; Look up 16-bit register from first operand, for non-stack opcodes
        ;
look_up_word_reg:
        LXI         H,general_word_register_db


;//////////////////////////////////////

        ;
        ; Look up 16-bit register from first operand, in db pointed to by HL
        ;
look_up_word_reg_loop:
        LXI         D,instr_first_arg_buffer
        ;
        ; Check for end of database (in case register name was not found)
        ;
        MOV         A,M
        ORA         A
        JZ          invalid_word_reg_err
        ;
        ; Compare the first character in register name
        ;
        LDAX        D
        CMP         M
        JZ          word_reg_potential_match
        ;
        ; If no match, continue checking with next database entry
        ;
        LXI         B,4
        DAD         B
        JMP         look_up_word_reg_loop

word_reg_potential_match:
        ;
        ; Get register-bitmap for potential match
        ;
        INX         H
        MOV         B,M
        ;
        ; Compare the rest of the name
        ;
compare_next_word_reg_char:
        INX         D
        LDAX        D
        INX         H
        CMP         M
        JNZ         invalid_word_reg_err
        ORA         A
        JNZ         compare_next_word_reg_char
        ;
        ; If match, return the opcode bitmap associated with register
        ;
        MOV         A,B
        RET


;//////////////////////////////////////

        ;
        ; Raise error in case invalid register name
        ;
invalid_word_reg_err:
        MVI         A,INC_REG_ERR
        STA         current_error_nr
        RET


;//////////////////////////////////////

        ;
        ; 16-bit register database for stack operations
        ;
stack_op_word_register_db:
        DB          'B',000H
        DB          NULL,NULL
        DB          'D',010H
        DB          NULL,NULL
        DB          'H',020H
        DB          NULL,NULL
        DB          'P',030H
        DB          'SW'
        DB          NULL

        ;
        ; 16-bit register database for non-stack operations
        ;
general_word_register_db:
        DB          'B',000H
        DB          NULL,NULL
        DB          'D',010H
        DB          NULL,NULL
        DB          'H',020H
        DB          NULL,NULL
        DB          'S',030H
        DB          'P',NULL
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Assert that the end of the argument has been reached
        ;
assert_argument_end:
        LDAX        D
        ORA         A
        RZ
        MVI         A,LONG_LN_ERR
        STA         current_error_nr
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines: Common for both passes
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get and prepare next source-code input line for parsing
        ;
get_next_input_file_line:
        ;
        ; Prepare variables for new line
        ;
        XRA         A
        STA         current_error_nr
        STA         no_inst_in_line_flag
        ;
        ; Get next line from source code file
        ;
        LXI         D,input_line_buffer
        LHLD        SI_FCB
        CALL        GET
        JNC         prepare_source_code_line
        ;
        ; Check for end-of-file on exception, immediately quit to TOS if not
        ;
        ORA         A
        STC
        JNZ         exit_to_tos
        ;
        ; On end-of-file, add premature end-of-file error to listing
        ;
        LXI         H,listing_line_str_buffer
        LXI         D,end_error_str
        CALL        insert_substring
        ;
        ; Inject implied end-of-file pseudo-instruction for assembler
        ;
        CALL        clear_src_line_data_buffers
        LXI         H,instr_name_buffer
        LXI         D,end_str
        CALL        insert_substring
        ;
        ; Increase error-count
        ;
        LXI         H,total_error_count
        INR         M
        RET


;//////////////////////////////////////

end_error_str:
        DB          '      ****ERROR**** END MISSING',CR,NULL
end_str:
        DB          'END',NULL


;//////////////////////////////////////

        ;
        ; Go over source-code line and convert relevant bits to uppercase
        ;
prepare_source_code_line:
        ;
        ; Make sure source-code line is properly terminated, and clear buffers
        ;
        MVI         A,CR
        STA         input_line_buffer + 80
        CALL        flush_listing_line_buffer
        CALL        clear_src_line_data_buffers
        ;
        ; Prepare source-code line for parsing
        ;
        LXI         H,input_line_buffer - 1
prepare_next_source_char:
        ;
        ; Check for line end
        ;
        INX         H
        MOV         A,M
        CPI         CR
        JZ          source_code_line_ready
        ;
        ; Make sure to leave string expressions and comments as-is
        ;
        CPI         APOSTROPHE
        JZ          scan_to_end_of_str_expr
        CPI         SEMICOLON
        JZ          source_code_line_ready
        ;
        ; Everything else is converted to uppercase
        ;
        CPI         'a' - 1
        JC          prepare_next_source_char
        SUI         'a' - 'A'
        MOV         M,A
        JMP         prepare_next_source_char

scan_to_end_of_str_expr:
        ;
        ; Check for end of string expression
        ;
        INX         H
        MOV         A,M
        CPI         APOSTROPHE
        JZ          prepare_next_source_char
        ;
        ; Check for end of line
        ;
        CPI         CR
        JNZ         scan_to_end_of_str_expr
        ;
        ; Assume implied end of string expression on line end
        ;


;//////////////////////////////////////

        ;
        ; Insert source-code line into listing line, with proper tabulation
        ;
source_code_line_ready:
        ;
        ; Prepare to copy from source-code line to listing line
        ;
        LXI         D,input_line_buffer
        LXI         H,listing_line_str_buffer + 26
        LDAX        D
        MOV         C,A
        ;
        ; Insert source code line into listing line, character by character
        ;
list_next_source_code_char:
        ;
        ; List current and advance to next character of source-code line
        ;
        LDAX        D
        INX         D
        MOV         M,A
        ;
        ; Check for end of line
        ;
        CPI         CR
        JZ          source_code_listing_ready
        ;
        ; Check for instruction-part separating whitespace
        ;
        CPI         CURR
        JZ          source_code_whitespace
        CPI         HTAB
        JNZ         list_src_advance_to_next_char
source_code_whitespace:
        ;
        ; Don't list whitespaces if line is a layout parameter change
        ;
        MOV         A,C
        CPI         '$'
        JNZ         list_src_whitespace
        MVI         A,' '
        JMP         list_src_advance_to_next_char

list_src_whitespace:
        ;
        ; Replace whitespace control chars with a space character in listing
        ;
        MVI         M,' '
        ;
        ; Tabulate between first parts of instruction
        ;
        CALL        tab_to_next_listing_pos
        JMP         list_next_source_code_char

list_src_advance_to_next_char:
        ;
        ; Ignore other control-characters entirely for the listing
        ;
        CPI         ' '
        JC          list_next_source_code_char
        ;
        ; Otherwise advance to next character in listing line
        ;
        INX         H
        JMP         list_next_source_code_char


;//////////////////////////////////////

        ;
        ; Add line number to listing
        ;
source_code_listing_ready:
        ;
        ; Increase printed source-code line number, digit 1-2
        ;
        LXI         H,source_code_line_nr_bcd
        XRA         A
        MOV         A,M
        INR         A
        DAA
        MOV         M,A
        MOV         E,A
        ;
        ; Increase printed source-code line number, digit 2-3
        ;
        MVI         A,000H
        INX         H
        ADC         M
        DAA
        MOV         M,A
        MOV         D,A
        ;
        ; Increase printed source-code line number, digit 4-5
        ;
        MVI         A,000H
        INX         H
        ADC         M
        DAA
        MOV         M,A
        ;
        ; Insert source-code line number into listing line
        ;
        LXI         H,listing_line_str_buffer + 19
        CALL        EDBH
        CALL        EDWH
        ;
        ; Clear leading zeroes from souce-code line number in listing line
        ;
        LXI         H,listing_line_str_buffer + 19
clear_line_nr_leading_zeroes_loop:
        MOV         A,M
        CPI         '0'
        JNZ         line_nr_listing_ready
        MVI         M,' '
        INX         H
        JMP         clear_line_nr_leading_zeroes_loop


;//////////////////////////////////////

        ;
        ; Divide formatted listing line into separate parts
        ;
line_nr_listing_ready:
        ;
        ; Find start of instruction in listing line
        ;
        LXI         H,listing_line_str_buffer + 25
scan_for_instr_start_loop:
        INX         H
        MOV         A,M
        CPI         ' '
        JZ          scan_for_instr_start_loop
        CPI         CR
        JZ          instr_start_not_found
        CPI         SEMICOLON
        JNZ         instr_start_found
instr_start_not_found:
        MVI         A,TRUE
        STA         no_inst_in_line_flag
        RET

instr_start_found:
        ;
        ; Copy instruction name into buffer
        ;
        LXI         H,input_line_buffer
        LXI         D,instr_name_buffer
        MVI         B,20
        CALL        copy_instruction_part
        ;
        ; Check for symbol definition
        ;
        CPI         ':'
        JNZ         instr_name_ready
        ;
        ; If so, copy the name into name buffer instead
        ;
        PUSH        H
        LXI         H,instr_name_buffer
        LXI         D,symb_name_buffer
copy_symb_def_name_loop:
        MOV         A,M
        CPI         ':'
        JZ          symb_def_name_ready
        STAX        D
        INX         H
        INX         D
        JMP         copy_symb_def_name_loop

symb_def_name_ready:
        ;
        ; Name was moved to symbol name buffer, clear instruction name buffer
        ;
        LXI         H,instr_name_buffer
        MVI         B,21
clear_symb_def_inst_loop:
        MVI         M,NULL
        INX         H
        DCR         B
        JNZ         clear_symb_def_inst_loop
        POP         H
        ;
        ; Copy eventual instruction name after symbol definition into buffer
        ;
        LXI         D,instr_name_buffer
        MVI         B,6
        CALL        copy_instruction_part
instr_name_ready:
        ;
        ; Get arguments to instruction, if any
        ;
        CALL        get_to_next_arg
        SHLD        instr_str_first_arg_ptr
        MVI         B,40
        LXI         D,instr_first_arg_buffer
        CALL        copy_instruction_part
        MVI         B,40
        LXI         D,instr_second_arg_buffer
        CALL        copy_instruction_part
        ;
        ; Expect end of instruction here (ignoring control characters)
        ;
scan_for_end_of_instr:
        MOV         A,M
        INX         H
        CPI         CR
        JZ          instr_end_found
        CPI         SEMICOLON
        JZ          instr_end_found
        CPI         ' '+1
        JC          scan_for_end_of_instr
        ;
        ; If end of instruction was not found, raise long line error
        ;
        MVI         A,LONG_LN_ERR
        STA         current_error_nr


;//////////////////////////////////////

        ;
        ; Handle the special grammar-case for EQU
        ;
instr_end_found:
        ;
        ; Check for EQU pseudo-instruction
        ;
        LXI         H,instr_first_arg_buffer
        MOV         A,M
        CPI         'E'
        RNZ
        INX         H
        MOV         A,M
        CPI         'Q'
        RNZ
        INX         H
        MOV         A,M
        CPI         'U'
        RNZ
        INX         H
        MOV         A,M
        ORA         A
        RNZ
        ;
        ; If so, the first word is a symbol name, so move to correct buffer
        ;
        LXI         H,instr_name_buffer
        LXI         D,symb_name_buffer
        MVI         B,7
move_equ_name_loop:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         B
        JNZ         move_equ_name_loop
        ;
        ; The second word is the instruction name, so move to correct buffer
        ;
        LXI         H,instr_first_arg_buffer
        LXI         D,instr_name_buffer
        MVI         B,21
move_equ_instr_loop:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         move_equ_instr_loop
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Tabulate listing to next tab stop position in listing line
        ;
tab_to_next_listing_pos:
        ;
        ; Make sure to tab at least one space
        ;
        INX         H
        ;
        ; Prepare to scan for next tab stop
        ;
        PUSH        D
        XCHG
        LXI         H,tab_stop_ptr_list
check_next_tab_stop:
        ;
        ; Check if at end of tab-stop list
        ;
        MOV         A,M
        ORA         A
        JZ          tab_done
        ;
        ; Get next tab stop pointer from list and compare with current position
        ;
        MOV         C,M
        INX         H
        MOV         A,M
        INX         H
        CMP         D
        JNZ         coarse_tab_check
        MOV         A,C
fine_tab_check:
        CMP         E
        JZ          tab_done
coarse_tab_check:
        JC          check_next_tab_stop
        ;
        ; If a tab stop is chosen, advance cursor until it matches tab stop
        ;
        INX         D
        JMP         fine_tab_check

        ;
        ; Move updated pointer into listing line back to HL
        ;
tab_done:
        XCHG
        POP         D
        RET


;//////////////////////////////////////

        ;
        ; Tab stops, represented by pointers into the listing line string
        ;
tab_stop_ptr_list:
        dw          listing_line_str_buffer + 34
        dw          listing_line_str_buffer + 41
        dw          listing_line_str_buffer + 51
        dw          NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy up to B characters of the next instruction part
        ; from substring at HL to buffer at DE
        ;
copy_instruction_part:
        ;
        ; Move cursor (HL) to the start of the current instruction part
        ;
        CALL        get_to_next_arg
        ;
        ; Prepare to map out instruction part, clear inside-string flag
        ;
        MVI         C,FALSE
        XRA         A
        STA         instr_next_char
copy_instr_part_next_char:
        ;
        ; Get next character and check if inside a string definition argument
        ;
        MOV         A,C
        ORA         A
        MOV         A,M
        JNZ         get_to_end_of_str_arg
        ;
        ; If not, check for the start of a string definition argument
        ;
        CPI         APOSTROPHE
        JNZ         copy_instr_part_check_char
        MVI         C,TRUE
        JMP         copy_next_instr_part_char

        ;
        ; Check for the end of the string definition argument
        ;
get_to_end_of_str_arg:
        CPI         CR
        JZ          copy_instr_part_done
        CPI         APOSTROPHE
        JNZ         copy_next_instr_part_char
        MVI         C,FALSE
        JMP         copy_next_instr_part_char

        ;
        ; Check for special or illegal characters outside string definitions
        ;
copy_instr_part_check_char:
        CPI         ','
        JZ          copy_instr_part_done
        CPI         SEMICOLON
        JZ          copy_instr_part_done
        CPI         ' '+1
        JNC         copy_next_instr_part_char
        CMC
        JMP         copy_instr_part_done

copy_next_instr_part_char:
        ;
        ; Check if the character count for the copy has been exhausted
        ;
        MOV         A,B
        ORA         A
        JZ          copy_instr_char_done
        ;
        ; Copy the next character of instruction part
        ;
        MOV         A,M
        STA         instr_next_char
        STAX        D
        INX         D
        DCR         B
copy_instr_char_done:
        ;
        ; Check if next character to be copied is a colon, outside of a string
        ;
        MOV         A,M
        INX         H
        CPI         ':'
        JNZ         copy_instr_part_next_char
        MOV         A,C
        ORA         A
        JNZ         copy_instr_part_next_char
        ;
        ; If so, assume label definition and treat as end of instruction part
        ;
        MVI         A,':'
        STAX        D
        RET

copy_instr_part_done:
        LDA         instr_next_char
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set up code-listing header string with a title from string at HL
        ;
update_listing_title:
        ;
        ; Check if a title has already been set earlier
        ;
        LHLD        listing_line_title_end_ptr
        MOV         A,H
        ORA         L
        JZ          find_start_of_new_title_loop
        ;
        ; If so, blank the existing title from the header string
        ;
        PUSH        D
        XCHG
        LXI         H,listing_hdr_str_buffer + 34
blank_old_title_loop:
        MVI         M,' '
        INX         H
        MOV         A,H
        CMP         D
        JNZ         blank_old_title_loop
        MOV         A,L
        CMP         E
        JNZ         blank_old_title_loop
        POP         D
find_start_of_new_title_loop:
        ;
        ; Check if a new title has been provided at all
        ;
        LDAX        D
        INX         D
        CPI         CR
        RZ
        ;
        ; Skip any other leading control characters and whitespaces
        ;
        CPI         ' '+1
        JC          find_start_of_new_title_loop
        DCX         D
        ;
        ; Copy new title, replacing control characters with spaces
        ;
        LXI         H,listing_hdr_str_buffer + 34
copy_new_title_loop:
        CPI         ' '
        JNC         new_title_char_ready
        MVI         A,' '
new_title_char_ready:
        MOV         M,A
        INX         H
        INX         D
        LDAX        D
        CPI         CR
        JNZ         copy_new_title_loop
        SHLD        listing_line_title_end_ptr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get to the next argument in a string with a list of arguments
        ;
get_to_next_arg:
        ;
        ; Skip if at the end of the string of arguments
        ;
        MOV         A,M
        CPI         CR
        RZ
        ;
        ; Check for and ignore argument deliminator
        ;
        CPI         ','
        JZ          check_for_arg_at_next_char
        ;
        ; Check for end of label definition
        ;
        CPI         SEMICOLON
        RZ
        ;
        ; Check for and ignore other control characters and whitespaces
        ;
        CPI         ' '+1
        JC          check_for_arg_at_next_char
        RET

        ;
        ; Advance to check for start of new argument at the next character
        ;
check_for_arg_at_next_char:
        INX         H
        JMP         get_to_next_arg


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Insert zero-terminated string section at DE into string at HL
        ;
insert_substring:
        ;
        ; Copy substring into string
        ;
insert_substring_loop:
        LDAX        D
        ORA         A
        RZ
        MOV         M,A
        INX         H
        INX         D
        JMP         insert_substring_loop


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Validate instruction name and look it up in the instructions database
        ;
check_and_look_up_instr:
        ;
        ; Check if an instruction name has been provided at all
        ;
        LXI         H,instr_name_buffer
        MOV         A,M
        ORA         A
        JNZ         inst_name_ready
        STC
        RET

inst_name_ready:
        ;
        ; Check for layout-change (non-instruction)
        ;
        CPI         '$'
        JNZ         look_up_inst
        MVI         A,P_INS_LAYOT * JMP_LEN
        STA         current_line_bin_data
        MVI         A,IC_PSEUDO
        RET


;//////////////////////////////////////

        ;
        ; Look up instruction in database of instructions
        ;
look_up_inst:
        LXI         D,opcode_database
scan_next_inst_db_entry:
        ;
        ; Check for the end of the instruction database
        ;
        LDAX        D
        ORA         A
        RZ
        ;
        ; Compare the first character of the instruction name
        ;
        PUSH        D
        LXI         H,instr_name_buffer
        MVI         B,5
check_instr_name_char:
        CMP         M
        JZ          check_next_instr_name_char
        ;
        ; If no match, advance to the next instruction entry in the database
        ;
        POP         D
        LXI         H,7
        DAD         D
        XCHG
        JMP         scan_next_inst_db_entry

check_next_instr_name_char:
        ;
        ; Advance to check the next character in instruction name
        ;
        INX         H
        INX         D
        LDAX        D
        DCR         B
        JNZ         check_instr_name_char
        ;
        ; If the whole name is a match, get instruction entry template and type
        ;
        MOV         B,A
        INX         D
        LDAX        D
        STA         current_line_bin_data
        MOV         A,B
        POP         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Reset any flags related to scanning byte-expressions
        ;
init_data_byte_expr_parser:
        XRA         A
        STA         in_byte_string_expr_flag
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse next single-byte expression (no multi-character strings)
        ;
parse_single_byte_expression:
        MVI         A,EXP_CL_SB
        JMP         parse_expression


;//////////////////////////////////////

        ;
        ; Parse next word-value expression
        ;
parse_word_expression:
        XRA         A
        JMP         parse_expression


;//////////////////////////////////////

        ;
        ; Parse next byte-value from expression (incl. multi-character strings)
        ;
parse_data_byte_expression:
        ;
        ; Set expression class
        ;
        MVI         A,EXP_CL_DB
        STA         parsed_expression_class
        ;
        ; Parse expression as normal if not currenlty inside a string structure
        ;
        LDA         in_byte_string_expr_flag
        ORA         A
        JZ          expr_class_ready


;//////////////////////////////////////

        ;
        ; Get the next byte-character from string
        ;
expr_type_string:
        ;
        ; Get character and advance, ignoring any earlier expression parts
        ;
        LDAX        D
        INX         D
        MOV         L,A
        MVI         H,000H
        SHLD        expression_value
        ;
        ; Mark flag, to signal
        ;
        MVI         A,BASE_ABS + EX_PRL_CONT
        STA         expression_flags
        LDAX        D
        CPI         APOSTROPHE
        JNZ         verify_final_expr_value
        ;
        ; String end, reset flags and prepare for next byte expression
        ;
        INX         D
        XRA         A
        STA         in_byte_string_expr_flag
        ;
        ; Check for another expression part, and if positive or negative
        ;
        LDAX        D
        CPI         '+'
        JZ          parse_next_expr_part
        CPI         '-'
        JZ          parse_next_expr_part
        ;
        ; Otherwise return character as-is
        ;
        JMP         verify_exp_end


;//////////////////////////////////////

parse_expression:
        STA         parsed_expression_class
expr_class_ready:
        ;
        ; Prepare expression value
        ;
        LXI         H,00000H
        SHLD        expression_value
        XRA         A
        STA         expression_flags
parse_next_expr_part:
        ;
        ; Determine sign of next part of expression
        ;
        XRA         A
        STA         negative_expr_part_flag
        LDAX        D
        CPI         '+'
        JZ          expr_sign_ready
        CPI         '-'
        JNZ         parse_expr_part_value
        STA         negative_expr_part_flag
expr_sign_ready:
        ;
        ; Advance past sign, if specified
        ;
        INX         D
        LDAX        D
parse_expr_part_value:
        ;
        ; Determine expression type
        ;
        CPI         APOSTROPHE
        JZ          expr_type_str_or_char
        CPI         '$'
        JZ          expr_type_current_addr
        CPI         '0'
        JC          verify_exp_end
        CPI         '9'+1
        JC          expr_type_number
        CPI         'A'
        JC          verify_exp_end
        CPI         'Z'+1
        JC          expr_type_symbol
verify_exp_end:
        ;
        ; Expect that expression has ended
        ;
        STA         expr_next_char
        CALL        is_instr_separator
        INX         D
        JZ          verify_final_expr_value


;//////////////////////////////////////

        ;
        ; Mark invalid expression
        ;
expr_fault:
        LDA         expression_flags
        ORI         EXP_TP_ERR
        STA         expression_flags
        ;
        ; Fush the rest of the expression
        ;
flush_expr_loop:
        LDAX        D
        CALL        is_instr_separator
        JZ          flush_expr_done
        INX         D
        JMP         flush_expr_loop

flush_expr_done:
        STA         expr_next_char
        INX         D


;//////////////////////////////////////

        ;
        ; Verify that the value is not invalid in terms of expression bit-size
        ;
verify_final_expr_value:
        LHLD        expression_value
        ;
        ; Check if word-size expression
        ;
        LDA         parsed_expression_class
        ORA         A
        JZ          parse_expr_done
        ;
        ; If not, verify that value does not exceed 255
        ;
        MOV         A,H
        ORA         A
        JNZ         byte_expr_too_big
        LDA         expression_flags
        JZ          parse_expr_done

        ;
        ; Mark invalid instruction
        ;
byte_expr_too_big:
        LDA         expression_flags
        ORI         EXP_TP_ERR
        STA         expression_flags
        JMP         parse_expr_done


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse character or string type argument
        ;
expr_type_str_or_char:
        ;
        ; Check that it is not an empty character/string expression
        ;
        INX         D
        LDAX        D
        CPI         APOSTROPHE
        JZ          expr_fault
        ;
        ; Theck if it's a byte or word type expression
        ;
        LDA         parsed_expression_class
        CPI         EXP_CL_DB
        JNZ         expr_type_character
        ;
        ; Verify there being a closing apostrophe at the end of the definition
        ;
        PUSH        D
verify_str_expr_end_loop:
        ;
        ; Verify that there are no linebreaks in the string
        ;
        LDAX        D
        INX         D
        CPI         CR
        JNZ         valid_str_expr_char
        POP         B
        DCX         D
        JMP         expr_fault

        ;
        ; Advance to next character in search for closing apostrophe
        ;
valid_str_expr_char:
        CPI         APOSTROPHE
        JNZ         verify_str_expr_end_loop
        ;
        ; If at the start of a complete string/character definition, set flag
        ;
        STA         in_byte_string_expr_flag
        POP         D
        JMP         expr_type_string


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Character type expression (either word, or non-db byte)
        ;
expr_type_character:
        ;
        ; Get the first character in character expression
        ;
        LDAX        D
        MOV         L,A
        MVI         H,000H
        ;
        ; Check for end of character expression
        ;
        INX         D
        LDAX        D
        CPI         APOSTROPHE
        JZ          word_char_expr_ready
        ;
        ; Get second character of double-character expression
        ;
        MOV         H,L
        MOV         L,A
        ;
        ; Expect an end to the character expression at this point
        ;
        INX         D
        LDAX        D
        CPI         APOSTROPHE
        JNZ         expr_fault
word_char_expr_ready:
        ;
        ; Advance to parse the next part of the expression
        ;
        INX         D
        MVI         A,BASE_ABS
        JMP         expr_part_value_and_type_ready


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Current-address type expression
        ;
expr_type_current_addr:
        LHLD        current_addr_offset
        LDA         current_addr_base_type
        INX         D
        JMP         expr_part_value_and_type_ready


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Numeral type expression (incl. decimal, hexadecimal, octal, binary)
        ;
expr_type_number:
        ;
        ; Get the last character/digit of the number
        ;
        PUSH        D
        LXI         H,0
scan_for_nr_end_loop:
        MOV         B,A
        INX         D
        LDAX        D
        CALL        is_end_of_expr_number
        JNZ         scan_for_nr_end_loop
        POP         D
        ;
        ; Check character for number type
        ;
        MOV         A,B
        CPI         'B'
        JZ          parse_binary
        CPI         'O'
        JZ          parse_octadecimal
        CPI         'Q'
        JZ          parse_octadecimal
        CPI         'H'
        JZ          parse_hexadecimal


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse decimal number expression part
        ;
parse_next_decimal_digit:
        ;
        ; Get the next digit and check for end of number
        ;
        LDAX        D
        INX         D
        CALL        is_end_of_expr_number
        JNZ         parse_decimal_digit
        DCX         D
        JMP         number_expr_part_ready


;//////////////////////////////////////

        ;
        ; Parse one digit of decimal number
        ;
parse_decimal_digit:
        ;
        ; Check for decimal number end
        ;
        CPI         'D'
        JZ          number_expr_part_ready
        ;
        ; Get binary value of ASCII digit
        ;
        PUSH        H
        LXI         H,digit_table+6
        CALL        ascii_digit_to_bin
        POP         H
        JC          expr_fault
        ;
        ; Multiply previously accumulated digits by 10
        ;
        DAD         H
        MOV         B,H
        MOV         C,L
        DAD         H
        DAD         H
        DAD         B
        ;
        ; Add new ones digit to accumulated number
        ;
        ADD         L
        MOV         L,A
        JNC         parse_next_decimal_digit
        INR         H
        JMP         parse_next_decimal_digit


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse binary number expression part
        ;
parse_binary:
        ;
        ; Check for binary number end
        ;
        LDAX        D
        INX         D
        CPI         'B'
        JZ          number_expr_part_ready
        ;
        ; Get binary value of ASCII digit
        ;
        PUSH        H
        LXI         H,digit_table+14
        CALL        ascii_digit_to_bin
        POP         H
        JC          expr_fault
        ;
        ; Multiply previously accumulated digits by 2
        ;
        DAD         H
        ;
        ; Add new ones digit to accumulated number
        ;
        ADD         L
        MOV         L,A
        JMP         parse_binary


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse octadecimal number expression part
        ;
parse_octadecimal:
        ;
        ; Check for octadecimal number end
        ;
        LDAX        D
        INX         D
        CPI         'O'
        JZ          number_expr_part_ready
        CPI         'Q'
        JZ          number_expr_part_ready
        ;
        ; Get octadecimal value of ASCII digit
        ;
        PUSH        H
        LXI         H,digit_table+8
        CALL        ascii_digit_to_bin
        POP         H
        JC          expr_fault
        ;
        ; Multiply previously accumulated digits by 8
        ;
        DAD         H
        DAD         H
        DAD         H
        ;
        ; Add new ones digit to accumulated number
        ;
        ADD         L
        MOV         L,A
        JMP         parse_octadecimal


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse hexadecimal number expression part
        ;
parse_hexadecimal:
        ;
        ; Check for hexadecimal number end
        ;
        LDAX        D
        INX         D
        CPI         'H'
        JZ          number_expr_part_ready
        ;
        ; Get hexadecimal value of ASCII digit
        ;
        PUSH        H
        LXI         H,digit_table
        CALL        ascii_digit_to_bin
        POP         H
        JC          expr_fault
        ;
        ; Multiply previously accumulated digits by 16
        ;
        DAD         H
        DAD         H
        DAD         H
        DAD         H
        ;
        ; Add new ones digit to accumulated number
        ;
        ADD         L
        MOV         L,A
        JMP         parse_hexadecimal


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse symbol expression part
        ;
expr_type_symbol:
        ;
        ; Copy name of symbol from expression part into buffer
        ;
        LXI         H,expr_symb_name_buffer
        MVI         B,6
copy_expr_symb_loop:
        ;
        ; Check if the next character is a valid in a symbol name
        ;
        LDAX        D
        CPI         '0'
        JC          expr_symb_copied
        CPI         '9'+1
        JC          expr_symb_char_ready
        CPI         'A'
        JC          expr_symb_copied
        CPI         'Z'+1
        JNC         expr_symb_copied
expr_symb_char_ready:
        ;
        ; If the relevant part of the name has been copied, ignore the rest
        ;
        MOV         A,B
        ORA         A
        JZ          expr_symb_next_char
        ;
        ; Else, copy the character of the symbol name and advance
        ;
        LDAX        D
        MOV         M,A
        INX         H
        DCR         B
expr_symb_next_char:
        INX         D
        JMP         copy_expr_symb_loop

expr_symb_copied:
        ;
        ; Pad out the rest of the symbol name with zeroes
        ;
expr_symb_padding_loop:
        MOV         A,M
        ORA         A
        JZ          expr_symb_ready
        MVI         M,NULL
        INX         H
        DCR         B
        JMP         expr_symb_padding_loop

expr_symb_ready:
        ;
        ; Look up symbol name in symbols list
        ;
        PUSH        D
        LXI         D,expr_symb_name_buffer
        CALL        look_up_symbol
        MVI         B,000H
        JNC         expr_symb_found
        POP         D
        ;
        ; If not found, raise error unless a previous error is pending
        ;
        LDA         current_error_nr
        ORA         A
        JNZ         expr_symb_error_set
        MVI         A,UND_SYM_ERR
        STA         current_error_nr
expr_symb_error_set:
        MVI         A,EXP_TP_ERR
        JMP         expr_symb_done

expr_symb_found:
        ;
        ; Get symbol offset and type from list
        ;
        MOV         A,M
        DCX         H
        MOV         D,M
        DCX         H
        MOV         E,M
        XCHG
        POP         D
        MOV         B,A
        ;
        ; Forward the base type from the symbol as expression base
        ;
        ANI         BASE_CSEG + BASE_DSEG + BASE_ABS + BASE_EXT
        JNZ         expr_symb_done
        ;
        ; Set invalid expression if symbol is baseless
        ;
        MVI         A,EXP_TP_ERR
expr_symb_done:
        ORA         B
        JMP         expr_part_value_and_type_ready


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set base of numeric expressions
        ;
number_expr_part_ready:
        ;
        ; All numeric numbers are filed as absolute numbers
        ;
        MVI         A,BASE_ABS


;//////////////////////////////////////

        ;
        ; Do final preparations for expression value part
        ;
expr_part_value_and_type_ready:
        ;
        ; Mark value as not final null-expression
        ;
        MOV         C,A
        LDA         expression_flags
        ORI         EX_PRL_CONT
        STA         expression_flags
        MOV         A,C
        ;
        ; Check if this expression part raises an invalid expression error
        ;
        ANI         EXP_TP_ERR
        JNZ         expr_fault
        LDA         expression_flags
        MOV         B,A


;//////////////////////////////////////

        ;
        ; Check base between parts if expression is in the code segment
        ;
        MOV         A,C
        ANI         BASE_CSEG
        JZ          exp_dseg_check
        MOV         A,B
        ANI         BASE_CSEG
        JZ          expr_not_cseg
        ;
        ; Verify expression part is negative if everything is from code segment
        ;
        LDA         negative_expr_part_flag
        ORA         A
        JZ          expr_fault
        ;
        ; Convert difference between two code segment offsets to absolute value
        ;
        MOV         A,B
        ANI         NOT-BASE_CSEG
        MOV         B,A
        MOV         A,C
        ANI         NOT-BASE_CSEG
        ORI         BASE_ABS
        MOV         C,A
        JMP         expr_part_base_check_done

expr_not_cseg:
        ;
        ; Allow mismatch if accumulated expression is an absolute value...
        ;
        MOV         A,B
        ANI         BASE_DSEG + BASE_EXT
        JNZ         expr_fault
        ;
        ; ...and the current expression part is positive
        ;
        LDA         negative_expr_part_flag
        ORA         A
        JNZ         expr_fault
        JMP         expr_part_base_check_done


;//////////////////////////////////////

        ;
        ; Check base between parts if expression is in the data segment
        ;
exp_dseg_check:
        MOV         A,C
        ANI         BASE_DSEG
        JZ          exp_ext_check
        MOV         A,B
        ANI         BASE_DSEG
        JZ          expr_not_dseg
        ;
        ; Verify expression part is negative if everything is from data segment
        ;
        LDA         negative_expr_part_flag
        ORA         A
        JZ          expr_fault
        ;
        ; Convert difference between two data segment offsets to absolute value
        ;
        MOV         A,B
        ANI         NOT-BASE_DSEG
        MOV         B,A
        MOV         A,C
        ANI         NOT-BASE_DSEG
        ORI         BASE_ABS
        MOV         C,A
        JMP         expr_part_base_check_done

expr_not_dseg:
        ;
        ; Allow mismatch if accumulated expression is an absolute value...
        ;
        MOV         A,B
        ANI         BASE_CSEG + BASE_EXT
        JNZ         expr_fault
        ;
        ; ...and the current expression part is positive
        ;
        LDA         negative_expr_part_flag
        ORA         A
        JNZ         expr_fault
        JMP         expr_part_base_check_done


;//////////////////////////////////////

        ;
        ; Check base between parts if expression is external
        ;
exp_ext_check:
        ;
        ; Verify that the current expression part is either not external...
        ;
        MOV         A,C
        ANI         BASE_EXT
        JZ          expr_part_base_check_done
        ;
        ; ...or if the accumulated expression is absolute
        ;
        MOV         A,B
        ANI         BASE_CSEG + BASE_DSEG + BASE_EXT
        JNZ         expr_fault


;//////////////////////////////////////

        ;
        ; Combine expression part with accumulated expression value
        ;
expr_part_base_check_done:
        ;
        ; Negate expression part if it was marked negative
        ;
        PUSH        D
        XCHG
        LDA         negative_expr_part_flag
        ORA         A
        JZ          expr_val_sign_ready
        MOV         A,D
        CMA
        MOV         D,A
        MOV         A,E
        CMA
        MOV         E,A
        INX         D
expr_val_sign_ready:
        ;
        ; Add expression part value to accumulated expression value
        ;
        LHLD        expression_value
        DAD         D
        SHLD        expression_value
        POP         D
        ;
        ; Set expression type flags, mark as not last
        ;
        MOV         A,B
        ORA         C
        ORI         EX_PRL_CONT
        STA         expression_flags
        ;
        ; Check if more parts follow to this expression
        ;
        LDAX        D
        CPI         '+'
        JZ          parse_next_expr_part
        CPI         '-'
        JZ          parse_next_expr_part
        ;
        ; Expect end of expression here
        ;
        CALL        is_instr_separator
        JNZ         expr_fault
        STA         expr_next_char
        INX         D


;//////////////////////////////////////

        ;
        ; Do final checks on expression value
        ;
parse_expr_done:
        ;
        ; Check if single-byte expression
        ;
        LDA         parsed_expression_class
        SUI         EXP_CL_SB
        JNZ         expr_done_load_flags
        ;
        ; If so, verify the final value is within the limits of a signed byte
        ;
        ORA         H
        JZ          expr_done_load_flags
        INR         A
        JZ          expr_done_load_flags
        ;
        ; Otherwise mark invalid expression
        ;
        LDA         expression_flags
        ORI         EXP_TP_ERR
        JMP         expr_done_flags_ready

        ;
        ; Expression parsing done, mark as final value unless EX_PRL_CONT set
        ;
expr_done_load_flags:
        LDA         expression_flags
expr_done_flags_ready:
        XRI         EXP_TP_END
        STA         expression_flags
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII digit in A to binary, if part of character-table at HL
        ;
ascii_digit_to_bin:
        ;
        ; Scan through table of characters to look up digit
        ;
scan_for_digit_loop:
        CMP         M
        JZ          digit_found
        INX         H
        PUSH        PSW
        MOV         A,M
        ORA         A
        JZ          digit_not_found
        POP         PSW
        JMP         scan_for_digit_loop

        ;
        ; Flag error if digit was not found
        ;
digit_not_found:
        POP         PSW
        STC
        RET

        ;
        ; Convert from ASCII hexadecimal to binary value
        ;
digit_found:
        CPI         'A'
        JC          hex_compensation_done
        SUI         'A' - ('9'+1)
hex_compensation_done:
        SUI         '0'
        RET


;//////////////////////////////////////

digit_table:
        DB          'FEDCBA9876543210',NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Returns Zero if character is an arithmetic operator
        ;
is_end_of_expr_number:
        CPI         '+'
        RZ
        CPI         '-'
        RZ


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Returns Zero if character is a separating character
        ;
is_instr_separator:
        CPI         ' '
        RZ
        CPI         SEMICOLON
        RZ
        CPI         ','
        RZ
        CPI         CR
        RZ
        CPI         CURR
        RZ
        CPI         HTAB
        RZ
        ORA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Look up symbol pointed to by DE in list of symbols
        ; HL points to symbol type byte on return
        ;
look_up_symbol:
        LXI         H,00000H
        SHLD        current_ext_symb_nr
        LHLD        symbol_buffer_start_ptr
compare_symbol:
        PUSH        D
        PUSH        H
        MVI         B,6
        ;
        ; Check for if at end of symbols list
        ;
        MOV         A,M
        ORA         A
        JZ          symbol_not_found
        ;
        ; Compare if the current symbol in the list matches
        ;
compare_symbol_loop:
        LDAX        D
        CMP         M
        JNZ         compare_next_symbol
        INX         H
        INX         D
        DCR         B
        JNZ         compare_symbol_loop
        ;
        ; Get type of found symbol from list entry
        ;
        POP         D
        POP         D
        INX         H
        INX         H
        MOV         A,M
        ;
        ; Check if external
        ;
        ANI         BASE_EXT
        JZ          symb_lookup_done
        ;
        ; If so, make sure to update external-symbol nr of symbol
        ;
        PUSH        H
        LHLD        current_ext_symb_nr
        INX         H
        SHLD        current_ext_symb_nr
        POP         H
symb_lookup_done:
        RET

compare_next_symbol:
        ;
        ; Get type of not matched symbol
        ;
        POP         H
        LXI         D,8
        DAD         D
        POP         D
        MOV         A,M
        ;
        ; Check if external
        ;
        ANI         BASE_EXT
        JZ          ready_to_comp_next_symb
        ;
        ; If so, bookkeep external-symbol count in case matched symbol is ext
        ;
        PUSH        H
        LHLD        current_ext_symb_nr
        INX         H
        SHLD        current_ext_symb_nr
        POP         H
ready_to_comp_next_symb:
        ;
        ; Advance to next symbol in list
        ;
        INX         H
        JMP         compare_symbol

symbol_not_found:
        POP         D
        POP         D
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse an ASCII decimal number, ignoring leading non-number characters
        ;
get_to_and_parse_number:
        LXI         H,0
        ;
        ; Scan for start of the next number, or line end
        ;
        LDAX        D
        CPI         CR
        JZ          parse_number_done
        CPI         '0'
        JC          not_a_digit
        CPI         '9'+1
        JC          parse_number
not_a_digit:
        INX         D
        JMP         get_to_and_parse_number


;//////////////////////////////////////

        ;
        ; Parse an ASCII decimal number
        ;
parse_number:
        ;
        ; Convert first digit from ASCII to binary
        ;
        SUI         '0'
        MOV         L,A
parse_next_digit:
        ;
        ; Advance and verify the next digit of number
        ;
        INX         D
        LDAX        D
        CPI         '0'
        JC          parse_number_done
        CPI         '9'+1
        JNC         parse_number_done
        ;
        ; Convert digit from ASCII to binary
        ;
        SUI         '0'
        ;
        ; Multiply previously held number by 10
        ;
        DAD         H
        MOV         B,H
        MOV         C,L
        DAD         H
        DAD         H
        DAD         B
        ;
        ; Add new digit of ones to number
        ;
        ADD         L
        MOV         L,A
        JNC         parse_next_digit
        INR         H
        JMP         parse_next_digit

parse_number_done:
        ;
        ; Check if the parsed number is non-zero
        ;
        MOV         A,H
        ORA         A
        MOV         A,L
        RZ
        MVI         A,TRUE_ALT
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prepare to start the first page of the code listing
        ;
init_first_listing_page:
        ;
        ; Reset page-number to zero
        ;
        LXI         H,00000H
        SHLD        page_nr_counter_bcd
        ;
        ; Blank listing header string buffer
        ;
        LXI         H,listing_hdr_str_buffer
        MVI         A,(listing_hdr_str_buffer_end-1) - listing_hdr_str_buffer
blank_header_str_loop:
        MVI         M,' '
        INX         H
        DCR         A
        JNZ         blank_header_str_loop
        MVI         M,CR
        ;
        ; Insert assembler version substring into page header string
        ;
        LXI         H,listing_hdr_str_buffer
        LXI         D,rasm_title_str
        CALL        insert_substring
        ;
        ; Prepare error string buffer
        ;
        LXI         H,listing_error_str_buffer
        LXI         D,error_str
        CALL        insert_substring
        ;
        ; Precompensate lines left on page -1, to account for a bottom margin
        ;
        MVI         A,-4
        STA         lines_left_on_page
        RET


;//////////////////////////////////////

rasm_title_str:
        DB          'TDV 2100 ASSEMBLER V.2.2',NULL,CR
error_str:
        DB          '****ERROR****: 00',CR,NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string at DE to listing, if A is FALSE or listing device is set
        ;
add_str_to_listing:
        ORA         A
        JZ          print_str_to_listing
        LDA         primary_listing_dev_flag
        ORA         A
        RZ
        JMP         print_str_to_listing


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print any eventually pending error code to code listing
        ;
list_error_if_any:
        ;
        ; Check if an error is raised
        ;
        LDA         current_error_nr
        ORA         A
        RZ
        ;
        ; Insert error number into error string and increase total error count
        ;
        LXI         H,listing_error_str_buffer + 15
        CALL        EDBH
        LXI         H,total_error_count
        INR         M
        ;
        ; Add error-string to code listing
        ;
        LXI         D,listing_error_str_buffer
        JMP         print_str_to_listing


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print listing line, with verbosity based on listing type
        ;
print_listing_line:
        ;
        ; If no listing device has been provided, only list lines with errors
        ;
        LDA         primary_listing_dev_flag
        ORA         A
        JNZ         cont_printing_listing_line
        LDA         current_error_nr
        ORA         A
        RZ
cont_printing_listing_line:
        ;
        ; Make sure to terminate listing line at page width
        ;
        LXI         D,listing_line_str_buffer
        LDA         listing_page_width
        MOV         L,A
        MVI         H,000H
        DAD         D
        MVI         M,CR


;//////////////////////////////////////

        ;
        ; Add the string at DE to listing
        ;
print_str_to_listing:
        ;
        ; Go to the next page if first page or no more lines left on page
        ;
        PUSH        D
        LDA         listing_started_flag
        ORA         A
        CZ          listing_start_new_page
        LDA         lines_left_on_page
        ORA         A
        CZ          listing_start_new_page
        POP         D
        ;
        ; Print the current listing line to listing device
        ;
        LHLD        SL_FCB
        CALL        PUT
        ;
        ; Advance lines left on page countdown
        ;
        LDA         lines_left_on_page
        DCR         A
        STA         lines_left_on_page
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Feed to the next page and print title
        ;
listing_start_new_page:
        MVI         A,TRUE
        STA         listing_started_flag
        ;
        ; Skip if listing to console
        ;
        LDA         listing_to_console_flag
        ORA         A
        RNZ
        ;
        ; Move to the next page and feed out the page top margin
        ;
        CALL        feed_rest_of_listing_page
        MVI         C,4
        CALL        feed_listing_lines
        ;
        ; Increase the page number
        ;
        LXI         H,page_nr_counter_bcd
        XRA         A
        MOV         A,M
        INR         A
        DAA
        MOV         M,A
        MOV         E,A
        MVI         A,000H
        INX         H
        ADC         M
        DAA
        MOV         M,A
        ;
        ; Update the page number numeral substring in the header string
        ;
        MOV         D,A
        LHLD        listing_line_page_nr_offset
        CALL        EDWH
        MVI         M,CR
        ;
        ; Replace leading zeroes of the page number with spaces
        ;
        LHLD        listing_line_page_nr_offset
blank_leading_zeroes_loop:
        MOV         A,M
        CPI         '0'
        JNZ         page_number_substr_ready
        MVI         M,' '
        INX         H
        JMP         blank_leading_zeroes_loop

page_number_substr_ready:
        ;
        ; Print updated header string to listing device
        ;
        LXI         D,listing_hdr_str_buffer
        LHLD        SL_FCB
        CALL        PUT
        MVI         C,1
        CALL        feed_listing_lines
        ;
        ; Reset lines left on page countdown to not include header and margins
        ;
        LDA         listing_page_length
        SUI         2 + 2*4
        STA         lines_left_on_page
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Feed the rest of the current page of the code listing
        ;
feed_rest_of_listing_page:
        ;
        ; Add bottom page margin to line-count
        ;
        LDA         lines_left_on_page
        ADI         4
        ;
        ; Skip if there's no lines to feed, else prepare for linefeeding
        ;
        ORA         A
        RZ
        MOV         C,A


;//////////////////////////////////////

        ;
        ; Linefeed listing with C additional lines
        ;
feed_listing_lines:
        ;
        ; Skip if listing to console
        ;
        LDA         listing_to_console_flag
        ORA         A
        RNZ
        ;
        ; Otherwise print linefeeds
        ;
        LHLD        SL_FCB
listing_feed_loop:
        LXI         D,newline_str
        CALL        PUT
        DCR         C
        JNZ         listing_feed_loop
        RET


;//////////////////////////////////////

newline_str:
        DB          CR


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Fill the entire source code line parsed data with null characters
        ;
clear_src_line_data_buffers:
        LXI         H,src_line_data_buffers
        MVI         A,src_line_data_buffers_end - src_line_data_buffers
clear_src_line_data_loop:
        MVI         M,NULL
        INX         H
        DCR         A
        JNZ         clear_src_line_data_loop
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Fill the entire listing line buffer with spaces
        ;
flush_listing_line_buffer:
        LXI         H,listing_line_str_buffer
        MVI         A,listing_line_str_buffer_end - listing_line_str_buffer
flush_listing_line_loop:
        MVI         M,' '
        INX         H
        DCR         A
        JNZ         flush_listing_line_loop
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Instruction database
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; All 8080-opcode and pseudo-instruction names
        ;
opcode_database:
        ;
        ; General pseudo-instruction names
        ;
        DB          'ORG',NULL,NULL
        DB          IC_PSEUDO
        DB          P_INS_ORG * JMP_LEN
        DB          'CSEG',NULL
        DB          IC_PSEUDO
        DB          P_INS_CSEG * JMP_LEN
        DB          'DSEG',NULL
        DB          IC_PSEUDO
        DB          P_INS_DSEG * JMP_LEN
        DB          'DW',NULL,NULL,NULL
        DB          IC_PSEUDO
        DB          P_INS_DW * JMP_LEN
        DB          'DB',NULL,NULL,NULL
        DB          IC_PSEUDO
        DB          P_INS_DB * JMP_LEN
        DB          'DS',NULL,NULL,NULL
        DB          IC_PSEUDO
        DB          P_INS_DS * JMP_LEN
        DB          'END',NULL,NULL
        DB          IC_PSEUDO
        DB          P_INS_END * JMP_LEN
        DB          'EQU',NULL,NULL
        DB          IC_PSEUDO
        DB          P_INS_EQU * JMP_LEN
        DB          'EXTRN'
        DB          IC_PSEUDO
        DB          P_INS_EXTRN * JMP_LEN
        DB          'PUBLI'
        DB          IC_PSEUDO
        DB          P_INS_PUBLI * JMP_LEN
        ;
        ; Opcodes without operands (1 byte)
        ;
        DB          'PCHL',NULL
        DB          IC_NO_ARGS
        PCHL
        DB          'RET',NULL,NULL
        DB          IC_NO_ARGS
        RET
        DB          'RNZ',NULL,NULL
        DB          IC_NO_ARGS
        RNZ
        DB          'RZ',NULL,NULL,NULL
        DB          IC_NO_ARGS
        RZ
        DB          'RNC',NULL,NULL
        DB          IC_NO_ARGS
        RNC
        DB          'RC',NULL,NULL,NULL
        DB          IC_NO_ARGS
        RC
        DB          'RPO',NULL,NULL
        DB          IC_NO_ARGS
        RPO
        DB          'RPE',NULL,NULL
        DB          IC_NO_ARGS
        RPE
        DB          'RP',NULL,NULL,NULL
        DB          IC_NO_ARGS
        RP
        DB          'RM',NULL,NULL,NULL
        DB          IC_NO_ARGS
        RM
        DB          'RLC',NULL,NULL
        DB          IC_NO_ARGS
        RLC
        DB          'RRC',NULL,NULL
        DB          IC_NO_ARGS
        RRC
        DB          'RAL',NULL,NULL
        DB          IC_NO_ARGS
        RAL
        DB          'RAR',NULL,NULL
        DB          IC_NO_ARGS
        RAR
        DB          'NOP',NULL,NULL
        DB          IC_NO_ARGS
        NOP
        DB          'HLT',NULL,NULL
        DB          IC_NO_ARGS
        HLT
        DB          'DI',NULL,NULL,NULL
        DB          IC_NO_ARGS
        DI
        DB          'EI',NULL,NULL,NULL
        DB          IC_NO_ARGS
        EI
        DB          'XTHL',NULL
        DB          IC_NO_ARGS
        XTHL
        DB          'SPHL',NULL
        DB          IC_NO_ARGS
        SPHL
        DB          'XCHG',NULL
        DB          IC_NO_ARGS
        XCHG
        DB          'DAA',NULL,NULL
        DB          IC_NO_ARGS
        DAA
        DB          'CMA',NULL,NULL
        DB          IC_NO_ARGS
        CMA
        DB          'STC',NULL,NULL
        DB          IC_NO_ARGS
        STC
        DB          'CMC',NULL,NULL
        DB          IC_NO_ARGS
        CMC
        ;
        ; Single 8-bit register argument opcodes (1 byte)
        ;
        DB          'INR',NULL,NULL
        DB          IC_BR_COUNT
        INR         B
        DB          'DCR',NULL,NULL
        DB          IC_BR_COUNT
        DCR         B
        DB          'ADD',NULL,NULL
        DB          IC_BR_ARITH
        ADD         B
        DB          'ADC',NULL,NULL
        DB          IC_BR_ARITH
        ADC         B
        DB          'SUB',NULL,NULL
        DB          IC_BR_ARITH
        SUB         B
        DB          'SBB',NULL,NULL
        DB          IC_BR_ARITH
        SBB         B
        DB          'ANA',NULL,NULL
        DB          IC_BR_ARITH
        ANA         B
        DB          'XRA',NULL,NULL
        DB          IC_BR_ARITH
        XRA         B
        DB          'ORA',NULL,NULL
        DB          IC_BR_ARITH
        ORA         B
        DB          'CMP',NULL,NULL
        DB          IC_BR_ARITH
        CMP         B
        ;
        ; Dual 8-bit register argument opcode (1 byte)
        ;
        DB          'MOV',NULL,NULL
        DB          IC_BR_MOVE
        MOV         B,B
        ;
        ; 16-bit register argument opcodes (1 byte)
        ;
        DB          'LDAX',NULL
        DB          IC_WR_DATA
        LDAX        B
        DB          'STAX',NULL
        DB          IC_WR_DATA
        STAX        B
        DB          'PUSH',NULL
        DB          IC_WR_STACK
        PUSH        B
        DB          'POP',NULL,NULL
        DB          IC_WR_STACK
        POP         B
        DB          'INX',NULL,NULL
        DB          IC_WR_ARITH
        INX         B
        DB          'DCX',NULL,NULL
        DB          IC_WR_ARITH
        DCX         B
        DB          'DAD',NULL,NULL
        DB          IC_WR_ARITH
        DAD         B
        ;
        ; opcodes with an enumerated argument (1 byte)
        ;
        DB          'RST',NULL,NULL
        DB          IC_N_RESET
        RST         0
        ;
        ; Immediate-byte argument opcodes (2 bytes)
        ;
        DB          'ADI',NULL,NULL
        DB          IC_BI_ARITH
        DB          0C6H
        DB          'ACI',NULL,NULL
        DB          IC_BI_ARITH
        DB          0CEH
        DB          'SUI',NULL,NULL
        DB          IC_BI_ARITH
        DB          0D6H
        DB          'SBI',NULL,NULL
        DB          IC_BI_ARITH
        DB          0DEH
        DB          'ANI',NULL,NULL
        DB          IC_BI_ARITH
        DB          0E6H
        DB          'XRI',NULL,NULL
        DB          IC_BI_ARITH
        DB          0EEH
        DB          'ORI',NULL,NULL
        DB          IC_BI_ARITH
        DB          0F6H
        DB          'CPI',NULL,NULL
        DB          IC_BI_ARITH
        DB          0FEH
        DB          'IN',NULL,NULL,NULL
        DB          IC_BI_ARITH
        DB          0DBH
        DB          'OUT',NULL,NULL
        DB          IC_BI_ARITH
        DB          0D3H
        ;
        ; 8-bit register with immediate argument opcode (2 bytes)
        ;
        DB          'MVI',NULL,NULL
        DB          IC_BI_MOVE
        DB          006H
        ;
        ; Immediate-word argument opcodes (3 bytes)
        ;
        DB          'JMP',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0C3H
        DB          'JNZ',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0C2H
        DB          'JZ',NULL,NULL,NULL
        DB          IC_WI_BRNCH
        DB          0CAH
        DB          'JNC',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0D2H
        DB          'JC',NULL,NULL,NULL
        DB          IC_WI_BRNCH
        DB          0DAH
        DB          'JPO',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0E2H
        DB          'JPE',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0EAH
        DB          'JP',NULL,NULL,NULL
        DB          IC_WI_BRNCH
        DB          0F2H
        DB          'JM',NULL,NULL,NULL
        DB          IC_WI_BRNCH
        DB          0FAH
        DB          'CALL',NULL
        DB          IC_WI_BRNCH
        DB          0CDH
        DB          'CNZ',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0C4H
        DB          'CZ',NULL,NULL,NULL
        DB          IC_WI_BRNCH
        DB          0CCH
        DB          'CNC',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0D4H
        DB          'CC',NULL,NULL,NULL
        DB          IC_WI_BRNCH
        DB          0DCH
        DB          'CPO',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0E4H
        DB          'CPE',NULL,NULL
        DB          IC_WI_BRNCH
        DB          0ECH
        DB          'CP',NULL,NULL,NULL
        DB          IC_WI_BRNCH
        DB          0F4H
        DB          'CM',NULL,NULL,NULL
        DB          IC_WI_BRNCH
        DB          0FCH
        DB          'LDA',NULL,NULL
        DB          IC_WI_BRNCH
        DB          03AH
        DB          'STA',NULL,NULL
        DB          IC_WI_BRNCH
        DB          032H
        DB          'LHLD',NULL
        DB          IC_WI_BRNCH
        DB          02AH
        DB          'SHLD',NULL
        DB          IC_WI_BRNCH
        DB          022H
        ;
        ; 16-bit register with immediate arguments opcodes (3 bytes)
        ;
        DB          'LXI',NULL,NULL
        DB          IC_WI_MOVE
        DB          001H
        DB          NULL
end_of_program:
