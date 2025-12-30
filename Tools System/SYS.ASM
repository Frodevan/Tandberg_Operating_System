;//////////////////////////////////////////////////////////////////////////////
;//
;//     SYS - Set TOS system switches
;//
;//         Extra parameters:
;//
;//             [$<switch>]
;//
;//                 switch      Switch to set, none clears previously set switch
;//
;//                 Switch sw:
;//
;//                     S       Disable write-protection feature
;//
;//
;//         Sets or clears the system switch for TOS. This switch is used to change
;//         the behaviour of different functionality in TOS, allthough the switch
;//         may only be set to one unique setting at any time.
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
;//                 -> Adds support for lowercase input
;//
;//             1.6: Entry at 0xC000
;//
;//                 -> Version ID written to 0x2700
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

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature
SSWITCH     EQU     0272CH      ; TOS system switch

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'SYS',NULL,NULL,NULL
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Get and verify system flag from command line arguments
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         'S'
        JZ          valid_system_flag
        CPI         's'
        JNZ         clear_system_flag
        SUI         'a' - 'A'
        JMP         valid_system_flag

clear_system_flag:
        ;
        ; Default to clear system flag
        ;
        SUB         A
valid_system_flag:
        ;
        ; Update TOS system flag
        ;
        STA         SSWITCH
        ANA         A
        RET
