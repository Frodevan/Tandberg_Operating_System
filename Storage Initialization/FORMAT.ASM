;//////////////////////////////////////////////////////////////////////////////
;//
;//     FORMAT - Initialize new TOS filesystem (soft-formating)
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<labelname>[,S]
;//             $[:<Tn>:]<labelname>[,L]
;//
;//                 Tn          Drive type and number to format, default :F0:
;//                 labelname   Label of new disk
;//                 S           Make bootable TOS system disk/tape switch
;//                 L           Only change label and nothing else
;//
;//                 Drive type T:
;//                     F       Floppy
;//                     M       Tape
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         This program writes a fresh TOS file system to either a preformated
;//         floppy-disk or a tape cartridge. In the process, any old files saved
;//         onto the device will be erased. For floppy disks, this is not a deep
;//         'low-level' format, just a quick-format where the file-system is reset
;//         to a blank state. If your disk is degaused, or completely fresh and not
;//         preformatted, use INIT to lay down a low-level format first. Tape media
;//         can on the other hand be used with FORMAT right away, without the need
;//         of any additional preparation.
;//
;//         If the S argument is given, any system files from the same drive FORMAT
;//         was run from will be copied over to the newly formatted disk, keeping
;//         all of their file attributes intact.
;//
;//         Should the L argument be given, only the label will be changed of the
;//         medium in the specified drive. This assumes that there is already a
;//         valid TOS file system on the disk or tape.
;//
;//         NOTE: This version uses buffered copying, where start of RAM is taken
;//               from the TOS start-of-ram constant. This feature was introduced
;//               in TOS v1.7, and as such this version will require TOS v1.7 in
;//               order to run with the S argument.
;//
;//         NOTE: Due to a bug, at least 48KB user-RAM is required to prevent a
;//               full system crash when copying large files.
;//
;//         NOTE: It is not possible to use the drive which is being formatted as
;//               the source drive for the system-files when bootable system-media
;//               is made. As such, it is impossible to use the S argument on
;//               machines with only a single drive of any type. The error message
;//               that prints if this is violated, may incorrecrly claim that drive
;//               0 was used even if another drive number was used.
;//
;//         NOTE: Uses XMON API for tape interfacing, and this API was optional and
;//               may as such not be installed in all machines. As such, be careful
;//               if you plan on using this program with the tape device type.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where the contents of ISIS.MAP and ISIS.ERR is not
;//                    prepared on disk if the S command line argument is used
;//                 -> Only has skeleton-code for parsing the system attribute in a
;//                    directory instead of code to actually transfer the system
;//
;//             1.5a: Entry at 0xC000
;//
;//                 -> Optimizes parsing of drive type
;//                 -> Gets system drive from command line buffer instead of
;//                    blindly assuming :F0: to be the system disk
;//                 -> Replaces the skeleton-code from v1.3 with working code that
;//                    transfers the system
;//                 -> Adds the S command line argument for drive type M
;//                 -> Flushes excess input on exit
;//                 -> Fixes the map/message-file preparation bug from v1.3
;//                 -> Has a bug where the drive-requirements for the S argument
;//                    is only being checked if a floppy disk is being formatted
;//
;//             1.5b: Entry at 0xC261
;//
;//                 -> Based on v1.5a
;//                 -> Adds a message-entry in ISIS.ERR related to B and J files.
;//                    However, this remains in the unused portion of the template,
;//                    and is as such never actually written to disk.
;//
;//             1.6: Entry at 0xC261
;//
;//                 -> Version ID written to 0x2700
;//                 -> Leaves out two unused sectors of extra error-messages in
;//                    the internal datastructure of ISIS.ERR, as these sectors
;//                    were never written to disk anyways
;//                 -> All error-messages in ISIS.ERR are now left-adjusted, to
;//                    ensure all defined messages now look alike
;//
;//             1.7a: Entry at 0xC279
;//
;//                 -> Adds the L command line argument
;//                 -> Skips system-files with the X (Direct-Access) attribute set,
;//                    when copying system from floppy disk
;//                 -> Introduces a bug that the X attribute is not chcked when
;//                    copying the system from tape
;//                 -> Copied system-file names are printed to CO
;//                 -> System-files are copied buffered instead of byte-by-byte,
;//                    using the TOS define for start of RAM
;//                 -> Defines the three previously unused error-messages in the
;//                    ISIS.ERR file
;//                 -> Introduces a bug where the S argument drive-requirement is
;//                    checked on floppy, even when that argument is not applied.
;//                 -> Introduces a bug where the buffer size is calculated to be
;//                    the negative number of bytes free, not the positive
;//                 -> Introduces a bug where operation aborted status won't be
;//                    printed if opening directory file fails before system copy
;//                    from a floppy disk
;//
;//             1.7b: Entry at 0xBC79
;//
;//                 -> Fixes the S argument drive-check bug from v1.7a
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
; IO ports
;
CBLKLG_IOH  EQU     021H        ; Tape block data length high byte
CBLKLG_IOL  EQU     022H        ; Tape block data length low byte
CBUF_IOH    EQU     023H        ; Tape block data address high byte
CBUF_IOL    EQU     024H        ; Tape block data address low byte
CCMD_IO     EQU     027H        ; Tape command (W) and status (R)

;
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; XMON system calls
;
DCALW       EQU     00070H      ; Reset disk drive with wait
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
CCAL        EQU     00091H      ; Reset tape cartridge
CUN         EQU     000A6H      ; Rewind and unload tape cartridge
CWT         EQU     000ACH      ; Wait for tape command complete
CBRDW       EQU     000AFH      ; Read data from tape cartridge with wait
CBWRW       EQU     000B2H      ; Write data to tape cartridge with wait
CBTMW       EQU     000B8H      ; Write tape mark to tape cartridge with wait
CLOCDIR     EQU     000C1H      ; Look up filetable entry of filename on tape

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SIGNATURE   EQU     02700H      ; Program signature
TRK         EQU     02731H      ; Pointer to block address of next directory data block
CPROG       EQU     02741H      ; Tape prog status
CUNIT       EQU     02742H      ; Tape unit number
CCONT       EQU     02743H      ; Tape cont address
CBUF        EQU     02745H      ; Tape data buffer address
CTRK        EQU     02747H      ; Tape track nr
CRETRY      EQU     0274DH      ; Tape retry address
CBLKLG      EQU     02750H      ; Tape block length

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
FILENAME    EQU     0FDCDH      ; Input TOS filename

