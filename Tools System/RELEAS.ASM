;//////////////////////////////////////////////////////////////////////////////
;//
;//     RELEAS - Release devices assigned with ASSIGN
;//
;//         Extra parameters:
;//
;//             [$<dev>[,<dev>[,<dev>[...]]]]
;//
;//                 dev         Device to be released, none means no change
;//
;//                 Device dev:
;//                     SI      Release SI
;//                     SO      Release SO
;//                     SL      Release SL
;//                     AI      Release AI
;//                     AO      Release AO
;//                     AL      Release AL
;//
;//
;//         Releases a list of assigned devices, and enables reasignement of these.
;//         This should be done to revert any assignements done earlier by ASSIGN,
;//         when the effects of ASSIGN is no longer needed.
;//
;//         NOTE: This tool does not actually check for the devices to be released
;//               to be a comma-separated list, and the comma in the extra
;//               parameters is as such optional. It is included here for
;//               readability case, but due to the implementation it should also
;//               work with no comma, or even any non-alphabetic character as
;//               separator such as space or period.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> Files to be released are now specified as a list of command-
;//                    line arguments, instead of all files being released
;//
;//             1.6a: Entry at 0xC000
;//
;//                 -> Version ID added
;//                 -> Has a bug where Version ID is not written to 0x2700
;//
;//             1.6b: Entry at 0xC000
;//
;//                 -> Fixes Version ID bug from v1.6a
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
CR          EQU     00DH        ; Cartridge Return

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer
AI_FCB      EQU     0FF0AH      ; Auxilliary input abstract file FCB pointer
AO_FCB      EQU     0FF0CH      ; Auxilliary output abstract file FCB pointer
AL_FCB      EQU     0FF0EH      ; Auxilliary line-printer output abstract file FCB pointer

;
; FCB mode flags
;
FM_ASSIGNED EQU     020H        ; Assigned and opened by command line flag
FM_NO_CLOSE EQU     040H        ; Don't close file flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'RELEAS'
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Parse next file handle name from command line arguments
        ;
parse_next_argument:
        ;
        ; Get first char of file handle name and convert it to uppercase
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JZ          release_done
        CPI         'A'
        JC          parse_next_argument
        CPI         'Z'+1
        JC          parse_first_char
        SUI         'a' - 'A'
parse_first_char:
        ;
        ; Select offset to sub-list in list of file pointers
        ;
        CPI         'S'
        MVI         B,std_file_ptr_list - file_ptr_list
        JZ          valid_first_char
        CPI         'A'
        MVI         B,aux_file_ptr_list - file_ptr_list
        JNZ         invalid_parameter
valid_first_char:
        ;
        ; Get second char of file handle name and convert it to uppercase
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         'Z'+1
        JC          parse_second_char
        SUI         'a' - 'A'
parse_second_char:
        ;
        ; Select offset inside of sub-list in list file pointers
        ;
        CPI         'I'
        MVI         C,000H
        JZ          release_file
        CPI         'O'
        MVI         C,002H
        JZ          release_file
        CPI         'L'
        MVI         C,004H
        JNZ         invalid_parameter


;//////////////////////////////////////

release_file:
        ;
        ; Get relative offset to entry in file pointer list
        ;
        MOV         A,B
        ADD         C
        MOV         C,A
        MVI         B,000H
        ;
        ; Get absolute pointer to entry in file pointer list
        ;
        LXI         H,file_ptr_list
        DAD         B
        MOV         E,M
        INX         H
        MOV         D,M
        ;
        ; Read out file pointer from list entry
        ;
        XCHG
        MOV         E,M
        INX         H
        MOV         D,M
        ;
        ; Check if FCB is assigned and if stay-open flag is currently set
        ;
        MOV         A,D
        ORA         E
        JZ          parse_next_argument
        INX         D
        LDAX        D
        ANI         FM_NO_CLOSE
        JZ          parse_next_argument
        ;
        ; Check if FCB was assigned by TOS from a command line argument
        ;
        LDAX        D
        ANI         FM_ASSIGNED
        JZ          parse_next_argument
        ;
        ; Clear flag to enable file to be closed by TOS on program termination
        ;
        LDAX        D
        XRI         FM_NO_CLOSE
        STAX        D
        JMP         parse_next_argument


;//////////////////////////////////////

invalid_parameter:
        ;
        ; Flush remaining command line arguments
        ;
flush_next_char:
        CPI         CR
        JZ          flush_done
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         flush_next_char

flush_done:
        LXI         D,invalid_parameters_str
        JMP         print_and_quit

release_done:
        LXI         D,released_str
        ;
        ; Print status and quit
        ;
print_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

file_ptr_list:
std_file_ptr_list:
        DW          SI_FCB
        DW          SO_FCB
        DW          SL_FCB
aux_file_ptr_list:
        DW          AI_FCB
        DW          AO_FCB
        DW          AL_FCB

released_str:
        DB          'RELEASED',CR
invalid_parameters_str:
        DB          'IMPROPER PARAMETER LIST',CR
