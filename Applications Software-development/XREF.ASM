;//////////////////////////////////////////////////////////////////////////////
;//
;//     XREF - Create cross-reference list from RASM/ASM assembly source file
;//
;//         Extra parameters:
;//
;//             [$[[PL]<pl_nr>][PW<pw_nr>]]
;//
;//                 pl_nr       Force $PL argument, page-length (64-132)
;//                 pw_nr       Force $PW argument, page-width (12-255)
;//
;//
;//         Creates a cross-reference listing from an input file containing valid
;//         assembly-code for ASM/RASM, the Tandberg TDV-2100 series Assemblers.
;//         Input-file is defined by SI, and must be set for the program to run.
;//         Output is printed to SL if set, otherwise SO if set, or CO if neither
;//         SL or SO has been given.
;//
;//         This program will print out a list of references by line number to all
;//         labels in a source code file for the ASM assembler. The list will be
;//         sorted alphabetically on labels, with each label having a paragraph of
;//         associated references. A reference marked with a # sign, indicated a
;//         label definition, whereas the rest of the line numbers listed just
;//         references the given label.
;//
;//
;//         NOTE: There is very little in the means of checking for invalid syntax
;//               in this program, and it is as such a good idea to make sure the
;//               source code actually correctly assembles in ASM/RASM before
;//               running it through XREF.
;//
;//         NOTE: This versions will try to use memory starting at 0x4000, 0x8000,
;//               or 0xC000. Should there be memory at 0x4000, the algorithm will
;//               allow for a gap if there is no memory at 0x8000 to 0xBFFF. This
;//               version does not break with 54KB of user RAM, but it will not
;//               utilize more than what a 48KB system can provide.
;//
;//
;//         Changelog:
;//
;//             1.2: Entry at 0xD000
;//
;//                 -> First version I have
;//                 -> Has a bug where only the first part of opcode is compared,
;//                    until end of word in input line. This can falsely identify
;//                    non-opcode words as opcodes.
;//                 -> Has a bug where the bottom margin will not be printed if a
;//                    paragraph of references prints over a pagebreak
;//                 -> Has a bug where it will treat the dummy stop-node of the
;//                    label-database as an active label when printing the final
;//                    report
;//                 -> Has a bug where the final page will not be fed out of the
;//                    printer all the way
;//
;//             1.4: Entry at 0xC800
;//
;//                 -> Fixes the bottom margin bug of v1.2
;//                 -> Fixes the off-by-one last label database bug from v1.2
;//                 -> Fixes the final page feed-out bug from v1.2
;//                 -> Default page length changed from 72 to 48
;//                 -> Default page width changed from 79 to 110
;//                 -> Can accept user-input numbers up to and including 65535,
;//                    instead of the limit of 255 as seen in previous versions
;//                 -> No longer ignores unexpected non-numeral characters
;//                    preceding numbers from user input
;//                 -> Adds new reserved words from RASM
;//                 -> Adds extra command line arguments
;//                 -> Adds a bug if PL is set as an extra parameter, but without
;//                    the explicit PL prefix. The most significant digit will be
;//                    incorrectly ignored in this case.
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
TRUE        EQU     -1          ; Boolean True

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
HTAB        EQU     009H        ; Horizontal tabulation
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return
CURR        EQU     018H        ; Cursor right
APOSTROPHE  EQU     027H        ; Aphostrophe
SEMICOLON   EQU     03BH        ; Semicolon

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
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer

;
; TOS Errors
;
ERROR_2E    EQU     02EH        ; IMPROPER ASSIGNMENT FORMAT


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C800H
start:
        ;
        ; Zero all uninitialized working variables
        ;
        LXI         H,variables_memory
        MVI         A,variables_memory_end - variables_memory
        CALL        clear_memory
        ;
        ; Print program title
        ;
        LXI         D,program_title_str
        LHLD        CO_FCB
        CALL        PUT


;//////////////////////////////////////

        ;
        ; Test memory at 4000H, set free-memory start if RAM found
        ;
        LXI         H,04000H
        CALL        test_memory
        JNZ         check_ram_from_8000
        SHLD        free_mem_start_addr
        ;
        ; Memory at 4000H, test memory at 8000H
        ;
        LXI         H,08000H
        CALL        test_memory
        JNZ         ram_to_7fff
        ;
        ; Memory at both 4000H & 8000H, continous ram pool from 4000H to C7FFH
        ;
ram_to_c7ff:
        ;
        ; Set free memory end to C7FFH
        ;
        MVI         A,0C7H
set_primary_ram_pool_end:
        STA         free_mem_end_addr_msb
        JMP         verify_files

check_ram_from_8000:
        ;
        ; No memory at 4000H, test memory at 8000H
        ;
        LXI         H,08000H
        CALL        test_memory
        JNZ         ram_from_c000
        ;
        ; Memory at 8000H only, continous ram pool from 8000H to C7FFH
        ;
        JMP         set_continous_ram_pool

ram_to_7fff:
        ;
        ; Memory at 4000H only; First part of split ram pool at 4000H to 7FFFH
        ;
        MVI         A,07FH
        JMP         set_primary_ram_pool_end

ram_from_c000:
        ;
        ; No extra memory, so only ram pool available is at C000H-C7FFH
        ;
        LXI         H,0C000H
