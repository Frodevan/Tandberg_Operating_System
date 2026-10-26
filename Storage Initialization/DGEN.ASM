;//////////////////////////////////////////////////////////////////////////////
;//
;//     DGEN - Copy all files from floppy to floppy
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:[,:<Tn>:],][option]
;//
;//                 Tn          Drive type and number, default :D0:,:D1:
;//                 option      User option, default I
;//
;//                 Drive type T:
;//                     D       Floppy, TOS double-sided double-density
;//                     F       Floppy, TOS single-sided single-density
;//
;//                 Drive number n:
;//                     0-3
;//
;//                 Options:
;//                     S       Include system files in copy
;//
;//
;//         Copy every single file from source floppy disk to destination floppy,
;//         using TOS system-calls to do the binary transfers. If a file already
;//         exsists on the target floppy, the copying of that file is skipped.
;//
;//         Files with the format or direct-access attributes will not be included
;//         in the copy. System files will only be included if the S option is
;//         included.
;//
;//
;//         NOTE: This version relies on a preliminarty version of the TOS-II API,
;//               so copying from double-sided disks will only work on the Beta-
;//               version of TOS-II v2.0.
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
;//             2.0a: Entry at 0x301E
;//
;//                 -> Command-line options formalized, using source-destination
;//                    drive designators instead of hardcoded drive numbers
;//                 -> Double-sided drive type added
;//                 -> Has a bug that at least a source drive must be specified to
;//                    add the S option
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
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; XMON system calls
;
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
DDSWRW      EQU     0009AH      ; Write to double-sided disk with wait
DLOCDIR     EQU     000CDH      ; Look up filetable entry of filename on double-sided disk

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SIGNATURE   EQU     02700H      ; Program signature
SYSDRV_TYPE EQU     0270EH      ; Current system drive type
BUFLIM      EQU     0272EH      ; Lowest address of current TOS buffers
TRK         EQU     02731H      ; Pointer to block address of next directory data block

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
GETBIN      EQU     0FD18H      ; Input a given number of raw bytes
OPEN        EQU     0FD1EH      ; Open block device
CLOSE       EQU     0FD27H      ; Close block device
DNEXTFILE   EQU     0FDB8H      ; Get next file on double-sided disk

;
; TOS constants
;
TABTD_PTR   EQU     0FDE6H      ; Pointer to Tandberg double-sided floppy disk device driver
TABIN_PTR   EQU     0FDEAH      ; Pointer to Intel floppy disk device driver

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_26    EQU     026H        ; IMPROPER PARAMETER OR PARAMETER STRING

;
; TOS file attributes
;
ATTR_NONE   EQU     000H        ; Normal file
ATTR_I      EQU     001H        ; Invisible file
ATTR_S      EQU     002H        ; System file
ATTR_W      EQU     004H        ; Write-protected file
ATTR_X      EQU     040H        ; Direct-access file
ATTR_F      EQU     080H        ; Format file

;
; TOS-II file attributes byte 1
;
ATTR_S_DSDD EQU     004H        ; System file
ATTR_W_DSDD EQU     040H        ; Write-protected file
ATTR_X_DSDD EQU     080H        ; Direct-access file

;
; TOS-II file attributes byte 2
;
ATTR_I_DSDD EQU     001H        ; Invisible file

;
; TOS-II file attributes byte 3
;
ATTR_F_DSDD EQU     020H        ; Format file

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
FCB_DEVTYP  EQU     010H        ; Block-device type
FCB_DRVNR   EQU     011H        ; Drive number
FCB_FNAME   EQU     012H        ; Filename string
FCB_FEXT    EQU     FCB_FNAME+6 ; File extension string
FCB_DRVFMT  EQU     01BH        ; Media format

;
; FCB mode flags
;
FM_NONE     EQU     000H        ; No file mode set, typically closed file
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
        DB          '200'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02800H
input_char:
        DB          CR
