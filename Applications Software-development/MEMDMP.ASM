;//////////////////////////////////////////////////////////////////////////////
;//
;//     MEMDMP - Dump memory-blocks to Intel Absolute Binary format
;//
;//         Extra parameters:
;//
;//             [$<start>,<end>[,<entry>]]
;//
;//                 start       Start address in hexadecimal
;//                 end         End address (inclusive) in hexadecimal
;//                 entry       Entry-point for code execution
;//
;//
;//         Dumps blocks of memory to file in Intel Absolute Binary format. This
;//         file can later be loaded or run as a program through TOS. If input is
;//         not specified as extra parameters, it will be prompted for during
;//         runtime. The output file is specified by the SO assignement.
;//
;//         If an entry address is not provided as extra parameters, additional
;//         input will be prompted for by the program. The input for the last block
;//         to be dumped must contain the entry-point argument.
;//
;//
;//         Input:
;//
;//             <start>,<end>[\n<start>,<end>[\n<start>,<end>[...]]],<entry>\n
;//
;//                 start       Start address in hexadecimal
;//                 end         End address (inclusive) in hexadecimal
;//                 entry       Entry-point for code execution
;//
;//
;//         NOTE: Device-file SO is not verified to be set in advance, and should
;//               be set to a block-device file by the user (filesystem file). The
;//               program will check for settings that are unique to this type of
;//               file, to determine if data can be buffered in sectors before
;//               being written or not.
;//
;//               If a file on an Intel type floppy is set as SO, each sector will
;//               be verified after written. Should the verification of a sector
;//               fail, then the sector will be rewritten up to 20 times until the
;//               verification passes. The last sector of the file will be padded
;//               with zero-bytes.
;//
;//         NOTE: The program does not distinguish between comma or space when
;//               parsing through input. These can be used interchangingly.
;//
;//         NOTE: This version will use the XMON API directly for console output.
;//               These will not support reassignement of CO. However, later
;//               versions will use the TOS API and CO properly.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0x2000
;//
;//                 -> First version I have
;//
;//             1.5: Entry at 0x2000
;//
;//                 -> Checks CI and SO file type before starting
;//                 -> Rewrites most of the program to account for different types
;//                    of destination
;//                 -> Adds verification of data dumped to floppy disk
;//                 -> Adds support for multiple blocks to be dumped at once
;//                 -> Adds support for custom entry-point
;//                 -> Prints prompt if no command line arguments
;//                 -> Uses local algorithm for converting hexadecimal to binary,
;//                    instead of TOS API call. This local implementation supports
;//                    lowercase input.
;//
;//             1.6: Entry at 0x2000
;//
;//                 -> Version ID written to 0x2700
;//
;//             1.7: Entry at 0x2000
;//
;//                 -> Uses TOS device-files for text output, instead of XMON API
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
BEL         EQU     007H        ; Bell (short beep)
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
TTO         EQU     00043H      ; Console output
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUTBIN      EQU     0FD1BH      ; Output a given number of raw bytes

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer

;
; TOS File Control Block, block device variables
;
FCB_DEVTYP  EQU     010H        ; Block-device type
FCB_DRVNR   EQU     011H        ; Drive number
FCB_DRVFMT  EQU     01BH        ; Media format
FCB_LNKIDX  EQU     01FH        ; Floppy block-device linking block buffer index


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02000H
start:
        ;
        ; Save stack pointer, for breaking out of program from subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        stack_pointer_backup
        ;
        ; Assume SO is a block-device, check device type and format
        ;
        LHLD        SO_FCB
        LXI         D,FCB_DEVTYP
        DAD         D
        MOV         B,M
        LXI         D,FCB_DRVFMT - FCB_DEVTYP
        DAD         D
        MOV         A,M
        ADD         B
        SUI         1
        STA         output_not_intel_floppy_flag
        ;
        ; Set up data-buffer to fill up when first sector is written to disk
        ;
        MVI         A,0
        STA         data_buffer_index
        MVI         A,129
        STA         data_buffer_size
        LXI         H,data_buffer
        SHLD        data_buffer_ptr
        ;
        ; Check CI device type
        ;
        LHLD        CI_FCB
        MOV         A,M
        CPI         4
        JNZ         user_input_prompt
        ;
        ; If type is buffered input, then peek at the pending character
        ;
        INX         H
        INX         H
        MOV         E,M             ; CI_FCB + FCB_BUFIDX
        INX         H
        MOV         D,M
        PUSH        D
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; CI_FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        POP         H
        DAD         D
        MOV         A,M
        ;
        ; Skip printing user prompt if command line arguments are provided
        ;
        CPI         LF
        JNZ         parse_prompt_input


;//////////////////////////////////////

        ;
        ; Prompt for block to dump
        ;
user_input_prompt:
        LXI         H,user_prompt_str
new_prompt_attempt:
        CALL        print_str
