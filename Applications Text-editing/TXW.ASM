;//////////////////////////////////////////////////////////////////////////////
;//
;//     TXW - Render text with page/paragraph-layout coding
;//
;//         Parses ASCII text input from SI to render in a nicely formatted manner.
;//         The layout-setup is expected to be contained in the input text, by
;//         special format-tags that will be recognized and parsed accordingly as
;//         the input is being received. Layout-settings that can be set include
;//         for instance margins, page-lengths, headers and footings, tabulations,
;//         text-alignment, as well as having separate settings per paragraph.
;//         Using this type of formatting removes the need of manually pre-
;//         formatting the text in order to have it print nicely on a line-printer.
;//
;//         The intended way of setting up the format, is by adding formatting tags
;//         to a plaintext file. There are two kinds of tags, global-level layout
;//         and temprary paragraph-level layout. At the end of a paragraph, the
;//         layout setting will be restored to the global layout.
;//
;//         Whitespaces in the text to output are removed and re-applied according
;//         to the format layout specified.
;//
;//         Output is sent to SO or SL, whichever is assigned, otherwise the output
;//         goes to CO. Input is taken from SI, or AI may be used instead to point
;//         to a job-list file containing the names of several files to render as
;//         if all of them were a single file.
;//
;//
;//         Text inline special characters:
;//
;//             !       Immediately force linebreak
;//             >       Immediately align to next tabulation stop
;//             -       Splitting of word is possible here on word-wrap
;//             !\      Output literal ! without special function
;//             >\      Output literal > without special function
;//             -\      Output literal - without special function
;//
;//
;//             NOTE: If a - character is used with it's special function, it will
;//                   only be added to the output if the particular word-wrap word-
;//                   split it enables actually happens. Otherwise it is skipped
;//                   entirely.
;//
;//
;//         Default settings:
;//
;//             Left margin             1
;//             Right margin            80
;//             Alignment               Left
;//             Tabulation stops        1,1,1,... (None)
;//             Paragraph gap           0
;//             Page length             72
;//             First line of text      5
;//             Last line of text       68
;//             Page numbering          0,0,0,0 (None)
;//             Documment title         0,0, (None)
;//             Mode                    Formated
;//             Line prefix             No prefix
;//
;//
;//         Layout codes:
;//
;//             <scope>[<format_code>[<format_code>[<format_code>[...]]]]
;//
;//                 scope:
;//                     .       Paragraph layout change
;//                     :       Global layout change
;//
;//                 format_code:
;//                     LM<char_nr>                                 Left margin
;//                     RM<char_nr>                                 Right margin
;//                     RA                                          Right align
;//                     NA                                          Left align
;//                     TS<char_nr>[<char_nr>[<char_nr>[...]]]      Tab stops
;//                     TP<tab_nr>[,<first_tab>]                    Paragraph tab
;//                     SL<lines>                                   Paragraph gap
;//
;//                     PL<lines>                                   Page length
;//                     FL<line_nr>                                 First text line
;//                     LL<line_nr>                                 Last text line
;//                     PN<line_nr>,<char_nr>,<pn_fmt>[,<pn_start>] Page numbering
;//                     HT<line_nr>,<char_nr>,<title>               Document title
;//
;//                     UF                                          Disable layout
;//                     NP                                          Goto next page
;//                     ST<line_nr>                                 Goto line
;//
;//                         char_nr         Horizontal position, character in line
;//                         line_nr         Vertical position, line on page
;//                         first_tab       Tab number of first line in paragraph
;//                         tab_nr          Tab number of the rest of the paragraph
;//                         lines           Number of lines
;//                         pn_fmt          Page-number format
;//                         pn_start        Printed page-number of current page
;//                         title           Printed page-header title
;//
;//                         pn_fmt:
;//
;//                             Odd             Output leading zeroes
;//                             Even            Skip leading zeroes
;//
;//                             0 1             <nr>
;//                             2 3 6 7         - <nr> -
;//                             4 5             PAGE <nr>
;//                             8 9             Page <nr>
;//
;//
;//             NOTE: All layout-format lines will start a new paragraph, including
;//                   a line containing just a single colon or period.
;//
;//             NOTE: RA is recognized but not implemented.
;//
;//             NOTE: PL, FL, LL, PN and HT will only have any effect when used
;//                   under a global layout-type format code. Likewise, UF, NP, ST,
;//                   EP and SP will only have an effect under the paragraph
;//                   layout-type code.
;//
;//             NOTE: Unreasonable parameter values are not checked, so it is fully
;//                   possible to set up the layout in a way that does not produce
;//                   any useful output. Values are interpreted as 0-255, and in
;//                   most cases the value of 0 will disable a feature.
;//
;//             NOTE: All non-alphanumeric characters may be used as deliminers,
;//                   and the format codes are not case sensitive. There may also
;//                   be deliminers between the code itself and the next parameter.
;//
;//
;//         Batch-file line:
;//
;//             [:<Tn>:]<filename>
;//
;//                 filename    Name of input file target
;//
;//                 Drive type T:
;//                     A       Floppy (IBM 3740, ASCII)
;//                     B       Floppy (IBM 3740, ASCII)
;//                     F       Floppy (Intel ISIS)
;//                     I       Floppy (IBM 3740, EBCDIC)
;//                     J       Floppy (IBM 3740, EBCDIC)
;//                     M       Tape
;//
;//
;//         Changelog:
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where if console output is selected, the screen
;//                    will only wait for the user after the first full screen of
;//                    output data
;//                 -> Right-alignment is recognized, but does not have any effect
;//                    on the output
;//
;//             1.6: Entry at 0xC000
;//
;//                 -> Version ID written to 0x2700
;//                 -> Adds use of the AL device file for batch-file input
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Flag values
;
TRUE        EQU     1           ; Boolean True

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
CR          EQU     00DH        ; Cartridge Return
ERPAG       EQU     019H        ; Clear screen

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
OPEN        EQU     0FD1EH      ; Open block device
CLOSE       EQU     0FD27H      ; Close block device
EDWH        EQU     0FD2DH      ; Convert word to 4-character ASCII hexadecimal
PHYSINT     EQU     0FDDFH      ; Initialize FCB from full file designator

;
; TOS standard files
;
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer
AI_FCB      EQU     0FF0AH      ; Auxilliary input abstract file FCB pointer

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag

;
; Text-layout settings datastructure
;
LS_MARGIN_L EQU     000H        ; Left margin
LS_MARGIN_R EQU     001H        ; Right margin
LS_ALIGN_R  EQU     002H        ; Right alignment flag
LS_INDENT_F EQU     003H        ; Tabulation stop number for first-line indentation
LS_INDENT_G EQU     004H        ; Tabulation stop number for general indentation
LS_TAB_LIST EQU     005H        ; Horizontal tabulation stops
LS_SPACE_V  EQU     023H        ; Number of empty lines between paragraphs