;
; TOS constants
;
TABTC_PTR   EQU     0FDE6H      ; Pointer to Tandberg tape cartridge device driver
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
ERROR_48    EQU     048H        ; TAPE MARK DETECTED

;
; TOS file attributes
;
ATTR_NONE   EQU     000H        ; Normal file
ATTR_I      EQU     001H        ; Invisible file
ATTR_S      EQU     002H        ; System file
ATTR_X      EQU     040H        ; Direct-access file
ATTR_F      EQU     080H        ; Format file

;
; TOS File Control Block, block device variables
;
FCB_MODE    EQU     001H        ; File mode
FCB_BUFIDX  EQU     002H        ; Block/buffered-device data buffer index
FCB_BUFLEN  EQU     004H        ; Length of block/buffered-device data buffer
FCB_BUFPTR  EQU     006H        ; Pointer to block/buffered-device data buffer
FCB_READ    EQU     008H        ; Device-driver Read API call
FCB_WRITE   EQU     00AH        ; Device-driver Write API call
FCB_OPEN    EQU     00CH        ; Device-driver Open API call
FCB_CLOSE   EQU     00EH        ; Device-driver Close API call
FCB_DEVTYP  EQU     010H        ; Block-device type
FCB_DRVNR   EQU     011H        ; Drive number
FCB_FNAME   EQU     012H        ; Filename string
FCB_FEXT    EQU     FCB_FNAME+6 ; File extension string
FCB_DRVFMT  EQU     01BH        ; Media format
FCB_OVRPTR  EQU     01CH        ; Pointer to tape block-device buffer overrun bytes
FCB_LNKPTR  EQU     020H        ; Pointer to floppy block-device linking block buffer

;
; FCB mode flags
;
FM_NONE     EQU     000H        ; No file mode set, typically closed file
FM_INPUT    EQU     001H        ; File open for reading flag
FM_OUTPUT   EQU     002H        ; File open for writing flag
FM_BINARY   EQU     004H        ; Binary flag


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data buffers
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02000H
dest_file_data_buffer:
        DS          128
src_file_data_buffer:
        DS          128
tape_buffer_overrun:
        DS          2
src_file_linking_block:
        DS          128
dest_file_linking_block:
        DS          128
dir_file_data_buffer:
        DS          128
dir_file_linking_block_buffer:
        DS          128
scratchpad_ram:
        DS          16


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'FORMAT'
        DB          '107'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Legacy program entry
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0BA00H
program_origin:
        JMP         beginning


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

label_filename:
        DB          'ISIS',NULL,NULL
        DB          'LAB'
input_char:
        DB          NULL
sys_drive_type:
        DB          'F'
drive_type:
        DB          'F'
tape_sys_file_count:
        DB          1
tape_skip_file_countdown:
        DB          0
sys_file_buffer_ptr:
        DW          00000H
sys_file_buffer_size:
        DW          0
sys_file_buffer_free:
        DW          0
sys_file_buffer_char_count:
        DW          0
copy_complete_flag:
        DB          FALSE
sys_file_attributes:
        DB          ATTR_NONE
sys_transfer_dir_block:
        DW          0*DISK_TRACK + 0*DISK_SECTOR
sys_transfer_file_entry_ptr:
        DW          00000H
sys_transfer_file_entry_countdown:
        DB          0
sys_drive_number:
        DB          0
drive_number:
        DB          0
user_option_flag:
        DB          FALSE
        DB          000H

intel_label_str:
        DS          9

data_buffer:
        DS          128

first_directory_block:
        DB          000H
        DB          'ISIS',NULL,NULL
        DB          'DIR'
        DB          ATTR_I + ATTR_F
        DB          128
        DW          25
        DW          1*DISK_TRACK + 1*DISK_SECTOR

        DB          000H
        DB          'ISIS',NULL,NULL
        DB          'MAP'
        DB          ATTR_I + ATTR_F
        DB          128
        DW          2
        DW          2*DISK_TRACK + 1*DISK_SECTOR

        DB          000H
        DB          'ISIS',NULL,NULL
        DB          'LAB'
        DB          ATTR_I + ATTR_F
        DB          128
        DW          1
        DW          0*DISK_TRACK + 25*DISK_SECTOR

        DB          000H
        DB          'ISIS',NULL,NULL
        DB          'ERR'
        DB          ATTR_I + ATTR_F
        DB          128
        DW          23
        DW          0*DISK_TRACK + 24*DISK_SECTOR

empty_directory_block:
        DB          07FH
        DB          NULL,NULL,NULL,NULL,NULL,NULL
        DB          NULL,NULL,NULL
        DB          ATTR_NONE
        DB          0
        DW          0
        DW          0*DISK_TRACK + 0*DISK_SECTOR

        DB          07FH
        DB          NULL,NULL,NULL,NULL,NULL,NULL
        DB          NULL,NULL,NULL
        DB          ATTR_NONE
        DB          0
        Dw          0
        DW          0*DISK_TRACK + 0*DISK_SECTOR

        DB          07FH
        DB          NULL,NULL,NULL,NULL,NULL,NULL
        DB          NULL,NULL,NULL
        DB          ATTR_NONE
        DB          0
        DW          0
        DW          0*DISK_TRACK + 0*DISK_SECTOR

        DB          07FH
        DB          NULL,NULL,NULL,NULL,NULL,NULL
        DB          NULL,NULL,NULL
        DB          ATTR_NONE
        DB          0
        DW          0
        DW          0*DISK_TRACK + 0*DISK_SECTOR

        DB          07FH
        DB          NULL,NULL,NULL,NULL,NULL,NULL
        DB          NULL,NULL,NULL
        DB          ATTR_NONE
        DB          0
        DW          0
        DW          0*DISK_TRACK + 0*DISK_SECTOR

        DB          07FH
        DB          NULL,NULL,NULL,NULL,NULL,NULL
        DB          NULL,NULL,NULL
        DB          ATTR_NONE
        DB          0
        DW          0
        DW          0*DISK_TRACK + 0*DISK_SECTOR

        DB          07FH
        DB          NULL,NULL,NULL,NULL,NULL,NULL
        DB          NULL,NULL,NULL
        DB          ATTR_NONE
        DB          0
        DW          0
        DW          0*DISK_TRACK + 0*DISK_SECTOR

