;//////////////////////////////////////////////////////////////////////////////
;//
;//     DDUMC - Backup floppy image to tape
;//
;//         Transfers all data from floppy-disk unit 0 to tape 0 track 0. Data is
;//         oriented sequentially, starting with sector 1-13 and 14-26 of track 0,
;//         immediately followed by track 1 etc.. all the way to track 76.
;//
;//         This tool is meant to be used to create a backup that can be recovered
;//         using the DRSTC tool later.
;//
;//         NOTE: Uses XMON API calls for all operations, including text I/O, and
;//               as such any device-file assignements will be ignored. Disk and
;//               tape operations are handled through the XMON API in all versions,
;//               so care should still be taken since the tape portion of this API
;//               is missing on some versions of the computer.
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
;//                 -> Accepts uppercase letters at the prompt
;//                 -> Will never raise tape-mark-detected at the end of dump
;//
;//             1.6: Entry at 0xC05D
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
DSRDW       EQU     00073H      ; Read from disk with wait
CCAL        EQU     00091H      ; Reset tape cartridge
CUN         EQU     000A6H      ; Rewind and unload tape cartridge
CBWRW       EQU     000B2H      ; Write data to tape cartridge with wait
CBTMW       EQU     000B8H      ; Write tape mark to tape cartridge with wait

;
; TOS Errors
;
ERROR_48    EQU     048H        ; TAPE MARK DETECTED


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Legacy program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
        JMP         main_program


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

welcome_prompt_str:
        DB          'DUMP FROM DISKETTE 0 TO CARTRIDGE 0 TRK 0  TYPE Y TO START',CR
dump_done_str:
        DB          'END OF DUMP',CR

current_track_nr:
        DS          1


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string pointed to by HL, incl. cartridge return and new line
        ;
print_str:
        PUSH        PSW
        PUSH        H
print_str_loop:
        MOV         A,M
        CALL        TTO
        INX         H
        CPI         CR
        JNZ         print_str_loop
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

start:
main_program:
        ;
        ; Print user prompt and expect a 'Y' to continue
        ;
        LXI         H,welcome_prompt_str
        CALL        print_str
        CALL        TTI
        CALL        to_uppercase
        CPI         'Y'
        JZ          start_disk_dump
        ANA         A
        RET

start_disk_dump:
        ;
        ; Echo input and advance cursor to the next line
        ;
        CALL        TTO
        MVI         A,CR
        CALL        TTO
        MVI         A,LF
        CALL        TTO
        ;
        ; Get everything ready for copying
        ;
        SUB         A
        STA         current_track_nr
        SUB         A
        CALL        CCAL
        RC
        SUB         A
        CALL        DCALW
        RC
        ;
        ; Dump a track to tape cartridge
        ;
dump_next_track:
        ;
        ; Prepare to read first half of track from disk
        ;
        LXI         H,data_buffer
        LDA         current_track_nr
        MOV         B,A
        MVI         C,1
        ;
        ; Dump the next sector from disk to data buffer
        ;
dump_next_sector_first_half_track:
        SUB         A
        CALL        DSRDW
        RC
        LXI         D,128
        DAD         D
        INR         C
        MOV         A,C
        CPI         14
        JNZ         dump_next_sector_first_half_track
        ;
        ; Write buffer with first half of track to tape
        ;
        SUB         A
        MOV         B,A
        LXI         D,128*13
        LXI         H,data_buffer
        CALL        CBWRW
        RC
        ;
        ; Prepare to read second half of track from disk
        ;
        LXI         H,data_buffer
        LDA         current_track_nr
        MOV         B,A
        MVI         C,14
        ;
        ; Dump the next sector from disk to data buffer
        ;
dump_next_sector_last_half_track:
        SUB         A
        CALL        DSRDW
        RC
        LXI         D,128
        DAD         D
        INR         C
        MOV         A,C
        CPI         27
        JNZ         dump_next_sector_last_half_track
        ;
        ; Write buffer with second half of track to tape
        ;
        SUB         A
        MOV         B,A
        LXI         D,128*13
        LXI         H,data_buffer
        CALL        CBWRW
        RC
        ;
        ; Advance to next track on disk
        ;
        LDA         current_track_nr
        INR         A
        STA         current_track_nr
        CPI         77
        JNZ         dump_next_track
        ;
        ; Write tape mark and unload
        ;
        SUB         A
        MOV         B,A
        CALL        CBTMW
        JNC         tape_mark_written
        CPI         ERROR_48
        JZ          tape_mark_written
        STC
        RET

tape_mark_written:
        RC
        SUB         A
        CALL        CUN
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert character in A to uppercase
        ;
to_uppercase:
        CPI         'a'
        RM
        CPI         'z'+1
        RP
        ANI         0DFH
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Databuffer
;//
;//////////////////////////////////////////////////////////////////////////////

data_buffer:
        DS          128*13