source_drive_type:
        DB          'D'
target_drive_type:
        DB          'D'

data_buffer_ptr:
        DW          00000H
file_entry_ptr:
        DW          00000H
data_buffer_length:
        DW          0
data_buffer_free:
        DW          0
data_buffer_chars:
        DW          0

sp_backup:
        DW          00000H
end_of_file_flag:
        DB          FALSE
file_attributes:
        DB          000H, 000H, 000H
source_drive_nr:
        DB          0
target_drive_nr:
        DB          1
copy_system_flag:
        DB          FALSE

type_d_filename:
        DS          13
type_f_filename:
        DS          9

        DS          256
out_file_buffer:
        DS          256
in_file_buffer:
        DS          256
in_file_linking_block_buffer:
        DS          256
out_file_linking_block_buffer:
        DS          256
dir_file_buffer:
        DS          256
dir_file_linking_block_buffer:
        DS          256
flush_outlet:
        DS          128


;//////////////////////////////////////

directory_file_fcb:
        DB          5
        DB          FM_NONE
        DW          0
        DW          128
        DW          dir_file_buffer
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
        DB          000H
        DW          dir_file_linking_block_buffer


;//////////////////////////////////////

directory_iterator:
        DB          FALSE
        DB          0
        DW          dir_file_linking_block_buffer
        DW          dir_file_buffer
        DW          00000H
        DW          00000H
        DW          0*DISK_TRACK + 0*DISK_SECTOR


;//////////////////////////////////////

input_file_fcb:
        DB          5
        DB          FM_NONE
        DW          0
        DW          0
        DW          in_file_buffer
        DW          00000H
        DW          00000H
        DW          00000H
        DW          00000H
        DB          0
        DB          0
        DS          9
        DB          000H
        DW          00000H
        DB          0
        DB          000H
        DW          in_file_linking_block_buffer


;//////////////////////////////////////

output_file_fcb:
        DB          5
        DB          FM_NONE
        DW          0
        DW          0
        DW          out_file_buffer
        DW          00000H
        DW          00000H
        DW          00000H
        DW          00000H
        DB          0
        DB          0
        DS          9
        DB          001H
        DW          00000H
        DB          0
        DB          000H
        DW          out_file_linking_block_buffer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Initialization
;//
;//////////////////////////////////////////////////////////////////////////////

start:
        LXI         H,00000H
        DAD         SP
        SHLD        sp_backup
        ;
        ; Set start of buffer to start of available RAM
        ;
        LXI         H,program_end
        SHLD        data_buffer_ptr
        ;
        ; Subtract program end from TOS buffers start to get data buffer length
        ;
        MOV         A,L
        CMA
        MOV         E,A
        MOV         A,H
        CMA
        MOV         D,A
        INX         D
        LHLD        BUFLIM
        DAD         D
        SHLD        data_buffer_length
        ;
        ; Check default source drive type
        ;
        LDA         SYSDRV_TYPE
        ANA         A
        JM          default_drive_ready
        MVI         A,'F'
        STA         source_drive_type
default_drive_ready:
        ;
        ; Check if CLI input is a buffered line-based file
        ;
        LHLD        CI_FCB
        MOV         A,M
        CPI         4
        JNZ         args_parsed
        ;
        ; Verify that there are CLI data pending in file
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
        CPI         LF
        JZ          args_parsed
        ;
        ; Get input arguments
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         CR
        JZ          args_parsed

