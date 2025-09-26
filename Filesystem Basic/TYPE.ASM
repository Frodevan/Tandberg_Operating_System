;//////////////////////////////////////////////////////////////////////////////
;//
;//     TYPE - Type file content to console
;//
;//         Prints the contents of file SI to the screen, in pages. At the end of a
;//         page, the user can press space to see the next page, or cartridge
;//         return to quit the program.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return
ERPAG       EQU     019H        ; Clear screen

;
; XMON system calls
;
TTO         EQU     00043H      ; Console output

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character

;
; TOS standard files
;
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
type_next_page:
        ;
        ; Clear screen
        ;
        LHLD        SI_FCB
        MVI         A,ERPAG
        CALL        TTO
        ;
        ; Print the next 24 lines from input file
        ;
        MVI         C,24
type_next_char:       
        ;
        ; Get next character, assume end of file on error
        ;
        CALL        INCHAR
        JNC         check_newline
        SUB         A
        RET         

check_newline:       
        ;
        ; Check for end of line, and if so check for end of page
        ;
        CALL        TTO
        CPI         CR
        JNZ         type_next_char
        MVI         A,LF
        CALL        TTO
        DCR         C
        JNZ         type_next_char
        ;
        ; Wait for user to press space or cartridge return at end of page
        ;
end_of_page_prompt:       
        CALL        TTI
        CALL        TTO
        CPI         ' '
        JZ          type_next_page
        CPI         CR
        RZ          
        MVI         A,'?'
        CALL        TTO
        JMP         end_of_page_prompt