set_continous_ram_pool:
        ;
        ; Use one continous block as ram pool, ending at C7FFH
        ;
        SHLD        free_mem_start_addr
        JMP         ram_to_c7ff


;//////////////////////////////////////

verify_files:
        ;
        ; Verify that input file SI is assigned
        ;
        LHLD        SI_FCB
        MOV         A,L
        ORA         H
        MVI         A,ERROR_2E
        STC
        RZ
        ;
        ; Check if output file SL is assigned
        ;
        LHLD        SL_FCB
        MOV         A,L
        ORA         H
        JNZ         check_for_cli_args
        ;
        ; If not, check if file SO is assigned instead
        ;
        LHLD        SO_FCB
        MOV         A,L
        ORA         H
        JNZ         assign_output_file
        ;
        ; If neither SL or SO is assigned, use CO as a last-resort
        ;
        LHLD        CO_FCB
assign_output_file:
        ;
        ; Swap selected output file with SL
        ;
        SHLD        SL_FCB
        LXI         H,00000H
        SHLD        SO_FCB


;//////////////////////////////////////

check_for_cli_args:
        ;
        ; Check if console input is a buffered input file
        ;
        LHLD        CI_FCB
        MOV         A,M
        CPI         4
        JNZ         main
        ;
        ; Point to last character in the console input buffer
        ;
        INX         H
        INX         H
        MOV         C,M         ; CI_FCB + FCB_BUFIDX
        INX         H
        MOV         B,M
        INX         H
        INX         H
        INX         H
        MOV         E,M         ; CI_FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        DAD         B
        ;
        ; Skip parsing command line arguments if console input buffer is empty
        ;
        MOV         A,M
        CPI         LF
        JZ          main
        ;
        ; Read out command line argument string
        ;
        LXI         D,input_line_buffer
        LHLD        CI_FCB
        CALL        GET
        RC
        ;
        ; Prepare to parse command line argument string
        ;
        LXI         H,input_line_buffer
        CALL        input_to_uppercase
        LXI         H,input_line_buffer-1
parse_next_cli_arg:
        ;
        ; Assume a deliminator character between several arguments
        ;
        INX         H
parse_cli_arg:
        ;
        ; Check for end of argument string
        ;
        MOV         A,M
        CPI         CR
        JZ          main
        ;
        ; Check if explicit page-size related argument
        ;
        CPI         'P'
        JNZ         implied_page_length_arg
        INX         H
        MOV         A,M
        CPI         'L'
        JZ          parse_page_length_arg
        CPI         'W'
        JNZ         parse_cli_arg
        INX         H
        ;
        ; Set page width from command line argument
        ;
        CALL        set_page_width
        MVI         A,TRUE
        STA         page_width_from_cli_arg_flag
        JMP         parse_cli_arg

implied_page_length_arg:
        ;
        ; Check for implied page length, without the PL prefix
        ;
        CPI         '0'
        JC          parse_next_cli_arg
        CPI         '9'+1
        JNC         parse_next_cli_arg
parse_page_length_arg:
        INX         H
        ;
        ; Set page length from command line argument
        ;
        CALL        set_page_length
        MVI         A,TRUE
        STA         page_length_from_cli_arg_flag
        JMP         parse_cli_arg


;//////////////////////////////////////////////////////////////////////////////

main:
        ;
        ; Get next line from input source-code file
        ;
        LXI         H,input_line_buffer
        SHLD        input_line_ptr
        XCHG
        LHLD        SI_FCB
        CALL        GET
        JNC         parse_input_line
        ;
        ; Check for end of file
        ;
        ORA         A
        JZ          compose_xref_report
        STC
        RET

parse_input_line:
        CALL        input_to_uppercase
        ;
        ; Advance line counter (BCD format)
        ;
        LXI         H,line_counter_bcd_nr
        XRA         A
        MOV         A,M
        INR         A
        DAA
        MOV         M,A
        INX         H
        MOV         A,M
        ACI         0
        DAA
        MOV         M,A
        ;
        ; Replace any alternative whitespace-characters with spaces
        ;
        LXI         H,whitespace_chars_list
        CALL        prepare_input_line
        ;
        ; Check if first character of line is an argument line
        ;
        CALL        get_next_char
        MOV         A,M
        CPI         '$'
        JNZ         parse_code_line


;//////////////////////////////////////

        ;
        ; Check if it is the page width argument
        ;
        LXI         D,page_width_arg_name_str
        CALL        compare_arg_name
        JNZ         check_for_page_length_arg
        ;
        ; Only update page width from source code args if not already set
        ;
        LDA         page_width_from_cli_arg_flag
        ORA         A
        JNZ         main
        SHLD        input_line_ptr
        CALL        set_page_width
        JMP         main

check_for_page_length_arg:
        ;
        ; Check if it is the page length argument
        ;
        LXI         D,page_length_arg_name_str
        CALL        compare_arg_name
        JNZ         check_for_title_arg
        ;
        ; Only update page length from source code args if not already set
        ;
        LDA         page_length_from_cli_arg_flag
        ORA         A
        JNZ         main
        SHLD        input_line_ptr
        CALL        set_page_length
        JMP         main

check_for_title_arg:
        ;
        ; Check if it is the page title argument
        ;
        LXI         D,title_arg_name_str
        CALL        compare_arg_name
        JNZ         main
        ;
        ; Copy title from argument to header string
        ;
        SHLD        input_line_ptr
        CALL        get_next_char
        LXI         D,header_str