;//////////////////////////////////////

        ;
        ; Parse input arguments
        ;
        CPI         ':'
        JNZ         drives_set
        ;
        ; Parse source drive designator
        ;
        CALL        parse_drive_designator
        MOV         A,B
        STA         source_drive_type
        STA         welcome_prompt_str+28
        MOV         A,C
        STA         source_drive_nr
        ADI         '0'
        STA         welcome_prompt_str+29
        ;
        ; Check for more arguments
        ;
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ','
        JNZ         invalid_params
        CALL        INCHAR
        RC
        STA         input_char
        ;
        ; Parse destination drive designator
        ;
        CALL        parse_drive_designator
        MOV         A,B
        STA         target_drive_type
        STA         welcome_prompt_str+45
        MOV         A,C
        STA         target_drive_nr
        ADI         '0'
        STA         welcome_prompt_str+46
        ;
        ; Check for more arguments
        ;
        CALL        INCHAR
        RC
        STA         input_char
        CPI         CR
        JZ          args_parsed
        CPI         ','
        JNZ         invalid_params
        CALL        INCHAR
        RC
        STA         input_char
drives_set:
        ;
        ; Check for S option
        ;
        CPI         'S'
        JNZ         invalid_params
        STA         copy_system_flag
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         CR
        JNZ         invalid_params
args_parsed:


;//////////////////////////////////////

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
        CALL        to_uppercase
        MOV         B,A
        ;
        ; Clear any remaining input from console
        ;
flush_excess_input:
        CPI         CR
        JZ          prompt_input_flushed
        CALL        INCHAR
        RC
        JMP         flush_excess_input

prompt_input_flushed:
        ;
        ; Check prompt input
        ;
        MOV         A,B
        CPI         'Y'
        JZ          start_copying
        ANA         A
        JMP         exit_to_tos

start_copying:
        ;
        ; Set up for source drive read
        ;
        LDA         source_drive_type
        CPI         'F'
        JZ          read_from_single_sided
        CPI         'D'
        JZ          read_from_double_sided
        JMP         invalid_params


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Copy files from single-sided TOS disk
;//
;//////////////////////////////////////////////////////////////////////////////

read_from_single_sided:
        ;
        ; Assign Intel Floppy device driver to source directory file
        ;
        LHLD        TABIN_PTR
        SHLD        directory_file_fcb + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        directory_file_fcb + FCB_READ
        DAD         D
        SHLD        directory_file_fcb + FCB_CLOSE
        ;
        ; Assign source directory file drive number
        ;
        LDA         source_drive_nr
        STA         directory_file_fcb + FCB_DRVNR
        ;
        ; Open directory file for reading
        ;
        LXI         H,directory_file_fcb
        MVI         A,FM_INPUT
        CALL        OPEN
        JC          operation_aborted
        ;
        ; Ensure directory read mode is binary
        ;
        INX         H
        MOV         A,M             ; directory_file_fcb + FCB_MODE
        ORI         FM_BINARY
        MOV         M,A
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
        JZ          operation_complete
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
        ; Get attributes of file
        ;
        CALL        INCHAR
        JC          operation_aborted
        MOV         B,A
        ;
        ; Initially clear stored double-sided format attribute bytes
        ;
        LXI         D,file_attributes
        XRA         A
        STAX        D
        INX         D
        STAX        D
        INX         D
        STAX        D
        ;
        ; Rearrange format attribute (3rd byte)
        ;
        MOV         A,B
        ANI         ATTR_F
        JZ          attribute_f_ready
        LDAX        D
        ORI         ATTR_F_DSDD
        STAX        D
attribute_f_ready:
        DCX         D
        ;
        ; Rearrange invisible attribute (2nd byte)
        ;
        MOV         A,B
        ANI         ATTR_I
        JZ          attribute_i_ready
        LDAX        D
        ORI         ATTR_I_DSDD
        STAX        D
attribute_i_ready:
        DCX         D
        ;
        ; Rearrange system attribute (1st byte)
        ;
        MOV         A,B
        ANI         ATTR_S
        JZ          attribute_s_ready
        LDAX        D
        ORI         ATTR_S_DSDD
        STAX        D
attribute_s_ready:
        ;
        ; Rearrange write-protect attribute (1st byte)
        ;
        MOV         A,B
        ANI         ATTR_W
        JZ          attribute_w_ready
        LDAX        D
        ORI         ATTR_W_DSDD
        STAX        D
