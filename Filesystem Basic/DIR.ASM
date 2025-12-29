;//////////////////////////////////////////////////////////////////////////////
;//
;//     DIR - Directory listing
;//
;//         Extra parameters:
;//
;//             [$[I][:<Tn>:]]
;//
;//                 I           Show invisible files (for drive type F and M)
;//                 Tn          Drive type and number, default :F0:
;//
;//                 Drive type T:
;//                     A       Floppy (IBM 3740, ASCII)
;//                     B       Floppy (IBM 3740, ASCII)
;//                     F       Floppy (Intel ISIS)
;//                     I       Floppy (IBM 3740, EBCDIC)
;//                     J       Floppy (IBM 3740, EBCDIC)
;//                     M       Tape
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         Outputs a directory listing of all files on the specified drive. Output
;//         will primarely be sent to SO, but CO will be used if no SO is assigned.
;//         The columns in the prinout will depend on the drive type used.
;//
;//         When using CO as default output, the file-listing is printed in pages.
;//         To go to the next page, press any key on the keyboard except Q. In the
;//         case Q is pressed, the directory listing will end immediately. It
;//         should be noted that if SO=:CO: is assigned, the listing will on the
;//         contrary not have any pagebreaks.
;//
;//         NOTE: Tape operations depends on the optional XMON API for tape drives.
;//               Not all machines have this installed, so care should be taken if
;//               this program is to be used with tape.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC25E
;//
;//                 -> First version I have
;//                 -> Has a bug where aliases claim to have a file size
;//                 -> Has a bug where the name-extension deliminer is printed
;//                    even if the file/label has no extension. Affects filenames
;//                    of intel files, as well as both intel and tape labels.
;//                 -> Has a bug where all files on tape are listed, even hidden
;//                    files, regardless of the I command line argument being used
;//                 -> Has a bug where the tape-file attributes are printed off-
;//                    by-one character to the left
;//                 -> Has a bug where an additional / is printed on the summary-
;//                    line for each tape track
;//                 -> Has a bug where the datapointer is not set correctly when
;//                    printing the tape-track summary for track 2 to 4
;//                 -> Has a bug where the file size of an empty intel-file will
;//                    print as attribute-character 083H and the number 88480
;//                 -> Has a bug where an empty file will claim to use 65439 blocks
;//
;//             1.5a: Entry at 0xC000
;//
;//                 -> Flushes excess console input before ending
;//                 -> Small optimalizations, like when checking drive number
;//                 -> Pads out layout with additional cartridge returns
;//                 -> Prints track number on tape summary
;//                 -> Waits until first IBM file found before printing header
;//                 -> Asserts valid IBM file-entry tags
;//                 -> Key to prematurely end listing changed from E to Q
;//                 -> Fixes the file-extension bug from v1.3 for intel files and
;//                    tape labels
;//                 -> Fixes the alias bug from v1.3
;//                 -> Fixes the tape-attribute print position from v1.3
;//                 -> Fixes the two tape-track summary print issues from v1.3
;//                 -> Fixes tape-track 2-4 summary bug from v1.3
;//                 -> Fixes file-size bug of empty intel-files
;//
;//             1.5b: Entry at 0xC293
;//
;//                 -> Recognizes B and J as valid drive types
;//
;//             1.6a: Entry at 0xC165
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Flag values
;
FALSE       EQU     0           ; Boolean False
TRUE        EQU     -1          ; Boolean True

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
CR          EQU     00DH        ; Cartridge Return

;
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
DSRAW       EQU     0007CH      ; Read from disk with wait and translate EBCDIC to ASCII
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
CCAL        EQU     00091H      ; Reset tape cartridge
CBRDW       EQU     000AFH      ; Read data from tape cartridge with wait

;
; XMON and TOS system data
;
MAP1        EQU     02739H      ; Block address of first half of mapfile data
MAP2        EQU     0273BH      ; Block address of last half of mapfile data

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
GETBIN      EQU     0FD18H      ; Input a given number of raw bytes
PUTBIN      EQU     0FD1BH      ; Output a given number of raw bytes
OPEN        EQU     0FD1EH      ; Open block device
DCALW       EQU     0FD70H      ; Reset disk drive with wait
DSRDW       EQU     0FD73H      ; Read from disk with wait

;
; TOS constants
;
TABIN_PTR   EQU     0FDEAH      ; Pointer to Intel floppy disk device driver

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer

;
; TOS Errors
;
ERROR_20    EQU     020H        ; DELETED DATA RECORD