copy_next_title_char:
        MOV         A,M
        STAX        D
        CPI         CR
        JZ          main
        INX         D
        INX         H
        JMP         copy_next_title_char


;//////////////////////////////////////

        ;
        ; Identify opcodes, and find potential label definitions and references
        ;
parse_code_line:
        ;
        ; Replace all possible gramatical deliminators with spaces
        ;
        LXI         H,deliminator_chars_list
        CALL        prepare_input_line
        ;
        ; This might be a label definition until proved otherwise, so set flag
        ;
        MVI         A,TRUE
        STA         is_label_def_flag
        JMP         parse_code_word

parse_next_code_word:
        ;
        ; Line has several words, skip past current word to next space in line
        ;
        XRA         A
        STA         is_label_def_flag
        CALL        get_next_space
parse_code_word:
        ;
        ; Check for end of line, else check if start of next word is alphabetic
        ;
        CALL        get_next_char
        CPI         CR
        JZ          main
        CPI         'A'-1
        JC          parse_next_code_word
        CPI         'Z'+1
        JNC         parse_next_code_word
        ;
        ; Check if word matches an opcode from the list
        ;
        MVI         B,88
        LXI         H,opcode_database
compare_next_opcode:
        SHLD        opcode_database_ptr
        ;
        ; Get length of opcode entry from database
        ;
        INX         H
        MVI         D,000H
        MOV         E,M
        INX         H
        XCHG
        SHLD        current_opcode_db_item_len
        ;
        ; Compare name of opcode to current word
        ;
        LHLD        input_line_ptr
compare_opcode_char:
        ;
        ; Compare current character of opcode string
        ;
        LDAX        D
        CMP         M
        JZ          compare_next_opcode_char
        ;
        ; If opcode does not match, check for end of opcode database
        ;
        DCR         B
        JZ          code_word_is_label
        ;
        ; Advance to compare with next opcode in database
        ;
        LHLD        current_opcode_db_item_len
        XCHG
        LHLD        opcode_database_ptr
        DAD         D
        JMP         compare_next_opcode

compare_next_opcode_char:
        ;
        ; Check for end of word in input string
        ;
        INX         H
        MOV         A,M
        CPI         ' '
        JZ          opcode_match_found
        ;
        ; Otherwise advance to next character of opcode to compare with
        ;
        INX         D
        JMP         compare_opcode_char

opcode_match_found:
        ;
        ; Skip to end of opcode, and clear flag as opcodes can only use labels
        ;
        SHLD        input_line_ptr
        XRA         A
        STA         is_label_def_flag
        ;
        ; Get word-count to which operand in opcode is a label reference
        ;
        LHLD        opcode_database_ptr
        MOV         A,M
opcode_skip_operands_loop:
        ;
        ; Check if at potential label reference
        ;
        ORA         A
        JZ          parse_code_word
        ;
        ; Skip next opcode operand, checking for end of line along the way
        ;
        DCR         A
        MOV         B,A
        CALL        get_next_char
        CALL        get_next_space
        CPI         CR
        JZ          main
        MOV         A,B
        JMP         opcode_skip_operands_loop


;//////////////////////////////////////

        ;
        ; Assume current word to be a label definition or label reference
        ;
code_word_is_label:
        LXI         H,label_db_linked_list_head
        SHLD        current_label_db_ptr
        ;
        ; Look for label in alphabetically sorted database of known labels
        ;
compare_next_db_label:
        ;
        ; Get next item in label database, and point to its name
        ;
        CALL        get_next_label_db_item
        JC          operation_aborted
        LXI         D,004H
        DAD         D
        ;
        ; Compare contents of xref list name with current word of input line
        ;
        XCHG
        LHLD        input_line_ptr
        MVI         C,6
        XCHG
compare_db_label_char:
        ;
        ; Compare next character of new label with label from database
        ;
        LDAX        D
        CMP         M
        JZ          compare_next_db_label_name_char
        ;
        ; Make sure to scan to alphabetically correct place to insert new item
        ;
        JC          add_new_label_to_db
        JMP         compare_next_db_label

compare_next_db_label_name_char:
        ;
        ; Check for end of label
        ;
        CPI         ' '
        JZ          label_found_in_db
        ;
        ; Otherwise advance to next character of label to compare with
        ;
        INX         H
        INX         D
        DCR         C
        JNZ         compare_db_label_char
label_found_in_db:
        ;
        ; Entry for label found in database, check if it has a reference list
        ;
        LHLD        current_label_db_ptr
        LXI         D,00CH
        DAD         D
        CALL        get_next_ref_list_entry
        JZ          operation_aborted
        JMP         add_new_label_reference

add_new_label_to_db:
        LXI         H,00000H
        SHLD        current_ref_list_head_ptr
        ;
        ; Reserve database item for new label
        ;
        MVI         B,00EH
        CALL        allocate_memory
        JC          out_of_ram
        SHLD        current_datastruct_addr
        ;
        ; Save address if this is the first item in the label database
        ;
        XCHG
        LHLD        first_label_db_item_addr
        MOV         A,L
        ORA         H
        JNZ         first_db_addr_set
        MOV         H,D
        MOV         L,E
        SHLD        first_label_db_item_addr
