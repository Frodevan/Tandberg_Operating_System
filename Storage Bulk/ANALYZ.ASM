;//////////////////////////////////////////////////////////////////////////////
;//
;//     ANALYZ - Check floppy disk for errors
;//
;//         Extra parameters:
;//
;//             [$[:<Tn>:][<x>]]
;//
;//                 x           Number of reads per sector. 1-99, default 20
;//                 Tn          Drive type and number, default :F0:
;//
;//                 Drive type T:
;//                     A       Floppy
;//                     F       Floppy
;//                     I       Floppy
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         Analyze a single-sided single-density floppy disk for bad sectors. This
;//         test will read each sector on a disk multiple times, to verify that the
;//         disk is in good reliable condition.
;//
;//         A full list of bad sectors will be written after the test is over.
;//         Output is written to CO by default, but if SO is assigned then the
;//         final report will be written to SO instead of CO.
;//
;//         Only the sectors are tested, not the format or file-system on the disk.
;//         As such, there are no difference in the test itself between the various
;//         device types that can be provided as an extra parameter.
;//
;//
;//         Changelog:
;//
;//             1.2: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the number of reads will be wrong if more
;//                    than two digits are entered
;//                 -> Has a bug where the wrong error will be returned if the
;//                    command line arguments are invalid
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
; XMON system calls
;
DSRDW       EQU     00073H      ; Read from disk with wait

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer

;
; TOS Errors
;
ERROR_02    EQU     002H        ; CRC ERROR
ERROR_10    EQU     010H        ; NON-VALID DISKETTE COMMAND


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Prepare to parse arguments
        ;
        LHLD        CI_FCB
        ;
        ; Get first input character
        ;
        CALL        INCHAR
        RC
        CPI         CR
        JZ          input_arguments_parsed
        CPI         ':'
        JNZ         parse_nr_of_reads


;//////////////////////////////////////

        ;
        ; Parse remaining argument as drive designator
        ;
        CALL        INCHAR
        RC
        ;
        ; Verify drive type
        ;
        CPI         'F'
        JZ          valid_drive_type
        CPI         'I'
        JZ          valid_drive_type
        CPI         'A'
        JNZ         invalid_parameters
valid_drive_type:
        ;
        ; Get and verify drive number
        ;
        CALL        INCHAR
        RC
        SUI         '0'
        CPI         4
        JNC         invalid_parameters
        STA         drive_number
        ;
        ; Verify end of drive designator
        ;
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_parameters


;//////////////////////////////////////

parse_nr_of_reads:
        ;
        ; Assume upcoming argument is next digit in nr of reads
        ;
        MVI         B,000H
        JMP         get_nr_of_reads_argument_digit

;//////////////////////////////////////

prepare_nr_of_reads_digit:
        ;
        ; Convert and validate from ASCII to BCD digit
        ;
        CPI         '0'
        JC          invalid_parameters
        CPI         '9'+1
        JNC         invalid_parameters
        SUI         '0'
        ;
        ; Shift BCD digit into B
        ;
        MOV         C,A
        MOV         A,B
        RLC
        RLC
        RLC
        RLC
        ORA         C
        MOV         B,A

get_nr_of_reads_argument_digit:
        ;
        ; Get next input character
        ;
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         prepare_nr_of_reads_digit
        ;
        ; Use default nr of reads if none or zero specified
        ;
        MOV         A,B
        ORA         A
        JZ          input_arguments_parsed


;//////////////////////////////////////

        ;
        ; Convert nr of retries from BCD to binary
        ;
        MVI         C,0
bcd_to_bin_loop:
        ;
        ; less or equal to 0AH in BCD is less than 10
        ;
        CPI         10
        JC          nr_of_reads_ready
        ;
        ; Move value 10 from BCD number to binary number
        ;
        MVI         A,10
        ADD         C
        MOV         C,A
        MOV         A,B
        SUI         010H
        MOV         B,A
        JMP         bcd_to_bin_loop

nr_of_reads_ready:
        ;
        ; Add leftover ones
        ;
        MOV         A,B
        ADD         C
        STA         number_of_reads


;//////////////////////////////////////

input_arguments_parsed:
        ;
        ; Select output file FCB
        ;
        LHLD        SO_FCB
        MOV         A,L
        ORA         H
        JNZ         output_file_selected
        LHLD        CO_FCB
        SHLD        SO_FCB
output_file_selected:


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear table for bad sectors
        ;
        LXI         H,bad_sectors_table
        SHLD        bad_sectors_table_ptr
        LXI         D,2002
clear_bad_sectors_table_loop:
        MVI         M,0
        INX         H
        DCX         D
        MOV         A,E
        ORA         D
        JNZ         clear_bad_sectors_table_loop


;//////////////////////////////////////

        ;
        ; Start a new test of a disk
        ;
        MVI         B,0
test_new_track:
        LDA         number_of_reads
        MOV         D,A
test_current_track:
        MVI         C,1
test_current_sector:
        LDA         drive_number
        LXI         H,disk_read_buffer
        CALL        DSRDW
        JNC         read_next_sector
        ;
        ; Check read operation error code
        ;
        MOV         L,A
        CPI         ERROR_02
        JZ          register_bad_sector
        ;
        ; Exit program if TOS error 003H to 007H
        ;
        ANI         006H
        MOV         A,L
        STC
        RZ