;
; Page number formatting byte
;
PN_TYPE_0   EQU     000H        ; Page number format: ####
PN_LDZERO_F EQU     001H        ; Include leading zeroes flag
PN_TYPE_1   EQU     002H        ; Page number format: - #### -
PN_TYPE_2   EQU     004H        ; Page number format: PAGE ####
PN_TYPE_3   EQU     008H        ; Page number format: Page ####


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'TXW',NULL,NULL,NULL
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Save stack pointer for breaking out of program from subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        sp_backup
        ;
        ; Initialize settings
        ;
        CALL        check_device_files
        CALL        reset_global_layout
        CALL        reset_temporary_layout


;//////////////////////////////////////

global_main:
        ;
        ; Get next line from input textfile, outside of paragraphs
        ;
        CALL        get_next_input_line
        JC          check_for_end_of_input
check_paragraph_break:
        ;
        ; Check if input starts with a paragraph break for changing settings
        ;
        LHLD        input_line_data_ptr
        MOV         A,M
        CPI         ':'
        JZ          global_settings_break
        CPI         '.'
        JZ          temp_settings_break
        ;
        ; Paragraph start
        ;
        CALL        start_new_paragraph
        CALL        start_new_text_line
paragraph_main:
        ;
        ; Get next line from input textfile, inside of paragraphs
        ;
        CALL        add_text_to_output
        CALL        get_next_input_line
        JC          check_for_end_of_input
        ;
        ; Check if line starts with a paragraph break
        ;
        LHLD        input_line_data_ptr
        MOV         A,M
        CPI         ':'
        JZ          end_current_paragraph
        CPI         '.'
        JNZ         paragraph_main
        ;
        ; Paragraph end
        ;
end_current_paragraph:
        ;
        ; Check if there's pending data in the current output line
        ;
        LHLD        output_line_data_ptr
        XCHG
        LXI         H,output_line_buffer
        MOV         A,D
        CMP         H
        JNZ         output_line_not_empty
        MOV         A,E
        CMP         L
        JZ          output_line_empty
output_line_not_empty:
        ;
        ; If so, make sure to write it to output file first
        ;
        XRA         A
        CALL        complete_output_line
output_line_empty:
        ;
        ; Reset local layout since the paragraph has ended
        ;
        CALL        reset_temporary_layout
        JMP         check_paragraph_break


;//////////////////////////////////////

global_settings_break:
        CALL        parse_global_layout_changes
        CALL        reset_temporary_layout
        JMP         global_main

temp_settings_break:
        CALL        parse_temp_layout_changes
        JMP         global_main


;//////////////////////////////////////

        ;
        ; Exception reading input data
        ;
check_for_end_of_input:
        ;
        ; Check for end of file
        ;
        ORA         A
        STC
        JNZ         quit
        ;
        ; Check if there's pending data in the current output line
        ;
        LHLD        output_line_data_ptr
        XCHG
        LXI         H,output_line_buffer
        MOV         A,D
        CMP         H
        JNZ         final_output_line_not_empty
        MOV         A,E
        CMP         L
        JZ          final_output_line_empty
final_output_line_not_empty:
        ;
        ; If so, make sure to write it to output file before leaving program
        ;
        XRA         A
        CALL        complete_output_line
final_output_line_empty:
        ;
        ; Feed out the rest of the final page and exit program nicely
        ;
        CALL        complete_current_page
        XRA         A
quit:
        LHLD        sp_backup
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set up behaviour of program based on input and output file types
        ;
check_device_files:
        ;
        ; Set default console flag to FALSE
        ;
        XRA         A
        STA         console_output_flag
        STA         not_first_file_flag
        ;
        ; Check if AI is assigned to a batch file
        ;
        LHLD        AI_FCB
        MOV         A,L
        ORA         H
        JZ          no_batch_file
        ;
        ; Check that SI is not assigned together with AI
        ;
        LHLD        SI_FCB
        MOV         A,L
        ORA         H
        JZ          input_file_ok
        ;
        ; If both AI and SI is assigned, input mode cannot be decided
        ;
        LXI         D,multiple_inputs_str
        LHLD        CO_FCB
        CALL        PUT
        JMP         quit

no_batch_file:
        ;
        ; Check if SI is assigned for input data
        ;
        LHLD        SI_FCB
        MOV         A,H
        ORA         L
        JNZ         input_file_ok
        ;
        ; If not, there's nothing to do. Complain and quit.
        ;
        LXI         D,missing_si_str
        LHLD        CO_FCB
        CALL        PUT
        JMP         quit

input_file_ok:
        ;
        ; Check if SL is assigned for output data
        ;
        LHLD        SL_FCB
        MOV         A,H
        ORA         L
        JNZ         uses_line_output_file
        ;
        ; If not, check that SO is assigned instead
        ;
        LHLD        SO_FCB
        MOV         A,H
        ORA         L
        RNZ
        ;
        ; If neither, use console for output as last resort
        ;
        LHLD        CO_FCB
        SHLD        SO_FCB
        MVI         A,TRUE
        STA         console_output_flag
        XRA         A
        STA         console_line_counter
        ;
        ; Clear screen to initially start of with a blank page
        ;
        MVI         A,ERPAG
        CALL        TTO
        RET

uses_line_output_file:
        ;
        ; If SL is assigned, check that SO is not: Only one of them can be used
        ;
        LHLD        SO_FCB
        MOV         A,H
        ORA         L
        JZ          line_output_file_ok
        ;
        ; If both are assigned, complain about the ambiguity and quit
        ;
        LXI         D,multiple_outputs_str
        LHLD        CO_FCB
        CALL        PUT
        JMP         quit

line_output_file_ok:
        ;
        ; Move SL assignement over to SO
        ;
        LHLD        SL_FCB
        SHLD        SO_FCB
        LXI         H,00000H
        SHLD        SL_FCB
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Initialize global layout settings
        ;
reset_global_layout:
        ;
        ; Set page bounds
        ;
        MVI         A,72
        STA         lines_per_page
        MVI         A,1
        STA         global_layout + LS_MARGIN_L
        MVI         A,80
        STA         global_layout + LS_MARGIN_R
        MVI         A,5
        STA         margin_top
        MVI         A,68
        STA         margin_bottom
        ;
        ; Set indentation settings
        ;
        XRA         A
        STA         global_layout + LS_INDENT_F
        STA         global_layout + LS_INDENT_G
        ;
        ; Set header and footer settings
        ;
        STA         line_nr_for_page_nr
        STA         line_nr_for_title
        ;
        ; Reset default misc settings and variables
        ;
        STA         global_layout + LS_ALIGN_R
        STA         global_layout + LS_SPACE_V
        STA         disable_layout_flag
        LXI         H,00000H
        SHLD        page_number_bcd
        ;
        ; Reset horizontal tabulation stops
        ;
        LXI         H,global_layout + LS_TAB_LIST
        MVI         A,30
