;//////////////////////////////////////////////////////////////////////////////
;//
;//     PROM - Interface tool for PROM programmers
;//
;//         Tool for interaction with PROM data-streams in BNPF paper-tape format.
;//         In this particular case, the format is extended with a few features:
;//         Using a Ctrl-B to signalize the start of a stream and a Ctrl-C to mark
;//         the end of a stream, and interpreting the character 'E' anywhere inside
;//         a word to mean that the whole word is to be immediately discarded. This
;//         alteration makes it possible to add descriptive text to the stream
;//         containing the letter B, as long as an E comes within 7 characters
;//         afterwards.
;//
;//         NOTE: This program will map out all unused ram in the machine not used
;//               by XMON, TOS and the PROM program itself. when loading a file, it
;//               is importaint that every binary data-block in the file (using
;//               Intel Absolute Binary format) fits fully within this free memory.
;//               If this is not the case, an error will be printed and the load
;//               will stop midway through. To fix this, should it happen, an
;//               offset can be added to the file's load addresses as an argument
;//               to the load command.
;//
;//         NOTE: This program is hardcoded to expec the Rx buffer at address
;//               0x25E0. This is not the case for XMON/F, and as such the input
;//               serial buffer will not be flushed properly before expecting new
;//               data on some machines.
;//
;//
;//         Commands:
;//
;//             C <start>,<end>                     Clear block of memory
;//             E                                   Quit to XMON debugger
;//             L [:<Tn>:]<name>[,<offset>]         Load memory image from file
;//             P <start>,<end>                     Send data block as BNPF
;//             Q                                   Quit to TOS
;//             T <start>                           Receive BNPF data block
;//             W [:<Tn>:]<name>,<start>,<length>   Write block of memory to file
;//
;//                 start           Address to first byte of datablock
;//                 end             Address to last (inclusive) byte of datablock
;//                 Tn              Drive type and number, default :F0:
;//                 offset          Offset added to data load addresses, default 0
;//                 length          Length of datablock
;//                 destination     Destination address for single-byte result
;//
;//                 Drive type T:
;//                     F       Floppy
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         NOTE: Leading spaces after the command-letter will be ignored.
;//
;//         NOTE: Any hexadecimal number may end with a 'H', but this is not a
;//               strict requirements
;//
;//         NOTE: The T command does not check for free memory, and will very much
;//               be able to overwrite anything in RAM if the start addres does not
;//               ensure enough space
;//
;//         NOTE: The W command does not check for a length of zero. If a length of
;//               zero is used, the entire 64KB memory map will be written to file,
;//               in an Intel Absolute Binary format file block that claims a size
;//               of 0 bytes.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the E command may not bring up the debugger,
;//                    unless the proper flag has been set witht he DEBUG command
;//                    before loading the PROM tool
;//                 -> Has a bug where the entry address tag is not written to
;//                    output file
;//                 -> Has a bug where specifying any file designator for loading
;//                    and saving files always will result in an invalid file error
;//                 -> Has a bug where the argument after a filename will not be
;//                    recognized
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> Fixes entry address bug from v1.3
;//                 -> Fixes file-designator bug from v1.3
;//                 -> Fixes the argument after filename bug from v1.3
;//                 -> Renames the Z command to C
;//                 -> Introduces sanitycheck to prevent overwriting anything when
;//                    loading data from file
;//
;//             1.6: Entry at 0xC2D7
;//
;//                 -> Version ID written to 0x2700
;//                 -> Fixes command E bug from v1.5, for newer XMON versions only
;//                 -> Introduces a bug where the strings used by the program may
;//                    be overwritten by a load using the L command. Should this
;//                    happen, the program will start to print garbage instead of
;//                    the expected text.
;//
;//             1.7a: Entry at 0xC2D7
;//
;//                 -> Uses a different value when setting the XMON debug flag
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

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
STX         EQU     002H        ; Start of text
ETX         EQU     003H        ; End of text
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
RESET       EQU     00000H      ; Reset XMON, can be used to trigger debugger
RCVI        EQU     00082H      ; Main UART input
XMIO        EQU     000CAH      ; Main UART output

