;//////////////////////////////////////////////////////////////////////////////
;//
;//     TPGEN - Copy all files from floppy to tape
;//
;//         Extra parameters:
;//
;//             [$Y]
;//
;//                 Y       Immediately start the transfer
;//
;//
;//         Copy every single file from floppy disk :F0: to tape :M0:, using TOS
;//         system-calls to do the binary transfers. If a file already exsists on
;//         a tape cartridge, the copying of that file is skipped.
;//
;//         Files with the format attribute will not be included in the copy.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where aliases will be copied as normal files
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
CR          EQU     00DH        ; Cartridge Return

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
GETBIN      EQU     0FD18H      ; Input a given number of raw bytes
OPEN        EQU     0FD1EH      ; Open block device
READ        EQU     0FD21H      ; Read from block device
WRITE       EQU     0FD24H      ; Write to block device
CLOSE       EQU     0FD27H      ; Close block device

;
; TOS constants
;
TABTC_PTR   EQU     0FDE6H      ; Pointer to Tandberg tape cartridge device driver
TABIN_PTR   EQU     0FDEAH      ; Pointer to Intel floppy disk device driver

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_3C    EQU     03CH        ; OUTPUT FILE ALREADY ON CARTR.

;
; TOS file attributes
;
ATTR_F      EQU     080H        ; Format file

;
; TOS File Control Block, block device variables
;
FCB_MODE    EQU     001H        ; File mode
FCB_BUFIDX  EQU     002H        ; Block/buffered-device data buffer index
FCB_BUFLEN  EQU     004H        ; Length of block/buffered-device data buffer
FCB_READ    EQU     008H        ; Device-driver Read API call
FCB_WRITE   EQU     00AH        ; Device-driver Write API call
FCB_OPEN    EQU     00CH        ; Device-driver Open API call
FCB_CLOSE   EQU     00EH        ; Device-driver Close API call
FCB_FNAME   EQU     012H        ; Filename string

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag
FM_OUTPUT   EQU     002H        ; File open for writing flag
FM_BINARY   EQU     004H        ; Binary flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

directory_file_fcb:
        DB          5
        DB          FM_BINARY
        DW          0
        DW          128
        DW          dir_file_buffer
        DS          2
        DW          00000H
        DS          2
        DS          2
        DB          0
        DB          0
        DB          'ISIS',NULL,NULL
        DB          'DIR'
        DB          001H
        DS          2
        DS          1
        DS          1
        DW          dir_file_linking_block_buffer

dir_file_buffer:
        DS          128
dir_file_linking_block_buffer:
        DS          128


;//////////////////////////////////////

input_file_fcb:
        DB          5
        DB          FM_BINARY
        DW          0
        DW          128
        DW          file_transfer_data_buffer
        DS          2
        DW          00000H
        DS          2
        DS          2
        DB          0
        DB          0
        DS          9
        DB          001H
        DS          2
        DS          1
        DS          1
        DW          in_file_linking_block_buffer

in_file_linking_block_buffer:
        DS          128


;//////////////////////////////////////

output_file_fcb:
        DB          5
        DB          FM_BINARY
        DW          0
        DW          128
        DW          file_transfer_data_buffer
        DW          00000H
        DS          2
        DS          2
        DS          2
        DB          1
        DB          0
        DS          9
        DB          001H
        DW          out_file_overrun_word
        DS          1
        DS          2
        DS          1
        DS          1
        DS          1
        DS          15

file_transfer_data_buffer:
        DS          128
out_file_overrun_word:
        DS          2


;//////////////////////////////////////

flush_outlet:
        DS          16

welcome_prompt_str:
        DB          'DATASET COPY FROM DISKETTE 0 TO CARTRIDGE 0 - TYPE Y TO START',CR
not_copied_str:
        DB          ' NOT'
copied_ok_str:
        DB          ' COPIED',CR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

beginning:
        ;
        ; Print welcome prompt and check response
        ;
        LXI         D,welcome_prompt_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         'Y'
        JZ          start_copying
        ANA         A
        RET

start_copying:
        ;
        ; Assign Intel Floppy device driver to input files
        ;
        LHLD        TABIN_PTR
        SHLD        directory_file_fcb + FCB_OPEN
        SHLD        input_file_fcb + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        directory_file_fcb + FCB_READ
        SHLD        input_file_fcb + FCB_READ
        DAD         D
        SHLD        directory_file_fcb + FCB_CLOSE
        SHLD        input_file_fcb + FCB_CLOSE
        ;
        ; Assign Tape Cartridge device driver to output file
        ;
        LHLD        TABTC_PTR
        LXI         B,003H
        DAD         B
        SHLD        output_file_fcb + FCB_OPEN
        DAD         D
        SHLD        output_file_fcb + FCB_WRITE
        DAD         D
        SHLD        output_file_fcb + FCB_CLOSE
        ;
        ; Open directory file for reading
        ;
        LXI         H,directory_file_fcb
        MVI         A,FM_INPUT
        CALL        OPEN
        RC
        ;
        ; Check each file entry of directory and copy all files found
        ;