reset_global_tabs_loop:
        MVI         M,1
        INX         H
        DCR         A
        JNZ         reset_global_tabs_loop
        ;
        ; Set up page, clear underrun character of output buffer just in case
        ;
        MVI         A,1
        STA         current_line_on_page
        LXI         H,one_indexed_output_line_buffer
        MVI         M,' '
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Advance to next input line of input file
        ;
get_next_input_line:
        ;
        ; Check if batch-file input mode
        ;
        LHLD        AI_FCB
        MOV         A,L
        ORA         H
        JZ          get_next_text_input_line
        ;
        ; If so, check if this is the first file in batch file
        ;
        LDA         not_first_file_flag
        ANA         A
        JNZ         get_next_text_input_line
        ;
        ; If first file, open it and set it as active input file
        ;
        DCR         A
        STA         not_first_file_flag
open_next_file_in_batch:
        ;
        ; Get filename from batch file
        ;
        LHLD        AI_FCB
        LXI         D,input_line_buffer
        CALL        GET
        RC
        ;
        ; Create file FCB from filename
        ;
        LXI         H,input_line_buffer
        XRA         A
        CALL        PHYSINT
        RC
        ;
        ; Allocate file to SI and open it for reading
        ;
        SHLD        SI_FCB
        MVI         A,FM_INPUT
        CALL        OPEN
        RC
get_next_text_input_line:
        ;
        ; Get next line from input file
        ;
        LXI         D,input_line_buffer
        LHLD        SI_FCB
        CALL        GET
        JNC         got_input_line
        ;
        ; Check for end of input text file
        ;
        ANA         A
        STC
        RNZ
        ;
        ; Return end of file if not batch-file input mode
        ;
        LHLD        AI_FCB
        MOV         A,L
        ORA         H
        STC
        RZ
        ;
        ; Otherwise advance to next text-file specified in batch file
        ;
        LHLD        SI_FCB
        CALL        CLOSE
        RC
        LXI         H,00000H
        SHLD        SI_FCB
        JMP         open_next_file_in_batch

got_input_line:
        ;
        ; Reset input line pointers
        ;
        LXI         H,input_line_buffer
        SHLD        input_line_data_ptr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Reset temporary layout settings
        ;
reset_temporary_layout:
        ;
        ; Copy global layout settings into the active settings
        ;
        LXI         H,global_layout
        LXI         D,active_layout
        MVI         B,36
copy_layout_settings_loop:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         B
        JNZ         copy_layout_settings_loop
        ;
        ; Enable layout again for the next paragraph, in case it was turned off
        ;
        XRA         A
        STA         disable_layout_flag
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prepare for a new paragraph, writing the space between paragraphs
        ;
start_new_paragraph:
        ;
        ; Set up new page if current line is very first line of a page
        ;
        LDA         current_line_on_page
        CPI         1
        CZ          start_new_page
        ;
        ; Reset paragraph line counter after previous paragraph
        ;
        XRA         A
        STA         paragraph_line_counter
        ;
        ; Check if we have passed the line nr of the bottom margin
        ;
        LDA         margin_bottom
        LXI         H,current_line_on_page
        SUB         M
        JC          new_paragraph_on_next_page
        ;
        ; Check if the paragraph break blank lines cross the bottom margin
        ;
        LXI         H,active_layout + LS_SPACE_V
        SUB         M
        JC          new_paragraph_on_next_page
        ;
        ; Check if there's less than 3 lines left after paragraph break
        ;
        CPI         3
        JNC         new_paragraph_on_same_page
new_paragraph_on_next_page:
        ;
        ; If yes to any of these, start paragraph on next page instead
        ;
        CALL        complete_current_page
        CALL        start_new_page
        XRA         A
        STA         active_layout + LS_SPACE_V
        RET

new_paragraph_on_same_page:
        ;
        ; Add blank lines between previous and new paragraph on the same page
        ;
write_next_paragraph_break_line:
        ;
        ; Check if all break lines have been added
        ;
        LDA         active_layout + LS_SPACE_V
        ORA         A
        RZ
        ;
        ; Clear output line and write to output file
        ;
        MVI         A,CR
        STA         output_line_buffer
        CALL        complete_output_line
        ;
        ; Check if we are violating the bottom margin, again, for good meassure
        ;
        LDA         current_line_on_page
        MOV         B,A
        LDA         margin_bottom
        CMP         B
        JZ          new_paragraph_on_next_page
        ;
        ; Advance paragraph break line count
        ;
        LDA         active_layout + LS_SPACE_V
        DCR         A
        STA         active_layout + LS_SPACE_V
        JMP         write_next_paragraph_break_line


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Advance to next page and add page top margin to output
        ;
start_new_page:
        ;
        ; Advance current page number, lower two digits
        ;
        LXI         H,page_number_bcd
        XRA         A
        MOV         A,M
        INR         A
        DAA
        MOV         M,A
        JNC         page_nr_ready
        ;
        ; Advance current page number, upper two digits if needed
        ;
        INX         H
        XRA         A
        MOV         A,M
        INR         A
        DAA
        MOV         M,A
page_nr_ready:
        ;
        ; Fill in top margin, if needed
        ;
write_next_top_margin_line:
        ;
        ; Clear output line, and check if all top margin lines have been added
        ;
        CALL        blank_output_line_buffer
        LDA         current_line_on_page
        MOV         B,A
        LDA         margin_top
        CMP         B
        RZ
        ;
        ; Check if we are at the line to output page number
        ;
        LDA         line_nr_for_page_nr
        CMP         B
        CZ          prepare_page_nr_output
        ;
        ; Check if we are at the line to output title
        ;
        LDA         current_line_on_page
        MOV         B,A
        LDA         line_nr_for_title
        CMP         B
        CZ          prepare_title_output
        ;
        ; Write line of top margin to output file
        ;
        XRA         A
        CALL        complete_output_line
        JMP         write_next_top_margin_line


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Start a new line of text, setting up the appropriate indentation
        ;
start_new_text_line:
        CALL        blank_output_line_buffer
        ;
        ; Check if layout is enabled
        ;
        LDA         disable_layout_flag
        ORA         A
        JNZ         no_line_indent
        ;
        ; Check and advance line nr in paragraph, and check if first line
        ;
        LXI         H,paragraph_line_counter
        MOV         A,M
        INR         M
        ORA         A
        JZ          get_first_line_indent
        ;
        ; Get tab stop number for general indent
        ;
        LDA         active_layout + LS_INDENT_G
        JMP         check_line_indent


;//////////////////////////////////////