;
; XMON and TOS system data
;
RCVBUF      EQU     025E0H      ; Main UART input buffer
SIGNATURE   EQU     02700H      ; Program signature
BUFLIM      EQU     0272EH      ; Lowest address of current TOS buffers
DEBUGX      EQU     0275EH      ; XMON debug flag

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
OPEN        EQU     0FD1EH      ; Open block device
CLOSE       EQU     0FD27H      ; Close block device

;
; TOS constants
;
TABIN_PTR   EQU     0FDEAH      ; Pointer to Intel floppy disk device driver

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS File Control Block, block device variables
;
FCB_MODE    EQU     001H        ; File mode
FCB_READ    EQU     008H        ; Device-driver Read API call
FCB_WRITE   EQU     00AH        ; Device-driver Write API call
FCB_OPEN    EQU     00CH        ; Device-driver Open API call
FCB_CLOSE   EQU     00EH        ; Device-driver Close API call
FCB_DRVNR   EQU     011H        ; Drive number
FCB_FNAME   EQU     012H        ; Filename string
FCB_FEXT    EQU     FCB_FNAME+6 ; File extension string
FCB_DRVFMT  EQU     01BH        ; Media format

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag
FM_OUTPUT   EQU     002H        ; File open for writing flag
FM_BINARY   EQU     004H        ; Binary flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'PROM',NULL,NULL
        DB          '107'


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

current_data_ptr:
        DS          2
end_address:
        DS          2
file_loaded_addr_offset:
        DS          2
load_chunk_start_addr:
        DS          2
load_chunk_length:
        DS          2
user_input_buffer:
        DS          81

input_file_fcb:
        DB          5
        DS          1
        DS          2
        DS          2
        DW          file_data_buffer
        DS          2
        DS          2
        DS          2
        DS          2
        DB          1
        DS          1
        DS          9
        DB          001H
        DS          2
        DS          1
        DS          1
        DW          file_linking_block

file_data_buffer:
        DS          128
file_linking_block:
        DS          128

output_file_fcb:
        DB          5
        DS          1
        DS          2
        DS          2
        DW          file_data_buffer
        DS          2
        DS          2
        DS          2
        DS          2
        DB          1
        DS          1
        DS          9
        DB          001H
        DS          2
        DS          1
        DS          1
        DW          file_linking_block

command_prompt_str:
        DB          ':',CR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Transmit the data-byte immediately following the call to this
        ;
serial_tx_inline:
        ;
        ; Get return-pointer from top of stack and transmit inline byte
        ;
        XTHL
        PUSH        PSW
        MOV         A,M
        CALL        XMIO
        ;
        ; Making sure to skip inline data-byte when returning from subroutine
        ;
        INX         H
        ;
        ; Wait a little bit before returning
        ;
        PUSH        D
        LXI         D,64
tx_wait_loop:
        DCX         D
        MOV         A,D
        ORA         E
        JNZ         tx_wait_loop
        POP         D
        POP         PSW
        ;
        ; Restore return-pointer to top of stack
        ;
        XTHL
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Store negative value of HL into DE
        ;
negate_word:
        MOV         A,L
        CMA
        MOV         E,A
        MOV         A,H
        CMA
        MOV         D,A
        INX         D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get word pointed to by BC into HL
        ;
fetch_next_word:
        LDAX        B
        MOV         L,A
        INX         B
        LDAX        B
        MOV         H,A
        INX         B
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
        ; Check if A is an alphanumeric ASCII character
        ;
is_alphanumeric:
        CPI         '0'
        JM          not_alphanumeric
        CPI         '9'+1
        JM          alphanumeric_found
        CPI         'A'
        JM          not_alphanumeric
        CPI         'Z'+1
        JM          alphanumeric_found
        CPI         'a'
        JM          not_alphanumeric
        CPI         'z'+1
        JP          not_alphanumeric
alphanumeric_found:
        ANA         A
        RET

not_alphanumeric:
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

get_input_filename:
        ;
        ; Clear drive number and name of input filename
        ;
        LXI         D,input_file_fcb + FCB_DRVNR
        MVI         B,FCB_DRVFMT - FCB_DRVNR