parse_prompt_input:
        ;
        ; Get whole input line in one go
        ;
        LXI         D,input_str
        LHLD        CI_FCB
        CALL        GET
        RC
        ;
        ; Get start address of next memory block and verify deliminer
        ;
        LXI         D,input_str
        CALL        ascii_hex_to_bin
        JC          invalid_input
        SHLD        mem_block_start_address
        CPI         ','
        JNZ         invalid_input
        ;
        ; Get end address of next memory block
        ;
        CALL        ascii_hex_to_bin
        SHLD        mem_block_end_address
        STA         final_block_flag
        ;
        ; Check if the entry-point is given, indicating the last block to dump
        ;
        CPI         CR
        JZ          verify_input
        CPI         ','
        JNZ         invalid_input
        ;
        ; Get entry-point address
        ;
        CALL        ascii_hex_to_bin
        JC          invalid_input
        SHLD        entry_point_address
        CPI         CR
        JZ          verify_input
invalid_input:
        LXI         H,invalid_input_str
        JMP         new_prompt_attempt

verify_input:
        ;
        ; Make sure block end address is after starting address
        ;
        LHLD        mem_block_end_address
        XCHG
        LHLD        mem_block_start_address
        MOV         A,H
        CMP         D
        JC          dump_mem_block
        JNZ         invalid_input
        MOV         A,E
        CMP         L
        JC          invalid_input


;//////////////////////////////////////

        ;
        ; Dump one memory block to file
        ;
dump_mem_block:
        ;
        ; Subtract start address from end address to get length
        ;
        MOV         A,H
        CMA
        MOV         H,A
        MOV         A,L
        CMA
        MOV         L,A
        DAD         D
        INX         H
        ;
        ; Add one since end address is inclusive
        ;
        INX         H
        ;
        ; Write length to file, as a part of a block header
        ;
        MOV         A,L
        CALL        write_byte
        MOV         A,H
        CALL        write_byte
        ;
        ; Write block address to file, as a part of a block header
        ;
        LDA         mem_block_start_address
        CALL        write_byte
        LDA         mem_block_start_address + 1
        CALL        write_byte
        ;
        ; Prepare to dump the data in the memory block
        ;
        LHLD        mem_block_end_address
        XCHG
        LHLD        mem_block_start_address
        ;
        ; Dump memory to file until HL pointer is at end address
        ;
dump_one_byte:
        MOV         A,M
        CALL        write_byte
        MOV         A,D
        CMP         H
        JNZ         dump_next_byte
        MOV         A,E
        CMP         L
        JZ          mem_block_dump_done
dump_next_byte:
        INX         H
        JMP         dump_one_byte

mem_block_dump_done:
        ;
        ; Check if this is the final block in the dump, or if there's more
        ;
        LDA         final_block_flag
        CPI         CR
        JZ          user_input_prompt
        ;
        ; Write final entry-address header
        ;
        MVI         A,000H
        CALL        write_byte
        CALL        write_byte
        LDA         entry_point_address
        CALL        write_byte
        LDA         entry_point_address + 1
        CALL        write_byte
        ;
        ; Check if the dump is being written to media with a non-intel format
        ;
        LDA         output_not_intel_floppy_flag
        ORA         A
        JNZ         break_quit_program
        ;
        ; Pad out dump file with additional zeroes to force through a write
        ;
        MVI         A,000H
        MVI         D,127
pad_dump_file_loop:
        CALL        write_byte
        DCR         D
        JNZ         pad_dump_file_loop
        ORA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Break out of program from anywhere
        ;
break_quit_program:
        LHLD        stack_pointer_backup
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print string pointed to by HL
        ;
print_str:
        MOV         A,M
        ANA         A
        RZ
        PUSH        H
        LHLD        CO_FCB
        CALL        OUTCHAR
        JC          break_quit_program
        POP         H
        INX         H
        JMP         print_str


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII hexadecimal string pointed to by DE to binary in HL
        ;
ascii_hex_to_bin:
        LXI         H,0
scan_for_hex_nr:
        LDAX        D
        INX         D
        CPI         ' '
        JZ          scan_for_hex_nr
        CPI         ','
        JZ          scan_for_hex_nr
        JMP         parse_hex_char


;//////////////////////////////////////

parse_next_hex_char:
        ;
        ; Advance to next character, and check for possible deliminator
        ;
        LDAX        D
        INX         D
        CPI         ','
        RZ
parse_hex_char:
        ;
        ; Check for end of hex number
        ;
        CPI         CR
        RZ
        ;
        ; Treat space as deliminator between numbers
        ;
        CPI         ' '
        JNZ         verify_hex_char
        MVI         A,','
        RET

verify_hex_char:
        ;
        ; Check for char within hex range
        ;
        CPI         '0'
        RC
        CPI         '9'+1
        JC          numeric_to_bin
        CPI         'A'
        RC
        CPI         'F'+1
        JC          hex_alpha_adjust
        CPI         'a'
        RC
        CPI         'f'+1
        JC          hex_alpha_case_adjust
        STC
        RET

        ;
        ; Convert hex digit to binary
        ;
hex_alpha_case_adjust:
        SUI         'a' - 'A'
