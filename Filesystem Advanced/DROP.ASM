;//////////////////////////////////////////////////////////////////////////////
;//
;//     DROP - Reserve sectors from file-operations on floppy
;//
;//         Extra parameters:
;//
;//             [$:<Tn>:]
;//
;//                 Tn          Drive type and number, default :F0:
;//
;//                 Drive type T:
;//                     F       Floppy
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         Will mark sectors as used in the Intel ISIS file system. If a free
;//         sector is marked, it will be reserved from further use by the file-
;//         system, and as such guaranteed to not be affected by file-operations on
;//         the disk. This tool achieves this by setting bits in the ISIS.MAP
;//         system file. In order to revert the map file back to it's original
;//         state, the map file needs to be re-generated, for example with REMAP.
;//
;//         Input is taken from SI if set, otherwise CI. Some versions of the
;//         program may print a help-string when CI is used, while other versions
;//         expect the user to know the format of the text-input by heart.
;//
;//
;//         Input:
;//
;//             <trk>/<sec>[,<trk>/<sec>[,<trk>/<sec>[...]]]\n
;//
;//                 trk         Track to mark, default 0
;//                 sec         Sector to mark of given track, default 0 (error)
;//
;//
;//         At input of trk, a cartridge return or newline will reset the input
;//         number. Otherwise, the number expected is numerical and not
;//         hexadecimal, and if any unexpected characters are input the program
;//         will terminate with an error. Should this happen, the sector map of the
;//         disk remains unchanged, any prior input being discarded.
;//
;//         Two newlines at the trk input or one newline after the sec input will
;//         write any pending changes to disk and exit the program.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the block(s) selected will be freed if used
;//                    instead of reserved if not used, due to the wrong TOS API
;//                    call being made
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> Accepts lower-case drive type
;//                 -> Flushes excess input characters from the extra parameters
;//                 -> Explicitly load mapfile from disk sectors instead of the
;//                    LOCDIR API-call in XMON
;//                 -> Uses local algorithm for finding and changing the bit in the
;//                    mapfile, rather than calls to the TOS API. This change fixes
;//                    the freed-vs-reserved bug from v1.3.
;//                 -> Replaces the XMON-based print-string routine from v1.3 with
;//                    a TOS-based print-single-character routine. This introduces
;//                    a bug where the most recent input-character is printed
;//                    instead of the status-message for "Illegal input parameter".
;//                 -> Ignores leading spaces before numbers
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
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
BUF1        EQU     02680H      ; Additional sector data for filesysyem operation
MAP1        EQU     02739H      ; Block address of first half of mapfile data
MAP2        EQU     0273BH      ; Block address of last half of mapfile data

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer

;
; TOS Errors
;
ERROR_11    EQU     011H        ; IMPROPER UNIT SPECIFICATION
ERROR_13    EQU     013H        ; DRIVE NUMBER NOT 0-3
ERROR_1D    EQU     01DH        ; COMMAND UNIT NOT :FN: OR :MN:
ERROR_35    EQU     035H        ; TRACK NUMBER > 76
ERROR_36    EQU     036H        ; SECTOR NUMBER = 0 OR > 26


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Check if there are command line arguments
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         CR
        JZ          use_default_drive
        ;
        ; Parse command line argument, drive designator
        ;
        CPI         ':'
        JNZ         improper_unit
        CALL        INCHAR
        RC
        CALL        to_uppercase
        STA         input_char
        CPI         'F'
        JNZ         invalid_drive_type
        CALL        INCHAR
        RC
        STA         input_char
        SUI         '0'
        CPI         4
        JNC         invalid_drive_nr
        STA         drive_nr
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ':'
        JNZ         improper_unit
        ;
        ; Flush remaining arguments
        ;
flush_next_input_char:
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         flush_next_input_char
        JMP         drive_nr_set

use_default_drive:
        ;
        ; Use :F0: default drive
        ;
        XRA         A
        STA         drive_nr
drive_nr_set:
        ;
        ; Determine input file, SI is prioritized over CI
        ;
        LHLD        SI_FCB
        MOV         A,L
        ORA         H
        JNZ         input_file_set
        LHLD        CI_FCB
        SHLD        SI_FCB
input_file_set:
        ;
        ; Read mapfile from the requested disk
        ;
        LHLD        MAP1
        MOV         B,H
        MOV         C,L
        LXI         H,BUF2
        LDA         drive_nr
        CALL        DSRDW
        RC
        LHLD        MAP2
        MOV         B,H
        MOV         C,L
        LXI         H,BUF1
        LDA         drive_nr
        CALL        DSRDW
        RC


;//////////////////////////////////////

parse_next_instruction:
        ;
        ; Assume valid instruction, so not at line end yet
        ;
        XRA         A
        STA         line_end_flag
parse_single_instruction:
        ;
        ; Get and verify track number
        ;
        CALL        get_ascii_decimal
        RC
        CPI         LF
        JZ          parse_single_instruction
        CPI         CR
        JZ          instruction_line_end
        CPI         '/'
        JNZ         invalid_parameters
        CALL        ascii_to_bin
        CPI         77
        JNC         invalid_track
        MOV         B,A
        ;
        ; Get and verify sector number
        ;
        CALL        get_ascii_decimal
        RC
        CPI         CR
        JZ          valid_instruction
        CPI         ','
        JNZ         invalid_parameters