get_first_line_indent:
        ;
        ; Get tab stop number for first-line indent
        ;
        LDA         active_layout + LS_INDENT_F
check_line_indent:
        ;
        ; Check if a tab-stop is selected for the particular indent
        ;
        ORA         A
        JNZ         look_up_indent_tab
no_line_indent:
        ;
        ; If no indent is to be used, just start line at left margin
        ;
        LDA         active_layout + LS_MARGIN_L
        MOV         C,A
        MVI         B,0
        JMP         set_paragraph_line_start


;//////////////////////////////////////

look_up_indent_tab:
        ;
        ; Look up tab stop of selected indent
        ;
        LXI         H,active_layout + LS_TAB_LIST-1
        MOV         C,A
        MVI         B,000H
        DAD         B
        MOV         C,M
set_paragraph_line_start:
        ;
        ; Set output line tabulation to selected indent
        ;
        LXI         H,one_indexed_output_line_buffer
        DAD         B
        SHLD        output_line_data_ptr
        SHLD        most_recent_tab_ptr
        RET


;//////////////////////////////////////////////////////////////////////////////

add_text_to_output:
        ;
        ; Check if layout is disabled
        ;
        LDA         disable_layout_flag
        ORA         A
        JNZ         add_line_without_layout
        ;
        ; Get pointers to current and output lines
        ;
        LHLD        input_line_data_ptr
        XCHG
        LHLD        output_line_data_ptr
advance_to_next_word:
        ;
        ; Reset pointer to potential wordbreak, since a new word is starting
        ;
        PUSH        H
        LXI         H,00000H
        SHLD        input_line_wordbreak_ptr
        POP         H
        ;
        ; Skip any leading whitespace, until start of next word
        ;
find_start_of_word_loop:
        LDAX        D
        CPI         ' '
        JNZ         parse_next_char
        INX         D
        JMP         find_start_of_word_loop

parse_next_char:
        ;
        ; Check for end of input line word
        ;
        LDAX        D
        CPI         ' '
        JNZ         check_for_linebreak
        ;
        ; If so, add a space to output line if one isn't already there
        ;
        DCX         H
        MOV         A,M
        CPI         ' '
        JZ          space_after_word_added
        INX         H
space_after_word_added:
        INX         H
        ;
        ; Update pointers to where we are in input and output lines and move on
        ;
        SHLD        output_line_data_ptr
        XCHG
        SHLD        input_line_data_ptr
        XCHG
        JMP         advance_to_next_word


;//////////////////////////////////////

check_for_linebreak:
        ;
        ; Check for forced-newline symbol
        ;
        CPI         '!'
        JNZ         check_for_tabulation
        ;
        ; Verify that symbol is not escaped
        ;
        MOV         B,A
        INX         D
        LDAX        D
        CPI         '/'
        JNZ         add_linebreak_to_output
        ;
        ; If escaped, treat as normal character
        ;
        MOV         A,B
        JMP         add_char_to_output

add_linebreak_to_output:
        ;
        ; Update pointer to current position in input line and end output line
        ;
        XCHG
        SHLD        input_line_data_ptr
        XRA         A
        CALL        complete_output_line
        LDA         current_line_on_page
        ;
        ; Check if bottom margin has been reached
        ;
        MOV         B,A
        LDA         margin_bottom
        CMP         B
        JNZ         add_linebreak_done
        ;
        ; If so, make sure to start a new page
        ;
        CALL        complete_current_page
        CALL        start_new_page
add_linebreak_done:
        ;
        ; Sort out indentation and things for the new line
        ;
        CALL        start_new_text_line
        JMP         add_text_to_output


;//////////////////////////////////////

check_for_tabulation:
        ;
        ; Check for next tabulation symbol
        ;
        CPI         '>'
        JNZ         check_for_word_wrap
        ;
        ; Verify that symbol is not escaped
        ;
        MOV         B,A
        INX         D
        LDAX        D
        CPI         '/'
        JNZ         advance_tabulation
        ;
        ; If escaped, treat as normal character
        ;
        MOV         A,B
        JMP         add_char_to_output

advance_tabulation:
        ;
        ; Skip one tabulation stop ahead in output line
        ;
        INX         H
        CALL        align_to_next_tab
        SHLD        most_recent_tab_ptr
        JMP         parse_next_char


;//////////////////////////////////////

check_for_word_wrap:
        ;
        ; Check if it is possible to do word-wrap here
        ;
        CPI         '-'
        JNZ         check_for_input_line_end
        ;
        ; Check next input character to see if this a stroke inside a word not
        ;
        MOV         B,A
        INX         D
        LDAX        D
        CPI         ' '
        JZ          freestanding_stroke
        CPI         CR
        JZ          freestanding_stroke
        CPI         '/'
        JZ          add_stroke
        CPI         '-'
        JZ          freestanding_stroke
        ;
        ; Check previous output character for the same reason
        ;
        DCX         H
        MOV         A,M
        INX         H
        CPI         '-'
        JZ          freestanding_stroke
        CPI         ' '
        JNZ         word_wrap_possible
freestanding_stroke:
        ;
        ; Treat a freestanding stroke as a normal character, so return pointer
        ;
        DCX         D
add_stroke:
        MOV         A,B
        JMP         add_char_to_output

        ;
        ; Stroke is in a word, alone and not escaped, so word-wrap is possible
        ;
word_wrap_possible:
        ;
        ; Check if it's already too crammed for a word-wrap right now
        ;
        CALL        get_chars_left_before_margin
        ORA         A
        JZ          no_more_space_on_line
        ;
        ; Otherwise, save pointers to this word-wrap spot if it is needed later
        ;
        SHLD        output_line_wordbreak_ptr
        XCHG
        SHLD        input_line_wordbreak_ptr
        XCHG
        ;
        ; Skip stroke and continue the word without word-wrap as of time being
        ;
        LDAX        D
        JMP         add_char_to_output


;//////////////////////////////////////

check_for_input_line_end:
        ;
        ; Check for input line end
        ;
        CPI         CR
        JNZ         add_char_to_output
        ;
        ; If so, add a space if prevous character of output is not a space
        ;
        DCX         H
        MOV         A,M
        CPI         ' '
        JZ          input_end_space_ready
        INX         H
input_end_space_ready:
        INX         H
        SHLD        output_line_data_ptr
        RET


;//////////////////////////////////////

add_char_to_output:
        ;
        ; Add current character to output line and advance to next character
        ;
        MOV         M,A
        INX         H
        INX         D
        ;
        ; Check if there is no more room left on the line
        ;
        CALL        get_chars_left_before_margin
        ORA         A
        JM          no_more_space_on_line
        JMP         parse_next_char


;//////////////////////////////////////

