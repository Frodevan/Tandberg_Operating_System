;//////////////////////////////////////////////////////////////////////////////
;//
;//     ASSIGN - Assign devices for consecutive commands
;//
;//         Assign standard devices and lock any of SI SO SL AI AO and/or AL for
;//         the duration of several program executions.
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
