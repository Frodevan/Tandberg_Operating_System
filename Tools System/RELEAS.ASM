;//////////////////////////////////////////////////////////////////////////////
;//
;//     RELEAS - Release devices assigned with ASSIGN
;//
;//         Releases all assigned devices, and enables reasignement of these.
;//         This should be done to revert any assignements done earlier by ASSIGN,
;//         when the effects of ASSIGN is no longer needed.
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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Clear stay-open flag of any cli-assigned abstract file
        ;
        LHLD        SI_FCB
        CALL        release_file
        LHLD        SO_FCB
        CALL        release_file
        LHLD        SL_FCB
        CALL        release_file
        LHLD        AI_FCB
        CALL        release_file
        LHLD        AO_FCB
        CALL        release_file
        LHLD        AL_FCB
        CALL        release_file
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

release_file:
        ;
        ; Check if FCB is assigned and if stay-open flag is currently set
        ;
        MOV         A,H
        ORA         L
        RZ
        INX         H
        MOV         A,M
        ANI         040H
        RZ
        ;
        ; Check if FCB was assigned by TOS from a command line argument
        ;
        MOV         A,M
        ANI         020H
        RZ
        ;
        ; Clear flag to enable file to be closed by TOS on program termination
        ;
        MOV         A,M
        XRI         040H
        MOV         M,A
        RET