check_next_file:
        LXI         H,directory_file_fcb
        CALL        INCHAR
        JC          copying_done
        ANA         A
        JZ          file_found
        LXI         H,directory_file_fcb
        MVI         B,15
        LXI         D,flush_outlet
        CALL        GETBIN
        RC
        JMP         check_next_file

file_found:
        ;
        ; Get filename from directory and put into input file FCB
        ;
        LXI         H,directory_file_fcb
        MVI         B,9
        LXI         D,input_file_fcb + FCB_FNAME
        CALL        GETBIN
        RC
        ;
        ; Check attributes of file, and don't copy if format file
        ;
        CALL        INCHAR
        RC
        ANI         ATTR_F
        JZ          copy_file
        LXI         D,flush_outlet
        MVI         B,5
        CALL        GETBIN
        RC
        JMP         check_next_file

copy_file:
        ;
        ; Flush remainder of file entry
        ;
        LXI         D,flush_outlet
        MVI         B,5
        CALL        GETBIN
        RC
        ;
        ; Reset FCB of input and output files
        ;
        LXI         H,128
        SHLD        input_file_fcb + FCB_BUFLEN
        SHLD        output_file_fcb + FCB_BUFLEN
        ;
        ; Open input file for reading
        ;
        LXI         H,input_file_fcb
        MVI         A,FM_INPUT
        CALL        OPEN
        RC
        ;
        ; Print filename of input file
        ;
        LXI         D,input_file_fcb + FCB_FNAME
        LHLD        CO_FCB
        MVI         B,6
print_next_filename_char:
        LDAX        D
        ANA         A
        JNZ         filename_char_ready
        MVI         A,' '
filename_char_ready:
        CALL        OUTCHAR
        RC
        INX         D
        DCR         B
        JNZ         print_next_filename_char
        MVI         A,'.'
        CALL        OUTCHAR
        RC
        MVI         B,3
print_next_file_ext_char:
        LDAX        D
        ANA         A
        JNZ         file_ext_char_ready
        MVI         A,' '
file_ext_char_ready:
        CALL        OUTCHAR
        RC
        INX         D
        DCR         B
        JNZ         print_next_file_ext_char
        ;
        ; Copy filename from input file FCB to output file FCB
        ;
        LXI         D,input_file_fcb + FCB_FNAME
        LXI         H,output_file_fcb + FCB_FNAME
        MVI         B,9
copy_filename_loop:
        LDAX        D
        MOV         M,A
        INX         D
        INX         H
        DCR         B
        JNZ         copy_filename_loop
        ;
        ; Open output file for writing
        ;
        LXI         H,output_file_fcb
        MVI         A,FM_OUTPUT
        CALL        OPEN
        JNC         write_output_data
        CPI         ERROR_3C
        JZ          not_copied
        STC
        RET

not_copied:
        LXI         D,not_copied_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        JMP         file_done

read_input_data:
        ;
        ; Load more data from input file
        ;
        LXI         H,input_file_fcb
        CALL        READ
        JC          read_error
write_output_data:
        ;
        ; Set output file buffer to cover the current input file buffer
        ;
        LXI         H,input_file_fcb + FCB_BUFLEN
        MOV         E,M
        INX         H
        MOV         D,M
        LXI         H,output_file_fcb + FCB_BUFIDX
        MOV         M,E
        INX         H
        MOV         M,D
        INX         H
        MOV         M,E
        INX         H
        MOV         M,D
        ;
        ; Write the currently loaded input file data-buffer to output file
        ;
        LXI         H,output_file_fcb
        CALL        WRITE
        RC
        JMP         read_input_data

read_error:
        ;
        ; Check for end of file
        ;
        ANA         A
        JZ          end_of_file
        STC
        RET

end_of_file:
        ;
        ; Copy went ok, print status, close output file to update file-system
        ;
        LXI         D,copied_ok_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        LXI         H,output_file_fcb
        CALL        CLOSE
        RC
file_done:
        ;
        ; Close input file, reset output file in case it was not closed
        ;
        LXI         H,output_file_fcb + FCB_MODE
        MVI         M,FM_BINARY
        LXI         H,input_file_fcb
        CALL        CLOSE
        RC
        JMP         check_next_file

copying_done:
        ;
        ; No more files to copy, check if the directory file is at end of file
        ;
        ANA         A
        RZ
        STC
        RET
