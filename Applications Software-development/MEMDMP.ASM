;//////////////////////////////////////////////////////////////////////////////
;//
;//     MEMDMP - Dump memory-blocks to Intel Absolute Binary format
;//
;//         Extra parameters:
;//
;//             [$<start>,<length>]
;//
;//                 start       Start address in hexadecimal
;//                 length      Length of memory block in hexadecimal
;//
;//
;//         Dumps blocks of memory to file in Intel Absolute Binary format. This
;//         file can later be loaded or run as a program through TOS. If input is
;//         not specified as extra parameters, it will be prompted for during
;//         runtime. The output file is specified by the SO assignement.
;//
;//
;//         Input:
;//
;//             <start>,<length>\n
;//
;//                 start       Start address in hexadecimal
;//                 length      Length of memory block in hexadecimal
;//
;//
;//         NOTE: The program does not distinguish between comma or space when
;//               parsing through input. These can be used interchangingly.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0x2000
;//
;//                 -> First version I have
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; TOS system calls
;
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR
EDHW        EQU     0FD33H      ; Convert 4-character ASCII hexadecimal to word
PUTBIN      EQU     0FD1BH      ; Output a given number of raw bytes

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
SO_FCB      EQU     0FF06H      ; Standard output abstract file FCB pointer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02000H
start:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

cli_input_args_buffer:
        DS          80

binary_block_header:
mem_block_length:
        DW          0
mem_block_address:
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Get all command line arguments at once
        ;
        LXI         D,cli_input_args_buffer
        LHLD        CI_FCB
        CALL        GET
        RC
        ;
        ; Parse pointer to memory to dump
        ;
        LXI         H,cli_input_args_buffer
        CALL        EDHW
        RC
        XCHG
        SHLD        mem_block_address
        ;
        ; Parse length of memory to dump
        ;
        LXI         H,cli_input_args_buffer + 5
        CALL        EDHW
        RC
        XCHG
        SHLD        mem_block_length
        ;
        ; Write Intel absolute binary format block header to output file
        ;
        MVI         B,4
        LXI         D,binary_block_header
        LHLD        SO_FCB
        CALL        PUTBIN
        RC
        ;
        ; Dump a small part now, to ensure remaining length is divisible by 256
        ;
        LDA         mem_block_length
        MOV         B,A
        LHLD        mem_block_address
        XCHG
        LHLD        SO_FCB
        CPI         0
        JZ          dump_whole_pages
        CALL        PUTBIN
        RC
dump_whole_pages:
        LDA         mem_block_length + 1
dump_next_page:
        ;
        ; Check if there are any more 256-byte pages to dump
        ;
        CPI         000H
        JZ          dump_done
        ;
        ; Dump 256 bytes
        ;
        MVI         B,255
        CALL        PUTBIN
        RC
        LDAX        D
        INX         D
        CALL        OUTCHAR
        RC
        ;
        ; Advance to next page
        ;
        LDA         mem_block_length + 1
        DCR         A
        STA         mem_block_length + 1
        JMP         dump_next_page

dump_done:
        ;
        ; Write final entry-address header
        ;
        LXI         H,0
        SHLD        mem_block_length
        MVI         B,4
        LXI         D,binary_block_header
        LHLD        SO_FCB
        CALL        PUTBIN
        RET