;
; TOS file attributes
;
ATTR_I      EQU     001H        ; Invisible file
ATTR_S      EQU     002H        ; System file
ATTR_W      EQU     004H        ; Write-protected file
ATTR_A      EQU     008H        ; Alias file
ATTR_B      EQU     010H        ; BASIC program file (EC-10 multiuser BASIC)
ATTR_D      EQU     020H        ; Data file (EC-10 multiuser BASIC)
ATTR_F      EQU     080H        ; Format file

;
; TOS File Control Block, block device variables
;
FCB_READ    EQU     008H        ; Device-driver Read API call
FCB_OPEN    EQU     00CH        ; Device-driver Open API call
FCB_CLOSE   EQU     00EH        ; Device-driver Close API call
FCB_DRVNR   EQU     011H        ; Drive number

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag
FM_BINARY   EQU     004H        ; Binary flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Legacy program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

intel_mapfile_name:
        DB          'ISIS',NULL,NULL
        DB          'MAP'

ibm_file_signature:
        DB          'HDR1'
ibm_deleted_signature:
        DB          'DDR1'

sp_backup:
        DS          2
input_char:
        DS          1

ibm_file_parameter_indexes:
        DB          01CH
        DB          022H
        DB          02AH
        DB          02FH
        DB          042H
        DB          04AH

ibm_read_call:
        DS          2

lines_left_on_page_counter:
        DB          24

use_console_flag:
        DB          FALSE
option_i_flag:
        DB          FALSE
first_ibm_file_found_flag:
        DB          FALSE

SO_FCB_backup:
        DW          00000H
total_block_count:
        DW          00000H

input_data_buffer:
        DS          128
dir_file_linking_block_buffer:
        DS          128

directory_file_fcb:
        DB          5
        DB          FM_BINARY
        DW          0
        DW          128
        DW          input_data_buffer
        DW          00000H
        DW          00000H
        DW          00000H
        DW          00000H
        DB          0
        DB          0
        DB          'ISIS',NULL,NULL
        DB          'DIR'
        DB          001H
        DW          00000H
        DB          0
        DB          0
        DW          dir_file_linking_block_buffer

intel_file_entry_buffer:
        DS          16

tape_cart_usage_block_data_ptr:
        DS          2

tape_track_nr_char:
        DS          1


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
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

start:
beginning:
        ;
        ; Save stack pointer for easy breaking out of program from subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        sp_backup
        ;
        ; Prioritize standard output file over console output, if assigned
        ;
        LHLD        SO_FCB
        SHLD        SO_FCB_backup
        MOV         A,H
        ORA         L
        JNZ         output_file_set
        LHLD        CO_FCB
        SHLD        SO_FCB
        MVI         A,TRUE
        STA         use_console_flag
output_file_set:
        ;
        ; Set default drive number and switches
        ;
        SUB         A
        STA         directory_file_fcb + FCB_DRVNR
        STA         option_i_flag
        ;
        ; Parse for command line switches
        ;
        CALL        get_next_char
        CPI         CR
        JZ          use_intel_format
        CALL        to_uppercase
        CPI         'I'
        JNZ         cli_switches_set
        MVI         A,TRUE
        STA         option_i_flag
        CALL        get_next_char
        CPI         CR
        JZ          use_intel_format
cli_switches_set:
        ;
        ; Parse for drive designator
        ;
        CPI         ':'
        JNZ         invalid_drive
        CALL        get_next_char
        CALL        to_uppercase
        CPI         'F'
        JNZ         parse_drive_type
        CALL        parse_drive_number


;//////////////////////////////////////////////////////////////////////////////

use_intel_format:
        ;
        ; Reset disk drive and read disk label
        ;
        LDA         directory_file_fcb + FCB_DRVNR
        CALL        DCALW
        JC          exit_program
        LXI         H,input_data_buffer
        LXI         B,26
        LDA         directory_file_fcb + FCB_DRVNR
        CALL        DSRDW
        JC          exit_program
        ;
        ; Prepare disk label string
        ;
        LXI         D,dir_label_str + 13
        LXI         H,input_data_buffer
        LXI         B,00603H
intel_labelname_copy_next_char:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         intel_labelname_copy_next_char
        MVI         A,'.'
        STAX        D
        INX         D
