;//////////////////////////////////////////////////////////////////////////////
;//
;//     LINK - Linker for Tandberg TDV-2100 Relocatable Assembler (RASM)
;//
;//         Extra parameters:
;//
;//             [$input]
;//
;//                 input       Force initial operation
;//
;//
;//         This is the 2-pass linker for the Tandberg TDV-2100 Relocatable
;//         Assembler (RASM), and will take a list of instructions to catalog a set
;//         of relocatable object files and link them into a loadable and runnable
;//         binary file in Intel Absolute Binary format. The output binary will be
;//         written to the block-device file assigned to SO, while input object-
;//         files are provided by the user on a prompt, or by using a batch script.
;//
;//         When the program starts, it provides a prompt for the user, unless a
;//         a batch-file has been assigned to AI. An information-dump about the
;//         references set by the linker will be printed to the file assigned to
;//         the SL output.
;//
;//         Being a 2-pass linker, the first pass is to set segment addresses and
;//         load object files to be linked together. This phase is active until the
;//         user decides to initiate pase 2, where inter-module dependencies are
;//         verified, and the output binary is composed and written to file.
;//
;//
;//         Valid operations:
;//
;//             *[param]=[addr]         Set current address-based parameter
;//             *D=*C                   DSEG follows CSEG for the next files
;//             *P=[lines]              Set SL output file line-ptinter page length
;//             [:<Tn>:]<obj_file>      Link next object-file (pass 1)
;//             /                       End of pass 1, do pass 2 and exit program
;//
;//                 Tn          Drive type and number, default :F0:
;//                 obj_file    Object-file name
;//                 addr        Hexadecimal absolute memory address (0-FFFF)
;//                 lines       Number of lines per page on the line printer (24-255)
;//
;//                 Drive type T:
;//                     F       Floppy
;//                     M       Tape
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         NOTE: If an initial operation is provided to LINK on the command line,
;//               it will be run first even in the case a batchfile has been
;//               assigned. Only one operation can be provided this way.
;//
;//         NOTE: The first pass of the linking assumes the labels are stored as an
;//               unbroken sequence of records right after exactly one header-
;//               record. The second pass, on the other hand, only assumes exactly
;//               one header-record but does not care if there's other types of
;//               record in-between the external label records. Only requirement
;//               being that an external label record needs to be placed before
;//               being referenced later by external reference records. As a
;//               result, the second pass may pick up on and try to use external
;//               labels that were missed by the first pass, and these will
;//               generate a "Symbol not found in pass 2" error.
;//
;//         NOTE: This program will identify start of User-RAM on it's own, and
;//               assumes a gap in the memory between the system-memory and the
;//               user-memory. This is true for systems configured with 48KB or
;//               less, but not for systems with the full 54KB of user-memory.
;//               As a result, this program will break on later systems with the
;//               full 54KB of User-RAM.
;//
;//
;//         Object-file format:
;//
;//             1   Header record
;//             X   Label records
;//             Y   Data/Reference/Start records
;//             1   End record
;//
;//             All records:
;//
;//                 DS  1   Record type
;//                 DS  1   Record length (N)
;//                 DS  N   Record data
;//
;//             Record data:
;//
;//                 001H - Header record:
;//
;//                     DS  2   CSEG length
;//                     DS  2   DSEG length
;//
;//                 002H - Label (public) record:
;//
;//                     DS  1   Address base (0: None, 1: CSEG, 2: DSEG)
;//                     DS  2   Address offset
;//                     DS  M   Label name
;//
;//                 003H - Label (external) record:
;//
;//                     DS  M   Label name
;//
;//                 004H - Data record:
;//
;//                     DS  1   Address base (0: None, 1: CSEG, 2: DSEG)
;//                     DS  2   Address offset
;//                     DS  M   Binary data
;//
;//                 005H - Reference (internal) record:
;//
;//                     DS  1   Address base (0: None, 1: CSEG, 2: DSEG)
;//                     DS  2   Address offset
;//                     DS  1   Referenced address base (0: None, 1: CSEG, 2: DSEG)
;//                     DS  2   Referenced address offset
;//
;//                 006H - Reference (external) record:
;//
;//                     DS  1   Address base (0: None, 1: CSEG, 2: DSEG)
;//                     DS  2   Address offset
;//                     DS  2   Referenced external label index (of local records)
;//                     DS  2   Referenced address offset
;//
;//                 007H - Start address (default) record:
;//
;//                     DS  1   Address base (0: None, 1: CSEG, 2: DSEG)
;//                     DS  2   Address offset
;//
;//                 0FFH - End record:
;//
;//                     (Zero-length/No record data)
;//
;//
;//         Changelog:
;//
;//             1.0: Entry at 0xC800
;//
;//                 -> Has a bug where manually setting the start address to 0x0000
;//                    will not protect it from being automatically changed later
;//
;//             1.1: Entry at 0xC800
;//
;//                 -> Version ID written to 0x2700
;//                 -> Fixes the start address bug from v1.0
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Flag values
;
TRUE        EQU     1           ; Boolean True
TRUE_ALT    EQU     -1          ; Boolean True

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
TTO         EQU     00043H      ; Console output

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
OPEN        EQU     0FD1EH      ; Open block device
EDWH        EQU     0FD2DH      ; Convert word to 4-character ASCII hexadecimal

;
; TOS constants
;
TABTC_PTR   EQU     0FDE6H      ; Pointer to Tandberg tape cartridge device driver
TABIN_PTR   EQU     0FDEAH      ; Pointer to Intel floppy disk device driver
BB_FCB_PTR  EQU     0FDF2H      ; Pointer to output sink device file

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer
AI_FCB      EQU     0FF0AH      ; Auxilliary input abstract file FCB pointer

;
; TOS File Control Block, block device variables
;
FCB_MODE    EQU     001H        ; File mode
FCB_BUFLEN  EQU     004H        ; Length of block/buffered-device data buffer
FCB_READ    EQU     008H        ; Device-driver Read API call
FCB_OPEN    EQU     00CH        ; Device-driver Open API call
FCB_CLOSE   EQU     00EH        ; Device-driver Close API call
FCB_DEVTYP  EQU     010H        ; Block-device type
FCB_DRVNR   EQU     011H        ; Drive number
FCB_FNAME   EQU     012H        ; Filename string
FCB_FEXT    EQU     FCB_FNAME+6 ; File extension string

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag
FM_BINARY   EQU     004H        ; Binary flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02000H
file_data_buffer:
        DS          128
file_linking_buffer:
        DS          128

command_str:
        DS          80
output_line_buffer:
        DS          132 + 1
output_bin_data_buffer_start_addr:
        DS          2
output_bin_data_block_length:
        DS          2
next_byte_in_block_abs_addr:
        DS          2
current_record_length:
        DS          1
current_record_data_abs_addr:
        DS          2
current_start_addr:
        DS          2
current_external_ref_offset:
        DS          2
current_operation_str:
        DS          15
label_input_buffer:
        DS          7
command_str_data_ptr:
        DS          2
sp_backup:
        DS          2
force_user_input_next_flag:
        DS          1
batch_file_flag:
        DS          1
lines_per_page:
        DS          1
remaining_lines_on_page:
        DS          1
object_file_list_start_ptr:
        DS          2
label_list_start_ptr:
        DS          2
xref_fault_severity:
        DS          1
cseg_addr:
        DS          2
obj_file_cseg_length:
        DS          2
dseg_addr:
        DS          2
obj_file_dseg_length:
        DS          2
disable_separate_dseg_flag:
        DS          1
objectfile_entry_nr:
        DS          1
current_label_tag:
        DS          1
current_label_abs_addr:
        DS          2
object_file_list_current_entry_ptr:
        DS          2
current_ext_labels_list_start_addr:
        DS          2
external_label_counter:
        DS          2
max_external_label_count:
        DS          2
start_addr_set_flag:
        DS          1

;
;   Object-file list entry:
;
;       DS  1   Drive type (+ bit 7 set)
;       DS  1   Drive number
;       DS  9   Filename
;       DS  2   CSEG address
;       DS  2   CSEG length
;       DS  2   DSEG address
;       DS  2   DSEG length
;

;
;   Label list entry:
;
;       DS  6   Label name
;       DS  2   Absolute address of label
;       DS  8   List of tags for label (obj-file nr, + bit 7 set if external ref.)
;
;       Note: Object-file number in a tag is 1-indexed
;
;       Note: Tags are only used for verifying dependencies and reference overview-
;             printouts, so if any list of tags overflows, the only side-effect is
;             that the printed list of cross-references will be missing some object
;             file names for the labels in question.
;

;
;   External labels list entry:
;
;       DS  6   Label name
;


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'LINK',NULL,NULL
        DB          '101'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C800H
program_origo:
start:
        ;
        ; Save stack pointer to enable breaking out of program from subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        sp_backup
        ;
        ; Set up files and variables
        ;
        CALL        setup_environment
main:
        ;
        ; Get command input
        ;
        CALL        get_next_command
do_next_operation:
        CALL        get_next_operation_from_cmd
        JC          main
        ;
        ; Check type of operation to do
        ;
        LDA         current_operation_str
        CPI         '*'
        JZ          control_operation
        CPI         '/'
        JZ          termination_operation
        ;
        ; Load and crossreference object file
        ;
        CALL        add_object_file_xrefs       ; Linking pass 1a
        JMP         do_next_operation

control_operation:
        ;
        ; Do control operation
        ;
        CALL        parse_control_operation     ; Control operation handlers
        JMP         do_next_operation

termination_operation:
        ;
        ; Do termination operation
        ;
        CALL        validate_xrefs              ; Linking pass 1b
        JC          do_next_operation
        CALL        generate_linked_binary      ; Linking pass 2
