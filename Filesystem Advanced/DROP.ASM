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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
ETX         EQU     003H        ; End of text
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
TTO         EQU     00043H      ; Console output

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
LOCDIR      EQU     0FD85H      ; Look up filetable entry of filename on disk
RELBLK      EQU     0FDD6H      ; Release a single block on current Intel disk

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
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
        CPI         CR
        JZ          use_default_drive
        ;
        ; Parse command line argument, drive designator
        ;
        CPI         ':'
        JNZ         improper_unit
        CALL        INCHAR
        RC
        CPI         'F'
        JNZ         invalid_drive_type
        CALL        INCHAR
        RC
        SUI         '0'
        CPI         4
        JNC         invalid_drive_nr
        STA         drive_nr
        CALL        INCHAR
        RC
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
        ; Prime system for changes to mapfile on the requested disk
        ;
        LXI         H,mapfile_name
        LDA         drive_nr
        CALL        LOCDIR
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
        PUSH        H
        CALL        ascii_to_bin
        ORA         A
        JZ          invalid_sector
        CPI         27
        JNC         invalid_sector
        MOV         C,A
        ;
        ; Reserve block in mapfile
        ;
        CALL        RELBLK
        RC
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
        RNZ
        DCR         A
        STA         line_end_flag
        JMP         parse_single_instruction


;//////////////////////////////////////

invalid_parameters:
        LXI         H,invalid_parameters_str
        CALL        print_str
        XRA         A
        RET


;//////////////////////////////////////

invalid_drive_nr:
        MVI         A,ERROR_13
        STC
        RET


;//////////////////////////////////////

improper_unit:
        MVI         A,ERROR_11
        STC
        RET


;//////////////////////////////////////

invalid_drive_type:
        MVI         A,ERROR_1D
        STC
        RET


;//////////////////////////////////////

invalid_track:
        MVI         A,ERROR_35
        STC
        RET


;//////////////////////////////////////

invalid_sector:
        MVI         A,ERROR_36
        STC
        RET


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
        ; Print string pointed to by HL
        ;
print_str:
        MOV         A,M
        CPI         ETX
        RZ
        CALL        TTO
        INX         H
        JMP         print_str


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

drive_nr:
        DS          1
line_end_flag:
        DS          1

mapfile_name:
        DB          'ISIS',NULL,NULL
        DB          'MAP'

invalid_parameters_str:
        DB          ' ILLEGAL INPUT PARAMETER',CR,LF,ETX
