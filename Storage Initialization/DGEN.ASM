;//////////////////////////////////////////////////////////////////////////////
;//
;//     DGEN - Copy all files from floppy to floppy
;//
;//         Extra parameters:
;//
;//             [$Y]
;//
;//                 Y       Immediately start the transfer
;//
;//
;//         Copy every single file from floppy disk :F0: to floppy :F1:, using TOS
;//         system-calls to do the binary transfers. If a file already exsists on
;//         the target floppy, the copying of that file is skipped.
;//
;//         Files with the format or direct-access attributes will not be included
;//         in the copy.
;//
;//         NOTE: Supports 54KB user-RAM. However, TOS v1.7 or more recent is
;//               required to run this version.
;//
;//         NOTE: Due to a bug, at least 48KB user-RAM is required to prevent a
;//               full system crash when copying large files.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First verifiable version I have
;//                 -> Has a bug where aliases will be copied as normal files
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> Accepts lower-case input to the prompt
;//                 -> Minor optimization in code after a file has been copied
;//
;//             1.6: Entry at 0xC2FD
;//
;//                 -> Version ID written to 0x2700
;//
;//             1.7: Entry at 0xCB83
;//
;//                 -> Gets free RAM from TOS to maximize data-buffer size, trying
;//                    to copy files whole instead of one sector at a time
;//                 -> Introduces a bug where the buffer size is calculated to be
;//                    the negative number of bytes free, not the positive
;//                 -> Flushes excess keypresses after the start-transfer prompt
;//                 -> Prints error if copy is prematurely aborted due to error
;//                 -> Stops at the very first non-deleted free file-entry
;//                 -> Optimizes printing of filenames
;//                 -> Ignonres files with the Direct-Access attribute set as well
;//                 -> Copies over any other attributes
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
; XMON system calls
;
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SIGNATURE   EQU     02700H      ; Program signature
TRK         EQU     02731H      ; Pointer to block address of next directory data block

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
GETBIN      EQU     0FD18H      ; Input a given number of raw bytes
OPEN        EQU     0FD1EH      ; Open block device
CLOSE       EQU     0FD27H      ; Close block device

;
; TOS constants
;
TABIN_PTR   EQU     0FDEAH      ; Pointer to Intel floppy disk device driver
RAMST       EQU     0FDFCH      ; Address to start of user-RAM

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_32    EQU     032H        ; OUTPUT FILE ALREADY ON DISKETTE

;
; TOS file attributes
;
ATTR_X      EQU     040H        ; Direct-access file
ATTR_F      EQU     080H        ; Format file

;
; TOS File Control Block, block device variables
;
FCB_MODE    EQU     001H        ; File mode
FCB_BUFLEN  EQU     004H        ; Length of block/buffered-device data buffer
FCB_READ    EQU     008H        ; Device-driver Read API call
FCB_WRITE   EQU     00AH        ; Device-driver Write API call
FCB_OPEN    EQU     00CH        ; Device-driver Open API call
FCB_CLOSE   EQU     00EH        ; Device-driver Close API call
FCB_FNAME   EQU     012H        ; Filename string
FCB_FEXT    EQU     FCB_FNAME+6 ; File extension string

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
        DB          'DGEN',NULL,NULL
        DB          '107'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Legacy program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C800H
program_origin:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

data_buffer_length:
        DW          0
data_buffer_free:
        DW          0
data_buffer_chars:
        DW          0
data_buffer_ptr:
        DW          00000H

end_of_file_flag:
        DB          FALSE
file_attributes:
        DB          000H

;//////////////////////////////////////

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
        DW          in_file_buffer
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

in_file_buffer:
        DS          128
in_file_linking_block_buffer:
        DS          128


;//////////////////////////////////////

output_file_fcb:
        DB          5
        DB          FM_BINARY
        DW          0
        DW          128
        DW          out_file_buffer
        DW          00000H
        DS          2
        DS          2
        DS          2
        DB          0
        DB          1
        DS          9
        DB          001H
        DS          2
        DS          1
        DS          1
        DW          out_file_linking_block_buffer

out_file_buffer:
        DS          128
out_file_linking_block_buffer:
        DS          128


