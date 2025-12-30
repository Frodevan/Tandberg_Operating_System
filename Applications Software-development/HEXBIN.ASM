;//////////////////////////////////////////////////////////////////////////////
;//
;//     HEXBIN - Convert Intel HEX file to Intel Absolute Binary format
;//
;//         Extra parameters:
;//
;//             [$<addr>]
;//
;//                 addr        Entry point of binary, default: 01-record address
;//
;//
;//         Converts a file of standard Intel HEX file format to Intel Absolute
;//         Binary format. This format is the same format used by TOS executables,
;//         so if a TOS program is converted from HEX to Binary the generated file
;//         will be the final runnable program.
;//
;//         This program will use SI as the input Intel HEX-format file, and write
;//         the binary output to SO. When the input file is loaded, a copy will be
;//         sent to the SL file if it has been assigned to anything.
;//
;//         NOTE: Only HEX-80 (record types 00 and 01) are supported.
;//
;//         NOTE: Hex-file data record checksums are not verified by this program,
;//               they are rather entirely ignored.
;//
;//         NOTE: This program has a max block-size of 4KB. If a HEX file contains
;//               blocks of data larger than this, those blocks will be split into
;//               several logical blocks in the final binary file format. This
;//               should not impact loading the file in TOS or Intel ISIS, but is
;//               worth noting if a generated binary file is used to manually
;//               reconstruct a memory-image later.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//
;//             1.6: Entry at 0xC061
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
CR          EQU     00DH        ; Cartridge Return

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature

;
; TOS system calls
;
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTBIN      EQU     0FD1BH      ; Output a given number of raw bytes
EDHB        EQU     0FD30H      ; Convert 2-character ASCII hexadecimal to byte
EDHW        EQU     0FD33H      ; Convert 4-character ASCII hexadecimal to word

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer
SI_FCB      EQU     0FF04H      ; Standard input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer
SL_FCB      EQU     0FF08H      ; Standard line-printer output abstract file FCB pointer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'HEXBIN'
        DB          '106'


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

input_buffer:
        DS          80

hex_record_bytes:
        DB          0

binary_block_header:
binary_block_length:
        DW          0
binary_block_address:
        DW          00000H

hex_record_address:
        DW          00000H

data_length:
        DW          0
data_start_address:
        DW          0FFFFH
data_end_address:
        DW          00000H
data_index:
        DW          0

requested_start_address:
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

start:
beginning:
        ;
        ; Get all command line args into local buffer
        ;
        LHLD        CI_FCB
        LXI         D,input_buffer
        CALL        GET
        RC
        ;
        ; Parse custom program-entry address if specified in the args
        ;
        LXI         H,input_buffer
        MOV         A,M
        CPI         CR
        JZ          parse_next_hexfile_line
        CALL        EDHW
        JC          start_address_arg_error
        XCHG
        SHLD        requested_start_address


;//////////////////////////////////////

        ;
        ; Parse one line from the Intel HEX-file (allocated to SI file)
        ;
parse_next_hexfile_line:
        ;
        ; Get next Intel hex-file line
        ;
        LHLD        SI_FCB
        LXI         D,input_buffer
        CALL        GET
        RC
        ;
        ; Echo hex-file line to SL, if allocated
        ;
        LHLD        SL_FCB
        MOV         A,H
        ORA         L
        JZ          hex_file_echo_done
        LXI         D,input_buffer
        CALL        PUT
        RC
hex_file_echo_done:
        ;
        ; Look for colon at start of hex record
        ;
        LXI         B,input_buffer
        LDAX        B
        INX         B
        CPI         CR
        JZ          parse_next_hexfile_line
        CPI         ':'
        JZ          parse_hex_record_type
scan_for_hex_record_start:
        LDAX        B
        INX         B
        CPI         ':'
        JZ          parse_hex_record_type
        CPI         CR
        JZ          parse_next_hexfile_line
        JMP         scan_for_hex_record_start
parse_hex_record_type:
        ;
        ; Get hex-record length
        ;
        PUSH        B
        POP         H
        CALL        EDHB
        RC
        STA         hex_record_bytes
        ;
        ; Get hex-record address
        ;
        CALL        EDHW
        RC
        XCHG
        SHLD        hex_record_address
        ;
        ; Get and verify hex-record type
        ;
        XCHG
        CALL        EDHB
        RC
        CPI         1
        JZ          hex_record_type_one
        CPI         0
        JZ          hex_record_type_zero
        LXI         D,record_type_err_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

hex_record_type_zero:
        XCHG
        ;
        ; Check if data start address has been set
        ;
        LHLD        data_start_address
        MOV         A,H
        ANA         L
        CPI         0FFH
        JNZ         verify_hex_record_address
        ;
        ; Set data start address if not set
        ;
        LHLD        hex_record_address
        SHLD        data_start_address
        JMP         parse_hex_record_data

verify_hex_record_address:
        ;
        ; Check if record is consecutive from previous record
        ;
        LHLD        hex_record_address
        MOV         A,H
        MOV         C,L
        LHLD        data_end_address
        CMP         H
        JNZ         start_new_data_block
        MOV         A,C
        CMP         L
        JNZ         start_new_data_block
        ;
        ; Parse data from hext record into databuffer
        ;