first_db_addr_set:
        ;
        ; Copy label name to new database entry
        ;
        LXI         H,004H
        DAD         D
        XCHG
        LHLD        input_line_ptr
        MVI         C,6
copy_char_to_label_db:
        MOV         A,M
        STAX        D
        CPI         ' '
        JNZ         copy_next_char_to_label_db
        ;
        ; Pad any remaining chars after name in new database item with spaces
        ;
copy_space_to_label_db:
        DCR         C
        JZ          insert_new_label_in_db_list
        INX         D
        STAX        D
        JMP         copy_space_to_label_db

copy_next_char_to_label_db:
        INX         H
        INX         D
        DCR         C
        JNZ         copy_char_to_label_db
        ;
        ; Name was max length of 6 characters, so force cursor to end of it
        ;
        CALL        get_next_space
        ;
        ; Chain new label database item between previous and current item
        ;
insert_new_label_in_db_list:
        ;
        ; Get address to previous item in linked list
        ;
        LHLD        previous_label_db_ptr
        MOV         B,H
        MOV         C,L
        ;
        ; Get address to current (to-be-next) item in linked list
        ;
        LHLD        current_label_db_ptr
        XCHG
        ;
        ; Get address to new (to-be-current) item that will be added to list
        ;
        LHLD        current_datastruct_addr
        ;
        ; We want to update previous item's forwards-pointer
        ;
        INX         B
        INX         B
        ;
        ; Set backwards-pointer of new item, LSB
        ;
        LDAX        D
        MOV         M,A
        ;
        ; Set appropriate backwards/forwards-pointer of existing items, LSB
        ;
        MOV         A,L
        STAX        D
        STAX        B
        ;
        ; Advance to do MSB
        ;
        INX         H
        INX         D
        INX         B
        ;
        ; Set backwards-pointer of new item, MSB
        ;
        LDAX        D
        MOV         M,A
        ;
        ; Set appropriate backwards/forwards-pointer of existing items, MSB
        ;
        DCX         H
        MOV         A,H
        STAX        D
        STAX        B
        ;
        ; Set forwards-pointer of new item
        ;
        DCX         D
        INX         H
        INX         H
        MOV         M,E
        INX         H
        MOV         M,D
        ;
        ; Make environment reflect the new item as the current item
        ;
        LHLD        current_datastruct_addr
        SHLD        current_label_db_ptr


;//////////////////////////////////////

        ;
        ; Add label-occurence to label database entry's reference list
        ;
add_new_label_reference:
        ;
        ; Reserve reference list entry for this label occurence
        ;
        MVI         B,7
        CALL        allocate_memory
        JC          out_of_ram
        SHLD        current_datastruct_addr
        XCHG
        ;
        ; Check if this is the first reference found for a new label
        ;
        LHLD        current_ref_list_head_ptr
        MOV         A,L
        ORA         H
        JZ          setup_new_reference_list
        ;
        ; If not, chain new reference list item onto old reference list head
        ;
        MOV         M,E
        INX         H
        MOV         M,D
        ;
        ; Make new reference list item the new head
        ;
        LHLD        current_label_db_ptr
        LXI         B,00CH
        DAD         B
        JMP         update_ref_list_head

setup_new_reference_list:
        ;
        ; Make sure environment reflects that a ref list now exists for label
        ;
        LHLD        current_datastruct_addr
        SHLD        current_ref_list_head_ptr
        ;
        ; Store new reference list item as tail in new label database item
        ;
        LHLD        current_label_db_ptr
        LXI         B,00AH
        DAD         B
        MOV         M,E
        INX         H
        MOV         M,D
        INX         H
update_ref_list_head:
        ;
        ; Update reference list head in label database entry
        ;
        MOV         M,E
        INX         H
        MOV         M,D
        ;
        ; Make sure next-item pointer in new reference list head is cleared
        ;
        XRA         A
        STAX        D
        INX         D
        STAX        D
        INX         D
        ;
        ; Store line number as ASCII in the reference list entry
        ;
        XRA         A
        STA         first_bcd_digit_found_flag
        LHLD        line_counter_bcd_nr
        MOV         A,H
        CALL        convert_bcd_byte_to_ascii
        MOV         A,L
        CALL        convert_bcd_byte_to_ascii
        ;
        ; Add tag to line-number if this is occurence is the label definition
        ;
        LDA         is_label_def_flag
        ORA         A
        JZ          label_is_ref_only
        MVI         A,'#'
ref_tag_char_ready:
        STAX        D
        JMP         parse_next_code_word

label_is_ref_only:
        MVI         A,' '
        JMP         ref_tag_char_ready


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Put together a final report of all labels and their references
        ;
compose_xref_report:
        ;
        ; Verify that something was added to the database at all
        ;
        LHLD        first_label_db_item_addr
        MOV         A,L
        ORA         H
        JZ          quit
        ;
        ; Start with first entry of label database, and clear pagecount
        ;
        LHLD        label_db_linked_list_head+2
        SHLD        current_label_db_ptr
        XRA         A
        STA         page_count_bcd
start_next_page:
        ;
        ; Print start of page and set up first line
        ;
        CALL        print_page_header
        CALL        get_total_nr_of_entries_in_line