no_more_space_on_line:
        ;
        ; Check if a word-wrap location is registered for the current word
        ;
        LHLD        input_line_wordbreak_ptr
        MOV         A,H
        ORA         L
        JZ          bump_word_to_next_line
        ;
        ; Pin down anything before the word-wrap point, and add stroke
        ;
        SHLD        input_line_data_ptr
        LHLD        output_line_wordbreak_ptr
        MVI         M,'-'
        INX         H
        JMP         continue_on_next_line

bump_word_to_next_line:
        ;
        ; Roll back output line to start of word
        ;
        LHLD        output_line_data_ptr
continue_on_next_line:
        ;
        ; Erase the partially added word that did not fit on output line
        ;
erase_unfinished_word_loop:
        MVI         M,' '
        INX         H
        MOV         A,M
        CPI         ' '
        JNZ         erase_unfinished_word_loop
        ;
        ; Write line to output, with in-paragraph flag set
        ;
        MVI         A,TRUE
        CALL        complete_output_line
        ;
        ; Check if we passed the bottom margin
        ;
        LDA         current_line_on_page
        MOV         B,A
        LDA         margin_bottom
        CMP         B
        JNZ         continue_on_next_line_ready
        ;
        ; If so, make sure to start a new page
        ;
        CALL        complete_current_page
        CALL        start_new_page
continue_on_next_line_ready:
        ;
        ; Set up indentation and such on the new line
        ;
        CALL        start_new_text_line
        JMP         add_text_to_output


;//////////////////////////////////////

add_line_without_layout:
        ;
        ; Prepare to add text from input to output without redoing the layout
        ;
        LHLD        input_line_data_ptr
        XCHG
        LHLD        output_line_data_ptr
        ;
        ; Copy line to output as-is, until input line is empty
        ;
add_next_char_directly:
        LDAX        D
        INX         D
        MOV         M,A
        INX         H
        CPI         CR
        JNZ         add_next_char_directly
        ;
        ; Write output to file
        ;
        XRA         A
        CALL        complete_output_line
        ;
        ; Check if we have passed the bottom of the page
        ;
        LDA         current_line_on_page
        MOV         B,A
        LDA         margin_bottom
        CMP         B
        JNZ         add_line_without_layout_done
        ;
        ; If so, advance to the next page
        ;
        CALL        complete_current_page
        CALL        start_new_page
add_line_without_layout_done:
        ;
        ; Prepare next output line
        ;
        CALL        start_new_text_line
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Calculate number of characters left for text on the line
        ;
get_chars_left_before_margin:
        PUSH        H
        PUSH        D
        XCHG
        ;
        ; Get absolute pointer to where the right margin starts
        ;
        LXI         H,output_line_buffer
        LDA         active_layout + LS_MARGIN_R
        MOV         C,A
        MVI         B,000H
        DAD         B
        ;
        ; Subtract pointer to right maring from current position
        ;
        MOV         A,D
        CMA
        MOV         D,A
        MOV         A,E
        CMA
        MOV         E,A
        INX         D
        DAD         D
        ;
        ; Return characters left in line in A
        ;
        MOV         A,L
        POP         D
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prepare and write string in output line buffer to file
        ;
complete_output_line:
        ;
        ; Check in-paragraph flag to determine if alignment is to be considered
        ;
        ORA         A
        JZ          alignment_ready
        LDA         active_layout + LS_ALIGN_R
        ORA         A
        CNZ         right_align_output_line
alignment_ready:
        ;
        ; Scan backwards from end of output buffer to find end of string
        ;
        LXI         H,output_line_buffer + 131
        LXI         D,output_line_buffer
output_str_end_scan_loop:
        MOV         A,M
        DCX         H
        CPI         ' '
        JNZ         output_str_end_found
        MOV         A,L
        CMP         E
        JNZ         output_str_end_scan_loop
        MOV         A,H
        CMP         D
        JNZ         output_str_end_scan_loop
        ;
        ; If buffer is empty, just terminate at the first character in string
        ;
        JMP         output_str_terminate

output_str_end_found:
        ;
        ; Non-empty output, point to first character after content
        ;
        INX         H
        INX         H
output_str_terminate:
        ;
        ; Terminate string and write to output file
        ;
        MVI         M,CR
        CALL        write_output_line
        ;
        ; Advance to next line on page
        ;
        LDA         current_line_on_page
        INR         A
        STA         current_line_on_page
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Go to the first line of the next page
        ;
complete_current_page:
        MVI         A,1
        STA         multiple_pages_flag


;//////////////////////////////////////

goto_line:
        STA         target_line_nr
goto_line_loop:
        ;
        ; Fill with blank lines by default
        ;
        CALL        blank_output_line_buffer
        ;
        ; Stop if target line has been reached
        ;
        LDA         current_line_on_page
        MOV         B,A
        LDA         target_line_nr
        CMP         B
        RZ
        ;
        ; Add page number if at the line where it is to be printed
        ;
        LDA         line_nr_for_page_nr
        CMP         B
        CZ          prepare_page_nr_output
        ;
        ; Add title if at the line where it is to be printed
        ;
        LDA         current_line_on_page
        MOV         B,A
        LDA         line_nr_for_title
        CMP         B
        CZ          prepare_title_output
        ;
        ; Write line to output
        ;
        CALL        complete_output_line
        ;
        ; Check if we have filled the current page
        ;
        LDA         current_line_on_page
        DCR         A
        MOV         B,A
        LDA         lines_per_page
        CMP         B
        JNZ         goto_line_loop
        ;
        ; if so, start atop the next page
        ;
        MVI         A,1
        STA         current_line_on_page
        JMP         goto_line_loop


;//////////////////////////////////////////////////////////////////////////////

write_output_line:
        ;
        ; Write line to output file
        ;
        LXI         D,output_line_buffer
        LHLD        SO_FCB
        CALL        PUT
        ;
        ; If output device is the console, pause for each full screen
        ;
        LDA         console_output_flag
        ORA         A
        RZ
        LDA         console_line_counter
        INR         A
        STA         console_line_counter
        SUI         24
        RNZ
        ;
        ; Wait for keypress before continuing
        ;
        CALL        TTI
        MVI         A,ERPAG
        CALL        TTO
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get and execute commands for global layout changes
        ;
parse_global_layout_changes:
        ;
        ; Parse and validate command number (1-indexed)
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JZ          parse_global_layout_changes
run_global_layout_cmd:
        ;
        ; Run selected command in jumptable
        ;
        MVI         B,000H
        LXI         H,global_layout_cmd_list-3
        DAD         B
        DAD         B
        DAD         B
        PCHL


;//////////////////////////////////////

