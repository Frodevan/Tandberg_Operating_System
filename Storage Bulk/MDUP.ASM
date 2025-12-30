;//////////////////////////////////////////////////////////////////////////////
;//
;//     MDUP - Duplicate tape
;//
;//
;//         Copy the entirety of tape in unit 0 onto the tape in unit 1. All
;//         records on all of the four tracks will be copied over as-is, making an
;//         exact copy.
;//
;//         NOTE: Uses XMON API calls for tape and everything. This enables this
;//               program to be loaded directly from the XMON debugger, with no
;//               dependency on TOS. Otherwise, the tape API calls were an optional
;//               addition to XMON, so some care should be taken to check for
;//               compatibility before running this program.
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
;//                 -> Will accept lowercase input at the prompt
;//
;//             1.6: Entry at 0xC055
;//
;//                 -> Version ID written to 0x2700
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
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
CCAL        EQU     00091H      ; Reset tape cartridge
CBBS        EQU     0009AH      ; Backspace one block on tape cartridge with wait
CUN         EQU     000A6H      ; Rewind and unload tape cartridge
CWT         EQU     000ACH      ; Wait for tape command complete
CBRDW       EQU     000AFH      ; Read data from tape cartridge with wait
CBWRW       EQU     000B2H      ; Write data to tape cartridge with wait
CBTMW       EQU     000B8H      ; Write tape mark to tape cartridge with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS Errors
;
ERROR_46    EQU     046H        ; READING ERASED TAPE
ERROR_48    EQU     048H        ; TAPE MARK DETECTED


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'MDUP',NULL,NULL
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
welcome_prompt_str:
        DB          'CARTRIDGE COPY FROM 0 TO 1 REPLY Y TO START',CR
copy_ok_str:
        DB          'COPY SUCCESSFULLY COMPLETED',CR
copy_aborted_str:
        DB          'NO COPY MADE',CR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program entry
;//
;//////////////////////////////////////////////////////////////////////////////

start:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////


current_track:
        DB          0
preliminary_data_end_ptr:
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string pointed to by HL
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
        MVI         A,LF
        CALL        TTO
        POP         H
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Fill databuffer with the particular byte in A
        ;
fill_data_buffer:
        PUSH        B
        PUSH        H
        LXI         B,2048
        INR         B
        LXI         H,data_buffer
fill_next_byte:
        MOV         M,A
        INX         H
        DCR         C
        JNZ         fill_next_byte
        DCR         B
        JNZ         fill_next_byte
        POP         B
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Find last byte of the databuffer that is not equal to the byte in A
        ;
get_data_end:
        LXI         H,data_buffer + 2047
        LXI         D,2048
search_for_end_loop:
        CMP         M
        JNZ         end_found
        DCX         H
        DCX         D
        PUSH        PSW
        MOV         A,D
        ORA         E
        JZ          no_data_found
        POP         PSW
        JMP         search_for_end_loop

no_data_found:
        POP         PSW
end_found:
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Prompt user to continue before starting to copy
        ;
        LXI         H,welcome_prompt_str
        CALL        print_str
        CALL        TTI
        CALL        to_uppercase
        CPI         'Y'
        JZ          user_affirmative
        CALL        TTO
        ;
        ; Print copy aborted status and quit program
        ;
abort_copy:
        MVI         A,CR
        CALL        TTO
        MVI         A,LF
        CALL        TTO
        LXI         H,copy_aborted_str
        CALL        print_str
        RET

user_affirmative:
        ;
        ; Verify that only Y was entered, and nothing more
        ;
        CALL        TTO
        CALL        TTI
        CPI         CR
        JNZ         abort_copy
        MVI         A,CR
        CALL        TTO
        MVI         A,LF
        CALL        TTO


;//////////////////////////////////////

        ;
        ; Prepare to start copy
        ;
        SUB         A
        STA         current_track
copy_next_track:
        ;
        ; Reset both tapes to start
        ;
        SUB         A
        CALL        CCAL
        RC
        MVI         A,1
        CALL        CCAL
        RC


;//////////////////////////////////////

read_next_data_block:
        ;
        ; Test-read the next block to buffer pre-filled with 00
        ;
        SUB         A
        CALL        fill_data_buffer
        LDA         current_track
        MOV         B,A
        SUB         A
        LXI         H,data_buffer
        CALL        CBRDW
        JC          read_exception
        ;
        ; Rewind back to start of block while probing for end of data in buffer
        ;
        LDA         current_track
        MOV         B,A
        SUB         A
        CALL        CBBS
        RC
        SUB         A
        CALL        get_data_end
        XCHG
        SHLD        preliminary_data_end_ptr
        CALL        CWT
        RC
        ;
        ; Read the same block again, this time to buffer pre-filled with FF
        ;
        MVI         A,0FFH
        CALL        fill_data_buffer
        LDA         current_track
        MOV         B,A
        SUB         A
        LXI         H,data_buffer
        CALL        CBRDW
        RC
        ;
        ; Probe for end of data again, select the highest end of data pointer
        ;
        MVI         A,0FFH
        CALL        get_data_end
        LHLD        preliminary_data_end_ptr
        MOV         A,H
        CMP         D
        JC          write_next_data_block
        JNZ         use_ff_test_end_ptr
        MOV         A,L
        CMP         E
        JC          write_next_data_block
use_ff_test_end_ptr:
        XCHG


;//////////////////////////////////////

write_next_data_block:
        ;
        ; Write data-block to destination tape
        ;
        LXI         H,data_buffer
        LDA         current_track
        MOV         B,A
        MVI         A,1
        CALL        CBWRW
        JNC         read_next_data_block
        ;
        ; Ignore any encountered tape-marks during write
        ;
        CPI         ERROR_48
        JZ          read_next_data_block
exit_with_error:
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

read_exception:
        ;
        ; Check for tape-mark
        ;
        CPI         ERROR_48
        JNZ         check_for_end_of_track
        ;
        ; Write tape-mark if so
        ;
        LDA         current_track
        MOV         B,A
        MVI         A,1
        CALL        CBTMW
        JNC         read_next_data_block
        CPI         ERROR_48
        JZ          read_next_data_block
        STC
        RET

check_for_end_of_track:
        ;
        ; Check for erased-tape
        ;
        CPI         ERROR_46
        JNZ         exit_with_error
        ;
        ; Assume end of track if so, advance to next track
        ;
        LDA         current_track
        INR         A
        STA         current_track
        ;
        ; Check for end of tape, unload cartridges and exit in the case
        ;
        CPI         4
        JNZ         copy_next_track
        SUB         A
        CALL        CUN
        MVI         A,1
        CALL        CUN
        LXI         H,copy_ok_str
        CALL        print_str
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII char in A to uppercase
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
;//     Data buffer
;//
;//////////////////////////////////////////////////////////////////////////////

data_buffer:
        DS          2048