tape_cart_usage_block:
        DB          07FH
        DB          0,0,0,0,0
        DB          0,0,0,0,0
        DB          0,0,0,0,0
        DB          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

tape_label_block:
        DB          088H
tape_label_str:
        DS          9
        DB          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

tape_track_end_block:
        DB          '/'
        DB          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

DIR_FCB:
        DB          5
        DB          FM_NONE
        DW          0
        DW          128
        DW          dir_file_data_buffer
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
        DB          000H
        DB          000H
        DW          dir_file_linking_block_buffer

SRC_FILE_FCB:
        DB          5
        DB          FM_NONE
        DW          0
        DW          128
        DW          src_file_data_buffer
        DW          00000H
        DW          00000H
        DW          00000H
        DW          00000H
        DB          0
        DB          0
        DS          9
        DB          000H
        DW          00000H
        DB          000H
        DB          000H
        DW          00000H

        DS          17

DEST_FILE_FCB:
        DB          5
        DB          FM_NONE
        DW          0
        DW          128
        DW          dest_file_data_buffer
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
        DW          00000H

        DS          17


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

invalid_drive:
        LXI         D,invalid_drive_str
        JMP         print_and_quit


;//////////////////////////////////////

invalid_cli_args:
        LXI         D,invalid_cli_args_str
        JMP         print_and_quit


;//////////////////////////////////////

label_not_found:
        LXI         D,label_not_found_str
        JMP         print_and_quit


;//////////////////////////////////////

same_drive_not_supported:
        LXI         D,same_sys_disk_str
        CPI         'F'
        JZ          print_and_quit
        LXI         D,same_sys_tape_str


;//////////////////////////////////////

print_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        RC
quit_program:
        ;
        ; Flush any remaining input before quitting
        ;
        LDA         input_char
        CPI         CR
        RZ
        LHLD        CI_FCB
        LXI         D,scratchpad_ram
        CALL        GET
        RET


;//////////////////////////////////////

start:
beginning:
        ;
        ; Set default disk drive to drive :F0:
        ;
        SUB         A
        STA         drive_number
        STA         user_option_flag
        ;
        ; Parse drive designator from command line args, if any
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ':'
        JNZ         drive_set
        CALL        INCHAR
        RC
        CALL        to_uppercase
        STA         drive_type
        STA         input_char
        CALL        INCHAR
        RC
        STA         input_char
        SUI         '0'
        JM          invalid_drive
        CPI         4
        JP          invalid_drive
        STA         drive_number
        CALL        INCHAR
        RC
        STA         input_char
        CPI         ':'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        STA         input_char
drive_set:
        ;
        ; Peek back into the start of the entire command line buffer
        ;
        LHLD        CI_FCB
        LXI         D,FCB_BUFPTR
        DAD         D
        MOV         E,M
        INX         H
        MOV         D,M
        ;
        ; Skip any spaces at start of command line buffer
        ;
skip_arg_spaces:
        LDAX        D
        INX         D
        CPI         ' '
        JZ          skip_arg_spaces
        ;
        ; Get optional system drive, if specified before the FORMAT command
        ;
        CPI         ':'
        JNZ         verify_drive_type
        LDAX        D
        CALL        to_uppercase
        STA         sys_drive_type
        INX         D
        LDAX        D
        SUI         '0'
        STA         sys_drive_number
        ;
        ; Verify the drive type and take action accordingly
        ;
verify_drive_type:
        LDA         drive_type
        CPI         'F'
        JNZ         check_other_drive_types
        LDA         input_char
use_intel_drive:
        ;
        ; Parse disk label from command line args
        ;
        LXI         D,intel_label_str
        CALL        FILENAME
        RC
        STA         input_char
        STA         user_option_flag
        CPI         CR
        JZ          format_intel_disk
        ;
        ; Check if system-transfer switch is set in args
        ;
        CPI         ','
        JNZ         invalid_cli_args
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CALL        to_uppercase
        STA         input_char
        STA         user_option_flag
        ;
        ; Make sure there is no more command line args after this
        ;
        CALL        INCHAR
        RC
        STA         input_char
        CPI         CR
        JNZ         invalid_cli_args
        ;
        ; Check user option
        ;
        LDA         user_option_flag
        CPI         'L'
        JZ          update_intel_label
        CPI         'S'
        JNZ         invalid_cli_args
        STA         user_option_flag
        ;
        ; Make sure to not format system drive if system-transfer switch is set
        ;
        CALL        verify_valid_system_drive
        JZ          same_drive_not_supported
        JMP         format_intel_disk


;//////////////////////////////////////

update_intel_label:
        ;
        ; Check that label file exists on drive
        ;
        LXI         H,label_filename
        LDA         drive_number
        CALL        LOCDIR
        JC          label_not_found
        ;
        ; Read labelfile datablock from disk
        ;
        LXI         B,0*DISK_TRACK + 26*DISK_SECTOR
        LDA         drive_number
        LXI         H,data_buffer
        CALL        DSRDW
        RC
        ;
        ; Overwrite old label with new label
        ;
        LXI         H,data_buffer
        LXI         D,intel_label_str
        MVI         B,9
copy_next_label_char:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         copy_next_label_char
        ;
        ; Write changes back to disk
        ;
        LXI         H,data_buffer
        LXI         B,0*DISK_TRACK + 26*DISK_SECTOR
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Print status and quit program
        ;
        LXI         D,label_changed_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

format_intel_disk:
        ;
        ; Check if there is already an Intel filesystem on the disk
        ;
        LXI         H,DIR_FCB + FCB_FNAME
        LDA         drive_number
        CALL        LOCDIR
        JC          write_new_intel_filesys
        XRA         A
        ORA         M
        JNZ         write_new_intel_filesys
        ;
        ; If filesystem already exists, prompt user if they want to overwrite
        ;
        LHLD        CO_FCB
        LXI         D,rewrite_filesys_prompt_str
        CALL        PUTSTR
        RC
        ;
        ; Wait for user response to prompt
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        ;
        ; Expect a single 'Y' to continue
        ;
        CALL        to_uppercase
        STA         input_char
        CPI         'Y'
        JNZ         quit_program
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CPI         CR
        JNZ         quit_program