;//////////////////////////////////////

flush_outlet:
        DS          16


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

start:
beginning:
        ;
        ; Set start of buffer to start of user-RAM
        ;
        LHLD        RAMST
        SHLD        data_buffer_ptr
        ;
        ; Subtract with program start and buffer start to get buffer length
        ;
        LXI         D,program_origin
        MOV         A,E
        CMA
        MOV         E,A
        MOV         A,D
        CMA
        MOV         D,A
        INX         D
        DAD         D
        SHLD        data_buffer_length
        ;
        ; Print welcome prompt and check response
        ;
        LXI         D,welcome_prompt_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         'Y'
        JZ          start_copying
        CPI         'y'
        JZ          start_copying
        ANA         A
        RET

start_copying:
        ;
        ; Clear any remaining input from console
        ;
flush_excess_input:
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         flush_excess_input
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
        ; Assign Intel Floppy device driver to output file
        ;
        LHLD        TABIN_PTR
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
        JC          operation_aborted
        ;
        ; Check each file entry of directory and copy all files found
        ;
check_next_file:
        LXI         H,directory_file_fcb
        CALL        INCHAR
        JC          copying_done
        ANA         A
        JZ          file_found
        CPI         07FH
        RZ
        LXI         H,directory_file_fcb
        MVI         B,15
        LXI         D,flush_outlet
        CALL        GETBIN
        JC          operation_aborted
        JMP         check_next_file

file_found:
        ;
        ; Get filename from directory and put into input file FCB
        ;
        LXI         H,directory_file_fcb
        MVI         B,9
        LXI         D,input_file_fcb + FCB_FNAME
        CALL        GETBIN
        JC          operation_aborted
        ;
        ; Check attributes of file, and skip if format or direct-access file
        ;
        CALL        INCHAR
        JC          operation_aborted
        STA         file_attributes
        ANI         ATTR_F + ATTR_X
        JZ          copy_file
        LXI         D,flush_outlet
        MVI         B,5
        CALL        GETBIN
        JC          operation_aborted
        JMP         check_next_file

copy_file:
        ;
        ; Flush remainder of file entry
        ;
        LXI         D,flush_outlet
        MVI         B,5
        CALL        GETBIN
        JC          operation_aborted
        ;
        ; Reset FCB of input and output files
        ;
        LXI         H,128
        SHLD        input_file_fcb + FCB_BUFLEN
        SHLD        output_file_fcb + FCB_BUFLEN
        MVI         A,FM_BINARY
        STA         input_file_fcb + FCB_MODE
        STA         output_file_fcb + FCB_MODE
        ;
        ; Open input file for reading
        ;
        LXI         H,input_file_fcb
        MVI         A,FM_INPUT
        CALL        OPEN
        JC          operation_aborted
        ;
        ; Print filename of input file
        ;
        LHLD        CO_FCB
        LXI         D,input_file_fcb + FCB_FNAME
        MVI         B,6
        CALL        print_filename_part
        RC
        MOV         C,B
        ;
        ; Check for filename extension, print it if so
        ;
        MVI         B,3
        INR         C
        LDA         input_file_fcb + FCB_FEXT
        ANA         A
        JZ          filename_printed
        DCR         C
        MVI         A,'.'
        CALL        OUTCHAR
        RC
        LXI         D,input_file_fcb + FCB_FEXT
        CALL        print_filename_part
        RC
        ;
        ; Pad out after filename with spaces
        ;
filename_printed:
        MOV         A,B
        ADD         C
        JZ          setup_file_copy
        MOV         B,A
pad_filename_print:
        MVI         A,' '
        CALL        OUTCHAR
        RC
        DCR         B
        JNZ         pad_filename_print
        JMP         setup_file_copy

        ;
        ; Print a string of a given length, or till first NULL
        ;
print_filename_part:
        LDAX        D
        ANA         A
        RZ
        CALL        OUTCHAR
        RC
        INX         D
        DCR         B
        JNZ         print_filename_part
        RET


;//////////////////////////////////////

setup_file_copy:
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
        JNC         read_from_source_file
        CPI         ERROR_32
        JZ          not_copied
        STC
        JMP         exit_with_error