clear_input_filename_loop:
        SUB         A
        STAX        D
        INX         D
        DCR         B
        JNZ         clear_input_filename_loop
        ;
        ; Verify valid drive type
        ;
        LXI         D,input_file_fcb + FCB_DRVNR
        CALL        get_next_char
        CPI         ':'
        JNZ         drive_set
        INX         H
        MOV         A,M
        INX         H
        CALL        to_uppercase
        CPI         'F'
        JNZ         invalid_input_file
        ;
        ; Verify valid drive number, and set it in FCB
        ;
        MOV         A,M
        INX         H
        CPI         '0'
        JM          invalid_input_file
        CPI         '4'
        JP          invalid_input_file
        SUI         '0'
        STAX        D
        ;
        ; Verify correctly formatted drive designator string
        ;
        MOV         A,M
        INX         H
        CPI         ':'
        JNZ         invalid_input_file
drive_set:
        ;
        ; Prepare to get filename and extension
        ;
        INX         D               ; input_file_fcb + FCB_FNAME
        LXI         B,00603H
        ;
        ; Get main part of filename from input string
        ;
get_next_filename_char:
        MOV         A,M
        INX         H
        CALL        is_alphanumeric
        JC          filename_done
        STAX        D
        INX         D
        DCR         B
        JNZ         get_next_filename_char
        ;
        ; Check if full 6-character filename has an extension
        ;
        MOV         A,M
        INX         H
        CPI         '.'
        JZ          get_next_file_ext_char
        ;
        ; Check proper deliminator or line end after filename
        ;
        CPI         ','
        RZ
        CPI         CR
        JNZ         invalid_input_file
        ANA         A
        RET

filename_done:
        ;
        ; Check if less-than-6-character filename has an extension
        ;
        CPI         '.'
        JNZ         file_extension_done
        ;
        ; Get file extension from input string
        ;
        LXI         D,input_file_fcb + FCB_FEXT
get_next_file_ext_char:
        MOV         A,M
        INX         H
        CALL        is_alphanumeric
        JC          file_extension_done
        STAX        D
        INX         D
        DCR         C
        JNZ         get_next_file_ext_char
        MOV         A,M
        INX         H
file_extension_done:
        ;
        ; Check proper deliminator or line end after filename
        ;
        CPI         ','
        JZ          valid_filename_end
        CPI         CR
        JNZ         invalid_input_file
valid_filename_end:
        ANA         A
        RET

invalid_input_file:
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

get_next_char:
        MOV         A,M
        CPI         ' '
        JZ          skip_space_or_comma
        CPI         ','
        RNZ
skip_space_or_comma:
        INX         H
        JMP         get_next_char


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII Hexadecimal digit in A to binary value
        ;
convert_hex_digit_to_bin:
        CALL        to_uppercase
        CPI         '0'
        JM          invalid_hex_char
        CPI         '9'+1
        JM          base_10_char
        CPI         'A'
        JM          invalid_hex_char
        CPI         'F'+1
        JM          base_16_to_base_10
invalid_hex_char:
        STC
        RET

base_16_to_base_10:
        SUI         'A' - ('9'+1)
base_10_char:
        SUI         '0'
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Converts a hex number in string at HL into a binary value in DE
        ;
parse_hex_number:
        ;
        ; Prepare accumulative variable
        ;
        LXI         D,0
parse_next_hex_digit:
        ;
        ; Get next potential hex digit and try to convert it to binary
        ;
        MOV         A,M
        CALL        convert_hex_digit_to_bin
        JC          non_hex_digit
        ;
        ; Multiply current value with 16 and add the value from the new digit
        ;
        XCHG
        DAD         H
        DAD         H
        DAD         H
        DAD         H
        MOV         C,A
        MVI         B,000H
        DAD         B
        XCHG
        ;
        ; Point to next potential digit
        ;
        INX         H
        JMP         parse_next_hex_digit

non_hex_digit:
        ;
        ; Check if standard hex suffix has been provided
        ;
        CPI         'H'
        JZ          h_after_number
        ;
        ; Verify line end or deliminator after hex number without H suffix
        ;
        CPI         CR
        JZ          end_of_hex_number
        CPI         ','
        JZ          end_of_hex_number
invalid_hex_number:
        STC
        RET

h_after_number:
        ;
        ; Verify line end or deliminator after hex number with H suffix
        ;
        INX         H
        MOV         A,M
        CPI         ','
        JZ          end_of_hex_number
        CPI         CR
        JNZ         invalid_hex_number
end_of_hex_number:
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