hex_alpha_adjust:
        SUI         'A' - ('9'+1)
numeric_to_bin:
        SUI         '0'
        ;
        ; Shift converted digit into binary result
        ;
        DAD         H
        DAD         H
        DAD         H
        DAD         H
        ADD         L
        MOV         L,A
        JMP         parse_next_hex_char


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write byte in A to output file in SO
        ;
write_byte:
        ;
        ; Check if we're writing to a file on an intel floppy or not
        ;
        PUSH        H
        PUSH        PSW
        LDA         output_not_intel_floppy_flag
        ORA         A
        JNZ         write_byte_directly
        POP         PSW
        ;
        ; If writing to a file on an Intel disk, add it to local buffer instead
        ;
        PUSH        PSW
        PUSH        D
        LHLD        data_buffer_index
        XCHG
        LXI         H,data_buffer
        MVI         D,000H
        DAD         D
        MOV         M,A
        ;
        ; Advance to next position of buffer
        ;
        MOV         A,E
        INR         A
        CPI         129
        JZ          data_buffer_full
write_byte_to_floppy_done:
        STA         data_buffer_index
        POP         D
        POP         PSW
        POP         H
        RET


;//////////////////////////////////////

        ;
        ; Write data-buffer to file on Intel floppy, with verify
        ;
data_buffer_full:
        ;
        ; Write entire buffer to file all at once
        ;
        LDA         data_buffer_size
        MOV         B,A
        LHLD        data_buffer_ptr
        XCHG
        LHLD        SO_FCB
        CALL        PUTBIN
        JC          break_quit_program
        MVI         A,0
        STA         verification_failure_counter
verify_written_sector:
        ;
        ; Get drive number
        ;
        LHLD        SO_FCB
        LXI         D,FCB_DRVNR
        DAD         D
        MOV         A,M
        STA         drive_number
        ;
        ; Get pointer to current entry in linking block buffer
        ;
        LXI         D,FCB_LNKIDX - FCB_DRVNR
        DAD         D
        MOV         A,M
        INX         H
        MOV         E,M             ; SO_FCB + FCB_LNKPTR
        INX         H
        MOV         D,M
        MOV         L,A
        MVI         H,000H
        DAD         D
        ;
        ; Get track number and sector number of previous sector written
        ;
        DCX         H
        MOV         A,M
        STA         track_number
        MOV         B,A
        DCX         H
        MOV         A,M
        STA         sector_number
        MOV         C,A
        ;
        ; Read back most recent sector written to output file
        ;
        LDA         drive_number
        LXI         H,readback_data_buffer
        CALL        DSRDW
        JC          break_quit_program
        ;
        ; Verify that written data equals read sector
        ;
        LXI         H,data_buffer
        LXI         D,readback_data_buffer
        MVI         B,128
verify_next_byte:
        LDAX        D
        CMP         M
        JNZ         verification_failed
        INX         H
        INX         D
        DCR         B
        JNZ         verify_next_byte
        ;
        ; Reset buffer, making sure to reserve first byte as read-only
        ;
        MVI         A,128
        STA         data_buffer_size
        LXI         H,data_buffer + 1
        SHLD        data_buffer_ptr
        ;
        ; Move last byte written to reserved index, for verification later
        ;
        LDA         data_buffer + 128
        STA         data_buffer
        MVI         A,1
        JMP         write_byte_to_floppy_done

verification_failed:
        ;
        ; Check if there are any remaining retries
        ;
        LDA         verification_failure_counter
        CPI         20
        JNZ         rewrite_sector
        STC
        JMP         break_quit_program

rewrite_sector:
        ;
        ; Advance retry counter
        ;
        INR         A
        STA         verification_failure_counter
        ;
        ; Write the sector to disk again
        ;
        LDA         track_number
        MOV         B,A
        LDA         sector_number
        MOV         C,A
        LDA         drive_number
        LXI         H,data_buffer
        CALL        DSWRW
        JC          break_quit_program
        JMP         verify_written_sector


;//////////////////////////////////////

        ;
        ; Use TOS API to write byte now, without any verification
        ;
write_byte_directly:
        POP         PSW
        LHLD        SO_FCB
        CALL        OUTCHAR
        JC          break_quit_program
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

invalid_input_str:
        DB          '?',BEL,CR,LF
user_prompt_str:
        DB          '>',NULL

data_buffer_size:
        DS          1
data_buffer_ptr:
        DS          2
final_block_flag:
        DS          1
data_buffer_index:
        DS          1

output_not_intel_floppy_flag:
        DS          1
verification_failure_counter:
        DS          1
drive_number:
        DS          1
track_number:
        DS          1
sector_number:
        DS          1

stack_pointer_backup:
        DS          2
mem_block_start_address:
        DS          2
mem_block_end_address:
        DS          2
entry_point_address:
        DS          2

input_str:
        DS          80
readback_data_buffer:
        DS          128
data_buffer:
        DS          129


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'MEMDMP'
        DB          '107'