break_quit:
        ;
        ; Quit program
        ;
        LHLD        sp_backup
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set up pointers, variables and flags
        ;
setup_environment:
        ;
        ; Verify that output file SO is a block-device if assigned
        ;
        LHLD        SO_FCB
        MOV         A,L
        ORA         H
        JZ          use_default_output_file
        MOV         A,M             ; FCB + FCB_TYPE
        CPI         5
        JZ          output_file_ready
        LXI         H,invalid_output_file_str
        CALL        print_str
        JMP         break_quit


;//////////////////////////////////////

use_default_output_file:
        ;
        ; Use default output
        ;
        LHLD        BB_FCB_PTR
        SHLD        SO_FCB
output_file_ready:
        ;
        ; Set default lines per page
        ;
        MVI         A,48
        STA         lines_per_page
        ;
        ; Check printer output file, and set to default file if not assigned
        ;
        LHLD        SL_FCB
        MOV         A,L
        ORA         H
        JNZ         printer_file_ready
        LHLD        BB_FCB_PTR
        SHLD        SL_FCB
printer_file_ready:
        ;
        ; Check if batch file input is assigned
        ;
        LHLD        AI_FCB
        MOV         A,H
        ORA         L
        STA         batch_file_flag
        ;
        ; Get the start of User-RAM
        ;
        LXI         H,program_origo
scan_for_memory_start_loop:
        DCR         H
        MOV         A,M
        INR         M
        CMP         M
        JNZ         scan_for_memory_start_loop
        INR         H
        MVI         L,000H
        ;
        ; Set addresses to data-buffers
        ;
        SHLD        object_file_list_start_ptr
        MVI         M,000H
        LXI         D,10*13H + 1
        DAD         D
        SHLD        label_list_start_ptr
        MVI         M,000H
        ;
        ; Reset misc. addresses and counters
        ;
        LXI         H,00000H
        SHLD        cseg_addr
        SHLD        dseg_addr
        SHLD        current_start_addr
        SHLD        max_external_label_count
        ;
        ; Initialize flags and indexes
        ;
        MVI         A,TRUE
        STA         disable_separate_dseg_flag
        XRA         A
        STA         objectfile_entry_nr
        STA         start_addr_set_flag
        ;
        ; Get next pending character of console input, if buffered line file
        ;
        LHLD        CI_FCB
        MOV         A,M             ; FCB + FCB_TYPE
        CPI         4
        RNZ
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFIDX
        INX         H
        MOV         D,M
        PUSH        D
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        POP         H
        DAD         D
        MOV         A,M
        ;
        ; Take command input from console next if there's pending characters
        ;
        SUI         LF
        STA         force_user_input_next_flag
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get command for the next linker operation
        ;
get_next_command:
        ;
        ; Reset command string buffer
        ;
        LXI         H,command_str
        SHLD        command_str_data_ptr
        XCHG
        ;
        ; Check if next input is temporarily forced to be from the user
        ;
        LDA         force_user_input_next_flag
        ORA         A
        JZ          get_command_input
        XRA         A
        STA         force_user_input_next_flag
        JMP         get_user_input


;//////////////////////////////////////

get_command_input:
        ;
        ; Print prompt if getting input from user
        ;
        LDA         batch_file_flag
        ORA         A
        JNZ         get_batch_file_input
        MVI         A,'>'
        CALL        TTO
get_user_input:
        ;
        ; Get next operation line from user
        ;
        LHLD        CI_FCB
        CALL        GET
        JC          break_quit
        RET


;//////////////////////////////////////

get_batch_file_input:
        ;
        ; Get next operation line from batch file
        ;
        LHLD        AI_FCB
        CALL        GET
        RNC
        ;
        ; Check for end of file if exception, get input from user instead if so
        ;
        ORA         A
        JNZ         batch_file_input_error
        STA         batch_file_flag
        JMP         get_next_command

batch_file_input_error:
        STC
        JMP         break_quit


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prepare a string containing the next operation of the current command
        ;
get_next_operation_from_cmd:
        ;
        ; Get next character of command string, and check for end of line
        ;
        LHLD        command_str_data_ptr
get_next_command_char:
        MOV         A,M
        CPI         CR
        JNZ         command_char_ready
        STC
        RET

command_char_ready:
        ;
        ; Skip commas between parts of command
        ;
        CPI         ','
        JNZ         get_next_cmd_operation
        INX         H
        JMP         get_next_command_char

get_next_cmd_operation:
        ;
        ; Prepare a copy of the next operation from the command string
        ;
        LXI         D,current_operation_str
        MVI         B,15-1
copy_next_operation_char:
        ;
        ; Copy next character and advance pointers
        ;
        STAX        D
        INX         H
        INX         D
        ;
        ; Check for end of operation in command string
        ;
        MOV         A,M
        CPI         CR
        JZ          current_operation_ready
        CPI         ','
        JZ          current_operation_ready
        DCR         B
        JNZ         copy_next_operation_char
        ;
        ; Operation in command string is too long, print status about it
        ;
        PUSH        H
        XRA         A
        STAX        D
        LXI         H,ignored_str
        CALL        print_str
        LXI         H,current_operation_str
        CALL        print_str
        POP         H
        ;
        ; Find the start of the next operation in the command string
        ;
skip_next_char_of_cmd:
        MOV         A,M
        CPI         CR
        JZ          current_operation_skipped
        CPI         ','
        JZ          current_operation_skipped
        CALL        TTO
        INX         H
        JMP         skip_next_char_of_cmd


;//////////////////////////////////////

current_operation_skipped:
        PUSH        H
        LXI         H,newline_str
        CALL        print_str
        POP         H
        JMP         get_next_command_char


;//////////////////////////////////////

current_operation_ready:
        ;
        ; Update command line cursor data-pointer
        ;
        SHLD        command_str_data_ptr
        ;
        ; Blank new operation from command string
        ;
        XRA         A
blank_operation_from_cmd_loop:
        STAX        D
        INX         D
        DCR         B
        JNZ         blank_operation_from_cmd_loop
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Control operation handlers
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse and handle control operation changes
        ;
parse_control_operation:
        ;
        ; Verify control operation prefix
        ;
        LXI         H,current_operation_str
        MOV         A,M
        CPI         '*'
        JNZ         invalid_control_operation
        ;
        ; Get control change type character and make it uppercase
        ;
        INX         H
        MOV         A,M
        CPI         'a'-1
        JC          control_change_char_ready
        SUI         'a' - 'A'
control_change_char_ready:
        ;
        ; Check and verify control change type
        ;
        CPI         'C'
        JZ          set_segmet_address
        CPI         'D'
        JZ          set_segmet_address
        CPI         'P'
        JZ          parse_lines_per_page
        CPI         'Q'
        JZ          break_quit
        CPI         'S'
        JNZ         invalid_control_operation


;//////////////////////////////////////

set_segmet_address:
        ;
        ; Save segment change type and verify required preceeding equal sign
        ;
        MOV         C,A
        INX         H
        MOV         A,M
        CPI         '='
        JNZ         invalid_control_operation
        INX         H
        ;
        ; Check for special case of *D=*C
        ;
        MOV         A,C
        CPI         'D'
        JNZ         parse_segment_address
        MOV         A,M
        CPI         '*'
        JNZ         parse_segment_address
        INX         H
        MOV         A,M
        CPI         'C'
        JZ          disable_separate_data_segment
        CPI         'c'
        JNZ         invalid_control_operation
disable_separate_data_segment:
        ;
        ; Verify end of operation string
        ;
        INX         H
        MOV         A,M
        ORA         A
        JNZ         invalid_control_operation
        ;
        ; Disable separate DSEG
        ;
        MVI         A,TRUE
        STA         disable_separate_dseg_flag
        RET


;//////////////////////////////////////

parse_segment_address:
        ;
        ; Prepare to parse address as BCD number from string
        ;
        XCHG
        LXI         H,00000H
        LDAX        D
        ORA         A
        JZ          invalid_control_operation
parse_next_address_digit:
        ;
        ; Get ASCII digit and check for end of string
        ;
        LDAX        D
        INX         D
        ORA         A
        JZ          parsed_address_ready
        ;
        ; Validate and from ASCII hexadecimal to binary digit
        ;
        CPI         '0'
        JC          invalid_control_operation
        CPI         '9'+1
        JC          valid_numerical_digit
        CPI         'A'
        JC          invalid_control_operation
        CPI         'F'+1
        JC          valid_hexadecimal_digit
        CPI         'a'
        JC          invalid_control_operation
        CPI         'f'+1
        JNC         invalid_control_operation
        SUI         'a' - 'A'
valid_hexadecimal_digit:
        SUI         'A' - ('9'+1)
valid_numerical_digit:
        SUI         '0'
        ;
        ; Shift digit into combined binary number
        ;
        DAD         H
        DAD         H
        DAD         H
        DAD         H
        ADD         L
        MOV         L,A
        JMP         parse_next_address_digit

parsed_address_ready:
        ;
        ; Check which address was parsed, and store it in the right variable
        ;
        MOV         A,C
        CPI         'C'
        JZ          save_cseg_addr
        CPI         'S'
        JZ          save_start_addr
        SHLD        dseg_addr
        XRA         A
        STA         disable_separate_dseg_flag
        RET

save_cseg_addr:
        SHLD        cseg_addr
        RET

save_start_addr:
        SHLD        current_start_addr
        MVI         A,TRUE_ALT
        STA         start_addr_set_flag
        RET


;//////////////////////////////////////

        ;
        ; Print operation skipped status
        ;
invalid_control_operation:
        LXI         H,ignored_str
        CALL        print_str
        LXI         H,current_operation_str
        CALL        print_str
        LXI         H,newline_str
        CALL        print_str
        RET


;//////////////////////////////////////