write_new_intel_filesys:
        ;
        ; Reset disk drive
        ;
        LDA         drive_number
        CALL        DCALW
        RC
        ;
        ; Write new label file data to disk
        ;
        CALL        clear_data_buffer
        LDA         drive_number
        LXI         H,intel_label_str
        LXI         B,0*DISK_TRACK + 26*DISK_SECTOR
        CALL        DSWRW
        RC
        ;
        ; Write new label file link block to disk
        ;
        LXI         H,0*DISK_TRACK + 26*DISK_SECTOR
        SHLD        data_buffer + 004H
        LXI         B,0*DISK_TRACK + 25*DISK_SECTOR
        LXI         H,data_buffer
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Write new directory file link block to disk
        ;
        LXI         H,data_buffer + 004H
        LXI         B,1*DISK_TRACK + 2*DISK_SECTOR
link_next_intel_dir_block:
        MOV         M,C
        INX         H
        MOV         M,B
        INX         H
        INR         C
        MOV         A,C
        CPI         27
        JNZ         link_next_intel_dir_block
        LXI         B,1*DISK_TRACK + 1*DISK_SECTOR
        LXI         H,data_buffer
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Write new directory file data to disk
        ;
        LXI         B,1*DISK_TRACK + 2*DISK_SECTOR
        LXI         H,first_directory_block
        LDA         drive_number
        CALL        DSWRW
        RC
        LXI         B,1*DISK_TRACK + 3*DISK_SECTOR
        LXI         H,empty_directory_block
write_next_intel_dir_block:
        LDA         drive_number
        CALL        DSWRW
        RC
        INR         C
        MOV         A,C
        CPI         27
        JNZ         write_next_intel_dir_block
        ;
        ; Write new mapfile link block to disk
        ;
        CALL        clear_data_buffer
        LXI         H,2*DISK_TRACK + 2*DISK_SECTOR
        SHLD        data_buffer + 004H
        LXI         H,2*DISK_TRACK + 3*DISK_SECTOR
        SHLD        data_buffer + 006H
        LXI         H,data_buffer
        LXI         B,2*DISK_TRACK + 1*DISK_SECTOR
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Write new mapfile data to disk
        ;
        CALL        clear_data_buffer
        LXI         H,0FFFFH
        SHLD        data_buffer
        SHLD        data_buffer + 002H
        SHLD        data_buffer + 004H
        MVI         A,0FEH
        STA         data_buffer + 006H
        LXI         H,data_buffer
        LXI         B,2*DISK_TRACK + 2*DISK_SECTOR
        LDA         drive_number
        CALL        DSWRW
        RC
        CALL        clear_data_buffer
        LXI         B,2*DISK_TRACK + 3*DISK_SECTOR
        LXI         H,data_buffer
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Write new errorfile data to disk
        ;
        LXI         H,errorfile_data
        LXI         B,0*DISK_TRACK + 1*DISK_SECTOR
write_next_intel_err_block:
        LDA         drive_number
        CALL        DSWRW
        RC
        INR         C
        LXI         D,128
        DAD         D
        MOV         A,C
        CPI         24
        JNZ         write_next_intel_err_block
        ;
        ; Write new errorfile link block to disk
        ;
        CALL        clear_data_buffer
        LXI         H,data_buffer + 004H
        MVI         A,001H
link_next_intel_err_block:
        MOV         M,A
        INX         H
        INX         H
        INR         A
        CPI         24
        JNZ         link_next_intel_err_block
        LXI         H,data_buffer
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Transfer system if system flag set
        ;
        LDA         user_option_flag
        CPI         'S'
        JZ          transfer_system
        ;
        ; Format of non-system disk complete, print status and quit
        ;
        LHLD        CO_FCB
        LXI         D,non_sys_disk_str
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program - System transfer
;//
;//////////////////////////////////////////////////////////////////////////////

transfer_system:
        ;
        ; Set up buffer
        ;
        LHLD        RAMST
        SHLD        sys_file_buffer_ptr
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
        SHLD        sys_file_buffer_size
        ;
        ; Print copying system status message
        ;
        LXI         D,copying_system_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Check if system to be copied from tape drive
        ;
        LDA         sys_drive_type
        CPI         'M'
        JZ          check_next_tape_file


;//////////////////////////////////////

        ;
        ; Assign Intel disk device driver to directory file
        ;
        LHLD        TABIN_PTR
        SHLD        DIR_FCB + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        DIR_FCB + FCB_READ
        DAD         D
        SHLD        DIR_FCB + FCB_CLOSE
        LDA         sys_drive_number
        STA         DIR_FCB + FCB_DRVNR
        LXI         H,DIR_FCB
        ;
        ; Open directory file for reading, in binary-mode
        ;
        MVI         A,FM_INPUT
        CALL        OPEN
        RC
        JC          operation_aborted
        INX         H
        MOV         A,M             ; DIR_FCB + FCB_MODE
        ORI         FM_BINARY
        MOV         M,A
        ;
        ; Scan through directory for files with the system attribute set
        ;
check_next_intel_file:
        ;
        ; Get and check status byte of file entry
        ;
        LXI         H,DIR_FCB
        CALL        INCHAR
        JC          transfer_from_disk_complete
        ANA         A
        JZ          intel_file_found
        ;
        ; Non-active file, skip to next entry
        ;
        MVI         B,15
        LXI         D,scratchpad_ram
        CALL        GETBIN
        JC          operation_aborted
        JMP         check_next_intel_file


;//////////////////////////////////////

check_next_tape_file:
        ;
        ; Reset tape drive and set up countdown to which file to check
        ;
        LDA         sys_drive_number
        CALL        CCAL
        JC          operation_aborted
        LDA         tape_sys_file_count
        STA         tape_skip_file_countdown
        ;
        ; Read tape first block, expect volume label
        ;
        LDA         sys_drive_number
        MVI         B,0
        LXI         H,data_buffer
        CALL        CBRDW
        JC          operation_aborted
        ;
        ; Expect volume label at start of trak, throw an error if not
        ;
        LDA         data_buffer
        CPI         088H
        MVI         A,03AH
        STC
        JNZ         operation_aborted
        ;
        ; Read tape files until next active file found
        ;