intel_labelext_copy_next_char:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         C
        JNZ         intel_labelext_copy_next_char
        ;
        ; Print disk label and file listing header
        ;
        LXI         D,dir_label_str
        CALL        print_str
        CALL        print_newline
        LXI         D,intel_dir_header_str
        CALL        print_str
        CALL        print_newline
        ;
        ; Prepare FCB for filetable directory file
        ;
        LHLD        TABIN_PTR
        PUSH        H
        LXI         B,006H
        DAD         B
        SHLD        directory_file_fcb + FCB_READ
        POP         H
        SHLD        directory_file_fcb + FCB_OPEN
        LXI         B,00CH
        DAD         B
        SHLD        directory_file_fcb + FCB_CLOSE
        ;
        ; Open filetable directory file for reading
        ;
        LXI         H,directory_file_fcb
        MVI         A,FM_INPUT
        CALL        OPEN
        JC          exit_program
        ;
        ; List file directory
        ;
list_next_intel_file:
        ;
        ; Copy directory entry
        ;
        LXI         D,intel_file_entry_buffer
        MVI         B,16
        LXI         H,directory_file_fcb
        CALL        GETBIN
        JC          intel_end_of_directory
        ;
        ; Check status of file
        ;
        LDA         intel_file_entry_buffer
        ANA         A
        JNZ         list_next_intel_file
        ;
        ; Check invisible attribute, if not I switch
        ;
        LDA         option_i_flag
        ORA         A
        JNZ         list_intel_file
        LDA         intel_file_entry_buffer + 00AH
        ANI         ATTR_I
        JNZ         list_next_intel_file


;//////////////////////////////////////

list_intel_file:
        ;
        ; Prepare filename for printing
        ;
        LXI         H,intel_file_entry_buffer + 001H
        MVI         B,9
intel_filename_prepare_next_char:
        MOV         A,M
        ANA         A
        JNZ         intel_filename_char_ready
        MVI         M,' '
intel_filename_char_ready:
        INX         H
        DCR         B
        JNZ         intel_filename_prepare_next_char
        ;
        ; Print filename
        ;
        LXI         D,intel_file_entry_buffer + 001H
        LHLD        SO_FCB
        MVI         B,6
        CALL        PUTBIN
        JC          exit_program
        ;
        ; Print filename extension deliminer, if extension present
        ;
        LDA         intel_file_entry_buffer + 007H
        CPI         ' '
        JZ          intel_file_ext_deliminer_ready
        MVI         A,'.'
intel_file_ext_deliminer_ready:
        CALL        print_char
        ;
        ; Print filename extension deliminer, if extension present
        ;
        LXI         D,intel_file_entry_buffer + 007H
        MVI         B,3
        CALL        PUTBIN
        JC          exit_program
        ;
        ; Skip blocks and file-size print if alias file
        ;
        LDA         intel_file_entry_buffer + 00AH
        ANI         ATTR_A
        JZ          intel_file_include_size
        MVI         B,18
        CALL        print_spaces
        JMP         intel_file_size_done

intel_file_include_size:
        ;
        ; Count and print blocks used by file
        ;
        LHLD        total_block_count
        XCHG
        LHLD        intel_file_entry_buffer + 00CH
        PUSH        D
        PUSH        H
        LXI         D,-62
        LXI         B,1
count_next_linking_block:
        DAD         D
        JNC         linking_blocks_counted
        INX         B
        JMP         count_next_linking_block

linking_blocks_counted:
        POP         H
        DAD         B
        POP         D
        PUSH        H
        DAD         D
        SHLD        total_block_count
        POP         H
        CALL        print_word
        MVI         B,3
        CALL        print_spaces
        ;
        ; Print file size
        ;
        LDA         intel_file_entry_buffer + 00BH
        MOV         E,A
        MVI         D,000H
        LHLD        intel_file_entry_buffer + 00CH
        CALL        calculate_file_size
        CALL        print_big_number
        MVI         A,' '
        CALL        print_char
intel_file_size_done:
        ;
        ; Print file attributes
        ;
        LDA         intel_file_entry_buffer + 00AH
        CALL        print_attribute_list
        JMP         list_next_intel_file


;//////////////////////////////////////

print_attribute_list:
        ;
        ; Prepare to print attributes if any is set
        ;
        MOV         B,A
        ANA         A
        JZ          done_printing_attributes
        PUSH        H
        LXI         H,attribute_list
print_next_atribute:
        ;
        ; Get bitmask of attribute
        ;
        MOV         A,M
        ORA         A
        JZ          all_attributes_printed
        ;
        ; Check if attribute bit is set and print its tag if so
        ;
        ANA         B
        INX         H
        MOV         A,M
        INX         H
        CNZ         print_char
        JMP         print_next_atribute

all_attributes_printed:
        POP         H
done_printing_attributes:
        CALL        print_newline
        RET