parse_lines_per_page:
        ;
        ; Verify required preceeding equal sign
        ;
        INX         H
        MOV         A,M
        CPI         '='
        JNZ         invalid_control_operation
        ;
        ; Prepare to parse ASCII decimal number and verify not at end of string
        ;
        INX         H
        XCHG
        LXI         H,0
        LDAX        D
        ORA         A
        JZ          invalid_control_operation
parse_next_lines_per_page_digit:
        ;
        ; Get ASCII digit and check for end of string
        ;
        LDAX        D
        INX         D
        ORA         A
        JZ          lines_per_page_ready
        ;
        ; Convert and validate decimal digit
        ;
        SUI         '0'
        JC          invalid_control_operation
        CPI         9+1
        JNC         invalid_control_operation
        ;
        ; Multiply accumulator by 10 and add new digit
        ;
        DAD         H
        MOV         B,H
        MOV         C,L
        DAD         H
        DAD         H
        DAD         B
        ADD         L
        JC          invalid_control_operation
        MOV         L,A
        JMP         parse_next_lines_per_page_digit

lines_per_page_ready:
        ;
        ; Verify minimum value for lines per page argument
        ;
        MOV         A,L
        CPI         24
        JC          invalid_control_operation
        STA         lines_per_page
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Linking pass 1a: Opening object-file and cataloging cross-references
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add object file to program that is being linked
        ;
add_object_file_xrefs:
        ;
        ; Set up file and open object file
        ;
        CALL        prepare_objectfile_name
        RC
        CALL        open_objectfile
        RC
        ;
        ; Load and verify header, get parameters from it and prepare for labels
        ;
        CALL        load_objectfile_header
        RC
        LDA         objectfile_entry_nr
        INR         A
        STA         objectfile_entry_nr
        CALL        add_objectfile_to_list
        LXI         H,00000H
        SHLD        external_label_counter
        ;
        ; Load list of labels immediately following header
        ;
        CALL        load_objectfile_lables
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse and set up objectfile control block
        ;
prepare_objectfile_name:
        ;
        ; Set default drive number to 0
        ;
        XRA         A
        STA         SRC_FILE_FCB + FCB_DRVNR
        ;
        ; Check for drive designator, otherwise use same drive type as before
        ;
        LXI         H,current_operation_str
        MOV         A,M
        CPI         ':'
        JNZ         objectfile_drive_ready
        ;
        ; Get drive type from drive designator and make it uppercase
        ;
        INX         H
        MOV         A,M
        CPI         'a'-1
        JC          objectfile_drive_type_char_ready
        SUI         'a' - 'A'
objectfile_drive_type_char_ready:
        ;
        ; Get drive type of object file based on drive designator
        ;
        MVI         B,0
        CPI         'F'
        JZ          objectfile_drive_type_ready
        MVI         B,1
        CPI         'M'
        JNZ         invalid_objectfile_handle
objectfile_drive_type_ready:
        INX         H
        ;
        ; Parse and set drive number from drive designator
        ;
        MOV         A,M
        CPI         '0'
        JC          invalid_objectfile_handle
        CPI         '4'
        JNC         invalid_objectfile_handle
        SUI         '0'
        ;
        ; Set drive type and number in file
        ;
        STA         SRC_FILE_FCB + FCB_DRVNR
        MOV         A,B
        STA         SRC_FILE_FCB + FCB_DEVTYP
        ;
        ; Validate closing semicolon of file designator
        ;
        INX         H
        MOV         A,M
        CPI         ':'
        JNZ         invalid_objectfile_handle
        INX         H
objectfile_drive_ready:
        ;
        ; Verify first character of filename main part
        ;
        MOV         A,M
        CPI         'A'
        JC          invalid_objectfile_handle
        CPI         'Z'+1
        JC          valid_objectfile_filename
        CPI         'a'
        JC          invalid_objectfile_handle
        CPI         'z'+1
        JNC         invalid_objectfile_handle
valid_objectfile_filename:
        ;
        ; Clear filename field of file-control block
        ;
        LXI         D,SRC_FILE_FCB + FCB_FNAME
        MVI         B,9
        XRA         A
clear_objectfile_filename_loop:
        STAX        D
        INX         D
        DCR         B
        JNZ         clear_objectfile_filename_loop
        ;
        ; Copy over object file filename to file control block
        ;
        LXI         D,SRC_FILE_FCB + FCB_FNAME
        MVI         B,6
copy_objectfile_filename_loop:
        ;
        ; Check for the end of the main part of the filename
        ;
        MOV         A,M
        CPI         '.'
        JZ          objectfile_main_filename_ready
        ORA         A
        RZ
        ;
        ; Verify next character of filename main part
        ;
        CPI         '0'
        JC          invalid_objectfile_handle
        CPI         '9'+1
        JC          objectfile_valid_filename_char
        CPI         'A'
        JC          invalid_objectfile_handle
        CPI         'Z'+1
        JC          objectfile_valid_filename_char
        CPI         'a'
        JC          invalid_objectfile_handle
        CPI         'z'+1
        JNC         invalid_objectfile_handle
objectfile_valid_filename_char:
        ;
        ; Store filename character and advance to the next character
        ;
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         copy_objectfile_filename_loop
        ;
        ; Check for a filename extension in the file handle
        ;
        MOV         A,M
        ORA         A
        RZ
        CPI         '.'
        JNZ         invalid_objectfile_handle
objectfile_main_filename_ready:
        ;
        ; Copy over object file filename extension to file control block
        ;
        LXI         D,SRC_FILE_FCB + FCB_FEXT
        MVI         B,3
        INX         H
copy_objectfile_filen_ext_loop:
        ;
        ; Check for the end of the filename extension
        ;
        MOV         A,M
        ORA         A
        RZ
        ;
        ; Verify next character of filename extension
        ;
        CPI         '0'
        JC          invalid_objectfile_handle
        CPI         '9'+1
        JC          objectfile_valid_file_ext_char
        CPI         'A'
        JC          invalid_objectfile_handle
        CPI         'Z'+1
        JC          objectfile_valid_file_ext_char
        CPI         'a'
        JC          invalid_objectfile_handle
        CPI         'z'+1
        JNC         invalid_objectfile_handle
objectfile_valid_file_ext_char:
        ;
        ; Store filename extension character and advance to the next character
        ;
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         copy_objectfile_filen_ext_loop
        ;
        ; Verify nothing more in operation string after file handle
        ;
        MOV         A,M
        ORA         A
        RZ
invalid_objectfile_handle:
        ;
        ; Print status about operation skipped
        ;
        LXI         H,ignored_str
        CALL        print_str
        LXI         H,current_operation_str
        CALL        print_str
        LXI         H,newline_str
        CALL        print_str
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Open objectfile for binary input
        ;
open_objectfile:
        ;
        ; Reset up file control block buffer
        ;
        LXI         H,128
        SHLD        SRC_FILE_FCB + FCB_BUFLEN
        ;
        ; Select correct device driver based on device type
        ;
        LHLD        TABIN_PTR
        LDA         SRC_FILE_FCB + FCB_DEVTYP
        ORA         A
        JZ          objectfile_driver_ready
        LHLD        TABTC_PTR
objectfile_driver_ready:
        ;
        ; Set up device driver references in object file fcb
        ;
        SHLD        SRC_FILE_FCB + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        SRC_FILE_FCB + FCB_READ
        DAD         D
        SHLD        SRC_FILE_FCB + FCB_CLOSE
        ;
        ; Set file mode and open it
        ;
        LXI         H,SRC_FILE_FCB + FCB_MODE
        MVI         M,FM_BINARY
        DCX         H
        MVI         A,FM_INPUT
        CALL        OPEN
        RNC
        ;
        ; Object file could not be loaded
        ;
        LXI         H,file_not_found_str
        CALL        print_str
        LXI         H,current_operation_str
        CALL        print_str
        LXI         H,newline_str
        CALL        print_str
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read and verify the header of the object file
        ;
load_objectfile_header:
        ;
        ; Get and verify record type of header
        ;
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        JC          break_quit
        CPI         001H
        JNZ         invalid_objectfile
        ;
        ; Record type 1: Header
        ; Get and verify header record size
        ;
        CALL        INCHAR
        JC          break_quit
        CPI         004H
        JNZ         invalid_objectfile
        ;
        ; Get CSEG and DSEG lengths from header
        ;
        CALL        read_objectfile_word
        PUSH        D
        CALL        read_objectfile_word
        XCHG
        SHLD        obj_file_dseg_length
        POP         H
        SHLD        obj_file_cseg_length
        XRA         A
        RET


;//////////////////////////////////////

        ;
        ; Print status about invalid file
        ;
invalid_objectfile:
        LXI         H,invalid_objectfile_str
        CALL        print_str
        LXI         H,current_operation_str
        CALL        print_str
        LXI         H,newline_str
        CALL        print_str
        STC
        RET


;//////////////////////////////////////

        ;
        ; Read next two bytes as a 16-bit low-endian word
        ;
read_objectfile_word:
        CALL        INCHAR
        JC          break_quit
        MOV         E,A
        CALL        INCHAR
        JC          break_quit
        MOV         D,A
        RET


;//////////////////////////////////////////////////////////////////////////////

add_objectfile_to_list:
        ;
        ; Find the head of the object-file list
        ;
        LHLD        object_file_list_start_ptr
get_obj_file_list_head_loop:
        MOV         A,M
        ORA         A
        JZ          obj_file_list_head_found
        LXI         D,013H
        DAD         D
        JMP         get_obj_file_list_head_loop

obj_file_list_head_found:
        SHLD        object_file_list_current_entry_ptr
        ;
        ; Make sure there's ample room in the object file list
        ;
        XCHG
        LHLD        label_list_start_ptr
        DCX         H
        MOV         A,D
        CMP         H
        JNZ         space_available_in_obj_file_list
        MOV         A,E
        CMP         L
        CZ          expand_object_file_list