print_next_label_entry:
        ;
        ; Get next label entry from database
        ;
        CALL        get_next_label_db_item
        JC          operation_aborted
        JZ          finish_page_and_quit
        INX         D
        ;
        ; Print label name
        ;
        MVI         B,6
print_next_label_char:
        LDAX        D
        CALL        print_char
        RC
        INX         D
        DCR         B
        JNZ         print_next_label_char
        MVI         A,' '
        CALL        print_char
        RC
        ;
        ; Get tail of label's reference list
        ;
        XCHG
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        ;
        ; Print references
        ;
print_next_ref_entry:
        MVI         B,5
        CALL        get_next_ref_list_entry
print_next_ref_char:
        INX         D
        LDAX        D
        CALL        print_char
        RC
        DCR         B
        JNZ         print_next_ref_char
        ;
        ; Check for end of reference list
        ;
        MOV         A,L
        ORA         H
        JZ          print_label_entry_done
        ;
        ; Check whether to print the next reference on a new line
        ;
        LXI         H,entries_left_on_line
        DCR         M
        JZ          print_on_next_line
        ;
        ; If not, pad reference print to align with entry width
        ;
        LXI         D,two_space_str
        CALL        print_str
        RC
        ;
        ; Continue printing reference-entries of label
        ;
print_ref_entry_done:
        LHLD        current_ref_list_head_ptr
        JMP         print_next_ref_entry

print_on_next_line:
        ;
        ; Reset counter for entries per line
        ;
        CALL        get_total_nr_of_entries_in_line
        ;
        ; Advance to next line and check for end of page
        ;
        LXI         H,lines_left_on_page
        DCR         M
        JNZ         next_line_ready
        ;
        ; If so, print bottom margin and new page header before continuing
        ;
        LXI         D,four_newline_str
        CALL        print_str_newline
        RC
        CALL        print_page_header
        JMP         continue_on_line_start

next_line_ready:
        ;
        ; Move print head or cursor to the next line, and print indentation
        ;
        LXI         D,newline_str
        CALL        print_str_newline
continue_on_line_start:
        RC
        LXI         D,seven_space_str
        CALL        print_str
        RC
        JMP         print_ref_entry_done

print_label_entry_done:
        ;
        ; Move to next line
        ;
        LXI         D,newline_str
        CALL        print_str_newline
        RC
        ;
        ; Reset counter for entries per line
        ;
        CALL        get_total_nr_of_entries_in_line
        ;
        ; Advance to next line and check for end of page
        ;
        LXI         H,lines_left_on_page
        DCR         M
        JNZ         print_next_label_entry
        ;
        ; Print bottom margin before eventually starting new page
        ;
        LXI         D,four_newline_str
        CALL        print_str
        RC
        ;
        ; Check for last entry in label database
        ;
        LHLD        current_label_db_ptr
        INX         H
        INX         H
        XRA         A
        ORA         M
        INX         H
        ORA         M
        JNZ         start_next_page
        JMP         quit

finish_page_and_quit:
        ;
        ; Check if there are any lines of last page to feed out of printer
        ;
        LDA         lines_left_on_page
        ORA         A
        JZ          final_page_filled
        ;
        ; Feed out remaining lines on final page
        ;
        MOV         B,A
fill_final_page_loop:
        DCR         B
        JZ          final_page_filled
        MVI         A,LF
        CALL        print_char
        RC
        JMP         fill_final_page_loop

final_page_filled:
        ;
        ; Print bottom margin at the final page of report
        ;
        LXI         D,four_newline_str
        CALL        print_str_newline
        RET

quit:
        XRA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Reserve a chunk of data in the blocks of available free memory
        ;
allocate_memory:
        PUSH        D
allocate_in_current_block:
        PUSH        PSW
        ;
        ; Get end address if we were to reserve the memory
        ;
        MOV         E,B
        MVI         D,000H
        LHLD        free_mem_start_addr
        XCHG
        DAD         D
        ;
        ; Check that the whole block to be reserved stays within free memory
        ;
        LDA         free_mem_end_addr_msb
        CMP         H
        JC          available_mem_block_full
        ;
        ; If so, shrink window of free memory according to the reservation
        ;
        SHLD        free_mem_start_addr
        XCHG
        POP         PSW
        POP         D
        ANA         A
        RET


;//////////////////////////////////////

        ;
        ; Swap available memory window if first one has filled completely up
        ;
available_mem_block_full:
        ;
        ; Check if available memory is continous or split
        ;
        CPI         0C7H
        JZ          completely_out_of_memory
        ;
        ; If split, forget about first block and start using second block
        ;
        LXI         H,0C000H
        SHLD        free_mem_start_addr
        MVI         A,0C7H
        STA         free_mem_end_addr_msb
        POP         PSW
        JMP         allocate_in_current_block

completely_out_of_memory:
        POP         PSW
        XCHG
        POP         D
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get next non-space character from currently loaded input line
        ;
get_next_char:
        LHLD        input_line_ptr
        ;
        ; Skip any spaces to get to start of next word
        ;
scan_for_char:
        MOV         A,M
        CPI         CR
        RZ
        CPI         ' '
        RNZ
        INX         H
        SHLD        input_line_ptr
        JMP         scan_for_char


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Skip any non-space character from currently loaded input line
        ;
get_next_space:
        LHLD        input_line_ptr
        ;
        ; Skip any non-space chars to get to end of current word
        ;