scan_for_next_tape_file:
        ;
        ; Read file entry
        ;
        LDA         sys_drive_number
        MVI         B,0
        LXI         H,data_buffer
        CALL        CBRDW
        JC          operation_aborted
        ;
        ; Check status of file. Expect active, deleted or cartridge usage block
        ;
        LDA         data_buffer
        ANA         A
        JZ          tape_file_found
        CPI         0FFH
        JZ          scan_for_next_tape_file
        CPI         07FH
        JZ          transfered_from_tape_complete
        MVI         A,03BH
        STC
        JMP         operation_aborted

tape_file_found:
        ;
        ; Check file attributes for system file
        ;
        LDA         data_buffer + 012H
        STA         sys_file_attributes
        ANI         ATTR_S
        JZ          scan_for_next_tape_file
        ;
        ; Check if we are at the target system file, keep scanning if not
        ;
        LXI         H,tape_skip_file_countdown
        DCR         M
        JNZ         scan_for_next_tape_file
        LXI         H,tape_sys_file_count
        INR         M
        ;
        ; Set up source file-control-block to read the target file from tape
        ;
        LXI         H,data_buffer + 001H
        LXI         D,SRC_FILE_FCB + FCB_FNAME
        MVI         C,9
        CALL        copy_memory
        MVI         A,1
        STA         SRC_FILE_FCB + FCB_DEVTYP
        STA         SRC_FILE_FCB + FCB_DRVFMT
        LXI         H,tape_buffer_overrun
        SHLD        SRC_FILE_FCB + FCB_OVRPTR
        LHLD        TABTC_PTR
        JMP         copy_system_file


;//////////////////////////////////////

intel_file_found:
        ;
        ; Read filename from file entry into source file file-control-block
        ;
        LXI         H,DIR_FCB
        MVI         B,9
        LXI         D,SRC_FILE_FCB + FCB_FNAME
        CALL        GETBIN
        JC          operation_aborted
        ;
        ; Get file attribute of source file
        ;
        CALL        INCHAR
        JC          operation_aborted
        STA         sys_file_attributes
        ;
        ; Flush remaining bytes of file entry
        ;
        MVI         B,5
        LXI         D,scratchpad_ram
        CALL        GETBIN
        JC          operation_aborted
        ;
        ; Check file attributes for system file and not direct-access file
        ;
        LDA         sys_file_attributes
        ANI         ATTR_S
        JZ          check_next_intel_file
        LDA         sys_file_attributes
        ANI         ATTR_X
        JNZ         check_next_intel_file
        ;
        ; Set up the rest of source file FCB
        ;
        MVI         A,1
        STA         SRC_FILE_FCB + FCB_DRVFMT
        LXI         H,src_file_linking_block
        SHLD        SRC_FILE_FCB + FCB_LNKPTR
        XRA         A
        STA         SRC_FILE_FCB + FCB_DEVTYP
        LHLD        TABIN_PTR


;//////////////////////////////////////

copy_system_file:
        ;
        ; Set up source file-control-block device drivers
        ;
        SHLD        SRC_FILE_FCB + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        SRC_FILE_FCB + FCB_READ
        DAD         D
        SHLD        SRC_FILE_FCB + FCB_CLOSE
        ;
        ; Set up source FCB buffer and device number
        ;
        LXI         H,0
        SHLD        SRC_FILE_FCB + FCB_BUFIDX
        LXI         H,128
        SHLD        SRC_FILE_FCB + FCB_BUFLEN
        LDA         sys_drive_number
        STA         SRC_FILE_FCB + FCB_DRVNR
        ;
        ; Open source file for reading
        ;
        LXI         H,SRC_FILE_FCB
        MVI         A,FM_INPUT
        CALL        OPEN
        JC          operation_aborted
        ;
        ; Check destination drive type
        ;
        LDA         drive_type
        CPI         'M'
        JZ          copy_to_tape
        ;
        ; Set up destination file-control-block for floppy disk
        ;
        MVI         A,1
        STA         DEST_FILE_FCB + FCB_DRVFMT
        XRA         A
        STA         DEST_FILE_FCB + FCB_DEVTYP
        LXI         H,dest_file_linking_block
        SHLD        DEST_FILE_FCB + FCB_LNKPTR
        LHLD        TABIN_PTR
        JMP         write_system_file

copy_to_tape:
        ;
        ; Set up destination file-control-block for tape cartridge
        ;
        MVI         A,1
        STA         DEST_FILE_FCB + FCB_DRVFMT
        STA         DEST_FILE_FCB + FCB_DEVTYP
        LXI         H,tape_buffer_overrun
        SHLD        DEST_FILE_FCB + FCB_OVRPTR
        LHLD        TABTC_PTR
write_system_file:
        ;
        ; Set up destination FCB device drivers
        ;
        INX         H
        INX         H
        INX         H
        SHLD        DEST_FILE_FCB + FCB_OPEN
        LXI         D,006H
        DAD         D
        SHLD        DEST_FILE_FCB + FCB_WRITE
        DAD         D
        SHLD        DEST_FILE_FCB + FCB_CLOSE
        ;
        ; Set up destination FCB buffer and device number
        ;
        LXI         H,0
        SHLD        DEST_FILE_FCB + FCB_BUFIDX
        LXI         H,128
        SHLD        DEST_FILE_FCB + FCB_BUFLEN
        LDA         drive_number
        STA         DEST_FILE_FCB + FCB_DRVNR
        ;
        ; Set destination filename
        ;
        LXI         H,SRC_FILE_FCB + FCB_FNAME
        LXI         D,DEST_FILE_FCB + FCB_FNAME
        MVI         C,9
        CALL        copy_memory
        ;
        ; Open destination file for writing
        ;
        LXI         H,DEST_FILE_FCB
        MVI         A,FM_OUTPUT
        CALL        OPEN
        JC          operation_aborted
        ;
        ; Print filename
        ;
        LHLD        CO_FCB
        LXI         D,DEST_FILE_FCB + FCB_FNAME
        MVI         B,6
        CALL        print_part_of_filename
        RC
        ;
        ; Print filename extension, if any
        ;
        LXI         D,DEST_FILE_FCB + FCB_FEXT
        LDAX        D
        ANA         A
        JZ          copy_next_portion_of_file
        MVI         A,'.'
        CALL        OUTCHAR
        RC
        MVI         B,3
        CALL        print_part_of_filename
        RC
        JMP         copy_next_portion_of_file


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print up to B characters, or until the first NULL character
        ;