space_available_in_obj_file_list:
        ;
        ; Prepare the next entry in the list, first set device info
        ;
        XCHG
        LDA         SRC_FILE_FCB + FCB_DEVTYP
        ADI         080H
        MOV         M,A
        INX         H
        LDA         SRC_FILE_FCB + FCB_DRVNR
        MOV         M,A
        INX         H
        ;
        ; Set filename of list entry
        ;
        LXI         D,SRC_FILE_FCB + FCB_FNAME
        MVI         B,9
prep_list_copy_filename_loop:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         prep_list_copy_filename_loop
        ;
        ; Set CSEG extent of list entry, if object file has a CSEG
        ;
        MOV         B,H
        MOV         C,L
        LHLD        obj_file_cseg_length
        MOV         A,H
        ORA         L
        JNZ         prep_list_has_cseg
        ;
        ; No CSEG, so store null for both address and length
        ;
        CALL        store_word
        CALL        store_word
        JMP         prep_list_cseg_done

prep_list_has_cseg:
        LHLD        cseg_addr
        CALL        store_word
        LHLD        obj_file_cseg_length
        CALL        store_word
prep_list_cseg_done:
        ;
        ; Place DSEG right after CSEG if no particular address has been set up
        ;
        LDA         disable_separate_dseg_flag
        ORA         A
        JZ          prep_list_dseg_ready
        XCHG
        LHLD        cseg_addr
        DAD         D
        SHLD        dseg_addr
prep_list_dseg_ready:
        ;
        ; Set DSEG extent of list entry, if object file has a DSEG
        ;
        LHLD        obj_file_dseg_length
        MOV         A,H
        ORA         L
        JNZ         prep_list_has_dseg
        ;
        ; No DSEG, so store null for both address and length
        ;
        CALL        store_word
        CALL        store_word
        JMP         prep_list_dseg_done

prep_list_has_dseg:
        LHLD        dseg_addr
        CALL        store_word
        LHLD        obj_file_dseg_length
        CALL        store_word
prep_list_dseg_done:
        ;
        ; Set new head of object-file list
        ;
        XRA         A
        STAX        B
        LHLD        object_file_list_current_entry_ptr
        CALL        print_object_file_info
        RET


;//////////////////////////////////////

        ;
        ; Store HL to memory pointed to by BC
        ;
store_word:
        MOV         A,L
        STAX        B
        INX         B
        MOV         A,H
        STAX        B
        INX         B
        RET


;//////////////////////////////////////

expand_object_file_list:
        ;
        ; Find the head of the list of labels
        ;
        PUSH        D
        LHLD        label_list_start_ptr
        MOV         B,H
        MOV         C,L
        ;
        ; Get the end of label list
        ;
get_label_list_head_loop:
        MOV         A,M
        ORA         A
        JZ          label_list_head_found
        LXI         D,010H
        DAD         D
        JMP         get_label_list_head_loop

        ;
        ; Move entire label list to make room for 10 more object-file entries
        ;
label_list_head_found:
        ;
        ; Get new end of label list
        ;
        XCHG
        LXI         H,10*013H
        DAD         D
move_label_list_byte:
        ;
        ; Move the next byte from old list position to new list position
        ;
        LDAX        D
        MOV         M,A
        ;
        ; Check if the whole label list has been moved
        ;
        MOV         A,B
        CMP         D
        JNZ         move_next_label_list_byte
        MOV         A,C
        CMP         E
        JZ          label_list_move_done
move_next_label_list_byte:
        ;
        ; Advance to next byte
        ;
        DCX         D
        DCX         H
        JMP         move_label_list_byte

label_list_move_done:
        ;
        ; Update pointer for new start-of-list
        ;
        LXI         H,10*013H
        DAD         B
        SHLD        label_list_start_ptr
        POP         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print info about the current object file list entry
        ;
print_object_file_info:
        CALL        get_object_file_info_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Compose string with info about the current object file list entry
        ;
get_object_file_info_str:
        ;
        ; Clear string buffer that will be used
        ;
        PUSH        H
        CALL        clear_output_line_buffer
        LXI         H,output_line_buffer
        POP         D
        ;
        ; Add file designator and drive type
        ;
        MVI         M,':'
        INX         H
        MVI         M,'F'
        LDAX        D
        ANI         001H
        JZ          obj_file_info_drive_type_ready
        MVI         M,'M'
obj_file_info_drive_type_ready:
        INX         H
        INX         D
        ;
        ; Add drive number and close file designator
        ;
        LDAX        D
        ADI         '0'
        MOV         M,A
        INX         H
        MVI         M,':'
        INX         H
        INX         D
        ;
        ; Add main part of filename
        ;
        MVI         B,6
        MVI         C,0
obj_file_info_add_filename_loop:
        LDAX        D
        ORA         A
        JZ          obj_file_info_filename_char_done
        MOV         M,A
        INX         H
        INR         C
obj_file_info_filename_char_done:
        INX         D
        DCR         B
        JNZ         obj_file_info_add_filename_loop
        ;
        ; Add file extension
        ;
        LDAX        D
        ORA         A
        JZ          obj_file_info_file_ext_done
        MVI         M,'.'
        INX         H
        INR         C
        MVI         B,3
obj_file_info_add_file_ext_loop:
        LDAX        D
        ORA         A
        JZ          obj_file_info_file_ext_done
        MOV         M,A
        INX         H
        INX         D
        INR         C
        DCR         B
        JNZ         obj_file_info_add_file_ext_loop
obj_file_info_file_ext_done:
        ;
        ; Calculate how much to tab after filename, based on filename length
        ;
        MVI         A,13
        SUB         C
        MOV         C,A
        MVI         B,000H
        DAD         B
        PUSH        H
        ;
        ; Check if there is a CSEG in the object file
        ;
        LHLD        obj_file_cseg_length
        MOV         A,H
        ORA         L
        POP         H
        JNZ         obj_file_info_print_cseg
        ;
        ; No CSEG, so tab past this part too
        ;
        LXI         B,17
        DAD         B
        JMP         obj_file_info_check_dseg

obj_file_info_print_cseg:
        ;
        ; Add CSEG start address to string
        ;
        MVI         M,'C'
        INX         H
        MVI         M,':'
        INX         H
        INX         H
        PUSH        H
        LHLD        cseg_addr
        XCHG
        POP         H
        CALL        EDWH
        ;
        ; Add CSEG end address to string
        ;
        INX         H
        MVI         M,'-'
        INX         H
        INX         H
        PUSH        H
        LHLD        cseg_addr
        XCHG
        LHLD        obj_file_cseg_length
        DAD         D
        DCX         H
        XCHG
        POP         H
        CALL        EDWH
        INX         H
        INX         H
        INX         H
obj_file_info_check_dseg:
        ;
        ; Check if there is a DSEG in the object file
        ;
        PUSH        H
        LHLD        obj_file_dseg_length
        MOV         A,H
        ORA         L
        POP         H
        JZ          obj_file_info_ready
        ;
        ; Add DSEG start address to string
        ;
        MVI         M,'D'
        INX         H
        MVI         M,':'
        INX         H
        INX         H
        PUSH        H
        LHLD        dseg_addr
        XCHG
        POP         H
        CALL        EDWH
        ;
        ; Add DSEG end address to string
        ;
        INX         H
        MVI         M,'-'
        INX         H
        INX         H
        PUSH        H
        LHLD        dseg_addr
        XCHG
        LHLD        obj_file_dseg_length
        DAD         D
        DCX         H
        XCHG
        POP         H
        CALL        EDWH
obj_file_info_ready:
        ;
        ; Terminate info string with a newline
        ;
        MVI         M,CR
        LXI         D,output_line_buffer
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Load all remaining lables in object-file
        ;
load_objectfile_lables:
        ;
        ; Load the next label from file
        ;
load_next_label:
        ;
        ; Check label type
        ;
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        CPI         002H
        JZ          load_public_label
        CPI         003H
        JNZ         label_loading_done


;//////////////////////////////////////

        ;
        ; Record type 3: External label
        ; Get number of character in label
        ;
        CALL        INCHAR
        MOV         B,A
        ;
        ; Set tag, to tie this label to its objectfile later
        ;
        LDA         objectfile_entry_nr
        ADI         080H
        STA         current_label_tag
        ;
        ;
        ;
        LXI         H,00000H
        SHLD        current_label_abs_addr
        ;
        ; Increase counter of external labels for this object file
        ;
        LHLD        external_label_counter
        INX         H
        SHLD        external_label_counter
        JMP         load_label_name


;//////////////////////////////////////

        ;
        ; Record type 2: Public label
        ;
load_public_label:
        ;
        ; Set tag, to tie this label to its objectfile later
        ;
        LDA         objectfile_entry_nr
        STA         current_label_tag
        ;
        ; Get number of character in label
        ;
        CALL        INCHAR
        SUI         3
        MOV         B,A
        ;
        ; Get address base for this particular record
        ;
        CALL        INCHAR
        ORA         A
        JZ          abs_addr_public_label
        CPI         001H
        JZ          cseg_rel_addr_public_label
        LHLD        dseg_addr
        JMP         load_addr_public_label

abs_addr_public_label:
        LXI         H,00000H
        JMP         load_addr_public_label

cseg_rel_addr_public_label:
        LHLD        cseg_addr
load_addr_public_label:
        ;
        ; Get absolute address of label
        ;
        PUSH        H
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        MOV         E,A
        CALL        INCHAR
        MOV         D,A
        POP         H
        DAD         D
        SHLD        current_label_abs_addr


;//////////////////////////////////////

load_label_name:
        ;
        ; Clear label input buffer
        ;
        LXI         H,label_input_buffer
        MVI         C,6
