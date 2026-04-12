;//////////////////////////////////////////////////////////////////////////////
;//
;//     COPY - Copy one block-device file to another block device file
;//
;//         Copies block device file SI to output block device file SO. This can
;//         only be used to copy files on block devices.
;//
;//
;//         Changelog:
;//
;//             1.2: Entry at 0xC000
;//
;//                 -> First version I have
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; TOS system calls
;
READ        EQU     0FD21H      ; Read next block from block device
WRITE       EQU     0FD24H      ; Write next block to block device

;
; TOS standard files
;
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer

;
; TOS Errors
;
ERROR_00    EQU     000H        ; END OF FILE

;
; TOS File Control Block, block device variables
;
FCB_BUFPTR  EQU     006H        ; Pointer to block/buffered-device data buffer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Get pointer to input/output file buffers
        ;
        LHLD        SI_FCB
        LXI         D,FCB_BUFPTR
        DAD         D
        MOV         E,M
        INX         H
        MOV         D,M
        LHLD        SO_FCB
        LXI         B,FCB_BUFPTR
        DAD         B
        MOV         C,M
        INX         H
        MOV         B,M
        JMP         copy_block

copy_next_block:
        ;
        ; Read next block
        ;
        LHLD        SI_FCB
        CALL        READ
        JC          read_exception
copy_block:
        ;
        ; Copy bytes from input file buffer to output file buffer
        ;
        PUSH        D
        PUSH        B
        MVI         H,128
copy_next_byte:
        LDAX        D
        STAX        B
        INX         D
        INX         B
        DCR         H
        JNZ         copy_next_byte
        ;
        ; Get read length
        ;
        LHLD        SI_FCB
        INX         H
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; SI_FCB + FCB_BUFLEN
        INX         H
        MOV         D,M
        ;
        ; Set output file buffer index and length to cover input file buffer
        ;
        LHLD        SO_FCB
        INX         H
        INX         H
        MOV         M,E             ; SO_FCB + FCB_BUFIDX
        INX         H
        MOV         M,D
        INX         H
        MOV         M,E             ; SO_FCB + FCB_BUFLEN
        INX         H
        MOV         M,D
        POP         B
        POP         D
        ;
        ; Write copied block
        ;
        LHLD        SO_FCB
        CALL        WRITE
        RC
        JMP         copy_next_block

read_exception:
        ;
        ; Check for end of file
        ;
        CPI         ERROR_00
        RZ
        STC
        RET
