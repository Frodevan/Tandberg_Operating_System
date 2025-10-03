;//////////////////////////////////////////////////////////////////////////////
;//
;//     DDUMC - Backup floppy image to tape
;//
;//         Extra parameters:
;//
;//             [$Y]
;//
;//                 Y       Immediately start the conversion
;//
;//
;//         Transfers all data from floppy-disk unit 0 to tape 0 track 0. Data is
;//         oriented sequentially, starting with sector 1-13 and 14-26 of track 0,
;//         immediately followed by track 1 etc.. all the way to track 76.
;//
;//         This tool is meant to be used to create a backup that can be recovered
;//         using the DRSTC tool later.
;//
;//         NOTE: Tape operations are handled through the XMON API in all versions,
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
;//                 -> Version ID written to 0x2700
;//
;//             1.7: Entry at 0xC04A
;//
;//                 -> Uses TOS device-files for text I/O, instead of XMON API
;//                 -> Flushes excess input characters from the extra parameters
;//                 -> Prints final status after the dump completes
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
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
DCALW       EQU     00070H      ; Reset disk drive with wait
DSRDW       EQU     00073H      ; Read from disk with wait
CCAL        EQU     00091H      ; Reset tape cartridge
CUN         EQU     000A6H      ; Rewind and unload tape cartridge
CBWRW       EQU     000B2H      ; Write data to tape cartridge with wait
CBTMW       EQU     000B8H      ; Write tape mark to tape cartridge with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_48    EQU     048H        ; TAPE MARK DETECTED


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DDUMC',NULL
        DB          '107'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
welcome_prompt_str:
        DB          'DUMP FROM DISKETTE 0 TO CARTRIDGE 0 TRK 0  TYPE Y TO START: ',CR
dump_done_str:
        DB          'END OF DUMP',CR

current_track_nr:
        DS          1


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

start:
        ;
        ; Print user prompt and expect a 'Y' to continue
        ;
        LXI         D,welcome_prompt_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        RZ
        CALL        to_uppercase
        MOV         C,A
flush_extra_input:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         flush_extra_input
        MOV         A,C
        CPI         'Y'
        JZ          start_disk_dump
        ANA         A
        RET

start_disk_dump:
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
        ;
        ; Print status and quit
        ;
        LXI         D,dump_done_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        SUB         A
        CALL        CUN
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
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