clear_label_input_buffer_loop:
        MVI         M,NULL
        INX         H
        DCR         C
        JNZ         clear_label_input_buffer_loop
        ;
        ; Read label from record in object file
        ;
        LXI         D,label_input_buffer
        LXI         H,SRC_FILE_FCB
load_label_name_loop:
        CALL        INCHAR
        STAX        D
        INX         D
        DCR         B
        JNZ         load_label_name_loop
        ;
        ; Check if the new label is already in the list of known labels
        ;
        LXI         D,label_input_buffer
        CALL        look_up_label_entry_tag_list
        JC          add_new_label
        ;
        ; If so, no new entry is needed
        ;
        DCX         H
        DCX         H
        PUSH        H
        JMP         update_label_entry

add_new_label:
        ;
        ; Copy over label name to new entry
        ;
        LXI         D,label_input_buffer
        MVI         B,6
LAB_ram_ce4b:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         LAB_ram_ce4b
        ;
        ; Clear the rest of the new label entry
        ;
        PUSH        H
        MVI         B,(010H - 6) + 1
prepare_label_entry_loop:
        MVI         M,NULL
        INX         H
        DCR         B
        JNZ         prepare_label_entry_loop


;//////////////////////////////////////

update_label_entry:
        ;
        ; Update absolute address of label entry in the case of public label
        ;
        LHLD        current_label_abs_addr
        XCHG
        POP         H
        MOV         A,E
        ORA         D
        JZ          label_entry_abs_addr_ready
        MOV         M,E
        INX         H
        MOV         M,D
        DCX         H
label_entry_abs_addr_ready:
        INX         H
        INX         H
        ;
        ; Prepare to add label tag to list of tags in label entry
        ;
        LDA         current_label_tag
        MOV         B,A
        MVI         C,8
label_entry_check_next_tag:
        ;
        ; Add tag directly if at end of entire list
        ;
        MOV         A,M
        ORA         A
        JZ          label_entry_add_new_tag
        ;
        ; Inject tag if at start of extenal tags portion of list
        ;
        ANI         080H
        JNZ         label_entry_check_external_tag
        ;
        ; Otherwise, let any existing public tags stay at the start of the list
        ;
        INX         H
        DCR         C
        JNZ         label_entry_check_next_tag
        JMP         load_next_label

label_entry_check_external_tag:
        ;
        ; Add tag to current position of the list of tags
        ;
        MOV         A,M
        MOV         M,B
        ;
        ; Add old tag from this position to the end of the list, if enough room
        ;
        MOV         B,A
        MOV         A,C
        ORA         A
label_entry_get_first_free_tag_slot_loop:
        JZ          load_next_label
        MOV         A,M
        ORA         A
        JZ          label_entry_add_new_tag
        INX         H
        DCR         C
        JMP         label_entry_get_first_free_tag_slot_loop

label_entry_add_new_tag:
        ;
        ; Add tag to current position of list of tags
        ;
        MOV         M,B
        JMP         load_next_label


;//////////////////////////////////////

label_loading_done:
        ;
        ; Update max nr. of external labels for a single object file, if needed
        ;
        LHLD        max_external_label_count
        XCHG
        LHLD        external_label_counter
        MOV         A,D
        CMP         H
        JC          new_max_ext_label_count
        JNZ         max_ext_label_count_ready
        MOV         A,E
        CMP         L
        JNC         max_ext_label_count_ready
new_max_ext_label_count:
        SHLD        max_external_label_count
max_ext_label_count_ready:
        ;
        ; Move DSEG for next object file
        ;
        LHLD        dseg_addr
        XCHG
        LHLD        obj_file_dseg_length
        DAD         D
        SHLD        dseg_addr
        ;
        ; Move CSEG for next object file
        ;
        LDA         disable_separate_dseg_flag
        ORA         A
        JZ          advcance_cseg
        SHLD        cseg_addr
        RET

advcance_cseg:
        LHLD        cseg_addr
        XCHG
        LHLD        obj_file_cseg_length
        DAD         D
        SHLD        cseg_addr
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Linking pass 1b: Validation of cross-references
;//
;//////////////////////////////////////////////////////////////////////////////

validate_xrefs:
        ;
        ; Prepare severity level before checks
        ;
        XRA         A
        STA         xref_fault_severity
        ;
        ; Scan through all labels, and verify public definitions exists
        ;
        LHLD        label_list_start_ptr
check_next_label_for_public_def:
        ;
        ; Check for the end of the label list
        ;
        MOV         A,M
        ORA         A
        JZ          label_public_defs_check_done
        ;
        ; Get first reference tag of label
        ;
        PUSH        H
        LXI         D,008H
        DAD         D
        MOV         A,M
        ;
        ; Verify that reference tag is of the public definition type
        ;
        ANI         080H
        POP         H
        CNZ         public_label_missing_fault
        ;
        ; Advance to the next label entry in the list
        ;
        LXI         D,010H
        DAD         D
        JMP         check_next_label_for_public_def

label_public_defs_check_done:


;//////////////////////////////////////

        ;
        ; Scan through all labels, and verify no double public definitions
        ;
        LHLD        label_list_start_ptr
check_label_for_no_double:
        ;
        ; Check for the end of the label list
        ;
        MOV         A,M
        ORA         A
        JZ          label_double_public_defs_check_done
        ;
        ; Get second reference tag entry of label
        ;
        PUSH        H
        LXI         D,008H + 1
        DAD         D
        MOV         A,M
        POP         H
        ;
        ; Check if reference tag is set at all, in case of no external refs
        ;
        ORA         A
        JZ          check_next_label_for_no_double
        ;
        ; Verify that the reference tag is external (not a public reference)
        ;
        ANI         080H
        CZ          double_public_label_fault
check_next_label_for_no_double:
        LXI         D,010H
        DAD         D
        JMP         check_label_for_no_double

label_double_public_defs_check_done:


;//////////////////////////////////////

        ;
        ; Check if any of the checks ended in a fault, and if it is recoverable
        ;
        LDA         xref_fault_severity
        CPI         2
        JZ          break_quit
        CPI         1
        CMC
        RET


;//////////////////////////////////////////////////////////////////////////////

double_public_label_fault:
        PUSH        H
        ;
        ; Check if this is the first time this error is encountered
        ;
        LDA         xref_fault_severity
        CPI         2
        JZ          double_public_status_ready
        ;
        ; If so, set severity-level to hard fault and print status
        ;
        MVI         A,2
        STA         xref_fault_severity
        LXI         D,double_symbols_str
        LHLD        CO_FCB
        CALL        PUT
double_public_status_ready:
        ;
        ; Clear line-buffer
        ;
        CALL        clear_output_line_buffer
        POP         H
        PUSH        H
        LXI         D,output_line_buffer
        ;
        ; Add label-name to details line
        ;
        MVI         B,6
double_public_copy_label_loop:
        MOV         A,M
        ORA         A
        JNZ         double_public_label_char_ready
        MVI         A,' '
double_public_label_char_ready:
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         double_public_copy_label_loop
        INX         D
        INX         D
        ;
        ; Add 'in'
        ;
        MVI         A,'i'
        STAX        D
        INX         D
        MVI         A,'n'
        STAX        D
        INX         D
        INX         D
        ;
        ; Prepare to print all public definition references to label
        ;
        INX         H
        MVI         B,8
double_public_status_add_next_tag:
        ;
        ; Check for end of reference tags for label
        ;
        INX         H
        MOV         A,M
        ORA         A
        JZ          double_public_status_str_done
        ;
        ; Check if at start of extern reference tags
        ;
        ANI         080H
        JNZ         double_public_status_str_done
        ;
        ; Otherwise still in public label tag part of list, so add name
        ;
        MOV         A,M
        CALL        get_ref_tag_name_str
        DCR         B
        JNZ         double_public_status_add_next_tag
double_public_status_str_done:
        ;
        ; Terminate status string with a newline and print it
        ;
        MVI         A,CR
        STAX        D
        LXI         D,output_line_buffer
        LHLD        CO_FCB
        CALL        PUT
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

public_label_missing_fault:
        PUSH        H
        ;
        ; Check if this is the first time this error is encountered
        ;
        LDA         xref_fault_severity
        ORA         A
        JNZ         public_missing_status_ready
        ;
        ; If so, set severity-level to recoverable fault and print status
        ;
        INR         A
        STA         xref_fault_severity
        LXI         D,externals_missing_str
        LHLD        CO_FCB
        CALL        PUT
public_missing_status_ready:
        ;
        ; Clear line-buffer
        ;
        CALL        clear_output_line_buffer
        POP         H
        PUSH        H
        LXI         D,output_line_buffer
        ;
        ; Add label-name to details line
        ;
        MVI         B,6
public_missing_copy_label_loop:
        MOV         A,M
        ORA         A
        JNZ         public_missing_label_char_ready
        MVI         A,' '
public_missing_label_char_ready:
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         public_missing_copy_label_loop
        INX         D
        INX         D
        ;
        ; Add 'in'
        ;
        MVI         A,'i'
        STAX        D
        INX         D
        MVI         A,'n'
        STAX        D
        INX         D
        INX         D
        ;
        ; Prepare to print all public definition references to label
        ;
        INX         H
        MVI         B,8
public_missing_status_add_next_tag:
        ;
        ; Check for end of reference tags for label
        ;
        INX         H
        MOV         A,M
        ORA         A
        JZ          public_missing_status_str_done
        ;
        ; Add names of all external refs
        ;
        CALL        get_ref_tag_name_str
        DCR         B
        JNZ         public_missing_status_add_next_tag
public_missing_status_str_done:
        ;
        ; Terminate status string with a newline and print it
        ;
        MVI         A,CR
        STAX        D
        LXI         D,output_line_buffer
        LHLD        CO_FCB
        CALL        PUT
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get objectfile name from label referenc tag
        ;
