;//////////////////////////////////////////////////////////////////////////////
;//
;//     DRSTC - Restore floppy image backup from tape
;//
;//         Recreates an entire floppy-disk in unit 0 from tape 0 track 0. Data is
;//         oriented sequentially, starting with sector 1-13 and 14-26 of track 0,
;//         immediately followed by track 1 etc.. all the way to track 76.
;//
;//         This tool is meant to be used to recover a backup that has been created
;//         using the DDUMC tool earlier.
;//
;//         This tool use XMON API calls for all operations, including text I/O,
;//         and as such any device-file assignements and extra parameters will be
;//         ignored for those particular versions. Disk and tape operations are
;//         handled through the XMON API, so care should still be taken since the
;//         tape portion of this API is missing on some versions of the computer.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the final report string is not printed
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
DCALW       EQU     00070H      ; Reset disk drive with wait
DSWRW       EQU     00076H      ; Write to disk with wait
CCAL        EQU     00091H      ; Reset tape cartridge
CUN         EQU     000A6H      ; Rewind and unload tape cartridge
CBRDW       EQU     000AFH      ; Read data from tape cartridge with wait


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

track_number:
        DS          1

welcome_prompt_str:
        DB          'RESTORE FROM CARTRIDGE 0 TRK 0 TO DISKETTE 0  TYPE Y TO START',CR
        DB          'END OF RESTORE',CR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string pointed to by
        ;
print_str:
        PUSH        PSW
        PUSH        H
print_next_char:
        MOV         A,M
        CALL        TTO
        INX         H
        CPI         CR
        JNZ         print_next_char
        ;
        ; Always print newline after cartridge return
        ;
        MVI         A,LF
        CALL        TTO
        POP         H
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Wait for user confirmation
        ;
        LXI         H,welcome_prompt_str
        CALL        print_str
        CALL        TTI
        CPI         'Y'
        JZ          start_recovery
        ANA         A
        RET


;//////////////////////////////////////

start_recovery:
        ;
        ; Echo user input from the prompt
        ;
        CALL        TTO
        MVI         A,CR
        CALL        TTO
        MVI         A,LF
        CALL        TTO
        ;
        ; Reset both tape and floppy drives
        ;
        SUB         A
        STA         track_number
        SUB         A
        CALL        CCAL
        RC
        SUB         A
        CALL        DCALW
        RC
        ;
        ; Restore the next track from tape to disk
        ;
restore_next_track:
        ;
        ; Read first half of track from tape
        ;
        SUB         A
        MOV         B,A
        LXI         H,data_buffer
        CALL        CBRDW
        RC
        ;
        ; Write databuffer to disk
        ;
        LXI         H,data_buffer
        LDA         track_number
        MOV         B,A
        MVI         C,1
restore_next_sector_first_half_track:
        SUB         A
        CALL        DSWRW
        RC
        LXI         D,128
        DAD         D
        INR         C
        MOV         A,C
        CPI         14
        JNZ         restore_next_sector_first_half_track
        ;
        ; Read second half of trck from tape
        ;
        SUB         A
        MOV         B,A
        LXI         H,data_buffer
        CALL        CBRDW
        RC
        ;
        ; Write databuffer to disk
        ;
        LXI         H,data_buffer
        LDA         track_number
        MOV         B,A
        MVI         C,14
restore_next_sector_last_half_track:
        SUB         A
        CALL        DSWRW
        RC
        LXI         D,128
        DAD         D
        INR         C
        MOV         A,C
        CPI         27
        JNZ         restore_next_sector_last_half_track
        ;
        ; Advance track number
        ;
        LDA         track_number
        INR         A
        STA         track_number
        CPI         77
        JNZ         restore_next_track
        ;
        ; Restore complete, unload tape
        ;
        SUB         A
        CALL        CUN
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Databuffer
;//
;//////////////////////////////////////////////////////////////////////////////

data_buffer:
        DS          128*13