start:
beginning:
        ;
        ; Set up input file control block driver to Intel floppy
        ;
        LHLD        TABIN_PTR
        SHLD        input_file_fcb + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        input_file_fcb + FCB_READ
        DAD         D
        SHLD        input_file_fcb + FCB_CLOSE
        ;
        ; Set up output file control block driver to Intel floppy
        ;
        LHLD        TABIN_PTR
        INX         H
        INX         H
        INX         H
        SHLD        output_file_fcb + FCB_OPEN
        DAD         D
        SHLD        output_file_fcb + FCB_WRITE
        DAD         D
        SHLD        output_file_fcb + FCB_CLOSE
        ;
        ; Make sure unwanted driver-operations of FCBs stay disabled
        ;
        LXI         H,00000H
        SHLD        input_file_fcb + FCB_WRITE
        SHLD        output_file_fcb + FCB_READ
        ;
        ; Test memory at 4000H
        ;
        LXI         H,04000H
        MOV         E,M
        XRA         A
        MOV         M,A
        CMP         M
        MOV         M,E
        JZ          ram_at_4000
        ;
        ; Test memory at 8000H
        ;
        DAD         H
        MOV         E,M
        MOV         M,A
        CMP         M
        MOV         M,E
        JZ          ram_at_8000
        ;
        ; Assume user memory starts at C000H, so only use RAM after program
        ;
        LXI         H,unused_program_memory
        SHLD        memory_window_2_start
        LHLD        BUFLIM
        SHLD        memory_window_2_end
        JMP         next_command_prompt

ram_at_8000:
        ;
        ; No RAM at 4000H, add RAM window starting at 8000H
        ;
        SHLD        memory_window_2_start
        JMP         ram_at_8fff

ram_at_4000:
        ;
        ; Add RAM window starting at 4000H
        ;
        SHLD        memory_window_2_start
        ;
        ; Test memory at 8000H as well
        ;
        DAD         H
        MOV         E,M
        MOV         M,A
        CMP         M
        MOV         M,E
        JNZ         set_end_of_ram_window
ram_at_8fff:
        ;
        ; Set end of available RAM at just before C000H
        ;
        MVI         H,0C0H
set_end_of_ram_window:
        DCX         H
        SHLD        memory_window_2_end
        ;
        ; Add RAM after program as a third RAM window
        ;
        LXI         H,unused_program_memory
        SHLD        memory_window_3_start
        LHLD        BUFLIM
        SHLD        memory_window_3_end
        JMP         next_command_prompt


;//////////////////////////////////////////////////////////////////////////////

memory_window_list:
        DW          02000H,024FFH
memory_window_2_start:
        DW          00000H
memory_window_2_end:
        DW          00000H
memory_window_3_start:
        DW          00000H
memory_window_3_end:
        DW          00000H
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Prompt user for next command
        ;
next_command_prompt:
        LHLD        CO_FCB
        LXI         D,command_prompt_str
        CALL        PUTSTR
        RC
        LHLD        CI_FCB
        LXI         D,user_input_buffer
        CALL        GET
        RC
        ;
        ; Ignore any whitespace at start of command string
        ;
        LXI         H,user_input_buffer
skip_leading_spaces:
        MOV         A,M
        INX         H
        CPI         CR
        JZ          next_command_prompt
        CPI         ' '
        JZ          skip_leading_spaces
        ;
        ; Check command against valid commands
        ;
        CALL        to_uppercase
        CPI         'E'
        JZ          cmd_enter_debugger
        CPI         'Q'
        RZ
        CPI         'L'
        JZ          cmd_load_file
        CPI         'P'
        JZ          cmd_program
        CPI         'T'
        JZ          cmd_receive_bnpf
        CPI         'W'
        JZ          cmd_write_to_file
        CPI         'C'
        JZ          cmd_clear_memory
        ;
        ; Command not found, run prompt again
        ;
command_error:
        LXI         D,command_error_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        JMP         next_command_prompt


;//////////////////////////////////////

        ;
        ; Enter XMON debugger
        ;
cmd_enter_debugger:
        MVI         A,TRUE
        STA         DEBUGX
        ;
        ; Push return address, then reset XMON to trigger ROM debugger
        ;
        LXI         H,next_command_prompt
        PUSH        H
        JMP         RESET


;//////////////////////////////////////

        ;
        ; Load a file into memory at a given location
        ;