register_bad_sector:
        ;
        ; Point to sector in bad-sector table, and flag it
        ;
        PUSH        B
        LHLD        bad_sectors_table_ptr
        MVI         B,000H
        DCR         C
        DAD         B
        MVI         M,1
        POP         B
read_next_sector:
        ;
        ; Advance one secor
        ;
        INR         C
        MOV         A,C
        CPI         27
        JC          test_current_sector
        ;
        ; Advance one read count
        ;
        DCR         D
        JNZ         test_current_track
        ;
        ; Advnce one track
        ;
        LHLD        bad_sectors_table_ptr
        LXI         D,26
        DAD         D
        SHLD        bad_sectors_table_ptr
        INR         B
        MOV         A,B
        CPI         77
        JC          test_new_track


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Compose final report
        ;
        MVI         B,0
        MVI         D,0
        LXI         H,final_report_line_buffer
        SHLD        final_report_line_buffer_ptr
        LXI         H,bad_sectors_table
sumarize_new_track:
        SHLD        bad_sectors_table_ptr
        MVI         C,1
sumarize_sector:
        ;
        ; Look up test-results of sector
        ;
        PUSH        B
        MVI         B,000H
        DCR         C
        LHLD        bad_sectors_table_ptr
        DAD         B
        POP         B
        XRA         A
        ORA         M
        JZ          sumarize_next_sector
        ;
        ; Add 'track/sector' of bad sector to report
        ;
        MOV         A,B
        CALL        add_number_to_string
        MVI         M,'/'
        INX         H
        SHLD        final_report_line_buffer_ptr
        MOV         A,C
        CALL        add_number_to_string
        ;
        ; If report line buffer is full, print it
        ;
        INR         D
        MOV         A,D
        CPI         10
        JC          continue_on_same_line
        SHLD        final_report_line_buffer_ptr
        CALL        print_final_report_buffer
        RC
        MVI         D,0
sumarize_next_sector:
        ;
        ; Advance sector
        ;
        INR         C
        MOV         A,C
        CPI         27
        JC          sumarize_sector
        ;
        ; Advance track
        ;
        INR         B
        MOV         A,B
        CPI         77
        JNC         sector_summary_done
        ;
        ; Advance pointer in table of bad sectors
        ;
        PUSH        D
        LXI         D,26
        LHLD        bad_sectors_table_ptr
        DAD         D
        POP         D
        JMP         sumarize_new_track

continue_on_same_line:
        ;
        ; Add comma, in case there's more data coming
        ;
        MVI         M,','
        INX         H
        SHLD        final_report_line_buffer_ptr
        JMP         sumarize_next_sector

sector_summary_done:
        ;
        ; Remove tailing comma of last line, if it contains anything
        ;
        XRA         A
        CMP         D
        JZ          print_overall_summary
        LHLD        final_report_line_buffer_ptr
        DCX         H
        SHLD        final_report_line_buffer_ptr
        CALL        print_final_report_buffer
        RC
print_overall_summary:
        ;
        ; Print empty line
        ;
        LXI         H,final_report_line_buffer
        SHLD        final_report_line_buffer_ptr
        CALL        print_final_report_buffer
        RET


;//////////////////////////////////////

        ;
        ; Flush remaining arg string and exit program with error
        ;
invalid_parameters:
        CPI         CR
        MVI         A,ERROR_10
        STC
        RZ
        CALL        INCHAR
        JMP         invalid_parameters


;//////////////////////////////////////

        ;
        ; Print and empty buffer with line for final report
        ;
print_final_report_buffer:
        LHLD        final_report_line_buffer_ptr
        MVI         M,CR
        LXI         H,final_report_line_buffer
        SHLD        final_report_line_buffer_ptr
        XCHG
        LHLD        SO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add a binary number to a string
        ;
add_number_to_string:
        PUSH        B
        LHLD        final_report_line_buffer_ptr
        ;
        ; Convert binary number to BCD
        ;
        MVI         B,000H
decimal_division_loop:
        CPI         10
        JC          decimal_division_done
        SUI         10
        PUSH        PSW
        MVI         A,010H
        ADD         B
        MOV         B,A
        POP         PSW
        JMP         decimal_division_loop

decimal_division_done:
        ;
        ; Convert BCD digits to ASCII and add them to string
        ;
        ADD         B
        PUSH        PSW
        ANI         0F0H
        CALL        add_upper_nibble_to_string
        POP         PSW
        ANI         0FH
        POP         B
        JMP         add_lower_nibble_to_string


;//////////////////////////////////////

add_upper_nibble_to_string:
        ;
        ; Shift upper nibble to lower nibble
        ;
        RRC
        RRC
        RRC
        RRC
add_lower_nibble_to_string:
        ;
        ; Convert to ASCII and add to string
        ;
        ADI         '0'
        MOV         M,A
        INX         H
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

drive_number:
        DB          0
number_of_reads:
        DB          20

final_report_line_buffer_ptr:
        DS          2
bad_sectors_table_ptr:
        DS          2

bad_sectors_table:
        DS          2002
final_report_line_buffer:
        DS          62
disk_read_buffer:
        DS          128
