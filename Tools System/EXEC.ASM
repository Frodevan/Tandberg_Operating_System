;//////////////////////////////////////////////////////////////////////////////
;//
;//     EXEC - Run command sequence with assigned devices
;//
;//         Used to run command line sequences stored in batch-files. To run a
;//         batch-file, run EXEC while assigning CI to the file containing the
;//         command-sequence to run through.
;//
;//         EXEC also ASSIGNs, so see ASSIGN for more details. But in addition,
;//         a flag is also set before handing back control to TOS. This flag is
;//         recognized by the TOS command line parser, and will ensure that CI is
;//         not released until an End of File status occurs.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have, binary identical to ASSIGN v1.3
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> Sets flag used to enable batch-file execution on TOS v1.5+
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
TRUE        EQU     -1          ; Boolean True

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature
EXSW        EQU     027B2H      ; TOS EXEC batch-file assigned switch

;
; TOS standard files
;
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
        DB          'EXEC',NULL,NULL
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
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
        ;
        ; Flag TOS that a batch-file is assigned to CI
        ;
        MVI         A,TRUE
        STA         EXSW
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