attribute_w_ready:
        ;
        ; Rearrange direct-access attribute (1st byte)
        ;
        MOV         A,B
        ANI         ATTR_X
        JZ          attribute_x_ready
        LDAX        D
        ORI         ATTR_X_DSDD
        STAX        D
attribute_x_ready:
        ;
        ; Flush remainder of file entry
        ;
        MVI         B,5
        LXI         D,flush_outlet
        CALL        GETBIN
        JC          operation_aborted
        ;
        ; Check attributes of file, and skip if format or direct-access file
        ;
        LDA         file_attributes
        ANI         ATTR_X_DSDD
        JNZ         check_next_file
        LDA         file_attributes+2
        ANI         ATTR_F_DSDD
        JNZ         check_next_file
        ;
        ; Skip if system file, unless S option has been used
        ;
        LDA         file_attributes
        ANI         ATTR_S_DSDD
        JZ          copy_file
        LDA         copy_system_flag
        CPI         'S'
        JNZ         check_next_file


;//////////////////////////////////////

copy_file:
        ;
        ; Prepare input file control block for reading
        ;
        MVI         A,1
        STA         input_file_fcb + FCB_DRVFMT
        XRA         A
        STA         input_file_fcb + FCB_DEVTYP
        LHLD        TABIN_PTR
        SHLD        input_file_fcb + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        input_file_fcb + FCB_READ
        DAD         D
        SHLD        input_file_fcb + FCB_CLOSE
        ;
        ; Reset FCB of input file
        ;
        LXI         H,0
        SHLD        input_file_fcb + FCB_BUFIDX
        LXI         H,128
        SHLD        input_file_fcb + FCB_BUFLEN
        LDA         source_drive_nr
        STA         input_file_fcb + FCB_DRVNR
        ;
        ; Set up filename for file to copy
        ;
        CALL        print_input_filename
        RC
        CALL        prepare_filename
        ;
        ; Try to look up file on destination drive
        ;
        LDA         target_drive_type
        CPI         'D'
        LDA         target_drive_nr
        JZ          look_up_type_d_file
        LXI         H,type_f_filename
        CALL        LOCDIR
        RC
        JMP         check_dest_file_status

look_up_type_d_file:
        LXI         H,type_d_filename
        CALL        DLOCDIR
        RC
check_dest_file_status:
        ;
        ; Check if file already existsed on the target drive
        ;
        MOV         A,M
        ANA         A
        JNZ         clear_to_write_copy
        LXI         D,not_copied_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        JMP         check_next_file

clear_to_write_copy:
        CALL        write_file_copy
        JC          operation_aborted
        CALL        set_file_copy_attributes
        JMP         check_next_file

copying_done:
        ;
        ; No more files to copy, check if the directory file is at end of file
        ;
        ANA         A
        STC
        JNZ         operation_aborted
operation_complete:
        LHLD        CO_FCB
        LXI         D,operation_completed_str
        CALL        PUT
        RC
        JMP         exit_to_tos


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Copy files from double-sided TOS disk
;//
;//////////////////////////////////////////////////////////////////////////////

read_from_double_sided:
        ;
        ; Set up directory iterator
        ;
        XRA         A
        STA         directory_iterator
        LDA         source_drive_nr
        STA         directory_iterator + 001H
        ;
        ; Check each file entry of directory and copy all files found
        ;
