;//////////////////////////////////////////////////////////////////////////////
;//
;//     DEBUG - Set debug flag
;//
;//         Sets the debug flag, to load the XMON debugger when a program is run.
;//         Early versions will only use a flag for TOS to reset after a load,
;//         relying on XMON defaulting to loading the debugger on a warm-start.
;//         Later versions will also set a debug flag for XMON, guaranteeing that
;//         XMON will bring up the debugger.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
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
; Flag values
;
TRUE        EQU     1           ; Boolean True

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature
DEBUG       EQU     0272DH      ; TOS debug flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DEBUG',NULL
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        MVI         A,TRUE
        STA         DEBUG
        RET