cmd_load_file:
        ;
        ; Reset pointer
        ;
        SUB         A
        STA         file_loaded_addr_offset
        STA         file_loaded_addr_offset+1
        ;
        ; Get filename and verify deliminator if more command arguments
        ;
        CALL        get_input_filename
        JC          command_error
        CPI         CR
        JZ          load_address_set
        CPI         ','
        JNZ         command_error
        ;
        ; Get and verify load address argument
        ;
        CALL        parse_hex_number
        JC          command_error
        CPI         CR
        JNZ         command_error
        XCHG
        SHLD        file_loaded_addr_offset
load_address_set:
        ;
        ; Set up input file FCB buffer
        ;
        LXI         H,input_file_fcb + FCB_MODE
        MVI         M,FM_BINARY
        INX         H
        SUB         A
        MOV         M,A             ; input_file_fcb + FCB_BUFIDX
        INX         H
        MOV         M,A
        INX         H
        MVI         M,128           ; input_file_fcb + FCB_BUFLEN
        INX         H
        MOV         M,A
        ;
        ; Open input file for reading
        ;
        LXI         H,input_file_fcb
        MVI         A,FM_INPUT
        CALL        OPEN
        RC
load_next_chunk:
        ;
        ; Get chunk load size, check for last block (size=0)
        ;
        LXI         H,input_file_fcb
        CALL        INCHAR
        JC          load_error
        MOV         E,A
        CALL        INCHAR
        JC          load_error
        MOV         D,A
        ORA         E
        JZ          load_complete
        ;
        ; Get chunk load address
        ;
        CALL        INCHAR
        JC          load_error
        MOV         C,A
        CALL        INCHAR
        JC          load_error
        MOV         B,A
        ;
        ; Add origo address as load offset, then save final address and length
        ;
        LHLD        file_loaded_addr_offset
        DAD         B
        SHLD        load_chunk_start_addr
        XCHG
        SHLD        load_chunk_length
        XCHG
        ;
        ; Negate address since we will compare by using addition as subtraction
        ;
        CALL        negate_word
        LXI         B,memory_window_list
check_next_memory_window:
        ;
        ; Get start of memory window, and check for end of memory window list
        ;
        CALL        fetch_next_word
        MOV         A,L
        ORA         H
        JZ          load_out_of_range
        ;
        ; Check that chunk start is at or later than current window start
        ;
        DAD         D
        JNC         load_start_check_done
        MOV         A,L
        ORA         H
        JNZ         load_out_of_range
load_start_check_done:
        ;
        ; Get end of memory window
        ;
        CALL        fetch_next_word
        ;
        ; Check that chunk end is at or before current memory window end
        ;
        PUSH        H
        DAD         D
        POP         H
        JNC         check_next_memory_window
        ;
        ; Get chunk end address
        ;
        PUSH        H
        LHLD        load_chunk_start_addr
        XCHG
        LHLD        load_chunk_length
        DAD         D
        ;
        ; Check that chunk does not wrap around the end of memory address space
        ;
        CALL        negate_word
        POP         H
        DAD         D
        JNC         load_out_of_range
        ;
        ; Recover chunk address and length for the actual load operation
        ;
        LHLD        load_chunk_length
        XCHG
        LHLD        load_chunk_start_addr
        MOV         C,L
        MOV         B,H
        ;
        ; Load all data in file chunk
        ;
        LXI         H,input_file_fcb
load_next_byte:
        CALL        INCHAR
        JC          load_error
        STAX        B
        INX         B
        DCX         D
        MOV         A,D
        ORA         E
        JNZ         load_next_byte
        JMP         load_next_chunk

load_out_of_range:
        LXI         D,load_out_of_range_str
        LHLD        CO_FCB
        CALL        PUT
        RC
load_complete:
        ;
        ; Close file when load is done
        ;
        LXI         H,input_file_fcb
        CALL        CLOSE
        RC
        JMP         next_command_prompt

load_error:
        ANA         A
        STC
        RNZ
        ;
        ; Error code is zero: Unexpected end of file
        ;
        LXI         D,eof_error_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        JMP         load_complete


;//////////////////////////////////////

