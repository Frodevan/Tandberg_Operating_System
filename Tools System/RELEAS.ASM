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
;//                     CI      Local input for CI handler
;//                     CE      Local input for CE handler
;//                     CO      Local output for CO handler
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
;//         NOTE: Releasing assigned XMON handlers requires features that were
;//               introduced in TOS v1.8. There is no safeguard against using these
;//               options on an unsuported version of TOS, and worst case you may
;//               end up with garbage being written all over RAM. This may in turn
;//               lead to unpredictable behaviour and eventually a system crash.
;//
;//         NOTE: Option CE is broken in TOS v1.8x due to a bug in TOS itself, and
;//               is likely to crash the system if selected.
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
;//             1.7: Entry at 0xC000
;//
;//                 -> Adds CI, CE and CO as valid options
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
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR

;
; TOS device file handler-pointer lists
;
DEV_CI_PTRS EQU     0FEE0H      ; Pointer to list with pointers to :CI: handler
DEV_CE_PTRS EQU     0FEE2H      ; Pointer to list with pointers to :CE: handler
DEV_CO_PTRS EQU     0FEE4H      ; Pointer to list with pointers to :CO: handler

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
        DB          '107'


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
        CPI         'C'
        JZ          console_handlers_arg
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


;//////////////////////////////////////////////////////////////////////////////

console_handlers_arg:
        CALL        INCHAR
        RC
        CPI         'Z'+1
        JC          parse_console_handler_second_char
        SUI         'a' - 'A'
parse_console_handler_second_char:
        CPI         'I'
        JZ          restore_ci
        CPI         'E'
        JZ          restore_ce
        CPI         'O'
        JZ          restore_co
        JMP         invalid_parameter


;//////////////////////////////////////

restore_ci:
        ;
        ; Point to list of :CI: handler pointers
        ;
        LHLD        DEV_CI_PTRS
replace_next_ci_handler_ptr_loop:
        ;
        ; Get next pointer from list
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        ;
        ; Check if we are at the end of the list
        ;
        MOV         A,E
        ORA         D
        JZ          parse_next_argument
        INX         H
        ;
        ; Restore one pointer to :CI: handler
        ;
        PUSH        H
        XCHG
        LXI         D,TTI
        MOV         M,E
        INX         H
        MOV         M,D
        POP         H
        JMP         replace_next_ci_handler_ptr_loop


;//////////////////////////////////////

restore_ce:
        ;
        ; Point to list of :CE: handler pointers
        ;
        LHLD        DEV_CE_PTRS
replace_next_ce_handler_ptr_loop:
        ;
        ; Get next pointer from list
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        ;
        ; Check if we are at the end of the list
        ;
        MOV         A,E
        ORA         D
        JZ          parse_next_argument
        INX         H
        ;
        ; Restore one pointer to :CE: handler
        ;
        PUSH        H
        XCHG
        LXI         D,TTI
        MOV         M,E
        INX         H
        MOV         M,D
        POP         H
        JMP         replace_next_ce_handler_ptr_loop


;//////////////////////////////////////

restore_co:
        ;
        ; Point to list of :CO: handler pointers
        ;
        LHLD        DEV_CO_PTRS
replace_next_co_handler_ptr_loop:
        ;
        ; Get next pointer from list
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        ;
        ; Check if we are at the end of the list
        ;
        MOV         A,E
        ORA         D
        JZ          parse_next_argument
        INX         H
        ;
        ; Restore one pointer to :CO: handler
        ;
        PUSH        H
        XCHG
        LXI         D,TTO
        MOV         M,E
        INX         H
        MOV         M,D
        POP         H
        JMP         replace_next_co_handler_ptr_loop


;//////////////////////////////////////////////////////////////////////////////

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