global_layout_cmd_list:
        JMP         cmd_global_left_margin
        JMP         cmd_global_right_margin
        JMP         cmd_global_right_align
        JMP         cmd_global_left_align
        JMP         cmd_global_tab_stops
        JMP         cmd_global_paragraph_indents
        JMP         cmd_global_paragraph_spacing
        JMP         cmd_global_page_length
        JMP         cmd_global_top_margin
        JMP         cmd_global_bottom_margin
        JMP         cmd_global_page_numbering
        JMP         cmd_global_page_header
        JMP         parse_global_layout_changes
        JMP         parse_global_layout_changes
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; New left margin
        ;
cmd_global_left_margin:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update global layout left margin
        ;
        MOV         A,B
        STA         global_layout + LS_MARGIN_L
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; New right margin
        ;
cmd_global_right_margin:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update global layout right margin
        ;
        MOV         A,B
        STA         global_layout + LS_MARGIN_R
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; Enable right alignment
        ;
cmd_global_right_align:
        MVI         A,TRUE
        STA         global_layout + LS_ALIGN_R
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; Disable right alignment
        ;
cmd_global_left_align:
        XRA         A
        STA         global_layout + LS_ALIGN_R
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; New tab stop list
        ;
cmd_global_tab_stops:
        LXI         H,global_layout + LS_TAB_LIST
add_next_global_tab_stop:
        ;
        ; Parse and verify command argument, expect a number
        ;
        PUSH        H
        CALL        parse_layout_command_part
        POP         H
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Add next tab stop to list
        ;
        MOV         M,B
        INX         H
        JMP         add_next_global_tab_stop


;//////////////////////////////////////

        ;
        ; New paragraph indents
        ;
cmd_global_paragraph_indents:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update first-line and general indents (default)
        ;
        MOV         A,B
        STA         global_layout + LS_INDENT_F
        STA         global_layout + LS_INDENT_G
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update general indents (custom)
        ;
        MOV         A,B
        STA         global_layout + LS_INDENT_G
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; New paragraph spacing
        ;
cmd_global_paragraph_spacing:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update lines between paragraph spacing
        ;
        MOV         A,B
        STA         global_layout + LS_SPACE_V
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; New page length
        ;
cmd_global_page_length:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update page length
        ;
        MOV         A,B
        STA         lines_per_page
        ;
        ; Crop bottom margin to new page end, if need be
        ;
        LDA         margin_bottom
        CMP         B
        JC          parse_global_layout_changes
        MOV         A,B
        DCR         A
        STA         margin_bottom
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; New top margin
        ;
cmd_global_top_margin:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update top margin
        ;
        MOV         A,B
        STA         margin_top
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; New bottom margin
        ;
cmd_global_bottom_margin:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update bottom margin
        ;
        MOV         A,B
        STA         margin_bottom
        JMP         parse_global_layout_changes


;//////////////////////////////////////

        ;
        ; New page numbering scheme
        ;
cmd_global_page_numbering:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Temporarily save line number for page nr
        ;
        MOV         A,B
        STA         target_line_nr
        ;
        ; Parse and verify next command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Temporarily save character in line for page nr
        ;
        MOV         A,B
        STA         target_line_pos
        ;
        ; Parse and verify next command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update page nr formatting
        ;
        MOV         A,B
        STA         page_number_format
        ;
        ; Update page nr placement
        ;
        LDA         target_line_pos
        STA         page_number_line_pos
        LDA         target_line_nr
        STA         line_nr_for_page_nr
        ;
        ; Parse current page number argument
        ;
        LHLD        input_line_data_ptr
        XCHG
        LXI         H,00000H
parse_new_page_nr_loop:
        ;
        ; Check for input line (command string) end
        ;
        LDAX        D
        CPI         CR
        RZ
        ;
        ; Check if next character of command string is a number
        ;
        CPI         '0'
        JC          new_page_nr_ready
        CPI         '9'+1
        JNC         parse_global_layout_changes
        ;
        ; Shift new digit into new line number (bcd format)
        ;
        DAD         H
        DAD         H
        DAD         H
        DAD         H
        SUI         '0'
        ADD         L
        MOV         L,A
        SHLD        page_number_bcd
new_page_nr_ready:
        ;
        ; Input is now after page number argument, update pointer
        ;
        INX         D
        XCHG
        SHLD        input_line_data_ptr
        XCHG
        JMP         parse_new_page_nr_loop


;//////////////////////////////////////

        ;
        ; New page header
        ;
cmd_global_page_header:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Temporarily save line number for page header
        ;
        MOV         A,B
        STA         target_line_nr
        ;
        ; Parse and verify next command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_global_layout_cmd
        ;
        ; Update character in line for the page header
        ;
        MOV         A,B
        STA         title_line_pos
        ;
        ; Update line on page for the page header
        ;
        LDA         target_line_nr
        STA         line_nr_for_title
        ;
        ; Scan to start of header message
        ;
        LHLD        input_line_data_ptr
        LXI         D,header_str
scan_to_header_loop:
        MOV         A,M
        INX         H
        CPI         ' '
        JZ          scan_to_header_loop
        JMP         copy_header_msg_str

        ;
        ; Copy the rest of the command string into the header message string
        ;
copy_header_loop:
        MOV         A,M
        INX         H
copy_header_msg_str:
        CPI         CR
        JZ          new_header_msg_str_ready
        STAX        D
        INX         D
        JMP         copy_header_loop

new_header_msg_str_ready:
        XRA         A
        STAX        D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get and execute commands for temporary this-paragraph layout changes
        ;
parse_temp_layout_changes:
        ;
        ; Parse and validate command number (1-indexed)
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JZ          parse_temp_layout_changes
run_temp_layout_cmd:
        ;
        ; Run selected command in jumptable
        ;
        MVI         B,000H
        LXI         H,temp_layout_cmd_list-3
        DAD         B
        DAD         B
        DAD         B
        PCHL


;//////////////////////////////////////

temp_layout_cmd_list:
        JMP         cmd_temp_left_margin
        JMP         cmd_temp_right_margin
        JMP         cmd_temp_right_align
        JMP         cmd_temp_left_align
        JMP         cmd_temp_tab_stops
        JMP         cmd_temp_paragraph_indents
        JMP         cmd_temp_paragraph_spacing
        JMP         parse_temp_layout_changes
        JMP         parse_temp_layout_changes
        JMP         parse_temp_layout_changes
        JMP         parse_temp_layout_changes
        JMP         parse_temp_layout_changes
        JMP         cmd_temp_disable_layout
        JMP         cmd_temp_goto_next_page
        JMP         cmd_temp_goto_line


;//////////////////////////////////////

        ;
        ; New temporary left margin
        ;
cmd_temp_left_margin:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_temp_layout_cmd
        ;
        ; Update actvie layout left margin
        ;
        MOV         A,B
        STA         active_layout + LS_MARGIN_L
        JMP         parse_temp_layout_changes


;//////////////////////////////////////

        ;
        ; New temporary right margin
        ;
