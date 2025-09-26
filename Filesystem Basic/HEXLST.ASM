;//////////////////////////////////////////////////////////////////////////////
;//
;//     HEXLST - List binary files as hexadecimal text
;//
;//         Lists input binary file SI as hexadecimal to output file SO. The
;//         listing will be in 16 bytes per line, 8 lines per paragraph.
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
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
EDBH        EQU     0FD2AH      ; Convert byte to 2-character ASCII hexadecimal

;
; TOS standard files
;
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer

;
; FCB mode flags
;
FM_BINARY   EQU     004H        ; Binary flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Set SI to binary read mode
        ;
        LHLD        SI_FCB
        INX         H
        MOV         A,M
        ORI         FM_BINARY
        MOV         M,A
        JMP         list_next_paragraph


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

data_buffer_index:
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

list_next_paragraph:
        ;
        ; Prepare to print one block of 8 lines
        ;
        MVI         C,8
list_next_line:
        ;
        ; Reset buffer and prepare to print one line
        ;
        MVI         B,16
        LXI         H,data_buffer
        SHLD        data_buffer_index
list_next_byte:
        ;
        ; Get next byte and add to buffer as hexadecimal ASCII
        ;
        LHLD        SI_FCB
        CALL        INCHAR
        JC          read_exception
        LHLD        data_buffer_index
        CALL        EDBH
        RC
        ;
        ; Separate bytes with a space and advance to next byte
        ;
        MVI         M,' '
        INX         H
        SHLD        data_buffer_index
        DCR         B
        JNZ         list_next_byte
        ;
        ; Line full, add line to output file and advance to next line
        ;
        LHLD        data_buffer_index
        MVI         M,CR
        LHLD        SO_FCB
        LXI         D,data_buffer
        CALL        PUT
        RC
        DCR         C
        JNZ         list_next_line
        ;
        ; Paragraph full, add extra newline directly to output file
        ;
        MVI         A,CR
        CALL        OUTCHAR
        RC
        MVI         A,LF
        CALL        OUTCHAR
        RC
        JMP         list_next_paragraph

read_exception:
        ;
        ; Assume end of file, so add final line of text to output file and quit
        ;
        LHLD        data_buffer_index
        MVI         M,CR
        LHLD        SO_FCB
        LXI         D,data_buffer
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data buffer
;//
;//////////////////////////////////////////////////////////////////////////////

data_buffer:
        DS          49