attribute_list:
        DB          ATTR_F,'F'
        DB          ATTR_D,'D'
        DB          ATTR_B,'B'
        DB          ATTR_A,'A'
        DB          ATTR_W,'W'
        DB          ATTR_S,'S'
        DB          ATTR_I,'I'
        DB          NULL


;//////////////////////////////////////

intel_end_of_directory:
        ;
        ; Print overal block count of files on disk
        ;
        MVI         B,10
        CALL        print_spaces
        LHLD        total_block_count
        CALL        print_word
        CALL        print_newline
        ;
        ; Load disk mapfile
        ;
        LXI         H,intel_mapfile_name
        LDA         directory_file_fcb + FCB_DRVNR
        CALL        LOCDIR
        JC          exit_program
        ;
        ; Count blocks reserved in mapfile
        ;
        LXI         H,0
        SHLD        total_block_count
        LHLD        MAP1
        CALL        add_bits_in_sector
        LHLD        MAP2
        CALL        add_bits_in_sector
        ;
        ; Print number of blocks reserved
        ;
        CALL        print_newline
        LXI         D,map_status_str
        CALL        print_partial_str
        LHLD        total_block_count
        CALL        print_word
        LXI         D,blocks_used_str
        CALL        print_str


;//////////////////////////////////////

file_listing_end:
        CALL        print_newline
exit_program:
        LHLD        sp_backup
        SPHL
        LHLD        SO_FCB_backup
        SHLD        SO_FCB
        ;
        ; Flush remaining console input, saving any raised error-code
        ;
        PUSH        PSW
        LDA         input_char
flush_next_char:
        CPI         CR
        JZ          quit
        LHLD        CI_FCB
        CALL        INCHAR
        JNC         flush_next_char
        ;
        ; Dispose any previous error if flushing itself resulted in error
        ;
        INX         SP
        INX         SP
        RET

quit:
        ;
        ; Flushing complete, recover error-code if any
        ;
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////

first_digit_found_flag:
        DB          FALSE
decimal_magnitude_ptr:
        DW          00000H

big_number_backup:
        DB          000H,000H,000H
big_number:
        DB          000H,000H,000H


;//////////////////////////////////////

print_big_number:
        MVI         A,' '
        CALL        print_char
        XRA         A
        STA         first_digit_found_flag
        ;
        ; The case of zero is handled separately to save on time
        ;
        LXI         H,big_number
        ORA         M
        INX         H
        ORA         M
        INX         H
        ORA         M
        JZ          big_number_is_zero
        ;
        ; Set up to divide with magnitudes to produce a 6 digit decimal
        ;
        MVI         A,6
        LXI         H,decimal_magnitude_list+2
get_next_decimal_digit:
        ;
        ; Save pointer to current decimal magnitude constant
        ;
        SHLD        decimal_magnitude_ptr
        ;
        ; Prepare division of next decimal magnitude
        ;
        PUSH        PSW
        LXI         D,big_number+2
        MVI         B,'0'
subtract_magnitude_const:
        PUSH        D
        ;
        ; Save big number in case next subtraction underflows
        ;
        LHLD        big_number+1
        SHLD        big_number_backup+1
        LDA         big_number
        STA         big_number_backup
        ;
        ; Subtract decimal magnitude using addition and negative constant
        ;
        LHLD        decimal_magnitude_ptr
        MVI         C,3
        XRA         A
subtract_next_bits:
        ;
        ; Subtract next 8 bit part of decimal magnitude from big number
        ;
        LDAX        D
        ADC         M
        STAX        D
        ;
        ; Advance to next 8 bits
        ;
        PUSH        PSW
        DCR         C
        JZ          single_subtraction_done
        DCX         H
        DCX         D
        POP         PSW
        JMP         subtract_next_bits

single_subtraction_done:
        ;
        ; Check if subtraction underflowed, meaning the division is done
        ;
        POP         PSW
        POP         D
        JNC         single_dvision_done
        ;
        ; If not done, add one to decimal digit and continue division
        ;
        INR         B
        JMP         subtract_magnitude_const

single_dvision_done:
        ;
        ; Revert the underflowing subtraction, to get the proper remainder
        ;
        LHLD        big_number_backup+1
        SHLD        big_number+1
        LDA         big_number_backup
        STA         big_number
        ;
        ; Recover decimal digit and make sure leading zeroes are blanked
        ;
        MOV         A,B
        CPI         '0'
        JNZ         non_zero_digit_found
        LDA         first_digit_found_flag
        ORA         A
        JNZ         include_next_digit
        MVI         A,' '
