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
;//                     C       Don't abort EXEC sequence on system error
;//                     S       Disable write-protection feature
;//
;//
;//         Sets or clears the system switch for TOS. This switch is used to change
;//         the behaviour of different functionality in TOS, allthough the switch
;//         may only be set to one unique setting at any time.
;//
;//         NOTE: The switch is not actually verified to be within A-Z, so other
;//               values can be set as well. TOS will likely ignore invalid settings.
;//               Any value above uppercase Z will be adjusted for lower-to-uppercase,
;//               and this does include some characters before actual lowercase a.
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
;//             1.7: Entry at 0xC000
;//
;//                 -> System switch input generalized to values A-Z
;//                 -> Flushes excess input characters from the extra parameters
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
CR          EQU     00DH        ; Cartridge Return

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
        DB          '107'


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
        MOV         C,A
        CPI         CR
        JZ          clear_system_flag
        CPI         'Z' + 1
        JC          valid_system_flag
        SUI         'a' - 'A'
        JMP         valid_system_flag

clear_system_flag:
        ;
        ; Default to clear system flag
        ;
        SUB         A
valid_system_flag:
        ;
        ; Update TOS system flag and flush excess input arguments
        ;
        STA         SSWITCH
        MOV         A,C
flush_next_char:
        CPI         CR
        RZ
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         flush_next_char