print_part_of_filename:
        LDAX        D
        ANA         A
        RZ
        CALL        OUTCHAR
        RC
        INX         D
        DCR         B
        JNZ         print_part_of_filename
        RET


;//////////////////////////////////////////////////////////////////////////////

copy_next_portion_of_file:
        ;
        ; Reset file data buffer
        ;
        LHLD        sys_file_buffer_size
        SHLD        sys_file_buffer_free
        LXI         H,0
        SHLD        sys_file_buffer_char_count
        XRA         A
        STA         copy_complete_flag
        ;
        ; Set source file read-mode to binary
        ;
        LXI         H,SRC_FILE_FCB + FCB_MODE
        MOV         A,M
        ORI         FM_BINARY
        MOV         M,A
        ;
        ; Prepare to read data into buffer
        ;
        LHLD        sys_file_buffer_ptr
        XCHG
read_next_byte_to_copy:
        ;
        ; Read one byte into buffer
        ;
        LXI         H,SRC_FILE_FCB
        CALL        INCHAR
        JC          copy_file_no_more_data
        STAX        D
        ;
        ; Advance to next byte in buffer
        ;
        INX         D
        LHLD        sys_file_buffer_char_count
        INX         H
        SHLD        sys_file_buffer_char_count
        LHLD        sys_file_buffer_free
        DCX         H
        SHLD        sys_file_buffer_free
        ;
        ; Check if buffer is empty
        ;
        MOV         A,L
        ORA         H
        JNZ         read_next_byte_to_copy
        JMP         sys_file_buffer_full

copy_file_no_more_data:
        ;
        ; Check for end of file, or read error
        ;
        ANA         A
        STC
        JNZ         copy_error
        MVI         A,TRUE
        STA         copy_complete_flag
sys_file_buffer_full:
        ;
        ; Check if file is empty
        ;
        LHLD        sys_file_buffer_char_count
        MOV         A,L
        ORA         H
        JZ          file_copy_done
        ;
        ; Set target file to binary mode
        ;
        LXI         H,DEST_FILE_FCB + FCB_MODE
        MOV         A,M
        ORI         FM_BINARY
        MOV         M,A
        ;
        ; Prepare to write data from buffer
        ;
        LHLD        sys_file_buffer_ptr
        XCHG
write_next_byte_to_copy:
        ;
        ; Write one byte into file copy and advance to next byte in buffer
        ;
        LXI         H,DEST_FILE_FCB
        LDAX        D
        INX         D
        CALL        OUTCHAR
        JC          copy_error
        LHLD        sys_file_buffer_char_count
        DCX         H
        SHLD        sys_file_buffer_char_count
        ;
        ; Check if buffer is empty
        ;
        MOV         A,L
        ORA         H
        JNZ         write_next_byte_to_copy
        ;
        ; Keep going if there's more file left
        ;
        LDA         copy_complete_flag
        ANA         A
        JZ          copy_next_portion_of_file


;//////////////////////////////////////

file_copy_done:
        ;
        ; Print newline
        ;
        LXI         D,newline_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Close input/output files
        ;
        LXI         H,SRC_FILE_FCB
        CALL        CLOSE
        JC          operation_aborted
        LXI         H,DEST_FILE_FCB
        CALL        CLOSE
        JC          operation_aborted
        ;
        ; Check destination drive type to update attributes
        ;
        LDA         drive_type
        CPI         'M'
        JZ          update_attributes_tape
        ;
        ; Look up floppy file entry for the file copy
        ;
        LDA         drive_number
        LXI         H,DEST_FILE_FCB + FCB_FNAME
        CALL        LOCDIR
        JC          operation_aborted
        ;
        ; Set attributes of copy to the same as souce file
        ;
        LXI         D,00AH
        DAD         D
        LDA         sys_file_attributes
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
        LDA         drive_number
        CALL        DSWRW
        JC          operation_aborted
        JMP         copy_next_file

update_attributes_tape:
        ;
        ; Look up tape file entry for the file copy
        ;
        LDA         drive_number
        STA         CUNIT
        LXI         H,DEST_FILE_FCB + FCB_FNAME
        CALL        CLOCDIR
        JC          operation_aborted
        SHLD        CBUF
        ;
        ; Set attributes of copy to the same as souce file
        ;
        LXI         D,012H
        DAD         D
        LDA         sys_file_attributes
        MOV         M,A
        ;
        ; Set up tape control block and prepare controller for write
        ;
        CALL        wait_for_tape_ready
        LHLD        CBUF
        MOV         A,H
        OUT         CBUF_IOH
        MOV         A,L
        OUT         CBUF_IOL
        MVI         A,0FFH
        STA         CPROG
        LXI         H,32
        SHLD        CBLKLG
        MOV         A,H
        OUT         CBLKLG_IOH
        MOV         A,L
        OUT         CBLKLG_IOL
        XRA         A
        STA         CTRK
        LXI         H,00000H
        SHLD        CCONT
        SHLD        CRETRY
        ;
        ; Send write command to tape controller
        ;
        LXI         H,CUNIT
        MOV         A,M
        ORI         030H
        OUT         CCMD_IO
        CALL        CWT
        JC          operation_aborted


;//////////////////////////////////////

copy_next_file:
        ;
        ; Copy complete, go copy next file
        ;
        LDA         sys_drive_type
        CPI         'F'
        JZ          check_next_intel_file
        JMP         check_next_tape_file


;//////////////////////////////////////

transfer_from_disk_complete:
        ANA         A
        STC
        JNZ         operation_aborted
transfered_from_tape_complete:
        LHLD        CO_FCB
        LDA         drive_type
        CPI         'M'
        JZ          transferred_from_tape_status
        ;
        ; Format of system disk complete, print status and quit
        ;
        LXI         D,format_sys_disk_ok_str
        CALL        PUT
        RC
        JMP         quit_program

transferred_from_tape_status:
        LXI         D,format_sys_tape_ok_str
        JMP         print_unload_tape_and_quit


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program - Tape
;//
;//////////////////////////////////////////////////////////////////////////////