print_next_big_number_digit:
        CALL        print_char
        POP         PSW
        DCR         A
        RZ
        ;
        ; Advance to magnitude constant for next decimal digit
        ;
        LHLD        decimal_magnitude_ptr
        LXI         D,3
        DAD         D
        JMP         get_next_decimal_digit

non_zero_digit_found:
        MVI         A,TRUE
        STA         first_digit_found_flag
include_next_digit:
        ;
        ; Recover decimal digit again, for printing
        ;
        MOV         A,B
        JMP         print_next_big_number_digit


;//////////////////////////////////////

big_number_is_zero:
        ;
        ; Just print a single zero with no further calculations
        ;
        MVI         B,5
        CALL        print_spaces
        MVI         A,'0'
        JMP         print_char


;//////////////////////////////////////

        ;
        ; NOTE: negative magnitude constants due to using additions to subtract
        ;
decimal_magnitude_list:
        DB          0FEH,079H,060H
        DB          0FFH,0D8H,0F0H
        DB          0FFH,0FCH,018H
        DB          0FFH,0FFH,09CH
        DB          0FFH,0FFH,0F6H
        DB          0FFH,0FFH,0FFH


;//////////////////////////////////////////////////////////////////////////////

parse_drive_type:
        CPI         'M'
        JZ          use_tape_format
        CPI         'J'
        JNZ         ibm_type_j_check_done
        DCR         A
ibm_type_j_check_done:
        CPI         'B'
        JNZ         ibm_type_b_check_done
        DCR         A
ibm_type_b_check_done:
        CPI         'I'
        JZ          use_ibm_edbdic_format
        CPI         'A'
        JZ          use_ibm_ascii_format
invalid_drive:
        LXI         D,invalid_drive_str
        CALL        print_str
        JMP         exit_program


;//////////////////////////////////////////////////////////////////////////////

use_tape_format:
        ;
        ; Reset tape drive
        ;
        CALL        parse_drive_number
        LDA         directory_file_fcb + FCB_DRVNR
        CALL        CCAL
        JC          exit_program
        ;
        ; Read first directory block
        ;
        LXI         H,input_data_buffer
        LDA         directory_file_fcb + FCB_DRVNR
        MVI         B,0
        CALL        CBRDW
        JC          exit_program
        ;
        ; Verify directory header block
        ;
        LDA         input_data_buffer
        CPI         088H
        JZ          tape_format_ok
        LXI         D,illegal_tape_fmt_str
        CALL        print_str
        JMP         exit_program

tape_format_ok:
        ;
        ; Get tape label and copy it to report string
        ;
        LXI         D,dir_label_str+13
        LXI         H,input_data_buffer+1
        LXI         B,00603H
copy_next_tape_labelname_char:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         copy_next_tape_labelname_char
        ;
        ; Skip deliminer if no extension
        ;
        XRA         A
        ORA         M
        JZ          copy_label_ext
        MVI         A,'.'
copy_label_ext:
        STAX        D
        INX         D
copy_next_tape_label_ext_char:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         C
        JNZ         copy_next_tape_label_ext_char
        ;
        ; Print tape label and filelist header
        ;
        LXI         D,dir_label_str
        CALL        print_str
        CALL        print_newline
        LXI         D,tape_dir_header_str
        CALL        print_str
        CALL        print_newline
        ;
        ; List file directory
        ;
list_next_tape_file:
        ;
        ; Read next directory block
        ;
        LDA         directory_file_fcb + FCB_DRVNR
        MVI         B,0
        LXI         H,input_data_buffer
        CALL        CBRDW
        JC          exit_program
        ;
        ; Check if file active
        ;
        LDA         input_data_buffer
        ANA         A
        JZ          check_tape_file
        CPI         0FFH
        JZ          list_next_tape_file
        CPI         07FH
        JZ          tape_end_of_directory
        LXI         D,illegal_tape_fmt_str
        CALL        print_str
        JMP         exit_program

check_tape_file:
        ;
        ; Check invisible attribute, if not I switch
        ;
        LDA         option_i_flag
        ORA         A
        JNZ         list_tape_file
        LDA         input_data_buffer + 012H
        ANI         ATTR_I
        JNZ         list_next_tape_file


;//////////////////////////////////////

list_tape_file:
        ;
        ; Prepare filename for printing
        ;
        LXI         H,input_data_buffer + 001H
        MVI         B,9
tape_filename_prepare_next_char:
        MOV         A,M
        ANA         A
        JNZ         tape_filename_char_ready
        MVI         M,' '