get_ref_tag_name_str:
        PUSH        B
        PUSH        H
        PUSH        D
        ;
        ; Remove public/external flag from tag to get object file list index
        ;
        ANI         07FH
        ;
        ; Scan through object file list to get to the appropriate index
        ;
        LXI         D,013H
        LHLD        object_file_list_start_ptr
        INX         H
        INX         H
tag_name_scan_to_obj_file_entry_loop:
        DCR         A
        JZ          tag_name_obj_file_entry_ready
        DAD         D
        JMP         tag_name_scan_to_obj_file_entry_loop
tag_name_obj_file_entry_ready:
        ;
        ; Copy main part of filename
        ;
        POP         D
        MVI         B,6
tag_name_copy_filename_loop:
        MOV         A,M
        ORA         A
        JZ          tag_name_filename_char_done
        STAX        D
        INX         D
tag_name_filename_char_done:
        INX         H
        DCR         B
        JNZ         tag_name_copy_filename_loop
        ;
        ; Check for filename extension, and add deliminator if so
        ;
        MOV         A,M
        ORA         A
        JZ          tag_name_str_ready
        MVI         A,'.'
        STAX        D
        ;
        ; Copy file extension from filename
        ;
        INX         D
        MVI         B,3
tag_name_copy_file_ext_loop:
        MOV         A,M
        ORA         A
        JZ          tag_name_str_ready
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         tag_name_copy_file_ext_loop
tag_name_str_ready:
        ;
        ; Add space at end of filename
        ;
        MVI         A,' '
        STAX        D
        INX         D
        POP         H
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Linking pass 2: Final linked binary file generation
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prepare to link binary, then go on to link it after printing header
        ;
generate_linked_binary:
        ;
        ; Scan to just after the list of labels for the next free part of RAM
        ;
        LHLD        label_list_start_ptr
get_end_of_label_list_loop:
        MOV         A,M
        ORA         A
        JZ          end_of_label_list_ready
        LXI         D,010H
        DAD         D
        JMP         get_end_of_label_list_loop

end_of_label_list_ready:
        INX         H
        ;
        ; Allocate 6*N + 1 bytes for the temporary list of external labels
        ;
        SHLD        current_ext_labels_list_start_addr
        XCHG
        LHLD        max_external_label_count
        DAD         H
        XCHG
        DAD         D
        DAD         D
        DAD         D
        INX         H
        ;
        ; Use memory after lists as buffer for the linked binary output data
        ;
        SHLD        output_bin_data_buffer_start_addr
        LXI         H,0
        SHLD        output_bin_data_block_length
        ;
        ; Pass 2 will start back at the first object file
        ;
        XRA         A
        STA         objectfile_entry_nr


;//////////////////////////////////////

        ;
        ; Print page header for first page on standard line-printer device
        ;
        MVI         B,4
prinit_initial_margin_loop:
        CALL        print_sl_newline
        DCR         B
        JNZ         prinit_initial_margin_loop
        LXI         D,program_title_str
        LHLD        SL_FCB
        CALL        PUT
        CALL        print_sl_newline
        ;
        ; Prepare program name string
        ;
        LXI         H,program_str
        LXI         D,output_line_buffer
copy_program_str_loop:
        MOV         A,M
        ORA         A
        JZ          program_str_ready
        STAX        D
        INX         D
        INX         H
        JMP         copy_program_str_loop

program_str_ready:
        ;
        ; Get pointer to output program filename
        ;
        LHLD        SO_FCB
        LXI         B,FCB_FNAME
        DAD         B
        ;
        ; Add main part of output filename to program name string
        ;
        MVI         B,6
copy_output_filename_loop:
        MOV         A,M
        ORA         A
        JZ          output_filename_char_done
        STAX        D
        INX         D
output_filename_char_done:
        INX         H
        DCR         B
        JNZ         copy_output_filename_loop
        ;
        ; Check for filename extension, and print deliminator if so
        ;
        MOV         A,M
        ORA         A
        JZ          output_file_ext_done
        MVI         A,'.'
        STAX        D
        INX         D
        ;
        ; Add output file extension to program name string
        ;
        MVI         B,3
copy_output_file_ext_loop:
        MOV         A,M
        ORA         A
        JZ          output_file_ext_done
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         copy_output_file_ext_loop
output_file_ext_done:
        ;
        ; Terminate output filename string and print it on line-printer
        ;
        MVI         A,CR
        STAX        D
        LXI         D,output_line_buffer
        LHLD        SL_FCB
        CALL        PUT
        CALL        print_sl_newline
        ;
        ; Print table-title for reference table on line-printer
        ;
        LXI         D,routine_table_header_str
        LHLD        SL_FCB
        CALL        PUT
        CALL        print_sl_newline
        LDA         lines_per_page
        SUI         4*2 + 6
        STA         remaining_lines_on_page
        ;
        ; Start linking pass 2
        ;
        JMP         link_next_object_file


;//////////////////////////////////////////////////////////////////////////////

link_next_object_file:
        ;
        ; Reset list of external labels for the current object file
        ;
        LHLD        current_ext_labels_list_start_addr
        MVI         M,NULL
        ;
        ; Get the next entry of the object-file list
        ;
        LDA         objectfile_entry_nr
        INR         A
        STA         objectfile_entry_nr
        LHLD        object_file_list_start_ptr
        LXI         D,013H
link_get_to_file_entry:
        DCR         A
        JZ          link_file_entry_ready
        DAD         D
        JMP         link_get_to_file_entry

link_file_entry_ready:
        ;
        ; Check for end of list, write current binary block as last block if so
        ;
        MOV         A,M
        ORA         A
        JZ          write_last_block_to_output
        ;
        ; Set up file control block to read object file, based on item entry
        ;
        PUSH        H
        ;
        ; Set file type
        ;
        MOV         A,M
        ANI         001H
        STA         SRC_FILE_FCB + FCB_DEVTYP
        ;
        ; Set device driver routines based on device type
        ;
        PUSH        H
        LHLD        TABIN_PTR
        ORA         A
        JZ          link_obj_file_driver_selected
        LHLD        TABTC_PTR
link_obj_file_driver_selected:
        SHLD        SRC_FILE_FCB + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        SRC_FILE_FCB + FCB_READ
        DAD         D
        SHLD        SRC_FILE_FCB + FCB_CLOSE
        POP         H
        ;
        ; Set drive number
        ;
        INX         H
        MOV         A,M
        STA         SRC_FILE_FCB + FCB_DRVNR
        ;
        ; Set filename
        ;
        INX         H
        LXI         D,SRC_FILE_FCB + FCB_FNAME
        MVI         B,9
link_obj_file_copy_filename_loop:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         link_obj_file_copy_filename_loop
        ;
        ; Set up CSEG address and length for file
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        XCHG
        SHLD        cseg_addr
        XCHG
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        XCHG
        SHLD        obj_file_cseg_length
        XCHG
        ;
        ; Set up DSEG address and length for file
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        XCHG
        SHLD        dseg_addr
        XCHG
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        SHLD        obj_file_dseg_length
        ;
        ; Set object file block size
        ;
        LXI         H,128
        SHLD        SRC_FILE_FCB + FCB_BUFLEN
        POP         H
        ;
        ; Print object file info on line printer
        ;
        CALL        get_object_file_info_str
        LXI         D,output_line_buffer
        LHLD        SL_FCB
        CALL        PUT
        ;
        ; Advance line number and add top/bottom margin if at page-break
        ;
        LDA         remaining_lines_on_page
        SUI         1
        JNZ         printer_line_number_ready
        MVI         B,4*2
printer_add_margins_loop:
        CALL        print_sl_newline
        DCR         B
        JNZ         printer_add_margins_loop
        LDA         lines_per_page
        SUI         4*2
printer_line_number_ready:
        STA         remaining_lines_on_page
        ;
        ; Open file for binary input
        ;
        LXI         H,SRC_FILE_FCB + FCB_MODE
        MVI         M,FM_BINARY
        DCX         H
        MVI         A,FM_INPUT
        CALL        OPEN
        JC          break_quit
        ;
        ; Prepare to skip header record
        ;
        MVI         B,6


;//////////////////////////////////////

        ;
        ; Skip current record
        ;
skip_current_record:
        LXI         H,SRC_FILE_FCB
skip_next_input_byte:
        CALL        INCHAR
        DCR         B
        JNZ         skip_next_input_byte


;//////////////////////////////////////

        ;
        ; Check and handle a object-file record, second linking pass edition
        ;
check_next_record:
        ;
        ; Get record type
        ;
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        CPI         002H
        JNZ         check_for_external_label_record
        ;
        ; Record type 2: Skip public labels this time
        ;
        CALL        INCHAR
        MOV         B,A
        JMP         skip_current_record

check_for_external_label_record:
        CPI         003H
        JNZ         check_for_other_records
        ;
        ; Record type 3: Add external label to list of current external labels
        ; Get record length first
        ;
        CALL        INCHAR
        MOV         B,A
        ;
        ; Count bytes left in external label list entry
        ;
        MVI         C,7
        ;
        ; Get next free entry in the list of current external labels
        ;
        PUSH        H
        LHLD        current_ext_labels_list_start_addr
        LXI         D,006H
get_next_extern_label_list_entry_loop:
        MOV         A,M
        ORA         A
        JZ          next_extern_label_list_entry_ready
        DAD         D
        JMP         get_next_extern_label_list_entry_loop
next_extern_label_list_entry_ready:
        XCHG
        POP         H
        ;
        ; Copy external label over to list entry
        ;
copy_ext_label_loop:
        CALL        INCHAR
        STAX        D
        INX         D
        DCR         C
        DCR         B
        JNZ         copy_ext_label_loop
        ;
        ; Clear any remaining characters in external label entry
        ;
        XRA         A
