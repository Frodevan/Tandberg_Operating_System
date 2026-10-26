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
;//             1.2: Entry at 0xC000
;//
;//                 -> First version I have
;//
;//             1.6: Entry at 0xC000
;//
;//                 -> Version ID written to 0x2700
;//                 -> Sets XMON debug flag for later XMON versions that needs this
;//
;//             2.0a: Entry at 0x2800
;//
;//                 -> No change
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
DEBUGX      EQU     0275EH      ; XMON debug flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DEBUG',NULL
        DB          '200'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02800H
start:
        MVI         A,TRUE
        STA         DEBUG
        STA         DEBUGX
        RET