d_check_next_file:
        ;
        ; Look up next file in directory
        ;
        LXI         H,directory_iterator
        CALL        DNEXTFILE
        JC          d_copying_done
        SHLD        file_entry_ptr
        ;
        ; Check if file is deleted, or if at end of directory
        ;
        MOV         A,M
        ANA         A
        JNZ         d_check_next_file
        CPI         07FH
        JZ          d_operation_complete
        ;
        ; Get file attributes from file entry
        ;
        LXI         D,00EH
        DAD         D
        LXI         D,file_attributes
        MVI         C,3
        CALL        copy_memory
        ;
        ; Check attributes of file, and skip if format or direct-access file
        ;
        LDA         file_attributes
        ANI         ATTR_X_DSDD
        JNZ         d_check_next_file
        LDA         file_attributes+2
        ANI         ATTR_F_DSDD
        JNZ         d_check_next_file
        ;
        ; Skip if system file, unless S option has been used
        ;
        LDA         file_attributes
        ANI         ATTR_S_DSDD
        JZ          d_copy_file
        LDA         copy_system_flag
        CPI         'S'
        JNZ         d_check_next_file
d_copy_file:
        ;
        ; Copy filename into input file control block
        ;
        LHLD        file_entry_ptr
        INX         H
        LXI         D,input_file_fcb + FCB_FNAME
        MVI         C,6
        CALL        copy_memory
        LHLD        file_entry_ptr
        LXI         D,9
        DAD         D
        LXI         D,input_file_fcb + FCB_FEXT
        MVI         C,3
        CALL        copy_memory
        ;
        ; Prepare input file control block for reading
        ;
        MVI         A,1 + 008H
        STA         input_file_fcb + FCB_DRVFMT
        MVI         A,1
        STA         input_file_fcb + FCB_DEVTYP
        LHLD        TABTD_PTR
        SHLD        input_file_fcb + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        input_file_fcb + FCB_READ
        DAD         D
        SHLD        input_file_fcb + FCB_CLOSE
        ;
        ; Reset FCB of input file
        ;
        LXI         H,0
        SHLD        input_file_fcb + FCB_BUFIDX
        LXI         H,256
        SHLD        input_file_fcb + FCB_BUFLEN
        LDA         source_drive_nr
        STA         input_file_fcb + FCB_DRVNR
        ;
        ; Set up filename for file to copy
        ;
        CALL        print_input_filename
        RC
        CALL        prepare_filename
        ;
        ; Try to look up file on destination drive
        ;
        LDA         target_drive_type
        CPI         'D'
        LDA         target_drive_nr
        JZ          d_look_up_type_d_file
        LXI         H,type_f_filename
        CALL        LOCDIR
        RC
        JMP         d_check_dest_file_status

d_look_up_type_d_file:
        LXI         H,type_d_filename
        CALL        DLOCDIR
        RC
d_check_dest_file_status:
        ;
        ; Check if file already existsed on the target drive
        ;
        MOV         A,M
        ANA         A
        JNZ         d_clear_to_write_copy
        LXI         D,not_copied_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        JMP         d_check_next_file

d_clear_to_write_copy:
        CALL        write_file_copy
        JC          operation_aborted
        CALL        set_file_copy_attributes
        JMP         d_check_next_file

d_copying_done:
        ;
        ; No more files to copy, check if the directory file is at end of file
        ;
        ANA         A
        STC
        JNZ         operation_aborted
d_operation_complete:
        LHLD        CO_FCB
        LXI         D,operation_completed_str
        CALL        PUT
        RC
        JMP         exit_to_tos


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Termination
;//
;//////////////////////////////////////////////////////////////////////////////

operation_aborted_on_newline:
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


;//////////////////////////////////////

invalid_params:
        MVI         A,ERROR_26
        STC


;//////////////////////////////////////

exit_to_tos:
        ;
        ; Flush any remaining input
        ;
        PUSH        PSW
        LDA         input_char
        CPI         CR
        JZ          excess_input_flushed
        LHLD        CI_FCB
        LXI         D,flush_outlet
        CALL        GET
excess_input_flushed:
        POP         PSW
        ;
        ; Restore stack pointer and exit to TOS
        ;
        LHLD        sp_backup
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy file of prepared input file control block to output drive
        ;