parse_hex_record_data:
        ;
        ; Subtract start address from hex record address to get index
        ;
        LHLD        data_start_address
        MOV         A,H
        XRI         0FFH
        MOV         B,A
        MOV         A,L
        XRI         0FFH
        MOV         C,A
        LHLD        hex_record_address
        DAD         B
        INX         H
parse_next_hex_byte:
        SHLD        data_index
        ;
        ; Check if 4KB data buffer is full
        ;
        MOV         A,H
        CPI         010H
        JNC         start_new_data_block
        ;
        ; Convert next byte from hex record to binary
        ;
        XCHG
        CALL        EDHB
        RC
        XCHG
        ;
        ; Store byte in data-buffer and advance to next byte in record
        ;
        LXI         B,data_buffer
        LHLD        data_index
        DAD         B
        MOV         M,A
        LHLD        hex_record_address
        INX         H
        SHLD        hex_record_address
        ;
        ; Update end address if new byte is beyond the current data block
        ;
        PUSH        D
        XCHG
        LHLD        data_end_address
        MOV         A,D
        CMP         H
        JC          end_address_changes_done
        JNZ         update_end_address
        MOV         A,E
        CMP         L
        JC          end_address_changes_done
update_end_address:
        XCHG
        SHLD        data_end_address
end_address_changes_done:
        POP         D
        ;
        ; Check if the hex record is empty
        ;
        LDA         hex_record_bytes
        DCR         A
        STA         hex_record_bytes
        JZ          parse_next_hexfile_line
        ;
        ; Still data in record, advance to the next byte in data buffer
        ;
        LHLD        data_index
        INX         H
        JMP         parse_next_hex_byte

start_new_data_block:
        ;
        ; Write data block to file and reset buffers
        ;
        CALL        write_binary_block
        RC
        LHLD        hex_record_address
        SHLD        data_start_address
        SHLD        data_end_address
        LXI         H,0
        JMP         parse_next_hex_byte


;//////////////////////////////////////

hex_record_type_one:
        ;
        ; Write any remaining data from buffer
        ;
        CALL        write_binary_block
        RC
        ;
        ; Prepare default entry-point header
        ;
        LXI         H,0
        SHLD        binary_block_length
        LHLD        hex_record_address
        SHLD        binary_block_address
        ;
        ; Update header if custom address has been requested
        ;
        LHLD        requested_start_address
        MOV         A,H
        ORA         L
        JZ          entrypoint_address_set
        SHLD        binary_block_address
entrypoint_address_set:
        ;
        ; Write entry-point header to file and quit program
        ;
        LHLD        SO_FCB
        LXI         D,binary_block_header
        MVI         B,4
        CALL        PUTBIN
        RET


;//////////////////////////////////////

write_binary_block:
        PUSH        D
        ;
        ; Set load address of block
        ;
        LHLD        data_start_address
        SHLD        binary_block_address
        ;
        ; Subtract end address from start address to get block length
        ;
        MOV         A,H
        XRI         0FFH
        MOV         B,A
        MOV         A,L
        XRI         0FFH
        MOV         C,A
        LHLD        data_end_address
        DAD         B
        INX         H
        SHLD        data_length
        SHLD        binary_block_length
        ;
        ; Write binary block header to file
        ;
        LHLD        SO_FCB
        LXI         D,binary_block_header
        MVI         B,4
        CALL        PUTBIN
        JC          write_binary_end
        ;
        ; Prepare to write binary block data to file
        ;
        LXI         D,data_buffer
write_next_data_chunk:
        ;
        ; Check if there's more than 256 bytes left to write
        ;
        LDA         data_length+1
        CPI         0
        JZ          last_two_data_chunks
        ;
        ; Write full 128-byte data chunk to binary file
        ;
        LHLD        data_length
        LXI         B,-128
        DAD         B
        SHLD        data_length
write_full_data_chunk:
        LHLD        SO_FCB
        MVI         B,128
        CALL        PUTBIN
        JC          write_binary_end
        JMP         write_next_data_chunk

last_two_data_chunks:
        ;
        ; Check if we are within last chunk of data
        ;
        LDA         data_length
        ANI         080H
        JZ          write_last_data_chunk
        ;
        ; Second-last chunk, so we have one more full 128-byte chunk to write
        ;
        LDA         data_length
        ANI         07FH
        STA         data_length
        JMP         write_full_data_chunk

write_last_data_chunk:
        ;
        ; Check if last chunk is empty, don't write anything if so
        ;
        LDA         data_length
        CPI         0
        JZ          write_binary_complete
        ;
        ; Write last (variable-size) data-chunk to binary file
        ;
        MOV         B,A
        LHLD        SO_FCB
        CALL        PUTBIN
        JC          write_binary_end
write_binary_complete:
        ANA         A
write_binary_end:
        POP         D
        RET


;//////////////////////////////////////

start_address_arg_error:
        LHLD        CO_FCB
        LXI         D,start_address_err_str
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data buffer
;//
;//////////////////////////////////////////////////////////////////////////////

data_buffer:
        DS          4096


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

record_type_err_str:
        DB          'RECORD TYPE ERROR',CR
start_address_err_str:
        DB          'START ADDRESS ERROR',CR