clear_remaining_ext_label_chars_loop:
        STAX        D
        INX         D
        DCR         C
        JNZ         clear_remaining_ext_label_chars_loop
        JMP         check_next_record


;//////////////////////////////////////

check_for_other_records:
        ;
        ; Check for the remaining non-label record types
        ;
        CPI         004H
        JZ          data_record
        CPI         005H
        JZ          reference_record
        CPI         006H
        JZ          ext_reference_record
        CPI         007H
        JZ          start_addr_record
        CPI         0FFH
        JZ          link_next_object_file
        ;
        ; Unknown record type at this point in object-file
        ;
        LXI         H,bad_record_str
        CALL        print_str
        XRA         A
        JMP         break_quit


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Data record, copy bytes to output binary
        ;
data_record:
        ;
        ; Get absoute start address and length for record data-chunk
        ;
        CALL        get_record_abs_address
        LDA         current_record_length
        MOV         B,A
        ;
        ; Add data-chunk to output file
        ;
wrtie_data_record_loop:
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        CALL        add_byte_to_output_block
        DCR         B
        JNZ         wrtie_data_record_loop
        JMP         check_next_record


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert from internal reference to absolute address pointer
        ;
reference_record:
        ;
        ; Get absoute pointer to record reference
        ;
        CALL        get_record_abs_address
        ;
        ; Get base segment absolute address
        ;
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        LXI         H,00000H
        ORA         A
        JZ          int_ref_base_addr_ready
        LHLD        cseg_addr
        CPI         001H
        JZ          int_ref_base_addr_ready
        LHLD        dseg_addr
int_ref_base_addr_ready:
        XCHG
        ;
        ; Get reference offset from base
        ;
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        MOV         B,A
        CALL        INCHAR
        MOV         H,A
        MOV         L,B
        ;
        ; Add base and offset to get absolute address referenced
        ;
        DAD         D
        ;
        ; Write absolute address derived from reference to output binary file
        ;
        MOV         A,L
        CALL        add_byte_to_output_block
        MOV         A,H
        CALL        add_byte_to_output_block
        JMP         check_next_record


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert from external reference to absolute address pointer
        ;
ext_reference_record:
        ;
        ; Get absoute pointer to record reference
        ;
        CALL        get_record_abs_address
        ;
        ; Get index into current file external labels list
        ;
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        MOV         C,A
        CALL        INCHAR
        MOV         B,A
        ;
        ; Get any potential offset provided from referenced external label
        ;
        CALL        INCHAR
        MOV         D,A
        CALL        INCHAR
        MOV         H,A
        MOV         L,D
        SHLD        current_external_ref_offset
        ;
        ; Look up label name in current object-file's external labels list
        ;
        LHLD        current_ext_labels_list_start_addr
        LXI         D,6
ext_ref_get_ext_label_entry_loop:
        DCX         B
        MOV         A,B
        ORA         C
        JZ          ext_ref_ext_label_entry_ready
        DAD         D
        JMP         ext_ref_get_ext_label_entry_loop

ext_ref_ext_label_entry_ready:
        XCHG
        ;
        ; Get absolute address of public label matching external label name
        ;
        CALL        look_up_label_entry_tag_list
        JNC         ext_ref_addr_ready
        ;
        ; If not found, the label referenced was not cataloged in pass 1
        ;
        LXI         H,symbol_missing_str
        CALL        print_str
        JMP         break_quit


;//////////////////////////////////////

ext_ref_addr_ready:
        ;
        ; Read absolute address from matching public label entry as base
        ;
        DCX         H
        MOV         D,M
        DCX         H
        MOV         E,M
        ;
        ; Add base and offset to get absolute address referenced
        ;
        LHLD        current_external_ref_offset
        DAD         D
        ;
        ; Write absolute address derived from reference to output binary file
        ;
        MOV         A,L
        CALL        add_byte_to_output_block
        MOV         A,H
        CALL        add_byte_to_output_block
        JMP         check_next_record


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set binary program execution start/entry-address
        ;
start_addr_record:
        ;
        ; Get absoute start address for start-address
        ;
        CALL        get_record_abs_address
        ;
        ; Update start-address parameter, unless it's already set by the user
        ;
        LDA         start_addr_set_flag
        ANA         A
        JNZ         check_next_record
        DCR         A
        STA         start_addr_set_flag
        LHLD        current_record_data_abs_addr
        SHLD        current_start_addr
        JMP         check_next_record


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write the final block of binary data and entry address to output file
        ;
write_last_block_to_output:
        ;
        ; Check if there is any data to write at all, write data-block if so
        ;
        LHLD        output_bin_data_block_length
        MOV         A,H
        ORA         L
        CNZ         write_block_to_output
        LXI         H,0
        SHLD        output_bin_data_block_length
        ;
        ; Get and check if the entry point parameter was set in advance
        ;
        LHLD        current_start_addr
        LDA         start_addr_set_flag
        ANA         A
        JNZ         entry_point_addr_ready
        ;
        ; If not, get the first object file CSEG as default entry point
        ;
        LHLD        object_file_list_start_ptr
        LXI         D,00BH
        DAD         D
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
entry_point_addr_ready:
        ;
        ; Write execution entrypoint reference to Intel Absolute Binary file
        ;
        XCHG
        LHLD        output_bin_data_buffer_start_addr
        INX         H
        INX         H
        MOV         M,E
        INX         H
        MOV         M,D
        CALL        write_block_to_output


;//////////////////////////////////////

        ;
        ; Print pagebreak if at end of page on line-printer and reserve 3 lines
        ;
        LDA         remaining_lines_on_page
        CPI         4
        JNC         linking_end_printer_line_ready
        ADI         4*2
        MOV         B,A
linking_end_sl_pagebreak_loop:
        CALL        print_sl_newline
        DCR         B
        JNZ         linking_end_sl_pagebreak_loop
        LDA         lines_per_page
        SUI         4*2
linking_end_printer_line_ready:
        SUI         3
        STA         remaining_lines_on_page
        ;
        ; Print cross-reference table header to line-printer
        ;
        CALL        print_sl_newline
        LXI         D,xref_header_str
        LHLD        SL_FCB
        CALL        PUT
        CALL        print_sl_newline
        ;
        ; Print table of labels and cross-references
        ;
print_next_xref:
        ;
        ; Print next label with cross-references to it
        ;
        CALL        clear_output_line_buffer
        CALL        find_next_alphabetic_label_entry
        JNC         print_label_xref_summary


;//////////////////////////////////////

        ;
        ; Table printed, feed out the remaining lines of the last page
        ;
        LDA         remaining_lines_on_page
        ADI         4
        MOV         B,A
final_printer_page_feed_loop:
        CALL        print_sl_newline
        DCR         B
        JNZ         final_printer_page_feed_loop
        ;
        ; Exit program with ok status
        ;
        XRA         A
        JMP         break_quit


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print label cross-reference summary
        ;
print_label_xref_summary:
        ;
        ; Prepare to compose status string
        ;
        XCHG
        PUSH        H
        LXI         D,output_line_buffer
        ;
        ; Copy name of label into the output line
        ;
        MVI         B,6
label_summary_copy_name_loop:
        MOV         A,M
        ORA         A
        JZ          label_summary_name_char_done
        STAX        D
label_summary_name_char_done:
        INX         D
        INX         H
        DCR         B
        JNZ         label_summary_copy_name_loop
        ;
        ; Get absolute address of label and add it to report
        ;
        MOV         B,M
        INX         H
        PUSH        H
        MOV         H,M
        MOV         L,B
        INX         D
        XCHG
        CALL        EDWH
        INX         H
        INX         H
        INX         H
        XCHG
        POP         H
        INX         H
        ;
        ; Add public label object-file name to string
        ;
        MOV         A,M
        CALL        get_ref_tag_name_str
        ;
        ; Add filename of the up to 6 last objectfiles referencing this label
        ;
        LXI         D,output_line_buffer + 27
        MVI         B,6
        JMP         label_summary_add_next_ref_name

label_summary_add_ref_name:
        CALL        get_ref_tag_name_str
label_summary_add_next_ref_name:
        INX         H
        MOV         A,M
        ORA         A
        JZ          label_summary_ready
        DCR         B
        JNZ         label_summary_add_ref_name
        ;
        ; If more than 6 references, indicate with an '->' arrow
        ;
        MVI         A,'-'
        STAX        D
        INX         D
        MVI         A,'>'
        STAX        D
        INX         D
label_summary_ready:
        ;
        ; Terminate status line and print it as line in table on line printer
        ;
        MVI         A,CR
        STAX        D
        LXI         D,output_line_buffer
        LHLD        SL_FCB
        CALL        PUT
        ;
        ; Advance line counter and add pagebreak if needed
        ;
        LDA         remaining_lines_on_page
        SUI         1
        JNZ         label_summary_next_line_ready
        MVI         B,4*2
label_summary_add_page_margin_loop:
        CALL        print_sl_newline
        DCR         B
        JNZ         label_summary_add_page_margin_loop
        LDA         lines_per_page
        SUI         4*2
label_summary_next_line_ready:
        STA         remaining_lines_on_page
        ;
        ; Mark the current label list entry as already chosen
        ;
        POP         H
        MVI         M,0FFH
        JMP         print_next_xref


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get absolute address of content for record types 4-7
        ;
get_record_abs_address:
        ;
        ; Get length of record, exclusing the general address bytes
        ;
        CALL        INCHAR
        SUI         3
        STA         current_record_length
        ;
        ; Get base segment type
        ;
        CALL        INCHAR
        MOV         B,A
        ;
        ; Get address offset
        ;
        CALL        INCHAR
        MOV         E,A
        CALL        INCHAR
        MOV         D,A
        ;
        ; Get absolute address of base segment
        ;
        MOV         A,B
        LXI         H,00000H
        ORA         A
        JZ          record_base_addr_ready
        LHLD        cseg_addr
        CPI         001H
        JZ          record_base_addr_ready
        LHLD        dseg_addr