check_other_drive_types:
        ;
        ; Verify non-intel drive designator from command line args
        ;
        CPI         'M'
        JNZ         invalid_drive
        LDA         input_char
        ;
        ; Parse tape label from command line args
        ;
        LXI         D,tape_label_str
        CALL        FILENAME
        RC
        STA         input_char
        ;
        ; Check if user option switch is set in args
        ;
        CPI         ','
        JNZ         no_more_tape_args
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         input_char
        CALL        to_uppercase
        CPI         'S'
        JZ          set_user_option_flag_for_tape
        CPI         'L'
        JNZ         invalid_cli_args


;//////////////////////////////////////

        ;
        ; L option has been selected, reset tape and overwrite old label block
        ;
        LDA         drive_number
        CALL        CCAL
        RC
        MVI         B,0
        LXI         D,32
        LXI         H,tape_label_block
        CALL        CBWRW
        RC
        ;
        ; Print status message
        ;
        LXI         D,label_changed_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

set_user_option_flag_for_tape:
        STA         user_option_flag
        CALL        INCHAR
        RC
        STA         input_char
no_more_tape_args:
        ;
        ; Make sure there is no more command line args after this
        ;
        CPI         CR
        JNZ         invalid_cli_args


;//////////////////////////////////////

        ;
        ; Reset tape drive
        ;
        LDA         drive_number
        CALL        CCAL
        RC
        ;
        ; Write new tape label block
        ;
        MVI         B,0
        LXI         D,32
        LXI         H,tape_label_block
        LDA         drive_number
        CALL        CBWRW
        RC
        ;
        ; Write new tape cartridge usage block
        ;
        LDA         drive_number
        MVI         B,0
        LXI         D,32
        LXI         H,tape_cart_usage_block
        CALL        CBWRW
        RC
        ;
        ; Write tape mark at end of track data
        ;
        LDA         drive_number
        MVI         B,0
        CALL        CBTMW
        JNC         tape_dir_track_done
        CPI         ERROR_48
        JZ          tape_dir_track_done
        STC
        RET

tape_dir_track_done:
        ;
        ; Start preparing file-data track 1
        ;
        MVI         B,1
prepare_tape_file_track:
        ;
        ; Reset tape
        ;
        LDA         drive_number
        CALL        CCAL
        RC
        ;
        ; Write track end block to start of file-data track
        ;
        LDA         drive_number
        LXI         D,32
        LXI         H,tape_track_end_block
        CALL        CBWRW
        RC
        ;
        ; Write tape mark at end of track data
        ;
        LDA         drive_number
        CALL        CBTMW
        JNC         tape_file_track_done
        CPI         ERROR_48
        JZ          tape_file_track_done
        STC
        RET

tape_file_track_done:
        ;
        ; Advance to next file data track
        ;
        INR         B
        MOV         A,B
        CPI         4
        JNZ         prepare_tape_file_track
        ;
        ; Transfer system if system flag set
        ;
        LDA         user_option_flag
        CPI         'S'
        JZ          transfer_system
        LXI         D,format_non_sys_tape_ok_str
print_unload_tape_and_quit:
        ;
        ; Print status
        ;
        LHLD        CO_FCB
        CALL        PUT
        RC
        ;
        ; Tape formatting complete, rewind and unload tape
        ;
        LDA         drive_number
        CALL        CUN
        RC
        JMP         quit_program


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Print aborted status and return
        ;
copy_error:
        ;
        ; Print newline
        ;
        PUSH        PSW
        LXI         D,newline_str
        LHLD        CO_FCB
        CALL        PUT
        JC          quit_program_from_subroutine
        POP         PSW
operation_aborted:
        ;
        ; Print aborted status
        ;
        PUSH        PSW
        LXI         D,operation_aborted_str
        LHLD        CO_FCB
        CALL        PUT
        JC          quit_program_from_subroutine
        POP         PSW
        RET

quit_program_from_subroutine:
        INX         SP
        INX         SP
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Wait for tape controller to set the ready-bit
        ;
wait_for_tape_ready:
        PUSH        PSW
tape_wait_loop:
        IN          CCMD_IO
        ANI         001H
        JNZ         tape_wait_loop
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Make sure drive to be formatted is not the same as system drive
        ;
verify_valid_system_drive:
        LDA         drive_number
        MOV         C,A
        LDA         sys_drive_number
        CMP         C
        RNZ
        LDA         drive_type
        MOV         C,A
        LDA         sys_drive_type
        CMP         C
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy C bytes pointed at by HL into memory pointed at by DE
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
        ; Clear sector data-buffer used for disk operations
        ;
clear_data_buffer:
        LXI         H,data_buffer
        MVI         B,128
        SUB         A
clear_next_byte:
        MOV         M,A
        INX         H
        DCR         B
        JNZ         clear_next_byte
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

rewrite_filesys_prompt_str:
        DB          'REINITIALIZATION DESIRED (Y/N) ',CR
non_sys_disk_str:
        DB          'NON - SYSTEM DISKETTE',CR
format_sys_disk_ok_str:
        DB          'SYSTEM DISKETTE CREATED',CR
invalid_drive_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
invalid_cli_args_str:
        DB          'IMPROPER PARAMETER LIST',CR
same_sys_disk_str:
        DB          'SYSTEM DISKETTE FORMATTING UNIT 0 NOT ALLOWED',CR
format_non_sys_tape_ok_str:
        DB          'NON - SYSTEM CARTRIDGE',CR
format_sys_tape_ok_str:
        DB          'SYSTEM CARTRIDGE CREATED',CR
copying_system_str:
        DB          'COPYING SYSTEM FILES',CR
same_sys_tape_str:
        DB          'SYSTEM CARTRIDGE FORMATTING UNIT 0 NOT ALLOWED',CR
label_changed_str:
        DB          'VOLUME LABEL CHANGED',CR
newline_str:
        DB          CR
label_not_found_str:
        DB          'LABEL NOT FOUND',CR
operation_aborted_str:
        DB          'OPERATION ABORTED',CR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     ISIS.ERR data
;//
;//////////////////////////////////////////////////////////////////////////////