cmd_program:
        ;
        ; Get start addess of data to send to programmer, and check deliminator
        ;
        CALL        get_next_char
        CALL        parse_hex_number
        JC          command_error
        CPI         ','
        JNZ         command_error
        INX         H
        XCHG
        SHLD        current_data_ptr
        ;
        ; Get end address of data
        ;
        XCHG
        CALL        parse_hex_number
        JC          command_error
        CPI         CR
        JNZ         command_error
        XCHG
        SHLD        end_address
        ;
        ; Prompt user to prepare programmer device, then press cartridge-return
        ;
        LXI         D,program_prompt_str
        LHLD        CO_FCB
        CALL        PUT
        LXI         D,press_cr_str
        CALL        PUT
        RC
        LXI         D,user_input_buffer
        LHLD        CI_FCB
        CALL        GET
        RC
        LDA         user_input_buffer
        CPI         CR
        JNZ         command_error
        ;
        ; Send start of transmission signal
        ;
        CALL        serial_tx_inline
        DB          STX
program_current_byte:
        ;
        ; Send BNPF byte-header and prepare for sending the bits of the byte
        ;
        CALL        serial_tx_inline
        DB          'B'
        MVI         B,8
        LHLD        current_data_ptr
        MOV         A,M
program_next_bit:
        ;
        ; Check next bit to select which character to send
        ;
        RLC
        JC          program_set_bit
        CALL        serial_tx_inline
        DB          'N'
bit_programmed:
        ;
        ; Advance to next bit in byte and check for end of byte
        ;
        DCR         B
        JNZ         program_next_bit
        ;
        ; Byte programmed, send BNPF byte-terminator
        ;
        CALL        serial_tx_inline
        DB          'F'
        ;
        ; Check if at end of data to send to programmer
        ;
        LHLD        current_data_ptr
        LXI         D,end_address
        LDAX        D
        CMP         L
        JNZ         program_next_byte
        INX         D
        LDAX        D
        CMP         H
        JNZ         program_next_byte
        ;
        ; All data sent, send end of transmission
        ;
        CALL        serial_tx_inline
        DB          ETX
        JMP         next_command_prompt

program_next_byte:
        ;
        ; Advance to next byte
        ;
        INX         H
        SHLD        current_data_ptr
        JMP         program_current_byte

program_set_bit:
        CALL        serial_tx_inline
        DB          'P'
        JMP         bit_programmed


;//////////////////////////////////////

cmd_clear_memory:
        ;
        ; Get start address of memory to clear and check deliminator
        ;
        CALL        get_next_char
        CALL        parse_hex_number
        JC          command_error
        CPI         ','
        JNZ         command_error
        INX         H
        XCHG
        SHLD        current_data_ptr
        XCHG
        ;
        ; Get end address and verify end of command arguments
        ;
        CALL        parse_hex_number
        JC          command_error
        CPI         CR
        JNZ         command_error
        ;
        ; Clear all data in specified memory block
        ;
        LHLD        current_data_ptr
clear_current_byte:
        MVI         M,000H
        MOV         A,H
        CMP         D
        JNZ         clear_next_byte
        MOV         A,L
        CMP         E
        JZ          next_command_prompt
clear_next_byte:
        INX         H
        JMP         clear_current_byte


;//////////////////////////////////////

cmd_receive_bnpf:
        ;
        ; Flush XMON UART receive buffer
        ;
        SUB         A
        STA         RCVBUF
        ;
        ; Get address of where to save received data
        ;
        CALL        get_next_char
        CALL        parse_hex_number
        JC          command_error
        CPI         CR
        JNZ         command_error
        ;
        ; Instruct user to start transfer on programming device
        ;
        PUSH        D
        LXI         D,start_transfer_str
        LHLD        CO_FCB
        CALL        PUT
        POP         D
        RC
        XCHG
        ;
        ; Wait for start of transmission control character
        ;
wait_for_rx_start:
        CALL        RCVI
        ANI         07FH
        CPI         ETX
        JZ          next_command_prompt
        CPI         STX
        JNZ         wait_for_rx_start
        ;
        ; Wait for header of BPNF byte package
        ;
wait_for_byte_start:
        CALL        RCVI
        ANI         07FH
        CPI         ETX
        JZ          next_command_prompt
        CPI         'B'
        JNZ         wait_for_byte_start
        ;
        ; Prepare bitmask and initial byte value
        ;
        MVI         B,080H
        MVI         C,000H
        ;
        ; Receive all bits in byte
        ;
receive_next_bit:
        CALL        RCVI
        ANI         07FH
        CPI         ETX
        JZ          next_command_prompt
        CPI         'E'
        JZ          wait_for_byte_start
        CPI         'P'
        JZ          receive_set_bit
        CPI         'N'
        JNZ         receive_next_bit
