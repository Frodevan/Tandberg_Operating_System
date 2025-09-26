;//////////////////////////////////////////////////////////////////////////////
;//
;//     MOVE - Move lines of text
;//
;//         Copy lines of text from input file SI to output file SO, as well as
;//         sending a second copy in all uppercase to SL if assigned.
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
; ASCII control characters
;
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; TOS system calls
;
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR

;
; TOS standard files
;
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer

;
; TOS Errors
;
ERROR_00    EQU     000H        ; END OF FILE


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
move_next_line:
        ;
        ; Get next line from input file into databuffer
        ;
        LHLD        SI_FCB
        LXI         D,data_buffer
        CALL        GET
        JC          read_exception
        ;
        ; Write line to output file
        ;
        LXI         D,data_buffer
        LHLD        SO_FCB
        CALL        PUT
        RC
        ;
        ; Check if line device is set
        ;
        LHLD        SL_FCB
        MOV         A,H
        ORA         L
        JZ          move_next_line
        ;
        ; Convert line to uppercase
        ;
        LXI         H,data_buffer
convert_next_char:
        MOV         A,M
        CPI         CR
        JZ          convert_line_done
        CPI         'a'
        JM          is_uppercase
        CPI         'z'+1
        JP          is_uppercase
        ANI         0DFH
        MOV         M,A
is_uppercase:
        INX         H
        JMP         convert_next_char

convert_line_done:
        ;
        ; Send converted line to line device
        ;
        LHLD        SL_FCB
        LXI         D,data_buffer
        CALL        PUT
        RC
        JMP         move_next_line

read_exception:
        ;
        ; Check for end of file
        ;
        CPI         ERROR_00
        RZ
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data buffer
;//
;//////////////////////////////////////////////////////////////////////////////

data_buffer:
        DS          80