valid_instruction:
        PUSH        PSW
        CALL        ascii_to_bin
        ORA         A
        JZ          invalid_sector
        CPI         27
        JNC         invalid_sector
        MOV         C,A
        ;
        ; Reserve block in mapfile pt1: Multiply track nr with 26
        ;
        MVI         H,000H
        MOV         L,B
        DAD         H
        PUSH        H
        DAD         H
        DAD         H
        PUSH        H
        DAD         H
        POP         D
        DAD         D
        POP         D
        DAD         D
        ;
        ; Reserve block in mapfile pt2: Add sector nr - 1 to get map bit index
        ;
        LXI         D,000H
        MOV         E,C
        DAD         D
        DCX         H
        ;
        ; Reserve block in mapfile pt3: Modulus index by 8 to get bit nr
        ;
        MOV         A,L
        ANI         007H
        MOV         C,A
        ;
        ; Reserve block in mapfile pt4: Divide index by 8 to get byte nr
        ;
        MOV         A,H
        RLC
        RLC
        RLC
        RLC
        RLC
        ANI         0E0H
        MOV         B,A
        MOV         A,L
        RRC
        RRC
        RRC
        ANI         01FH
        ORA         B
        MOV         L,A
        MOV         A,H
        RRC
        RRC
        RRC
        ANI         01FH
        MOV         H,A
        ;
        ; Reserve block in mapfile pt5: Set up pointer and bit mask
        ;
        LXI         D,BUF2
        DAD         D
        INR         C
        MVI         A,080H
shift_bitmask_loop:
        DCR         C
        JZ          bitmask_ready
        RRC
        ANI         07FH
        JMP         shift_bitmask_loop

bitmask_ready:
        ;
        ; Reserve block in mapfile pt6: Mark block as reserved
        ;
        ORA         M
        MOV         M,A
        ;
        ; Check if we are at end of line of instructions
        ;
        POP         PSW
        CPI         ','
        JZ          parse_next_instruction
instruction_line_end:
        ;
        ; Set end flag if not already set, otherwise quit program
        ;
        LDA         line_end_flag
        ORA         A
        JNZ         update_mapfile_data
        DCR         A
        STA         line_end_flag
        JMP         parse_single_instruction

update_mapfile_data:
        ;
        ; Write updated mapfile back to the requested disk
        ;
        LHLD        MAP1
        MOV         B,H
        MOV         C,L
        LXI         H,BUF2
        LDA         drive_nr
        CALL        DSWRW
        RC
        LHLD        MAP2
        MOV         B,H
        MOV         C,L
        LXI         H,BUF1
        LDA         drive_nr
        CALL        DSWRW
        RC
        ;
        ; Set return code to no error
        ;
        MVI         B,000H
quit_program:
        ;
        ; Flush remaining arguments at end of program
        ;
        LDA         input_char
flush_next_final_input_char:
        CPI         CR
        JZ          final_flush_complete
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         flush_next_final_input_char

final_flush_complete:
        ;
        ; Exit program, and raise error if any
        ;
        MOV         A,B
        ORA         A
        RZ
        STC
        RET

;//////////////////////////////////////

invalid_parameters:
        LXI         D,invalid_parameters_str
        CALL        print_str
        MVI         B,000H
        JNC         quit_program
        MOV         B,A
        JMP         quit_program


;//////////////////////////////////////

invalid_drive_nr:
        MVI         B,ERROR_13
        JMP         quit_program


;//////////////////////////////////////

improper_unit:
        MVI         B,ERROR_11
        JMP         quit_program


;//////////////////////////////////////

invalid_drive_type:
        MVI         B,ERROR_1D
        JMP         quit_program


;//////////////////////////////////////

invalid_track:
        MVI         B,ERROR_35
        JMP         quit_program


;//////////////////////////////////////

invalid_sector:
        MVI         B,ERROR_36
        JMP         quit_program


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Gets a 2-digit ASCII numerical into DE
        ;
get_ascii_decimal:
        LXI         D,'00'
        LHLD        SI_FCB
get_next_decimal_digit:
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          get_next_decimal_digit
        ;
        ; Check digit lower boundary
        ;
        CPI         '0'
        JNC         check_digit_upper
        CMC
        RET

check_digit_upper:
        ;
        ; Check digit upper boundary
        ;
        CPI         '9'+1
        RNC
        ;
        ; Shift digit into DE
        ;
        MOV         D,E
        MOV         E,A
        XRA         A
        STA         line_end_flag
        JMP         get_next_decimal_digit


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert 2-digit ASCII number in DE to binary in A
        ;
ascii_to_bin:
        ;
        ; Convert number to BCD
        ;
        MOV         A,D
        SUI         '0'
        RLC
        RLC
        RLC
        RLC
        MOV         D,A
        MOV         A,E
        SUI         '0'
        ORA         D
        MOV         D,A
        MVI         E,0
        ;
        ; Convert high digit of BCD in D to binary in E using 10/16 ratio
        ;
decimal_division_loop:
        CPI         10
        JC          decimal_division_done
        MVI         A,10
        ADD         E
        MOV         E,A
        MOV         A,D
        SUI         010H
        MOV         D,A
        JMP         decimal_division_loop
decimal_division_done:
        ;
        ; Add result in E (tens) to remainder in D (low BCD digit)
        ;
        MOV         A,D
        ADD         E
        RET


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

        ;
        ; Print string pointed to by DE
        ;
print_str:
        PUSH        H
        LHLD        CO_FCB
        CALL        OUTCHAR
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

input_char:
        DS          1
drive_nr:
        DS          1
line_end_flag:
        DS          1

mapfile_name:
        DB          'ISIS',NULL,NULL
        DB          'MAP'

invalid_parameters_str:
        DB          ' ILLEGAL INPUT PARAMETER',CR
