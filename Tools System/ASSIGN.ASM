;//////////////////////////////////////////////////////////////////////////////
;//
;//     ASSIGN - Assign devices for consecutive commands
;//
;//         Extra parameters:
;//
;//             [$<option>[,<option>[,<option>[...]]]]
;//
;//                 option      Swap assigned XMON handlers
;//
;//                 Options:
;//                     CI=RC   Main UART instead of local input for CI handler
;//                     CE=RE   Main UART instead of local input for CE handler
;//                     CO=XM   Printer instead of local output for CO handler
;//
;//
;//         Assign standard devices and lock any of SI SO SL AI AO and/or AL for
;//         the duration of several program executions. If extra options are added
;//         (and supported), these handlers are also updated.
;//
;//         NOTE: Swapping assigned XMON handlers requires features that were
;//               introduced in TOS v1.8. There is no safeguard against using these
;//               options on an unsuported version of TOS, and worst case you may
;//               end up with garbage being written all over RAM. This may in turn
;//               lead to unpredictable behaviour and eventually a system crash.
;//
;//         NOTE: Option CE=RE is broken in TOS v1.8x due to a bug in TOS itself,
;//               and is likely to crash the system if selected.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
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
;//                 -> Adds options if CI is a line device
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
RCVI        EQU     00082H      ; Main UART input
XMIO        EQU     000CAH      ; Main UART output

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
GET         EQU     0FD0FH      ; Input string, inclusive CR

;
; TOS device file handler-pointer lists
;
DEV_CI_REFS EQU     0FEE0H      ; Pointer to list with pointers to :CI: handler
DEV_CE_REFS EQU     0FEE2H      ; Pointer to list with pointers to :CE: handler
DEV_CO_REFS EQU     0FEE4H      ; Pointer to list with pointers to :CO: handler

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
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

;
; TOS Errors
;
ERROR_26    EQU     026H        ; IMPROPER PARAMETER


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'ASSIGN'
        DB          '107'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Check if CI is line-buffered
        ;
        LHLD        CI_FCB
        MOV         A,M
        CPI         4
        JNZ         no_more_args
        ;
        ; Get character count
        ;
        INX         H
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        PUSH        D
        INX         H
        ;
        ; Get pointer to buffer
        ;
        INX         H
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        POP         H
        ;
        ; Check if a complete line is ready
        ;
        DAD         D
        MOV         A,M
        CPI         LF
        JZ          no_more_args
        ;
        ; Get command line argument string
        ;
        LXI         D,cli_args_buffer
        LHLD        CI_FCB
        CALL        GET
        RC
        LXI         H,cli_args_buffer
        CALL        args_to_uppercase
        ;
        ; Parse argument string
        ;
        LXI         H,cli_args_buffer
parse_next_arg:
        ;
        ; Ignore spaces between arguments
        ;
skip_spaces_loop:
        MOV         A,M
        CPI         ' '
        JNZ         parse_argument
        INX         H
        JMP         skip_spaces_loop

        ;
        ; Parse single argument from argument string
        ;
parse_argument:
        ;
        ; Check if we got to the end of the args
        ;
        CPI         CR
        JZ          no_more_args
        ;
        ; Set up working pointers
        ;
        SHLD        cli_args_buffer_ptr
        LXI         H,available_args_list
        SHLD        (available_args_list_ptr)
test_arg_against_next_definition:
        ;
        ; Get pointer to next argument definition
        ;
        LHLD        (available_args_list_ptr)
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        SHLD        (available_args_list_ptr)
        ;
        ; Exit with error if no matches and no more definitions left
        ;
        MOV         A,E
        ORA         D
        MVI         A,ERROR_26
        STC
        RZ
        ;
        ; Compare current argument to definition
        ;
        LHLD        cli_args_buffer_ptr
compare_arg_loop:
        LDAX        D
        CMP         M
        JNZ         arg_comparison_done
        INX         H
        INX         D
        JMP         compare_arg_loop

arg_comparison_done:
        ;
        ; Check verdict of comparison, test against next definition if no match
        ;
        ANA         A
        JNZ         test_arg_against_next_definition
        ;
        ; Check if more args are coming, and if the correct deliminer is used
        ;
        MOV         A,M
        CPI         CR
        JZ          valid_argument_found
        CPI         ','
        MVI         A,ERROR_26
        STC
        RNZ