scan_for_space:
        MOV         A,M
        CPI         CR
        RZ
        CPI         ' '
        RZ
        INX         H
        SHLD        input_line_ptr
        JMP         scan_for_space


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII number from input line to BCD
        ;
ascii_number_to_bin:
        ;
        ; Get pointer to first digit and prepare accumulator
        ;
        SHLD        input_line_ptr
        CALL        get_next_char
        XCHG
        LXI         H,0
ascii_to_bin_loop:
        ;
        ; Get next character, and check for end of line
        ;
        LDAX        D
        CPI         CR
        JZ          end_of_number
        ;
        ; Verify that character is a numerical digit, and get digit's value
        ;
        CPI         '0'
        JC          end_of_number
        CPI         '9'+1
        JNC         end_of_number
        SUI         '0'
        ;
        ; Multiply accumulator by 10 to add new digit
        ;
        DAD         H
        MOV         B,H
        MOV         C,L
        DAD         H
        DAD         H
        DAD         B
        ADD         L
        MOV         L,A
        JNC         ascii_to_bin_next_char
        INR         H
ascii_to_bin_next_char:
        ;
        ; Advance to next digit in string
        ;
        INX         D
        JMP         ascii_to_bin_loop

end_of_number:
        ;
        ; Set returned zero-flag based on if number is greater than 256 or not
        ;
        MOV         A,H
        ORA         A
        MOV         A,L
        XCHG
        RZ
        MVI         A,TRUE
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse page width, and limit value to within the range of 64 and 132
        ;
set_page_width:
        CALL        ascii_number_to_bin
        PUSH        H
        LXI         H,page_width
        MVI         D,132
        MVI         E,64
        CALL        store_value_limit_range
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse page length, and limit value to within the range of 10 and 255
        ;
set_page_length:
        CALL        ascii_number_to_bin
        PUSH        H
        LXI         H,page_length
        MVI         D,255
        MVI         E,12
        CALL        store_value_limit_range
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert the entire input string to uppercase
        ;
input_to_uppercase:
        LXI         H,input_line_buffer
input_str_to_uppercase_loop:
        MOV         A,M
        CPI         CR
        RZ
        CPI         'a'
        JM          convert_next_input_str_char
        CPI         'z'+1
        JP          convert_next_input_str_char
        ANI         0DFH
        MOV         M,A
convert_next_input_str_char:
        INX         H
        JMP         input_str_to_uppercase_loop


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Store value in A, after applying a floor and ceiling limit in E and D
        ;
store_value_limit_range:
        ;
        ; Store ceiling first, and check if value is above this limit
        ;
        MOV         M,D
        CMP         D
        RNC
        ;
        ; If not, store floor, and check if value is below this limit
        ;
        MOV         M,E
        CMP         E
        RC
        ;
        ; If not, store value itself, as it is within bounds
        ;
        MOV         M,A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Blank out a list of chars (pointed to by HL) to ignore from input
        ;
prepare_input_line:
        ;
        ; Set up pointers
        ;
        SHLD        ignore_chars_list_ptr
        LHLD        input_line_ptr
check_input_char:
        ;
        ; Check for end-of-code conditions in line
        ;
        MOV         A,M
        CPI         CR
        JZ          cut_input_line_short
        CPI         SEMICOLON
        JNZ         prepare_code_char
cut_input_line_short:
        ;
        ; Make sure final word of line has a space at the end
        ;
        MVI         M,' '
        INX         H
        MVI         M,CR
        RET

prepare_code_char:
        ;
        ; Get back pointer to list of characters to ignore
        ;
        XCHG
        LHLD        ignore_chars_list_ptr
        XCHG
check_code_char_loop:
        ;
        ; Get entry in list of characters to ignore, and check for end of list
        ;
        LDAX        D
        ORA         A
        JZ          code_char_ok
        ;
        ; Verify that current character is not the character from the list
        ;
        CMP         M
        INX         D
        JZ          blank_problematic_char
        JMP         check_code_char_loop

blank_problematic_char:
        ;
        ; If character is the start of a string definition, blank entire string
        ;
        CPI         APOSTROPHE
        JNZ         ready_to_blank
blank_str_loop:
        MVI         M,' '
        INX         H
        MOV         A,M
        CPI         CR
        JZ          cut_input_line_short
        CPI         APOSTROPHE
        JNZ         blank_str_loop
ready_to_blank:
        MVI         M,' '
code_char_ok:
        INX         H
        JMP         check_input_char


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Compare string at HL and DE, until space in string at DE
        ;
compare_arg_name:
        LHLD        input_line_ptr
compare_memory_loop:
        LDAX        D
        CMP         M
        RNZ
        CPI         ' '
        RZ
        INX         H
        INX         D
        JMP         compare_memory_loop


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print a single character
        ;
print_char:
        PUSH        H
        LHLD        SL_FCB
        CALL        OUTCHAR
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string at DE, with newline at end
        ;
print_str_newline:
        PUSH        H
        LHLD        SL_FCB
        CALL        PUT
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string at DE, without newline at end
        ;
print_str:
        PUSH        H
        LHLD        SL_FCB
        CALL        PUTSTR
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print the header of a new page
        ;