write_file_copy:
        ;
        ; Check destination drive type
        ;
        LDA         target_drive_type
        CPI         'D'
        JZ          write_to_double_sided
        ;
        ; Prepare to write to single-sided disk
        ;
        MVI         A,1
        STA         output_file_fcb + FCB_DRVFMT
        XRA         A
        STA         output_file_fcb + FCB_DEVTYP
        LXI         H,128
        SHLD        output_file_fcb + FCB_BUFLEN
        LHLD        TABIN_PTR
        JMP         setup_file_copy

write_to_double_sided:
        ;
        ; Prepare to write to double-sided disk
        ;
        MVI         A,1 + 008H
        STA         output_file_fcb + FCB_DRVFMT
        MVI         A,1
        STA         output_file_fcb + FCB_DEVTYP
        LXI         H,256
        SHLD        output_file_fcb + FCB_BUFLEN
        LHLD        TABTD_PTR
setup_file_copy:
        ;
        ; Prepare output file control block for writing
        ;
        INX         H
        INX         H
        INX         H
        SHLD        output_file_fcb + FCB_OPEN
        LXI         D,6
        DAD         D
        SHLD        output_file_fcb + FCB_WRITE
        DAD         D
        SHLD        output_file_fcb + FCB_CLOSE
        ;
        ; Reset FCB of output file
        ;
        LXI         H,0
        SHLD        output_file_fcb + FCB_BUFIDX
        LDA         target_drive_nr
        STA         output_file_fcb + FCB_DRVNR
        ;
        ; Copy filename from input file FCB to output file FCB
        ;
        LXI         H,input_file_fcb + FCB_FNAME
        LXI         D,output_file_fcb + FCB_FNAME
        MVI         C,9
        CALL        copy_memory
        ;
        ; Open input file for reading
        ;
        LXI         H,input_file_fcb
        MVI         A,FM_INPUT
        CALL        OPEN
        JC          write_copy_error
        ;
        ; Open output file for writing
        ;
        LXI         H,output_file_fcb
        MVI         A,FM_OUTPUT
        CALL        OPEN
        JC          write_copy_error


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
        ; Read from binary input file into data-buffer
        ;
        XRA         A
        STA         end_of_file_flag
        LXI         H,input_file_fcb + FCB_MODE
        MOV         A,M
        ORI         FM_BINARY
        MOV         M,A
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
        JNZ         write_copy_error_on_newline
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
        ; Write data-buffer to binary output file
        ;
        LXI         H,output_file_fcb + FCB_MODE
        MOV         A,M
        ORI         FM_BINARY
        MOV         M,A
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
        JC          write_copy_error_on_newline
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
        ; Copy went ok, print status, close files to update file-system
        ;
        LXI         D,copied_ok_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        LXI         H,input_file_fcb
        CALL        CLOSE
        JC          write_copy_error
        LXI         H,output_file_fcb
        CALL        CLOSE
        JC          write_copy_error
        RET


;//////////////////////////////////////

write_copy_error:
        INX         SP
        INX         SP
        JMP         operation_aborted

write_copy_error_on_newline:
        INX         SP
        INX         SP
        JMP         operation_aborted_on_newline


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set attributes of a copied file
        ;
set_file_copy_attributes:
        ;
        ; Check destination drive type
        ;
        LDA         target_drive_type
        CPI         'F'
        JZ          set_single_sided_attributes


;//////////////////////////////////////

        ;
        ; Look up file entry of copy
        ;
        LDA         target_drive_nr
        LXI         H,type_d_filename
        CALL        DLOCDIR
        JC          operation_aborted
        ;
        ; Set file attributes to match source file
        ;
        LXI         D,00EH
        DAD         D
        XCHG
        LXI         H,file_attributes
        MVI         C,3
        CALL        copy_memory
        ;
        ; Write changes back to disk
        ;
        LHLD        TRK
        DCX         H
        MOV         B,M
        DCX         H
        MOV         C,M
        LXI         H,BUF2
        LDA         target_drive_nr
        CALL        DDSWRW
        JC          operation_aborted
        RET