valid_argument_found:
        ;
        ; Jump to arg handler
        ;
        SHLD        cli_args_buffer_ptr
        XCHG
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        PCHL


;//////////////////////////////////////////////////////////////////////////////

argument_handling_complete:
        ;
        ; Check if there are more args pending
        ;
        LHLD        cli_args_buffer_ptr
        MOV         A,M
        CPI         CR
        JZ          no_more_args
        INX         H
        JMP         parse_next_arg


;//////////////////////////////////////

set_ci_to_rc:
        ;
        ; Point to list of :CI: handler pointers
        ;
        LHLD        DEV_CI_REFS
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
        JZ          argument_handling_complete
        INX         H
        ;
        ; Replace one pointer to :CI: handler with pointer to handler for :RC:
        ;
        PUSH        H
        XCHG
        LXI         D,RCVI
        MOV         M,E
        INX         H
        MOV         M,D
        POP         H
        JMP         replace_next_ci_handler_ptr_loop


;//////////////////////////////////////

set_ce_to_re:
        ;
        ; Point to list of :CE: handler pointers
        ;
        LHLD        DEV_CE_REFS
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
        JZ          argument_handling_complete
        INX         H
        ;
        ; Replace one pointer to :CE: handler with pointer to handler for :RE:
        ;
        PUSH        H
        XCHG
        LXI         D,RCVI
        MOV         M,E
        INX         H
        MOV         M,D
        POP         H
        JMP         replace_next_ce_handler_ptr_loop


;//////////////////////////////////////

set_co_to_xm:
        ;
        ; Point to list of :CO: handler pointers
        ;
        LHLD        DEV_CO_REFS
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
        JZ          argument_handling_complete
        INX         H
        ;
        ; Replace one pointer to :CO: handler with pointer to handler for :XM:
        ;
        PUSH        H
        XCHG
        LXI         D,XMIO
        MOV         M,E
        INX         H
        MOV         M,D
        POP         H
        JMP         replace_next_co_handler_ptr_loop


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert entire arguments string to uppercase
        ;
args_to_uppercase:
        LXI         H,cli_args_buffer
str_to_uppercase_loop:
        MOV         A,M
        CPI         CR
        RZ
        CALL        to_uppercase
        MOV         M,A
        INX         H
        JMP         str_to_uppercase_loop


;//////////////////////////////////////

        ;
        ; Convert character in A to uppercase
        ;
to_uppercase:
        CPI         'a'
        RM
        CPI         'z'+1
        RP
        ANI         0DFH
        RET


;//////////////////////////////////////////////////////////////////////////////

available_args_list:
        DW          ci_to_rc_arg
        DW          ce_to_re_arg
        DW          co_to_xm_arg
        DW          0

ci_to_rc_arg:
        DB          'CI=RC',NULL
        DW          set_ci_to_rc

ce_to_re_arg:
        DB          'CE=RE',NULL
        DW          set_ce_to_re

co_to_xm_arg:
        DB          'CO=XM',NULL
        DW          set_co_to_xm


;//////////////////////////////////////////////////////////////////////////////

no_more_args:
        ;
        ; Flag any cli-assigned abstract file to stay open
        ;
        LHLD        SI_FCB
        CALL        lock_assigned_fcb_open
        LHLD        SO_FCB
        CALL        lock_assigned_fcb_open
        LHLD        SL_FCB
        CALL        lock_assigned_fcb_open
        LHLD        AI_FCB
        CALL        lock_assigned_fcb_open
        LHLD        AO_FCB
        CALL        lock_assigned_fcb_open
        LHLD        AL_FCB
        CALL        lock_assigned_fcb_open
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

lock_assigned_fcb_open:
        ;
        ; Check if FCB is assigned
        ;
        MOV         A,H
        ORA         L
        RZ
        ;
        ; Check if FCB was assigned by TOS from a command line argument
        ;
        INX         H
        MOV         A,M
        ANI         FM_ASSIGNED
        RZ
        ;
        ; Set flag to prevent file closure
        ;
        MOV         A,M
        ORI         FM_NO_CLOSE
        MOV         M,A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

cli_args_buffer_ptr:
        DW          00000H
available_args_list_ptr:
        DW          00000H

cli_args_buffer:
