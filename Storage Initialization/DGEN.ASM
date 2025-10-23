;//////////////////////////////////////////////////////////////////////////////
;//
;//     DGEN - Copy all files from floppy to floppy
;//
;//         Copy every single file from floppy disk :F0: to floppy :F1:, using TOS
;//         system-calls to do the binary transfers. If a file already exsists on
;//         the target floppy, the copying of that file is skipped.
;//
;//         Files with the alias attribute, or the first four files on the disk
;//         will not be included in the copy.
;//
;//         NOTE: Supports 54KB user-RAM. However, TOS v1.7 or more recent is
;//               required to run this version.
;//
;//         NOTE: Due to a bug, files with the X or W attributes set may cause
;//               problems when copied by this program.
;//
;//         NOTE: Due to a bug, if the file size of a source file is an exact
;//               multiple of the buffer size, incl. the case of an empty file, the
;//               contents of the entire 64KB memory space of the computer will be
;//               appended to the end of the file copy.
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
;//             1.8: Entry at 0xCD9A
;//
;//                 -> Total rewrite, but retaining much the same features as v1.7
;//                 -> No version ID at 0x2700
;//                 -> No extra parameters
;//                 -> Uses XMON API calls to check the file-dictionary, and
;//                    PHYSINT to prepare files for opening. This is in comparison
;//                    to static structures and TOS-calls to open files as done in
;//                    earlier versions.
;//                 -> Does not copy Aliases, or the first four files in the file
;//                    table on the source disk.
;//                 -> Has a bug where a newline single-char print is calling the
;//                    API call for print string instead
;//                 -> Introduces a bug where the file attribute byte of the source
;//                    file is written to the media type of the target file FCB
;//                    before the target file is being opened for writing.
;//                 -> Introduces a bug where the buffer is not checked against a
;//                    length of zero before writing data to file.
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
LF          EQU     00AH        ; Line Feed
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
DSRD        EQU     0005BH      ; Read from disk without wait
DSWT        EQU     0006DH      ; Wait for floppy disk controller
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
TRK         EQU     02731H      ; Pointer to block address of next directory data block

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
OUTCHAR     EQU     0FD0CH      ; Output single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
OPEN        EQU     0FD1EH      ; Open block device
CLOSE       EQU     0FD27H      ; Close block device
PHYSINT     EQU     0FDDFH      ; Initialize FCB from full file designator

;
; TOS constants
;
RAMST       EQU     0FDFCH      ; Address to start of user-RAM

;
; TOS standard files
;
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_08    EQU     008H        ; DRIVE NOT READY

;
; TOS file attributes
;
ATTR_A      EQU     008H        ; Alias file

;
; TOS File Control Block, block device variables
;
FCB_DRVFMT  EQU     01BH        ; Media format

;
; FCB mode flags
;
FM_INPUT    EQU     001H        ; File open for reading flag
FM_OUTPUT   EQU     002H        ; File open for writing flag
FM_BINARY   EQU     004H        ; Binary flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
filetable_buffer:
        DS          26*128
filetable_filename:
        DB          'ISIS',NULL,NULL
        DB          'DIR'

output_filename_str:
        DB          ':F1:'
filename_str:
        DS          16

input_char:
        DB          000H
file_attributes:
        DB          000H
data_buffer_end_page:
        DB          000H
sp_backup:
        DW          00000H
file_entry_ptr:
        DW          00000H
        DW          00000H

input_file_fcb:
        DW          00000H
output_file_fcb:
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

read_remaining_track:
        ;
        ; Read next sector in track from disk 0
        ;
        MVI         A,0
        INR         C
        CALL        DSRD
        RC
        ;
        ; Check if last sector of track
        ;
        MOV         A,C
        CPI         26
        RZ
        ;
        ; Advance to next sector and wait for disk controller
        ;
        LXI         D,128
        DAD         D
        CALL        DSWT
        RC
        JMP         read_remaining_track


;//////////////////////////////////////////////////////////////////////////////

prepare_filename_str:
        ;
        ; Copy filename into string buffer
        ;
        LXI         D,filename_str
        MVI         B,6
        CALL        copy_part_of_filename
        MVI         A,'.'
        STAX        D
        INX         D
        MVI         B,3
        CALL        copy_part_of_filename
        MVI         A,CR
        STAX        D
        ;
        ; Remove file extension deliminer if no file extension
        ;
        DCX         D
        LDAX        D
        CPI         '.'
        RNZ
        MVI         A,CR
        STAX        D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy string of given length, skipping any NULL chars
        ;
copy_part_of_filename:
        MOV         A,M
        INX         H
        ORA         A
        JZ          filename_char_done
        STAX        D
        INX         D
filename_char_done:
        DCR         B
        JNZ         copy_part_of_filename
        RET


;//////////////////////////////////////////////////////////////////////////////

open_input_file:
        ;
        ; Create input file FCB
        ;
        MVI         A,0
        CALL        PHYSINT
        RC
        ;
        ; Open file for reading
        ;
        MVI         A,FM_INPUT
        CALL        OPEN
        RC
        SHLD        input_file_fcb
        ;
        ; Set file to binary mode
        ;
        INX         H
        MOV         A,M
        ORI         FM_BINARY       ; input_file_fcb + FCB_MODE
        MOV         M,A
        DCX         H
        RET


;//////////////////////////////////////////////////////////////////////////////

open_output_file:
        ;
        ; Create output file FCB
        ;
        MVI         A,1
        CALL        PHYSINT
        RC
        SHLD        output_file_fcb
        ;
        ; Bug: Author mixed up the FCB and file-entry datastructs
        ;
        LXI         D,FCB_DRVFMT
        DAD         D
        LDA         file_attributes
        MOV         M,A
        ;
        ; Open file for writing
        ;
        LHLD        output_file_fcb
        MVI         A,FM_OUTPUT
        CALL        OPEN
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

start:
        ;
        ; Save stack pointer for breaking out of program from subroutines
        ;
        LXI         H,00000H
        DAD         SP
        SHLD        sp_backup
        ;
        ; Print welcome prompt
        ;
        LHLD        CO_FCB
        LXI         D,welcome_prompt_str
        CALL        PUTSTR
        RC
        ;
        ; Wait for user response
        ;
        MVI         A,0
        ANA         A
wait_for_user_input:
        STA         input_char
        CALL        TTI
        CALL        TTO
        RC
        CPI         CR
        JNZ         wait_for_user_input
        ;
        ; Check prompt input
        ;
        LDA         input_char
        CPI         'Y'
        JZ          start_copying
        CPI         'y'
        JZ          start_copying
        ANA         A
        JMP         exit_program

start_copying:
        LHLD        CO_FCB
        MVI         A,LF
        CALL        PUT
        ;
        ; Try to locate filetable on source disk
        ;
        LXI         H,filetable_filename
        MVI         A,0
        CALL        LOCDIR
        JNC         src_filetable_found
        CPI         ERROR_08
        JZ          src_filetable_read_error
        LHLD        CO_FCB
        LXI         D,invalid_source_str
        CALL        PUT
        MVI         A,000H
        ANA         A
        RET

src_filetable_read_error:
        STC
        RET

src_filetable_found:
        ;
        ; Load source disk filetable into buffer
        ;
        MVI         B,1
        MVI         C,1
        LXI         H,filetable_buffer
        CALL        read_remaining_track
        JC          exit_program
        ;
        ; Try to locate filetable on destination disk
        ;
        LXI         H,filetable_filename
        MVI         A,1
        CALL        LOCDIR
        JC          dest_filetable_not_found
        ;
        ; Verify file with destination filetable is active
        ;
        MOV         A,M
        ANA         A
        JZ          dest_filetable_found
dest_filetable_not_found:
        CPI         ERROR_08
        JNZ         dest_wrong_format
        STC
        RET

dest_wrong_format:
        LHLD        CO_FCB
        LXI         D,invalid_destination_str
        CALL        PUT
        MVI         A,000H
        ANA         A
        JMP         exit_program


;//////////////////////////////////////

dest_filetable_found:
        ;
        ; Skip the four first files (usually filesystem/format related files)
        ;
        LXI         H,filetable_buffer
        LXI         B,3*16
        DAD         B
        SHLD        file_entry_ptr
check_next_file:
        ;
        ; Advance to next file entry
        ;
        LHLD        file_entry_ptr
        LXI         B,16
        DAD         B
        SHLD        file_entry_ptr
        ;
        ; Check file-entry status
        ;
        MOV         A,M
        CPI         07FH
        JZ          program_complete
        CPI         0FFH
        JZ          check_next_file
        CPI         000H
        JNZ         program_complete
        ;
        ; File found, check if it already exists on target
        ;
        INX         H
        MVI         A,1
        CALL        LOCDIR
        RC
        MOV         A,M
        ANA         A
        JZ          file_already_exists
        ;
        ; Get and check file attributes
        ;
        LHLD        file_entry_ptr
        LXI         B,00AH
        DAD         B
        MOV         A,M
        STA         file_attributes
        ANI         ATTR_A
        JNZ         alias_file
        ;
        ; Print filename for file to be copied
        ;
        LHLD        file_entry_ptr
        INX         H
        CALL        prepare_filename_str
        LHLD        CO_FCB
        LXI         D,copy_file_str
        CALL        PUTSTR
        MVI         A,CR
        CALL        TTO
        LXI         D,filename_str
        CALL        PUT
        RC
        ;
        ; Open input and output files for IO
        ;
        LXI         H,filename_str
        CALL        open_input_file
        JC          exit_program
        LXI         H,output_filename_str
        CALL        open_output_file
        JC          exit_program


;//////////////////////////////////////

read_from_source_file:
        ;
        ; Flush data-buffer and prepare to read from input file
        ;
        LHLD        RAMST
        MOV         B,H
        MOV         C,L
        LHLD        input_file_fcb
        LXI         D,0
read_next_source_byte:
        ;
        ; Read byte
        ;
        CALL        INCHAR
        JC          read_error
        STAX        B
        INX         B
        ;
        ; Update data-buffer status and check if full
        ;
        INX         D
        MOV         A,B
        CPI         0C0H
        JZ          data_buffer_full
        JMP         read_next_source_byte

read_error:
        ;
        ; Make sure to also write the final data if only end of file
        ;
        ANA         A
        JNZ         program_complete
        CALL        CLOSE
        RC
data_buffer_full:
        MOV         A,B
        STA         data_buffer_end_page
        ;
        ; Write data-buffer to output file
        ;
        LHLD        RAMST
        MOV         B,H
        MOV         C,L
        LHLD        output_file_fcb
write_next_byte_to_copy:
        ;
        ; Write byte
        ;
        LDAX        B
        CALL        OUTCHAR
        RC
        INX         B
        ;
        ; Update data-buffer status and check if empty
        ;
        DCX         D
        MOV         A,D
        ORA         E
        JNZ         write_next_byte_to_copy
        LDA         data_buffer_end_page
        CPI         0C0H
        JZ          read_from_source_file
        ;
        ; Copy went ok, print status, close output file to update file-system
        ;
        LHLD        output_file_fcb
        CALL        CLOSE
        RC
        ;
        ; Look up file entry of copy
        ;
        LHLD        file_entry_ptr
        INX         H
        MVI         A,1
        CALL        LOCDIR
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
        LXI         H,BUF2
        MVI         A,1
        CALL        DSWRW
        RC
        JMP         check_next_file


;//////////////////////////////////////

file_already_exists:
        ;
        ; Set filename string
        ;
        LHLD        file_entry_ptr
        INX         H
        CALL        prepare_filename_str
        ;
        ; Print status message
        ;
        LHLD        CO_FCB
        LXI         D,file_exists_str
        CALL        PUTSTR
        MVI         A,CR
        CALL        TTO
        LXI         D,output_filename_str
        CALL        PUT
        JMP         check_next_file

alias_file:
        ;
        ; Set filename string
        ;
        LHLD        file_entry_ptr
        INX         H
        CALL        prepare_filename_str
        ;
        ; Print status message
        ;
        LHLD        CO_FCB
        LXI         D,alias_str
        CALL        PUTSTR
        MVI         A,CR
        CALL        TTO
        LXI         D,filename_str
        CALL        PUT
        RC
        JMP         check_next_file

program_complete:
        ;
        ; Clear any potential error codes and print program complete status
        ;
        MVI         A,000H
        ANA         A
        LHLD        CO_FCB
        LXI         D,program_complete_str
        CALL        PUT
exit_program:
        LHLD        sp_backup
        SPHL
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

welcome_prompt_str:
        DB          'File copy from :F0: to :F1:  Ready ? (Y/N): ',CR
file_exists_str:
        DB          '              :  Exists  ',CR
copy_file_str:
        DB          '              :  Copy   to  :F1: ',CR
alias_str:
        DB          '              :  Alias name.   No copy ',CR
program_complete_str:
        DB          '              :  Operation   completed',CR
invalid_destination_str:
        DB          'Diskette in drive 1 is not Tandberg formatted',CR
invalid_source_str:
        DB          'Diskette in drive 0 is not Tandberg formatted',CR
