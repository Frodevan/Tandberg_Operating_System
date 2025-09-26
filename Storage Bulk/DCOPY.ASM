;//////////////////////////////////////////////////////////////////////////////
;//
;//     DCOPY - Duplicate floppy
;//
;//         Extra parameters:
;//
;//             [$Y]
;//
;//                 Y       Copy from drive 0 to drive 1
;//
;//
;//         Duplicates an entire floppy-disk, track by track.
;//
;//         NOTE: Does not support sectors written using the deleted address marks.
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
; ASCII control characters
;
CR          EQU     00DH        ; Cartridge Return

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
DCALW       EQU     0FD70H      ; Reset disk drive with wait
DSRDW       EQU     0FD73H      ; Read from disk with wait
DSWRW       EQU     0FD76H      ; Write to disk with wait

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Print welcome prompt string
        ;
        LHLD        CO_FCB
        LXI         D,welcome_prompt_str
        CALL        PUT
        RC
parse_prompt_input:
        ;
        ; Expecy a Y to continue, otherwise exit program
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         'Y'
        RNZ
        ;
        ; Reset disk drives and get ready to start from track zero
        ;
        SUB         A
        CALL        DCALW
        RC
        MVI         A,1
        CALL        DCALW
        RC
        MVI         B,0
		;
		; Copy an entire track from floppy drive 0 to drive 1
		;
copy_next_track:
        ;
        ; Reset pointers and prepare to read from sector one
        ;
        LXI         H,original_track_buffer
        MVI         C,1
read_next_sector:
        SUB         A
        CALL        DSRDW
        RC
        LXI         D,128
        DAD         D
        MOV         A,C
        ADI         1
        MOV         C,A
        CPI         27
        JM          read_next_sector
        ;
        ; Reset pointers and prepare to write from sector one
        ;
        LXI         H,original_track_buffer
        MVI         C,1
write_next_sector:
        MVI         A,1
        CALL        DSWRW
        RC
        LXI         D,128
        DAD         D
        MOV         A,C
        ADI         1
        MOV         C,A
        CPI         27
        JM          write_next_sector
		;
		; Prepare to copy next track
		;
        INR         B
        MOV         A,B
        CPI         77
        JNZ         copy_next_track
        JMP         verify_copy


;//////////////////////////////////////

welcome_prompt_str:
        DB			'COPY FROM 0 TO 1 - TYPE Y TO START',CR


;//////////////////////////////////////////////////////////////////////////////

verify_copy:
        ;
        ; Reset disk drives and get ready to verify from track zero
        ;
        SUB         A
        CALL        DCALW
        RC
        MVI         A,1
        CALL        DCALW
        RC
        MVI         B,0
		;
		; Verify an entire track of floppy disks in drive 0 and 1
		;
verify_next_track:
		;
		; Read track from floppy drive 0
		;
        LXI         H,original_track_buffer
        MVI         C,1
read_next_original_sector:
        SUB         A
        CALL        DSRDW
        RC
        LXI         D,128
        DAD         D
        MOV         A,C
        ADI         1
        MOV         C,A
        CPI         27
        JM          read_next_original_sector
		;
		; Read track from floppy drive 1
		;
        LXI         H,copied_track_buffer
        MVI         C,1
read_next_copied_sector:
        MVI         A,1
        CALL        DSRDW
        RC
        LXI         D,128
        DAD         D
        MOV         A,C
        ADI         1
        MOV         C,A
        CPI         27
        JM          read_next_copied_sector
		;
		; Compare all bytes in the two tracks read
		;
        PUSH        B
        LXI         D,original_track_buffer
        LXI         H,copied_track_buffer
        LXI         B,26*128
verify_next_byte:
        LDAX        D
        CMP         M
        JNZ         verification_failed
        INX         H
        INX         D
        DCX         B
        MOV         A,B
        ORA         C
        JNZ         verify_next_byte
        POP         B
		;
		; Prepare to verify next track
		;
        INR         B
        MOV         A,B
        CPI         77
        JNZ         verify_next_track
		;
		; Disk verified correctly
		;
        LXI         D,good_copy_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        JMP         more_copies_prompt

verification_failed:
		;
		; Disk failed verification
		;
        POP         B
        LXI         D,bad_copy_str
        LHLD        CO_FCB
        CALL        PUT
        RC
		;
		; Prompt user if more copies are to be made
		;
more_copies_prompt:
        LXI         D,more_copies_ptompt_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JZ          parse_prompt_input
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

bad_copy_str:
		DB			'NOT '
good_copy_str:
		DB			'EQUAL',CR
more_copies_ptompt_str:
		DB			'MORE? - TYPE Y TO START NEXT',CR

original_track_buffer:
		DS			26*128
copied_track_buffer:
		DS			26*128