tape_filename_char_ready:
        INX         H
        DCR         B
        JNZ         tape_filename_prepare_next_char
        ;
        ; Print filename
        ;
        LXI         D,input_data_buffer + 001H
        LHLD        SO_FCB
        MVI         B,6
        CALL        PUTBIN
        JC          exit_program
        ;
        ; Print filename extension deliminer, if extension present
        ;
        LDA         input_data_buffer + 007H
        CPI         ' '
        JZ          tape_file_ext_deliminer_ready
        MVI         A,'.'
tape_file_ext_deliminer_ready:
        CALL        print_char
        ;
        ; Print filename extension deliminer, if extension present
        ;
        LXI         D,input_data_buffer + 007H
        MVI         B,3
        CALL        PUTBIN
        JC          exit_program
        ;
        ; Skip blocks and file-size print if alias file
        ;
        LDA         input_data_buffer + 012H
        ANI         ATTR_A
        JZ          tape_file_include_size
        MVI         B,29
        CALL        print_spaces
        JMP         tape_file_size_done

tape_file_include_size:
        ;
        ; Print file track number
        ;
        LDA         input_data_buffer + 00AH
        MOV         L,A
        MVI         H,000H
        CALL        print_word
        ;
        ; Print file number
        ;
        LDA         input_data_buffer + 00BH
        MOV         L,A
        MVI         H,000H
        CALL        print_word
        ;
        ; Print blocks used by file
        ;
        LHLD        input_data_buffer + 00EH
        CALL        print_word
        ;
        ; Print file size
        ;
        LHLD        input_data_buffer + 010H
        XCHG
        LHLD        input_data_buffer + 00EH
        CALL        calculate_file_size
        CALL        print_big_number
        MVI         A,' '
        CALL        print_char
tape_file_size_done:
        ;
        ; Print file attributes
        ;
        LDA         input_data_buffer + 012H
        CALL        print_attribute_list
        JMP         list_next_tape_file


;//////////////////////////////////////

tape_end_of_directory:
        ;
        ; Reset tape and print track status header
        ;
        LDA         directory_file_fcb + FCB_DRVNR
        CALL        CCAL
        RC
        CALL        print_newline
        LXI         D,tracks_usage_str
        CALL        print_str
        CALL        print_newline
        ;
        ; Print track status map from directory end block
        ;
        LXI         H,input_data_buffer + 001H
        SHLD        tape_cart_usage_block_data_ptr
        MVI         A,'1'
        STA         tape_track_nr_char
        ;
        ; Print status map for one track
        ;
tape_list_next_track_summary:
        MVI         B,15
        CALL        print_spaces
        ;
        ; Print an asterisk if track is not empty
        ;
        LHLD        tape_cart_usage_block_data_ptr
        MOV         A,M
        ANA         A
        MVI         A,' '
        JZ          tape_track_status_char_ready
        MVI         A,'*'
tape_track_status_char_ready:
        CALL        print_char
        LDA         tape_track_nr_char
        CALL        print_char
        ;
        ; Print number of blocks on track
        ;
        LHLD        tape_cart_usage_block_data_ptr
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        SHLD        tape_cart_usage_block_data_ptr
        XCHG
        CALL        print_word
        ;
        ; Print number of files on track
        ;
        LHLD        tape_cart_usage_block_data_ptr
        MOV         A,M
        INX         H
        INX         H
        SHLD        tape_cart_usage_block_data_ptr
        MOV         L,A
        MVI         H,000H
        CALL        print_word
        CALL        print_newline
        ;
        ; Advance to print status of next track
        ;
        LDA         tape_track_nr_char
        CPI         '3'
        JZ          file_listing_end
        INR         A
        STA         tape_track_nr_char
        JMP         tape_list_next_track_summary


;//////////////////////////////////////////////////////////////////////////////

use_ibm_ascii_format:
        LXI         H,DSRDW
        JMP         ibm_disk_type_set

use_ibm_edbdic_format:
        LXI         H,DSRAW
ibm_disk_type_set:
        ;
        ; Store IBM read sector api call pointer
        ;
        SHLD        ibm_read_call
        ;
        ; Get drive number
        ;
        CALL        parse_drive_number
        XRA         A
        STA         first_ibm_file_found_flag
        ;
        ; List all active IBM file entries, starting at sector 8
        ;
        LXI         B,0*DISK_TRACK + 8*DISK_SECTOR
get_ibm_file:
        ;
        ; Read file entry, ignore if deleted sector
        ;
        CALL        read_ibm_sector
        JNC         list_ibm_file
        CPI         ERROR_20
        STC
        JNZ         exit_program