cmd_temp_right_margin:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_temp_layout_cmd
        ;
        ; Update actvie layout right margin
        ;
        MOV         A,B
        STA         active_layout + LS_MARGIN_R
        JMP         parse_temp_layout_changes


;//////////////////////////////////////

        ;
        ; Enable temporary right alignment
        ;
cmd_temp_right_align:
        MVI         A,TRUE
        STA         active_layout + LS_ALIGN_R
        JMP         parse_temp_layout_changes


;//////////////////////////////////////

        ;
        ; Disable temporary right alignment
        ;
cmd_temp_left_align:
        XRA         A
        STA         active_layout + LS_ALIGN_R
        JMP         parse_temp_layout_changes


;//////////////////////////////////////

        ;
        ; New temporary tab stop list
        ;
cmd_temp_tab_stops:
        LXI         H,active_layout + LS_TAB_LIST
add_next_temp_tab_stop:
        ;
        ; Parse and verify command argument, expect a number
        ;
        PUSH        H
        CALL        parse_layout_command_part
        POP         H
        RC
        MOV         A,C
        ORA         A
        JNZ         run_temp_layout_cmd
        ;
        ; Add next tab stop to list
        ;
        MOV         M,B
        INX         H
        JMP         add_next_temp_tab_stop


;//////////////////////////////////////

        ;
        ; New temporary paragraph indents
        ;
cmd_temp_paragraph_indents:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_temp_layout_cmd
        ;
        ; Update first-line and general indents (default)
        ;
        MOV         A,B
        STA         active_layout + LS_INDENT_F
        STA         active_layout + LS_INDENT_G
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_temp_layout_cmd
        ;
        ; Update general indents (custom)
        ;
        MOV         A,B
        STA         active_layout + LS_INDENT_G
        JMP         parse_temp_layout_changes


;//////////////////////////////////////

        ;
        ; New temporary paragraph spacing
        ;
cmd_temp_paragraph_spacing:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_temp_layout_cmd
        ;
        ; Update lines between paragraph spacing
        ;
        MOV         A,B
        STA         active_layout + LS_SPACE_V
        JMP         parse_temp_layout_changes


;//////////////////////////////////////

        ;
        ; Temporarily disable layout formatting
        ;
cmd_temp_disable_layout:
        MVI         A,TRUE
        STA         disable_layout_flag
        JMP         parse_temp_layout_changes


;//////////////////////////////////////

        ;
        ; Immediately go to start of next page
        ;
cmd_temp_goto_next_page:
        CALL        complete_current_page
        JMP         parse_temp_layout_changes


;//////////////////////////////////////

        ;
        ; Immediately go forwards to given line number
        ;
cmd_temp_goto_line:
        ;
        ; Parse and verify command argument, expect a number
        ;
        CALL        parse_layout_command_part
        RC
        MOV         A,C
        ORA         A
        JNZ         run_temp_layout_cmd
        ;
        ; Go forwards to requested line
        ;
        MOV         A,B
        CALL        goto_line
        JMP         parse_temp_layout_changes


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Construct the page number string in the output line buffer
        ;
prepare_page_nr_output:
        ;
        ; Convert page number from BCD to ASCII number
        ;
        LHLD        page_number_bcd
        XCHG
        LXI         H,page_number_str
        CALL        EDWH
        MVI         M,NULL
        ;
        ; Get pointer to where to generate page number in output buffer
        ;
        LDA         page_number_line_pos
        MOV         C,A
        MVI         B,000H
        LXI         H,one_indexed_output_line_buffer
        DAD         B
        ;
        ; Check flag for if leading zeroes are to be included in page number
        ;
        LDA         page_number_format
        ANI         PN_LDZERO_F
        JNZ         compose_page_nr
        ;
        ; If not set, erase leading zeroes to be used in page number
        ;
        LXI         D,page_number_str
page_nr_scan_for_start_loop:
        LDAX        D
        SUI         '0'
        JNZ         compose_page_nr
        STAX        D
        INX         D
        JMP         page_nr_scan_for_start_loop

compose_page_nr:
        ;
        ; Check for page number format: - #### -
        ;
        LDA         page_number_format
        MOV         B,A
        ANI         PN_TYPE_1
        JZ          not_page_nr_type_1
        LXI         B,page_nr_prefix_1_str
        JMP         prefixed_page_nr_type

not_page_nr_type_1:
        ;
        ; Check for page number format: PAGE ####
        ;
        MOV         A,B
        ANI         PN_TYPE_2
        JZ          not_page_nr_type_2
        LXI         B,page_nr_prefix_2_str
        JMP         prefixed_page_nr_type

not_page_nr_type_2:
        ;
        ; Check for page number format: Page ####
        ;
        MOV         A,B
        ANI         PN_TYPE_3
        JZ          add_page_nr_numeral
        LXI         B,page_nr_prefix_3_str
prefixed_page_nr_type:
        ;
        ; Add selected prefix to page number
        ;
add_page_nr_prefix_char:
        ;
        ; Check for end of page number prefix
        ;
        LDAX        B
        ORA         A
        JZ          add_page_nr_numeral
        ;
        ; Copy next character from page number prefix to output line
        ;
        MOV         M,A
        INX         B
        INX         H
        JMP         add_page_nr_prefix_char

add_page_nr_numeral:
        ;
        ; Copy page number numeral to output line
        ;
        MVI         B,4
        LXI         D,page_number_str
copy_page_nr_char:
        LDAX        D
        ;
        ; Skip NULL characters, from erased leading zeroes
        ;
        ORA         A
        JZ          copy_next_page_nr_char
        MOV         M,A
        INX         H
copy_next_page_nr_char:
        INX         D
        DCR         B
        JNZ         copy_page_nr_char
        ;
        ; Add complimentary stroke character if page number type 1
        ;
        LDA         page_number_format
        ANI         PN_TYPE_1
        RZ
        MVI         M,' '
        INX         H
        MVI         M,'-'
        RET


;//////////////////////////////////////

page_nr_prefix_1_str:
        DB          '- ',NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Construct the header string in the output line buffer
        ;
prepare_title_output:
        ;
        ; Get pointer to where to generate header in output buffer
        ;
        LXI         H,one_indexed_output_line_buffer
        LDA         title_line_pos
        MOV         C,A
        MVI         B,000H
        DAD         B
        ;
        ; Add header string to given position in output line
        ;
        XCHG
        LXI         H,header_str
copy_header_char:
        MOV         A,M
        ORA         A
        RZ
        STAX        D
        INX         H
        INX         D
        JMP         copy_header_char


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse the next part of a command: Numeral in B, or command nr in C
        ;
parse_layout_command_part:
        ;
        ; Get and convert next character of command line string to uppercase
        ;
        LHLD        input_line_data_ptr
        MOV         A,M
        CPI         'a'-1
        JC          cmd_char_1_is_uppercase
        SUI         'a' - 'A'