print_page_header:
        ;
        ; Reserve top and bottom margin, as well as header lines
        ;
        LDA         page_length
        SUI         11
        STA         lines_left_on_page
        ;
        ; Get and advance page count
        ;
        LXI         H,page_count_bcd
        XRA         A
        STA         first_bcd_digit_found_flag
        ORA         M
        INR         A
        DAA
        MOV         M,A
        ;
        ; Keep page number string up to date
        ;
        LXI         D,page_number_str+5
        CALL        convert_bcd_byte_to_ascii
        ;
        ; Print top margin and start of header line
        ;
        LXI         D,four_newline_str
        CALL        print_str
        RC
        LXI         D,program_title_str
        CALL        print_str
        RC
        ;
        ; Right-align page number, pad out to give 9 characters room
        ;
        LDA         page_width
        SUI         9 + program_title_str_end - program_title_str
        MOV         B,A
pad_spaces_before_page_nr_loop:
        MVI         A,' '
        CALL        print_char
        DCR         B
        JNZ         pad_spaces_before_page_nr_loop
        ;
        ; Print page nr at end of header, then title from src code on next line
        ;
        LXI         D,page_number_str
        CALL        print_str_newline
        RC
        LXI         D,header_str
        CALL        print_str_newline
        RC
        LXI         D,newline_str
        CALL        print_str_newline
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get total number of entries that will fit on a line of set page width
        ;
get_total_nr_of_entries_in_line:
        ;
        ; Divide page width by 7 to get number of entries that will fit
        ;
        PUSH        B
        MVI         B,0
        LDA         page_width
        SUI         7
divide_page_width_by_7_loop:
        SUI         7
        INR         B
        CPI         7
        JNC         divide_page_width_by_7_loop
        MOV         A,B
        STA         entries_left_on_line
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get next label database entry from current entry at HL
        ;
get_next_label_db_item:
        ;
        ; Check if current entry is valid
        ;
        LHLD        current_label_db_ptr
        MOV         A,L
        ORA         H
        STC
        RZ
        ;
        ; Advance to next entry in database (linked list)
        ;
        SHLD        previous_label_db_ptr
        INX         H
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        SHLD        current_label_db_ptr
        ;
        ; Set zero-flag based on if at the end of the list or not
        ;
        MOV         A,L
        ORA         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get next reference list entry from current entry at HL
        ;
get_next_ref_list_entry:
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        SHLD        current_ref_list_head_ptr
        ;
        ; Set zero-flag based on if at the end of the list or not
        ;
        MOV         A,L
        ORA         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert BCD number in A into ASCII in string pointed to by DE
        ;
convert_bcd_byte_to_ascii:
        ;
        ; Convert most significant digit
        ;
        PUSH        PSW
        RRC
        RRC
        RRC
        RRC
        CALL        convert_bcd_digit_to_ascii
        POP         PSW
        ;
        ; Convert least significant digit
        ;


;//////////////////////////////////////

        ;
        ; Convert BCD digit in A into ASCII in string pointed to by DE
        ;
convert_bcd_digit_to_ascii:
        ;
        ; Convert and store digit
        ;
        ANI         00FH
        ADI         '0'
        STAX        D
        ;
        ; Check if first non-zero digit has been encountered
        ;
        LDA         first_bcd_digit_found_flag
        ORA         A
        JNZ         bcd_digit_converted
        ;
        ; Otherwise blank leading zeroes
        ;
        LDAX        D
        CPI         '0'
        JNZ         first_bcd_digit_stored
        MVI         A,' '
        STAX        D
        JMP         bcd_digit_converted

first_bcd_digit_stored:
        MVI         A,TRUE
        STA         first_bcd_digit_found_flag
bcd_digit_converted:
        INX         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Verify that memory at HL is writable
        ;
test_memory:
        ;
        ; Test writing 00H
        ;
        XRA         A
        MOV         M,A
        CMP         M
        RNZ
        ;
        ; Test writing FFH
        ;
        DCR         A
        MOV         M,A
        CMP         M
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear A bytes starting at HL
        ;
clear_memory:
        MVI         M,000H
        INX         H
        DCR         A
        RZ
        JMP         clear_memory


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Errors
;//
;//////////////////////////////////////////////////////////////////////////////

operation_aborted:
        LXI         D,operation_aborted_str
        JMP         print_and_quit


;//////////////////////////////////////

out_of_ram:
        LXI         D,out_of_ram_str


;//////////////////////////////////////

print_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

four_newline_str:
        DB          LF,LF,LF,LF,CR
program_title_str:
        DB          'TOS21 SYMBOL CROSS REFERENCE, V1.4'
program_title_str_end:
        DB          CR
page_number_str:
        DB          'PAGE 00',CR
out_of_ram_str:
        DB          'INSUFFICIENT RAM AREA AVAILABLE',CR
operation_aborted_str:
        DB          'OPERATION ABORTED',CR
seven_space_str:
        DB          '     '
two_space_str:
        DB          '  '
newline_str:
        DB          CR

page_width_arg_name_str:
        DB          '$PW '
page_length_arg_name_str:
        DB          '$PL '
title_arg_name_str:
        DB          '$TITLE '

deliminator_chars_list:
        DB          APOSTROPHE
        DB          ':'
        DB          ','
        DB          '('
        DB          ')'
        DB          '+'
        DB          '-'
        DB          '/'
        DB          '*'
whitespace_chars_list:
        DB          HTAB
        DB          CURR
        DB          NULL