list_next_ibm_file:
        ;
        ; Advance to next file entry
        ;
        MOV         A,C
        CPI         26
        INX         B
        JNZ         get_ibm_file
        CALL        print_newline
        JMP         exit_program

list_ibm_file:
        ;
        ; Check if file is active
        ;
        LXI         D,ibm_deleted_signature
        CALL        compare_ibm_signature
        JZ          list_next_ibm_file
        LXI         D,ibm_file_signature
        CALL        compare_ibm_signature
        JNZ         unrecognized_floppy_format
        ;
        ; Print header and set flag if first file to be listed
        ;
        LDA         first_ibm_file_found_flag
        ORA         A
        JNZ         list_ibm_file_data
        CALL        print_newline
        LXI         D,ibm_dir_header_str
        CALL        print_str
        MVI         A,TRUE
        STA         first_ibm_file_found_flag
list_ibm_file_data:
        ;
        ; Prepare file entry data for printing
        ;
        MVI         A,CR
        STA         input_data_buffer + 00DH
        STA         input_data_buffer + 01BH
        STA         input_data_buffer + 021H
        STA         input_data_buffer + 027H
        STA         input_data_buffer + 02BH
        STA         input_data_buffer + 035H
        STA         input_data_buffer + 048H
        STA         input_data_buffer + 04FH
        MVI         A,'/'
        STA         input_data_buffer + 01EH
        STA         input_data_buffer + 024H
        STA         input_data_buffer + 04CH
        ;
        ; Print sector number
        ;
        CALL        print_newline
        MOV         L,C
        MVI         H,000H
        PUSH        B
        CALL        print_word
        MVI         B,3
        CALL        print_spaces
        ;
        ; Print filename
        ;
        LXI         D,input_data_buffer + 005H
        CALL        print_partial_str
        MVI         B,2
        CALL        print_spaces
        ;
        ; Print record length
        ;
        LXI         D,input_data_buffer + 018H
        MVI         C,3
print_next_ibm_record_len_char:
        LDAX        D
        CALL        print_char
        INX         D
        DCR         C
        JNZ         print_next_ibm_record_len_char
        ;
        ; Print remaining file parameters using list of indexes
        ;
        MVI         C,6
        LXI         H,ibm_file_parameter_indexes
print_next_ibm_record_param:
        MVI         B,2
        CALL        print_spaces
        ;
        ; Point to parameter using current index
        ;
        LXI         D,input_data_buffer
        PUSH        H
        MOV         L,M
        MVI         H,000H
        DAD         D
        XCHG
        POP         H
        ;
        ; Print parameter and advance to next index
        ;
        CALL        print_partial_str
        INX         H
        DCR         C
        JNZ         print_next_ibm_record_param
        ;
        ; Done listing IBM file
        ;
        POP         B
        JMP         list_next_ibm_file


;//////////////////////////////////////

read_ibm_sector:
        ;
        ; Call stored API read-call by forcing it on the stack before returning
        ;
        LHLD        ibm_read_call
        PUSH        H
        LXI         H,input_data_buffer
        LDA         directory_file_fcb + FCB_DRVNR
        RET


;//////////////////////////////////////

unrecognized_floppy_format:
        LXI         D,newline_str
        CALL        print_str
        LXI         D,invalid_disk_format_str
        CALL        print_str
        JMP         exit_program


;//////////////////////////////////////

        ;
        ; Compare 4-character strings pointed to by DE and HL
        ;
compare_ibm_signature:
        LXI         H,input_data_buffer
        MVI         B,4
compare_next_ibm_sig_char:
        ;
        ; Compare current character
        ;
        LDAX        D
        CMP         M
        RNZ
        ;
        ; Advance to next character
        ;
        DCR         B
        RZ
        INX         H
        INX         D
        JMP         compare_next_ibm_sig_char


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string pointed to by HL
        ;
print_str:
        ;
        ; Print the string itself
        ;
        PUSH        H
        LHLD        SO_FCB
        CALL        PUT
        POP         H
        JC          exit_program
        ;
        ; Advance lines left counter if console output
        ;
        LDA         use_console_flag
        ORA         A
        RZ
        LXI         H,lines_left_on_page_counter
        DCR         M
        RNZ
        MVI         M,24
        ;
        ; Prompt for user when the screen is full, break if abort-key pressed
        ;
        MVI         A,CR
        CALL        TTO
        CALL        TTI
        CALL        to_uppercase
        CPI         'Q'
        JZ          file_listing_end
        XRA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string pinted to by HL without cartridge return and newline
        ;