cmd_char_1_is_uppercase:
        ;
        ; Validate first character in command string part
        ;
        CPI         '0'
        JC          cmd_invalid_char
        CPI         '9'+1
        JC          cmd_parse_number
        CPI         'A'
        JC          cmd_invalid_char
        CPI         'Z'+1
        JC          cmd_parse_cmd_name
cmd_invalid_char:
        ;
        ; Return error at end of line, else skip any unexpected characters
        ;
        CPI         CR
        JNZ         cmd_char_ignore
        MVI         C,0
        STC
        RET

cmd_char_ignore:
        INX         H
        SHLD        input_line_data_ptr
        JMP         parse_layout_command_part


;//////////////////////////////////////

cmd_parse_number:
        ;
        ; Assume ASCII decimal number, prepare to parse the rest of it
        ;
        XCHG
        LXI         H,0
        SUI         '0'
        MOV         L,A
add_next_decimal_nr_digit:
        ;
        ; Get next character from command string
        ;
        INX         D
        LDAX        D
        ;
        ; Verify that character is a valid decimal digit
        ;
        CPI         '0'
        JC          cmd_number_ready
        CPI         '9'+1
        JNC         cmd_number_ready
        SUI         '0'
        ;
        ; Multiply existing accumulator with 10 and add the new digit
        ;
        DAD         H
        MOV         B,H
        MOV         C,L
        DAD         H
        DAD         H
        DAD         B
        ADD         L
        MOV         L,A
        JMP         add_next_decimal_nr_digit

cmd_number_ready:
        ;
        ; Prepare return values to indicate a parsed numerical argument
        ;
        MOV         B,L
        MVI         C,000H
        XCHG
        SHLD        input_line_data_ptr
        XRA         A
        RET


;//////////////////////////////////////

cmd_parse_cmd_name:
        ;
        ; Get and convert next character of command line string to uppercase
        ;
        MOV         D,A
        MVI         E,000H
        INX         H
        MOV         A,M
        CPI         'a'-1
        JC          cmd_char_2_is_uppercase
        SUI         'a' - 'A'
cmd_char_2_is_uppercase:
        ;
        ; Verify that second character of command line part is alphabetic too
        ;
        CPI         'A'
        JC          cmd_char_2_ready
        CPI         'Z'+1
        JNC         cmd_char_2_ready
        MOV         E,A
        INX         H
cmd_char_2_ready:
        SHLD        input_line_data_ptr
        ;
        ; Search through command names database for a match with name in DE
        ;
        LXI         H,cmd_names_database
        MVI         C,0
check_next_cmd_name:
        ;
        ; Check for end of command names database, ignore current part if so
        ;
        MOV         A,M
        ORA         A
        JZ          parse_layout_command_part
        ;
        ; Compare first character of command name
        ;
        CMP         D
        JNZ         cmd_name_char_1_wrong
        ;
        ; Compare second character of command name
        ;
        INX         H
        MOV         A,M
        CMP         E
        JNZ         cmd_name_char_2_wrong
        ;
        ; Command found, get command number from database and return it
        ;
        INX         H
        MOV         C,M
        RET

        ;
        ; Get to next entry in command name database
        ;
cmd_name_char_1_wrong:
        INX         H
cmd_name_char_2_wrong:
        INX         H
        INX         H
        JMP         check_next_cmd_name


;//////////////////////////////////////

cmd_names_database:
        DB          'LM',1
        DB          'RM',2
        DB          'RA',3
        DB          'NA',4
        DB          'TS',5
        DB          'TP',6
        DB          'SL',7
        DB          'PL',8
        DB          'FL',9
        DB          'LL',10
        DB          'PN',11
        DB          'HT',12
        DB          'UF',13
        DB          'NP',14
        DB          'ST',15
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear entire output line, fill with spaces
        ;
blank_output_line_buffer:
        LXI         H,output_line_buffer
        MVI         A,132
blank_output_line_loop:
        MVI         M,' '
        INX         H
        DCR         A
        JNZ         blank_output_line_loop
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Align HL pointer (in output line buffer) to next tabulation stop
        ;
align_to_next_tab:
        PUSH        D
        XCHG
        LXI         B,active_layout + LS_TAB_LIST
check_tab_stop:
        ;
        ; Check for end of tab stops list
        ;
        LDAX        B
        PUSH        B
        ORA         A
        JZ          use_tab_stop
        ;
        ; Get pointer into output line buffer of checked tabulation stop
        ;
        MOV         C,A
        MVI         B,000H
        LXI         H,one_indexed_output_line_buffer
        DAD         B
        ;
        ; Select tab stop if pointer is after current output line buffer cursor
        ;
        MOV         A,H
        CMP         D
        JC          check_next_tab_stop
        JNZ         use_tab_stop
        MOV         A,L
        CMP         E
        JNC         use_tab_stop
check_next_tab_stop:
        ;
        ; Advance to check next tab stop
        ;
        POP         B
        INX         B
        JMP         check_tab_stop

use_tab_stop:
        POP         B
        POP         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert output line from left to right alignment
        ;
right_align_output_line:
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

sp_backup:
        DS          2
input_line_data_ptr:
        DS          2
most_recent_tab_ptr:
        DS          2
output_line_data_ptr:
        DS          2
console_output_flag:
        DS          1
console_line_counter:
        DS          1
lines_per_page:
        DS          1
margin_top:
        DS          1
margin_bottom:
        DS          1
page_number_str:
        DS          5
input_line_buffer:
        DS          129
        ;
        ; Tabs use output buffer 1-indexed, so reserve this byte just in case
        ;
one_indexed_output_line_buffer:
        DS          1
output_line_buffer:
        DS          132
output_line_buffer_overrun_char:
        DS          1
        DS          2
current_line_on_page:
        DS          1
multiple_pages_flag:
        DS          1
not_first_file_flag:
        DS          1
paragraph_line_counter:
        DS          1
input_line_wordbreak_ptr:
        DS          2
output_line_wordbreak_ptr:
        DS          2
line_nr_for_page_nr:
        DS          1
page_number_line_pos:
        DS          1
page_number_format:
        DS          1
page_number_bcd:
        DS          2
line_nr_for_title:
        DS          1
title_line_pos:
        DS          1
header_str:
        DS          75
global_layout:
        DS          36
active_layout:
        DS          36
disable_layout_flag:
        DS          1
target_line_nr:
        DS          1
target_line_pos:
        DS          1

missing_si_str:
        DB          'No SI assigned',CR
multiple_outputs_str:
        DB          'Both SO and SL',CR
multiple_inputs_str:
        DB          'Both SI and AI',CR

page_nr_prefix_2_str:
        DB          'PAGE ',NULL
page_nr_prefix_3_str:
        DB          'Page ',NULL