record_base_addr_ready:
        ;
        ; Add offset to get absolute address of record data content
        ;
        DAD         D
        SHLD        current_record_data_abs_addr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Add the next byte to the output binary file
        ;
add_byte_to_output_block:
        ;
        ; Save registers
        ;
        PUSH        B
        PUSH        D
        PUSH        H
        PUSH        PSW
        ;
        ; Check if the current block size is zero
        ;
        LHLD        output_bin_data_block_length
        MOV         A,H
        ORA         L
        JZ          add_byte_prepare_next_block
        ;
        ; Check if the output buffer is full
        ;
        XCHG
        LHLD        output_bin_data_buffer_start_addr
        DAD         D
        LXI         D,program_origo
        DCX         D
        MOV         A,D
        CMP         H
        JNZ         add_byte_buffer_ready
        MOV         A,E
        CMP         L
        JNZ         add_byte_buffer_ready
        ;
        ; If so, write it to output file as one block of binary data now
        ;
add_byte_write_current_block:
        CALL        write_block_to_output
add_byte_prepare_next_block:
        ;
        ; Update current byte absolute address, for the record
        ;
        LHLD        current_record_data_abs_addr
        SHLD        next_byte_in_block_abs_addr
        ;
        ; Prepare block header with its absolute load address
        ;
        XCHG
        LHLD        output_bin_data_buffer_start_addr
        INX         H
        INX         H
        MOV         M,E
        INX         H
        MOV         M,D
        ;
        ; Reset block length
        ;
        LXI         H,0
        SHLD        output_bin_data_block_length
add_byte_buffer_ready:
        ;
        ; Check if the next byte is consecutive with existing data
        ;
        LHLD        current_record_data_abs_addr
        XCHG
        LHLD        next_byte_in_block_abs_addr
        MOV         A,H
        CMP         D
        JNZ         add_byte_write_current_block
        MOV         A,L
        CMP         E
        JNZ         add_byte_write_current_block
        ;
        ; If so, increase current byte for next time
        ;
        INX         H
        SHLD        next_byte_in_block_abs_addr
        ;
        ; Increase size of current block
        ;
        LHLD        output_bin_data_block_length
        INX         H
        SHLD        output_bin_data_block_length
        ;
        ; Add buffer start address to get address of current byte in block
        ;
        XCHG
        LHLD        output_bin_data_buffer_start_addr
        XCHG
        DAD         D
        ;
        ; Add rest of bytes of block header to get address of byte in buffer
        ;
        INX         H
        INX         H
        INX         H
        ;
        ; Write byte to buffer
        ;
        POP         PSW
        MOV         M,A
        ;
        ; Advance address of next byte from record
        ;
        LHLD        current_record_data_abs_addr
        INX         H
        SHLD        current_record_data_abs_addr
        ;
        ; Recover the rest of the registers
        ;
        POP         H
        POP         D
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write block of linked binary data to output file
        ;
write_block_to_output:
        ;
        ; Save registers
        ;
        PUSH        PSW
        PUSH        H
        PUSH        B
        PUSH        D
        ;
        ; Set data-block length in Intel abs-bin header record
        ;
        LHLD        output_bin_data_block_length
        XCHG
        LHLD        output_bin_data_buffer_start_addr
        MOV         M,E
        INX         H
        MOV         M,D
        ;
        ; Add Intel abs-bin header record to number of bytes to write
        ;
        LXI         H,004H
        DAD         D
        MOV         B,H
        MOV         C,L
        ;
        ; Write from binary data buffer to file
        ;
        LHLD        output_bin_data_buffer_start_addr
        XCHG
        LHLD        SO_FCB
write_to_output_loop:
        LDAX        D
        CALL        OUTCHAR
        INX         D
        DCX         B
        MOV         A,B
        ORA         C
        JNZ         write_to_output_loop
        ;
        ; Restore registers
        ;
        POP         D
        POP         B
        POP         H
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Search for next label entry in list, pick in alphabetical order
        ;
find_next_alphabetic_label_entry:
        ;
        ; Scan to next label from the list that has not been chosen yet
        ;
        LHLD        label_list_start_ptr
find_first_unchosen_label_loop:
        ;
        ; Check for the end of the list
        ;
        MOV         A,M
        ORA         A
        STC
        RZ
        ;
        ; Check if the current entry of list has already been chosen
        ;
        CPI         0FFH
        JNZ         find_next_xref_label_check_candidate
        ;
        ; If so, advance to the next entry
        ;
        LXI         D,010H
        DAD         D
        JMP         find_first_unchosen_label_loop


;//////////////////////////////////////

        ;
        ; Compare list items until the label lowest in the alphabet is found
        ;
find_next_xref_label_check_candidate:
        ;
        ; Save pointer to candidate entry
        ;
        PUSH        H
        POP         D
        ;
        ; Get next label that hasn't been chosen yet
        ;
find_next_unprinted_label_loop:
        ;
        ; Advance to next item
        ;
        LXI         B,010H
        DAD         B
        ;
        ; Check for the end of the list
        ;
        MOV         A,M
        ORA         A
        RZ
        ;
        ; Check if the current entry of list has been chosen already
        ;
        CPI         0FFH
        JZ          find_next_unprinted_label_loop
        ;
        ; Save pointers to candidate and current item, to recover for next loop
        ;
        PUSH        H
        PUSH        D
        ;
        ; Compare label name of candidate and current item
        ;
        MVI         B,6
find_next_xref_label_compare_loop:
        ;
        ; Check if current item label is lower in the alphabet than candidate
        ;
        LDAX        D
        CMP         M
        JC          find_next_xref_label_keep_candidate
        JNZ         find_next_xref_label_new_candidate
        ;
        ; If still a posibility, compare next character of labels
        ;
        INX         D
        INX         H
        DCR         B
        JNZ         find_next_xref_label_compare_loop
        ;
        ; Special case, both labels are exactly equal: Reject the current entry
        ;
find_next_xref_label_keep_candidate:
        ;
        ; Keep candidate, advance current item
        ;
        POP         D
        POP         H
        JMP         find_next_unprinted_label_loop

find_next_xref_label_new_candidate:
        ;
        ; Set current item to candidate, advance current item
        ;
        POP         D
        POP         H
        JMP         find_next_xref_label_check_candidate


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Find label entry's reference tag list, using label name string at DE
        ;
look_up_label_entry_tag_list:
        ;
        ; Start scanning though list of labels
        ;
        LHLD        label_list_start_ptr
search_for_label_loop:
        ;
        ; Check for the end of the list of labels
        ;
        MOV         A,M
        ORA         A
        STC
        RZ
        ;
        ; Compare the rest of the label if first character matches list entry
        ;
        LDAX        D
        CMP         M
        JZ          compare_labels
check_next_label:
        ;
        ; Check next entry
        ;
        LXI         B,010H
        DAD         B
        JMP         search_for_label_loop


;//////////////////////////////////////

compare_labels:
        PUSH        H
        PUSH        D
        ;
        ; Compare the current label list item name with name string
        ;
        MVI         B,6
compare_current_label_loop:
        LDAX        D
        CMP         M
        JNZ         labels_not_equal
        INX         H
        INX         D
        DCR         B
        JNZ         compare_current_label_loop
        ;
        ; Label list entry found, get to the ref tags and return
        ;
        INX         H
        INX         H
        POP         D
        POP         D
        RET

labels_not_equal:
        POP         D
        POP         H
        JMP         check_next_label


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print a NULL-terminated string to console
        ;
print_str:
        MOV         A,M
        ORA         A
        RZ
        CALL        TTO
        INX         H
        JMP         print_str


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print newline on line-printer
        ;
print_sl_newline:
        LHLD        SL_FCB
        LXI         D,tos_newline_str
        CALL        PUT
        RET


;//////////////////////////////////////

tos_newline_str:
        DB          CR


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clear the string buffer by filling it with spaces
        ;
clear_output_line_buffer:
        LXI         H,output_line_buffer
        MVI         A,132
clear_current_operation_str:
        MVI         M,' '
        INX         H
        DCR         A
        JNZ         clear_current_operation_str
        MVI         M,CR
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File control blocks
;//
;//////////////////////////////////////////////////////////////////////////////

SRC_FILE_FCB:
        DB          5
        DB          FM_BINARY
        DW          0
        DW          80
        DW          file_data_buffer
        DW          00000H
        DW          00000H
        DW          00000H
        DW          00000H
        DB          0
        DB          0
        DS          9
        DB          001H
        DW          00000H
        DB          000H
        DB          000H
        DW          file_linking_buffer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

invalid_output_file_str:
        DB          'Bad assignment on SO',CR,LF,NULL
ignored_str:
        DB          'IGNORED: ',NULL
newline_str:
        DB          CR,LF,NULL
file_not_found_str:
        DB          'NOT FOUND: ',NULL
invalid_objectfile_str:
        DB          'NOT RELOC.: ',NULL
double_symbols_str:
        DB          'Doubly defined symbols:',CR
externals_missing_str:
        DB          'Undefined externals:',CR
routine_table_header_str:
        DB          'Routine table',CR
program_title_str:
        DB          'TDV 2100 LINKER V.1.1',CR
program_str:
        DB          'Program: ',NULL
bad_record_str:
        DB          'Bad record encountered',CR,LF,NULL
symbol_missing_str:
        DB          'Symbol not found in pass2. Linker error.',CR,LF,NULL
xref_header_str:
        DB          'Symbol Addr   Defined      Used',CR