not_copied:
        LXI         D,not_copied_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        JMP         file_done


;//////////////////////////////////////

read_from_source_file:
        ;
        ; Flush data-buffer
        ;
        LHLD        data_buffer_length
        SHLD        data_buffer_free
        LXI         H,0
        SHLD        data_buffer_chars
        ;
        ; Read from input file into data-buffer
        ;
        XRA         A
        STA         end_of_file_flag
        LHLD        data_buffer_ptr
        XCHG
read_next_source_byte:
        ;
        ; Read byte
        ;
        LXI         H,input_file_fcb
        CALL        INCHAR
        JC          read_error
        STAX        D
        INX         D
        ;
        ; Update data-buffer status and check if full
        ;
        LHLD        data_buffer_chars
        INX         H
        SHLD        data_buffer_chars
        LHLD        data_buffer_free
        DCX         H
        SHLD        data_buffer_free
        MOV         A,L
        ORA         H
        JNZ         read_next_source_byte
        JMP         write_to_file_copy

read_error:
        ;
        ; Make sure to also write the final data if only end of file
        ;
        ANA         A
        STC
        JNZ         exit_with_error
        MVI         A,TRUE
        STA         end_of_file_flag


;//////////////////////////////////////

write_to_file_copy:
        ;
        ; Check if the buffer is empty
        ;
        LHLD        data_buffer_chars
        MOV         A,L
        ORA         H
        JZ          finalize_copy
        ;
        ; Write data-buffer to output file
        ;
        LHLD        data_buffer_ptr
        XCHG
write_next_byte_to_copy:
        ;
        ; Write byte
        ;
        LXI         H,output_file_fcb
        LDAX        D
        INX         D
        CALL        OUTCHAR
        JC          exit_with_error
        ;
        ; Update data-buffer status and check if empty
        ;
        LHLD        data_buffer_chars
        DCX         H
        SHLD        data_buffer_chars
        MOV         A,L
        ORA         H
        JNZ         write_next_byte_to_copy
        LDA         end_of_file_flag
        ANA         A
        JZ          read_from_source_file


;//////////////////////////////////////

finalize_copy:
        ;
        ; Copy went ok, print status, close output file to update file-system
        ;
        LXI         D,copied_ok_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        LXI         H,output_file_fcb
        CALL        CLOSE
        JC          operation_aborted
        ;
        ; Look up file entry of copy
        ;
        LXI         H,output_file_fcb + FCB_FNAME
        MVI         A,1
        CALL        LOCDIR
        JC          operation_aborted
        ;
        ; Set file attributes to match source file
        ;
        LXI         D,00AH
        DAD         D
        LDA         file_attributes
        MOV         M,A
        ;
        ; Write changes back to disk
        ;
        LHLD        TRK
        DCX         H
        MOV         B,M
        DCX         H
        MOV         C,M
        MVI         A,1
        LXI         H,BUF2
        CALL        DSWRW
        JC          operation_aborted
file_done:
        ;
        ; Close input file
        ;
        LXI         H,input_file_fcb
        CALL        CLOSE
        JC          operation_aborted
        JMP         check_next_file

copying_done:
        ;
        ; No more files to copy, check if the directory file is at end of file
        ;
        ANA         A
        RZ
        STC
        JMP         operation_aborted


;//////////////////////////////////////

exit_with_error:
        PUSH        PSW
        LXI         D,newline_str
        LHLD        CO_FCB
        CALL        PUT
        JC          final_string_error
        POP         PSW
operation_aborted:
        PUSH        PSW
        LXI         D,operation_aborted_str
        LHLD        CO_FCB
        CALL        PUT
        JC          final_string_error
        POP         PSW
        RET

final_string_error:
        INX         SP
        INX         SP
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

welcome_prompt_str:
        DB          'DATASET COPY FROM DISKETTE 0 TO DISKETTE 1 - TYPE Y TO START ',CR
not_copied_str:
        DB          ' NOT'
copied_ok_str:
        DB          ' COPIED',CR
operation_aborted_str:
        DB          'OPERATION ABORTED',CR
newline_str:
        DB          CR