print_partial_str:
        PUSH        H
        LHLD        SO_FCB
        CALL        PUTSTR
        JMP         print_end


;//////////////////////////////////////

        ;
        ; Print single cartridge return and newline
        ;
print_newline:
        PUSH        D
        LXI         D,newline_str
        CALL        print_str
        POP         D
        RET


;//////////////////////////////////////

        ;
        ; Print single character in A
        ;
print_char:
        PUSH        H
        LHLD        SO_FCB
        CALL        OUTCHAR
print_end:
        POP         H
        JC          exit_program
        RET


;//////////////////////////////////////

        ;
        ; Get next input character from CI into A
        ;
get_next_char:
        PUSH        H
        LHLD        CI_FCB
        CALL        INCHAR
        STA         input_char
        JMP         print_end


;//////////////////////////////////////////////////////////////////////////////

parse_drive_number:
        ;
        ; Get drive number char and check for within bounds
        ;
        CALL        get_next_char
        SUI         '0'
        JM          invalid_drive
        CPI         4
        JP          invalid_drive
        ;
        ; Store drive nr and check drive designator final character
        ;
        STA         directory_file_fcb + FCB_DRVNR
        CALL        get_next_char
        CPI         ':'
        JNZ         invalid_drive
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print B number of spaces
        ;
print_spaces:
        MVI         A,' '
        CALL        print_char
        DCR         B
        JNZ         print_spaces
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print 16-bit binary in HL as decimal
        ;
print_word:
        MOV         A,L
        STA         big_number+2
        MOV         A,H
        STA         big_number+1
        XRA         A
        STA         big_number
        JMP         print_big_number


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Calculate file size based on HL blocks used and final block size E
        ;
calculate_file_size:
        ;
        ; Check for edge-case where file is completely empty
        ;
        MOV         A,L
        ORA         H
        JZ          block_count_ready
        ;
        ; Subtract 1 from HL since we are adding the last block size separately
        ;
        DCX         H
block_count_ready:
        ;
        ; Multiply full block count with block size of 128
        ;
        XRA         A
        MOV         A,H
        RAR
        STA         big_number
        MOV         A,L
        RAR
        STA         big_number+1
        RAR
        ANI         080H
        ;
        ; Add final block size E to result
        ;
        ADD         E
        STA         big_number+2
        LDA         big_number+1
        ACI         0
        STA         big_number+1
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Count all bits set in sector addressed by HL, and add to total count
        ;
add_bits_in_sector:
        ;
        ; Read sector from disk
        ;
        MOV         B,H
        MOV         C,L
        LXI         H,input_data_buffer
        LDA         directory_file_fcb + FCB_DRVNR
        CALL        DSRDW
        JC          exit_program
        ;
        ; Prepare to count bits in all 128 bytes
        ;
        LXI         D,0
        MVI         B,128
count_bits_in_next_byte:
        ;
        ; Set up bitmask to count bits in byte
        ;
        MVI         C,080H
        MOV         A,C
count_next_bit_in_byte:
        ANA         M
        JZ          done_counting_bit
        INX         D
done_counting_bit:
        ;
        ; Advance bitmask to next bit
        ;
        MOV         A,C
        RAR
        MOV         C,A
        JNC         count_next_bit_in_byte
        ;
        ; Advance to next byte of sector
        ;
        INX         H
        DCR         B
        JNZ         count_bits_in_next_byte
        ;
        ; Add bitcount to total count
        ;
        LHLD        total_block_count
        DAD         D
        SHLD        total_block_count
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

dir_label_str:
        DB          'DIRECTORY OF '
        DS          10
        DB          CR
intel_dir_header_str:
        DB          'NAME  .EXT   BLKS    LENGTH ATTR'
newline_str:
        DB          CR
invalid_drive_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
illegal_tape_fmt_str:
        DB          'ILLEGAL TAPE FORMAT',CR
tape_dir_header_str:
        DB          'NAME  .EXT    TRK   FILE   BLKS LENGTH ATTR',CR
tracks_usage_str:
        DB          'TRACK USAGE:  TRK   BLKS  FILES',CR
ibm_dir_header_str:
        DB          ' SECTOR   FILENAME  REC   BOE    EOE   P  CRDATE  EXDATE   EOD',CR
map_status_str:
        DB          'MAP STATUS',CR
blocks_used_str:
        DB          '/2002 BLOCKS USED',CR
invalid_disk_format_str:
        DB          'UNRECOGNIZED DISKETTE FORMAT',CR