;//////////////////////////////////////

set_single_sided_attributes:
        ;
        ; Look up file entry of copy
        ;
        LDA         target_drive_nr
        LXI         H,type_f_filename
        CALL        LOCDIR
        JC          operation_aborted
        ;
        ; Set file attributes to match source file
        ;
        LXI         D,00AH
        DAD         D
        LXI         D,file_attributes
        MVI         B,ATTR_NONE
        ;
        ; Copy write-protect attribute (1st byte)
        ;
        LDAX        D
        ANI         ATTR_W_DSDD
        JZ          attribute_w_set
        MOV         A,B
        ORI         ATTR_W
        MOV         B,A
attribute_w_set:
        ;
        ; Copy system attribute (1st byte)
        ;
        LDAX        D
        ANI         ATTR_S_DSDD
        JZ          attribute_s_set
        MOV         A,B
        ORI         ATTR_S
        MOV         B,A
attribute_s_set:
        INX         D
        ;
        ; Copy invisible attribute (2nd byte)
        ;
        LDAX        D
        ANI         ATTR_I_DSDD
        JZ          attribute_i_set
        MOV         A,B
        ORI         ATTR_I
        MOV         B,A
attribute_i_set:
        MOV         M,B
        ;
        ; Write changes back to disk
        ;
        LHLD        TRK
        DCX         H
        MOV         B,M
        DCX         H
        MOV         C,M
        LXI         H,BUF2
        LDA         target_drive_nr
        CALL        DSWRW
        JC          operation_aborted
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse and verify valid drive designator
        ;
parse_drive_designator:
        CPI         ':'
        JNZ         invalid_params
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CALL        to_uppercase
        MOV         B,A
        CPI         'F'
        JZ          valid_drive_type
        CPI         'D'
        JNZ         invalid_params
valid_drive_type:
        CALL        INCHAR
        RC
        STA         input_char
        SUI         '0'
        JC          invalid_params
        CPI         4
        JNC         invalid_params
        MOV         C,A
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ':'
        JNZ         invalid_params
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print filename of input file
        ;
print_input_filename:
        LXI         D,input_file_fcb + FCB_FNAME
        LHLD        CO_FCB
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
        RZ
        MOV         B,A
pad_filename_print:
        MVI         A,' '
        CALL        OUTCHAR
        RC
        DCR         B
        RZ
        JMP         pad_filename_print


;//////////////////////////////////////

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


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Unpack filename from file control block into buffers
        ;
prepare_filename:
        ;
        ; Single-sided format filename and extension
        ;
        LXI         H,input_file_fcb + FCB_FNAME
        LXI         D,type_f_filename
        MVI         C,9
        CALL        copy_memory
        ;
        ; Main part of double-sided format filename
        ;
        LXI         H,input_file_fcb + FCB_FNAME
        LXI         D,type_d_filename
        MVI         C,6
        CALL        copy_memory
        XRA         A
        STAX        D
        INX         D
        STAX        D
        INX         D
        ;
        ; File extension part of double-sided format filename
        ;
        MVI         C,3
        CALL        copy_memory
        XRA         A
        STAX        D
        INX         D
        STAX        D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy C bytes of memory starting at HL to memory starting at DE
        ;
copy_memory:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         C
        JNZ         copy_memory
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert a single ASCII character to uppercase
        ;
to_uppercase:
        CPI         'a'
        RM
        CPI         'z'+1
        RP
        ANI         0DFH
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

welcome_prompt_str:
        DB          'DATASET COPY FROM DISKETTE :D0: TO DISKETTE :D1:? (Y/N): ',CR
not_copied_str:
        DB          ' NOT'
copied_ok_str:
        DB          ' COPIED',CR
operation_aborted_str:
        DB          'OPERATION ABORTED',CR
newline_str:
        DB          CR
operation_completed_str:
        DB          'OPERATION COMPLETED',CR
program_end:
