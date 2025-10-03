;//////////////////////////////////////////////////////////////////////////////
;//
;//     DRSTC - Restore floppy image backup from tape
;//
;//         Extra parameters:
;//
;//             [$Y]
;//
;//                 Y       Immediately start the conversion
;//
;//
;//         Recreates an entire floppy-disk in unit 0 from tape 0 track 0. Data is
;//         oriented sequentially, starting with sector 1-13 and 14-26 of track 0,
;//         immediately followed by track 1 etc.. all the way to track 76.
;//
;//         This tool is meant to be used to recover a backup that has been created
;//         using the DDUMC tool earlier.
;//
;//         Disk and tape operations are handled through the XMON API, so care
;//         should still be taken since the tape portion of this API is missing on
;//         some versions of the computer.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the final report string is not printed
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> Accepts lowercase input
;//
;//             1.6: Entry at 0xC063
;//
;//                 -> Version ID written to 0x2700
;//
;//             1.7: Entry at 0xC050
;//
;//                 -> Uses TOS device-files for text I/O, instead of XMON API
;//                 -> Flushes excess input characters from the extra parameters
;//                 -> Fixes final report string bug from v1.3
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
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
DCALW       EQU     00070H      ; Reset disk drive with wait
DSWRW       EQU     00076H      ; Write to disk with wait
CCAL        EQU     00091H      ; Reset tape cartridge
CUN         EQU     000A6H      ; Rewind and unload tape cartridge
CBRDW       EQU     000AFH      ; Read data from tape cartridge with wait

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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DRSTC',NULL
        DB          '107'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
welcome_prompt_str:
        DB          'RESTORE FROM CARTRIDGE 0 TRK 0 TO DISKETTE 0  TYPE Y TO START: ',CR
restore_complete_str:
        DB          'END OF RESTORE',CR

track_number:
        DS          1


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

start:
        ;
        ; Wait for user confirmation
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
        ;
        ; Flush remaining input
        ;
        MOV         C,A
flush_next_input_char:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         flush_next_input_char
        MOV         A,C
        ;
        ; Verify user input
        ;
        CPI         'Y'
        RNZ


;//////////////////////////////////////

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
        RC
        LXI         D,restore_complete_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII character in A to uppercase
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