page_length_from_cli_arg_flag:
        DB          FALSE
page_width_from_cli_arg_flag:
        DB          FALSE
page_length:
        DB          48
page_width:
        DB          110

variables_memory:
lines_left_on_page:
        DS          1
entries_left_on_line:
        DS          1
page_count_bcd:
        DS          1
opcode_database_ptr:
        DS          2
current_ref_list_head_ptr:
        DS          2
first_label_db_item_addr:
        DS          2
line_counter_bcd_nr:
        DS          2
free_mem_end_addr_msb:
        DS          1
is_label_def_flag:
        DS          1
first_bcd_digit_found_flag:
        DS          1
input_line_ptr:
        DS          2
current_label_db_ptr:
        DS          2
previous_label_db_ptr:
        DS          2
current_datastruct_addr:
        DS          2
free_mem_start_addr:
        DS          2
current_opcode_db_item_len:
        DS          2
ignore_chars_list_ptr:
        DS          2
variables_memory_end:

        ;
        ; Label database entries consists of 14 bytes, except for the head and
        ; tail entries that use a special data-byte in the name as identifier.
        ;
        ;   000H    2   Pointer to previous database entry
        ;   002H    2   Pointer to next database entry
        ;   004H    6   Name of label (ASCII), or special non-ASCII byte
        ;   00AH    2   Pointer to tail of reference list
        ;   00CH    2   Pointer to head of reference list
        ;
        ; A reference list entry consists of 7 bytes:
        ;
        ;   000H    2   Pointer to next list entry (null-pointer if head)
        ;   002H    4   Line number of reference (ASCII)
        ;   006H    1   Tag to mark reference type (ASCII)
        ;
label_db_linked_list_head:
        DW          00000H
        DW          label_db_linked_list_tail
        DB          000H
label_db_linked_list_tail:
        DW          label_db_linked_list_head
        DW          00000H
        DB          0FFH

        ;
        ; Op-code database-entries consists of a few bytes:
        ;
        ;   000H    1   Number of non-label operands
        ;   001H    1   Length of op-code database entry (N)
        ;   002H    N-2 Op-code pattern (ASCII)
        ;
opcode_database:
        DB          0,5,'ACI'
        DB          1,5,'ADC'
        DB          1,5,'ADD'
        DB          0,5,'ADI'
        DB          1,5,'ANA'
        DB          0,5,'ANI'
        DB          0,6,'CALL'
        DB          0,4,'CC'
        DB          0,4,'CM'
        DB          0,5,'CMA'
        DB          0,5,'CMC'
        DB          1,5,'CMP'
        DB          0,5,'CNC'
        DB          0,5,'CNZ'
        DB          0,4,'CP'
        DB          0,5,'CPE'
        DB          0,5,'CPI'
        DB          0,5,'CPO'
        DB          0,6,'CSEG'
        DB          0,4,'CZ'
        DB          0,5,'DAA'
        DB          1,5,'DAD'
        DB          0,4,'DB'
        DB          1,5,'DCR'
        DB          1,5,'DCX'
        DB          0,4,'DI'
        DB          0,4,'DS'
        DB          0,6,'DSEG'
        DB          0,4,'DW'
        DB          0,4,'EI'
        DB          0,5,'END'
        DB          0,5,'EQU'
        DB          0,7,'EXTRN'
        DB          0,5,'HLT'
        DB          0,4,'IN'
        DB          1,5,'INR'
        DB          1,5,'INX'
        DB          0,4,'JC'
        DB          0,4,'JM'
        DB          0,5,'JMP'
        DB          0,5,'JNC'
        DB          0,5,'JNZ'
        DB          0,4,'JP'
        DB          0,5,'JPE'
        DB          0,5,'JPO'
        DB          0,4,'JZ'
        DB          0,5,'LDA'
        DB          1,6,'LDAX'
        DB          0,6,'LHLD'
        DB          1,5,'LXI'
        DB          2,5,'MOV'
        DB          1,5,'MVI'
        DB          0,5,'NOP'
        DB          1,5,'ORA'
        DB          0,5,'ORG'
        DB          0,5,'ORI'
        DB          0,5,'OUT'
        DB          0,6,'PCHL'
        DB          1,5,'POP'
        DB          0,8,'PUBLIC'
        DB          1,6,'PUSH'
        DB          0,5,'RAL'
        DB          0,5,'RAR'
        DB          0,4,'RC'
        DB          0,5,'RET'
        DB          0,5,'RLC'
        DB          0,4,'RM'
        DB          0,5,'RNC'
        DB          0,5,'RNZ'
        DB          0,4,'RP'
        DB          0,5,'RPE'
        DB          0,5,'RPO'
        DB          0,5,'RRC'
        DB          1,5,'RST'
        DB          0,4,'RZ'
        DB          1,5,'SBB'
        DB          0,5,'SBI'
        DB          0,6,'SHLD'
        DB          0,6,'SPHL'
        DB          0,5,'STA'
        DB          1,6,'STAX'
        DB          0,5,'STC'
        DB          1,5,'SUB'
        DB          0,5,'SUI'
        DB          0,6,'XCHG'
        DB          1,5,'XRA'
        DB          0,5,'XRI'
        DB          0,6,'XTHL'

input_line_buffer:
        DS          132
header_str:
        DB          CR
        DS          131