bit_received:
        ;
        ; Advance bitmap to next position and check if byte is complete
        ;
        MOV         A,B
        RRC
        ANI         07FH
        MOV         B,A
        JNZ         receive_next_bit
        ;
        ; Store complete byte in memory and advance pointer
        ;
        MOV         M,C
        INX         H
        ;
        ; Wait for BPNF byte terminating character
        ;
        CALL        RCVI
        ANI         07FH
        CPI         'F'
        JZ          wait_for_byte_start
        CPI         ETX
        JZ          next_command_prompt
        JMP         wait_for_byte_start

receive_set_bit:
        ;
        ; Add bitmask to byte value
        ;
        MOV         A,C
        ORA         B
        MOV         C,A
        JMP         bit_received


;//////////////////////////////////////

cmd_write_to_file:
        ;
        ; Get filename and verify next deliminer
        ;
        CALL        get_input_filename
        JC          command_error
        CPI         ','
        JNZ         command_error
        ;
        ; Copy filename to output file FCB
        ;
        PUSH        H
        LXI         D,input_file_fcb + FCB_DRVNR
        LXI         H,output_file_fcb + FCB_DRVNR
        MVI         B,FCB_DRVFMT - FCB_DRVNR
copy_next_filename_char:
        LDAX        D
        MOV         M,A
        INX         D
        INX         H
        DCR         B
        JNZ         copy_next_filename_char
        POP         H
        ;
        ; Get start address and verify next deliminer
        ;
        CALL        parse_hex_number
        JC          command_error
        CPI         ','
        JNZ         command_error
        INX         H
        XCHG
        SHLD        file_loaded_addr_offset
        XCHG
        ;
        ; Get data length and verify no more arguments
        ;
        CALL        parse_hex_number
        JC          command_error
        CPI         CR
        JNZ         command_error
        ;
        ; Set up output file FCB buffer
        ;
        LXI         H,output_file_fcb + FCB_MODE
        MVI         M,FM_BINARY
        INX         H
        SUB         A
        MOV         M,A             ; output_file_fcb + FCB_BUFIDX
        INX         H
        MOV         M,A
        INX         H
        MVI         M,128           ; output_file_fcb + FCB_BUFLEN
        INX         H
        MOV         M,A
        ;
        ; Open output file for writing
        ;
        LXI         H,output_file_fcb
        MVI         A,FM_OUTPUT
        CALL        OPEN
        RC
        ;
        ; Get back file data address
        ;
        LHLD        file_loaded_addr_offset
        MOV         B,H
        MOV         C,L
        ;
        ; Write data as a block with stored load-address of zero
        ;
        LXI         H,output_file_fcb
        MOV         A,E
        CALL        OUTCHAR
        RC
        MOV         A,D
        CALL        OUTCHAR
        RC
        SUB         A
        CALL        OUTCHAR
        RC
        SUB         A
        CALL        OUTCHAR
        RC
        ;
        ; Write all data of chunk to file
        ;
write_next_byte:
        LDAX        B
        CALL        OUTCHAR
        RC
        INX         B
        DCX         D
        MOV         A,D
        ORA         E
        JNZ         write_next_byte
        ;
        ; Data is written, now finish file off with an entrypoint of 0000H
        ;
        MVI         C,4
write_next_entrypoint_byte:
        SUB         A
        CALL        OUTCHAR
        RC
        DCR         C
        JNZ         write_next_entrypoint_byte
        ;
        ; Close output file
        ;
        LXI         H,output_file_fcb
        CALL        CLOSE
        RC
        JMP         next_command_prompt


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Start of free memory
;//
;//////////////////////////////////////////////////////////////////////////////

unused_program_memory:


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

command_error_str:
        DB          ' COMMAND ERROR',CR
program_prompt_str:
        DB          ' SET UP FOR LOAD I/O EXECUTE',CR
press_cr_str:
        DB          ' PRESS CR',CR
eof_error_str:
        DB          ' UNEXPECTED END-OF-FILE',CR
start_transfer_str:
        DB          ' SET UP FOR PROGRAM I/O EXECUTE',CR
load_out_of_range_str:
        DB          ' LOAD AREA OUT OF RANGE',CR