errorfile_data:
        DB          085H,'END OF FILE                    '
        DB          085H,'SECTOR MISSING                 '
        DB          085H,'CRC ERROR                      '
        DB          085H,'TIMING ERROR READ/WRITE XFER   '
        DB          085H,'NO ADDRESS MARK                '
        DB          085H,'DISKETTE OPERATION TIMEOUT     '
        DB          085H,'TIMING ERROR IN READ OPERATION '
        DB          085H,'BUSY-BIT TIMEOUT               '
        DB          085H,'DRIVE NOT READY                '
        DB          085H,'NAME NOT IN DIR AND DIR FULL   '
        DB          085H,'NAME NOT IN DIRECTORY          '
        DB          085H,'PROGRAM NAME NOT FOUND         '
        DB          085H,'ILLEGAL DIRECTORY ENTRY        '
        DB          085H,'DIRECTORY BLOCK ERROR - LOAD   '
        DB          085H,'DATA LENGTH ERROR DURING LOAD  '
        DB          085H,'DISKETTE MAP MISSING           '
        DB          085H,'NON-VALID DISKETTE COMMAND     '
        DB          085H,'IMPROPER UNIT SPECIFICATION    '
        DB          085H,'CONVERSION TABLE MISSING       '
        DB          085H,'DRIVE NUMBER NOT 0-3           '
        DB          085H,'FILE PROTECTED                 '
        DB          085H,'DE-EDIT NONHEX DIGIT (0-9,A-F) '
        DB          085H,'INPUT FROM NON-INPUT FILE      '
        DB          085H,'READ AFTER END-OF-FILE         '
        DB          085H,'OUTPUT TO NON-OUTPUT FILE      '
        DB          085H,'UNASSIGNED DEVICE              '
        DB          085H,'UNKNOWN DEVICE TYPE            '
        DB          085H,'COM/FNAM NOT LETTER/DIGIT 1ST  '
        DB          085H,'COM/FNAM > 6 OR EXT > 3 CHARS  '
        DB          085H,'COMMAND UNIT NOT :FN: OR :MN:  '
        DB          085H,'TOS NOT LOADED                 '
        DB          085H,'COMMAND NOT TERMINATED PROPERLY'
        DB          085H,'DELETED DATA RECORD            '
        DB          085H,'LOGICAL UNIT NAME UNKNOWN      '
        DB          085H,'WRITE ON NON-BLOCK FILE        '
        DB          085H,'WRITE/READ MISSING IN CTL-BLK  '
        DB          085H,'READ ON FILETYPE OTHER THAN 4,5'
        DB          085H,'LINE OVERFLOW                  '
        DB          085H,'IMPROPER PARAMETER             '
        DB          085H,'FILE ALREADY OPEN              '
        DB          085H,'NO OPEN-ROUTINE IN CTL-BLK     '
        DB          085H,'CLOSE ON CLOSED FILE           '
        DB          085H,'NO CLOSE-ROUTINE IN CTL-BLK    '
        DB          085H,'BUFFER CHAIN DESTROYED         '
        DB          085H,'BUFFER HEADER IMPROPER         '
        DB          085H,'IMPROPER FILE DESIGNATOR       '
        DB          085H,'IMPROPER ASSIGNMENT FORMAT     '
        DB          085H,'NO ROOM ON DISKETTE            '
        DB          085H,'ILLEGAL BUFFER TYPE            '
        DB          085H,'NON-EXISTENT FILE NAME - INPUT '
        DB          085H,'OUTPUT FILE ALREADY ON DISKETTE'
        DB          085H,'NO ROOM ON DISKETTE            '
        DB          085H,'FILENAME > 8 CHARACTERS        '
        DB          085H,'TRACK NUMBER > 76              '
        DB          085H,'SECTOR NUMBER = 0 OR > 26      '
        DB          085H,'BUFFER ADDRESS ZERO            '
        DB          085H,'ROUTINE NOT AVAILABLE          '
        DB          085H,':MN: DIR BLOCK NOT 32 BYTES    '
        DB          085H,'VOLUME HEADER MISSING          '
        DB          085H,'DIRECTORY BLOCK ERROR          '
        DB          085H,'OUTPUT FILE ALREADY ON CARTR.  '
        DB          085H,'NO MORE SPACE ON CARTRIDGE     '
        DB          085H,'INPUT FILE OVERRUN             '
        DB          085H,'EXTRA OR MISPLACED TAPEMARK    '
        DB          085H,'END OF TAPE ERROR              '
        DB          085H,'CARTRIDGE CRC ERROR            '
        DB          085H,'FATAL CARTRIDGE ERROR          '
        DB          085H,'CARTRIDGE CRC + FATAL ERROR    '
        DB          085H,'CARTR. WRITE PROTECT/INVALID CM'
        DB          085H,'CRC + WRIT.PROT/INV.COM        '
        DB          085H,'READING ERASED TAPE            '
        DB          085H,'CRC + FATAL + WR.PRT/INV.CM    '
        DB          085H,'TAPE MARK DETECTED             '
        DB          085H,'CRC + TAPE MARK                '
        DB          085H,'FATAL ERROR + TAPE MARK        '
        DB          085H,'CRC + FATAL + TAPE MARK        '
        DB          085H,'WRT.PT/INV.CM + TAPE MARK      '
        DB          085H,'CRC + WRT.PT/INV.CM + TAPE MARK'
        DB          085H,'FATAL+WRT.PT/INV.CM+TAPE MARK  '
        DB          085H,'CRC+FATAL+WPT/IVC+TAPE MARK    '
        DB          085H,'CARTR ILLEGAL UNIT NUMBER      '
        DB          085H,'CARTRIDGE ILLEGAL TRACK NUMBER '
        DB          085H,'CARTRIDGE BLOCK SIZE ILLEGAL   '
        DB          085H,'CARTRIDGE TRACK CHANGE ERROR   '
        DB          085H,'CARTRIDGE UNIT NOT READY       '
        DB          085H,'CARTRIDGE ILLEGAL BUFFER ADDR. '
        DB          085H,'CARTRIDGE NOT SUPPORTED        '
        DB          085H,'CARTRIDGE EXTRA BLOCKS IN FILE '
        DB          085H,'CARTRIDGE CONT. HDR MISSING    '
        DB          085H,'INCORRECT BLOCK TYPE IN HEADER '
        DB          085H,'INCORRECT NAME IN HEADER BLOCK '
        DB          085H,'INAPPROPRIATE BLK SIZE LOAD    '
