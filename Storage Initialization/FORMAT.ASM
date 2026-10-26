;//////////////////////////////////////////////////////////////////////////////
;//
;//     FORMAT - Initialize new TOS filesystem (soft-formating)
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<labelname>[,S]
;//             $[:<Tn>:]<labelname>[,L]
;//
;//                 Tn          Drive type and number to format, default :D0:
;//                 labelname   Label of new disk
;//                 S           Make bootable TOS system disk/tape switch
;//                 L           Only change label and nothing else
;//
;//                 Drive type T:
;//                     D       Floppy, TOS double-sided double-density
;//                     F       Floppy, TOS single-sided single-density
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         This program writes a fresh TOS file system to a floppy-disk. In the
;//         process, any old files saved onto the device will be erased. This is
;//         not a deep 'low-level' format, just a quick-format where the file-
;//         system is reset to a blank state. If your disk is degaused, or
;//         completely fresh and not preformatted, use INIT or INITD to lay down a
;//         low-level format first.
;//
;//         If the S argument is given, any system files from the same drive FORMAT
;//         was run from will be copied over to the newly formatted disk, keeping
;//         all of their file attributes intact.
;//
;//         Should the L argument be given, only the label will be changed of the
;//         medium in the specified drive. This assumes that there is already a
;//         valid TOS file system on the disk or tape.
;//
;//         NOTE: It is not possible to use the drive which is being formatted as
;//               the source drive for the system-files when bootable system-media
;//               is made. As such, it is impossible to use the S argument on
;//               machines with only a single drive of any type.
;//
;//         NOTE: This version relies on a preliminarty version of the TOS-II API,
;//               so copying from double-sided disks will only work on the Beta-
;//               version of TOS-II v2.0.
;//
;//
;//         Changelog:
;//
;//             1.2: Entry at 0xC000
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
;//                 -> Replaces the skeleton-code from v1.2 with working code that
;//                    transfers the system
;//                 -> Adds the S command line argument for drive type M
;//                 -> Flushes excess input on exit
;//                 -> Fixes the map/message-file preparation bug from v1.2
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
;//             2.0a: Entry at 0x3147
;//
;//                 -> Get system drive from TOS-II rather than command line
;//                 -> Fixes buffer-size bug from v1.7a
;//                 -> Adds support for double-sided disk type D
;//                 -> Fixes the buffer-size calculation bug from v1.7a
;//                 -> Introduces a bug where the confirmation prompt will be shown
;//                    when only changing the label of a double-sided disk
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
; XMON constants
;
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector
DISK_HEAD_1 EQU	    080H        ; Floppy disk sector number mask for disk head 1

;
; XMON system calls
;
DCALW       EQU     00070H      ; Reset disk drive with wait
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
DDSRDW      EQU     00097H      ; Read from double-sided disk with wait
DDSWRW      EQU     0009AH      ; Write to double-sided disk with wait
DLOCDIR     EQU     000CDH      ; Look up filetable entry of filename on double-sided disk

;
; XMON and TOS system data
;
BUF2        EQU     02600H      ; Sector data of last filesystem operation
SIGNATURE   EQU     02700H      ; Program signature
SYSDRV_NR   EQU     0270DH      ; Current system drive number
SYSDRV_TYPE EQU     0270EH      ; Current system drive type
TRK         EQU     02731H      ; Pointer to block address of next directory data block
BUFLIM      EQU     0272EH      ; Lowest address of current TOS buffers

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
DFILENAME   EQU     0FDBBH      ; Input TOS filename for double-sided disk
FILENAME    EQU     0FDCDH      ; Input TOS filename

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
ATTR_X_DSDD EQU     080H        ; Direct-access file
ATTR_W_DSDD EQU     040H        ; Write-protected file

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
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'FORMAT'
        DB          '200'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         02800H
label_filename:
        DB          'ISIS',NULL,NULL
        DB          'LAB'
tos_dsdd_signature:
        DB          'TANDBERG'
input_char:
        DB          NULL
sys_drive_type:
        DB          'D'
drive_type:
        DB          'D'
sys_file_buffer_ptr:
        DW          00000H
file_entry_ptr:
        DW          00000H
sys_file_buffer_size:
        DW          0
sys_file_buffer_free:
        DW          0
sys_file_buffer_char_count:
        DW          0
copy_complete_flag:
        DB          FALSE
file_attributes:
        DB          ATTR_NONE, ATTR_NONE, ATTR_NONE
        DB          000H
sys_drive_number:
        DB          0
drive_number:
        DB          0
user_option_flag:
        DB          FALSE
        DB          000H

tos_name_str:
        DS          13
intel_name_str:
        DS          9

data_buffer:
        DS          256
dest_file_data_buffer:
        DS          256
src_file_data_buffer:
        DS          256
src_file_linking_block:
        DS          256
dest_file_linking_block:
        DS          256
dir_file_data_buffer:
        DS          256
dir_file_linking_block_buffer:
        DS          256
scratchpad_ram:
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

        DB          07FH
        DB          NULL,NULL,NULL,NULL,NULL,NULL
        DB          NULL,NULL,NULL
        DB          ATTR_NONE
        DB          0
        DW          0
        DW          0*DISK_TRACK + 0*DISK_SECTOR

dsdd_err_file_linking_data:
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 1*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 2*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 3*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 4*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 5*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 6*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 7*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 8*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 9*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 10*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 11*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 12*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 13*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 14*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 15*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 16*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 17*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 18*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 19*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 20*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 21*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 22*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 23*DISK_SECTOR
        DW          (1 + DISK_HEAD_1)*DISK_TRACK + 24*DISK_SECTOR

dsdd_dir_file_linking_data:
        DW          1*DISK_TRACK + 6*DISK_SECTOR
        DW          1*DISK_TRACK + 7*DISK_SECTOR
        DW          1*DISK_TRACK + 8*DISK_SECTOR
        DW          1*DISK_TRACK + 9*DISK_SECTOR
        DW          1*DISK_TRACK + 10*DISK_SECTOR
        DW          1*DISK_TRACK + 11*DISK_SECTOR
        DW          1*DISK_TRACK + 12*DISK_SECTOR
        DW          1*DISK_TRACK + 13*DISK_SECTOR
        DW          1*DISK_TRACK + 14*DISK_SECTOR
        DW          1*DISK_TRACK + 15*DISK_SECTOR
        DW          1*DISK_TRACK + 16*DISK_SECTOR
        DW          1*DISK_TRACK + 17*DISK_SECTOR
        DW          1*DISK_TRACK + 18*DISK_SECTOR
        DW          1*DISK_TRACK + 19*DISK_SECTOR
        DW          1*DISK_TRACK + 20*DISK_SECTOR
        DW          1*DISK_TRACK + 21*DISK_SECTOR
        DW          1*DISK_TRACK + 22*DISK_SECTOR
        DW          1*DISK_TRACK + 23*DISK_SECTOR
        DW          1*DISK_TRACK + 24*DISK_SECTOR
        DW          1*DISK_TRACK + 25*DISK_SECTOR

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

directory_iterator:
        DB          FALSE
        DB          0
        DW          dir_file_linking_block_buffer
        DW          dir_file_data_buffer
        DW          00000H
        DW          00000H
        DW          0*DISK_TRACK + 0*DISK_SECTOR

SRC_FILE_FCB:
        DB          5
        DB          FM_NONE
        DW          0
        DW          0
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
        DW          src_file_linking_block

DEST_FILE_FCB:
        DB          5
        DB          FM_NONE
        DW          0
        DW          0
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
        DW          dest_file_linking_block


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Initialization
;//
;//////////////////////////////////////////////////////////////////////////////

start:
        ;
        ; Set default disk drive to :D0:, as well as defaut system drive
        ;
        XRA         A
        STA         drive_number
        STA         user_option_flag
        LDA         SYSDRV_NR
        STA         sys_drive_number
        LDA         SYSDRV_TYPE
        ANA         A
        JM          defaults_ready
        MVI         A,'F'
        STA         sys_drive_type
defaults_ready:
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
        ; Verify the drive type and take action accordingly
        ;
        LDA         drive_type
        CPI         'F'
        JZ          use_sssd_drive
        CPI         'D'
        JZ          use_dsdd_drive
        JMP         invalid_drive


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Format single-sided TOS disk
;//
;//////////////////////////////////////////////////////////////////////////////

use_sssd_drive:
        ;
        ; Parse disk label from command line args
        ;
        LDA         input_char
        LXI         D,intel_name_str
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
        LXI         D,intel_name_str
        MVI         C,9
        CALL        copy_memory
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
        MVI         B,128
        CALL        clear_data_buffer
        LDA         drive_number
        LXI         H,intel_name_str
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
        MVI         B,128
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
        MVI         B,128
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
        MVI         B,128
        CALL        clear_data_buffer
        LXI         B,2*DISK_TRACK + 3*DISK_SECTOR
        LXI         H,data_buffer
        LDA         drive_number
        CALL        DSWRW
        RC
        ;
        ; Write new errorfile data to disk
        ;
        LXI         H,f_errorfile_data
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
        MVI         B,128
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
        JNZ         non_system_disk_done
        LDA         sys_drive_type
        CPI         'F'
        JNZ         d_transfer_system


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: System transfer from single-sided TOS disk
;//
;//////////////////////////////////////////////////////////////////////////////

f_transfer_system:
        ;
        ; Set up buffer
        ;
        LXI         H,program_end
        SHLD        sys_file_buffer_ptr
        CALL        set_sys_file_buffer_end
        ;
        ; Print copying system status message
        ;
        LXI         D,copying_system_str
        LHLD        CO_FCB
        CALL        PUT
        RC


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
        JC          no_more_files
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
        ; Flush remaining bytes of file entry
        ;
        MVI         B,5
        LXI         D,scratchpad_ram
        CALL        GETBIN
        JC          operation_aborted
        ;
        ; Check file attributes for sys file and not direct-access/format file
        ;
        LDA         file_attributes
        ANI         ATTR_S_DSDD
        JZ          check_next_intel_file
        LDA         file_attributes
        ANI         ATTR_X_DSDD
        JNZ         check_next_intel_file
        LDA         file_attributes + 002H
        ANI         ATTR_F_DSDD
        JNZ         check_next_intel_file

        ;
        ; Set up the rest of source file FCB
        ;
        MVI         A,1
        STA         SRC_FILE_FCB + FCB_DRVFMT
        XRA         A
        STA         SRC_FILE_FCB + FCB_DEVTYP
        ;
        ; Set up source file-control-block device drivers
        ;
        LHLD        TABIN_PTR
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
        ; Copy file
        ;
        CALL        copy_file
        JC          operation_aborted
        CALL        set_file_copy_attributes
        JMP         check_next_intel_file


;//////////////////////////////////////

no_more_files:
        ANA         A
        STC
        JNZ         operation_aborted
        ;
        ; Format of system disk complete, print status and quit
        ;
        LHLD        CO_FCB
        LXI         D,format_sys_disk_ok_str
        CALL        PUT
        RC
        JMP         quit_program


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Format double-sided TOS disk
;//
;//////////////////////////////////////////////////////////////////////////////

use_dsdd_drive:
        ;
        ; Parse disk label from command line args
        ;
        LDA         input_char
        LXI         D,tos_name_str
        CALL        DFILENAME
        RC
        STA         input_char
        CPI         CR
        JZ          d_valid_option
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
        JZ          d_valid_option
        CPI         'S'
        JNZ         invalid_cli_args
d_valid_option:
        STA         user_option_flag
        ;
        ; Check if there's already a TOS-II double-sided filesystem on the disk
        ;
        LXI         B,1*DISK_TRACK + 26*DISK_SECTOR
        LXI         H,data_buffer
        LDA         drive_number
        CALL        DDSRDW
        RC
        LXI         H,data_buffer + 011H
        LXI         D,tos_dsdd_signature
        MVI         C,8
d_verify_format_signature_loop:
        LDAX        D
        CMP         M
        JNZ         d_prompt_done
        INX         H
        INX         D
        DCR         C
        JNZ         d_verify_format_signature_loop
        ;
        ; If filesystem already exists, prompt user if they want to overwrite
        ;
        LXI         D,rewrite_filesys_prompt_str
        LHLD        CO_FCB
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
d_prompt_done:
        ;
        ; Check user option
        ;
        LDA         user_option_flag
        CPI         'L'
        JZ          d_update_label
        CPI         'S'
        JNZ         d_write_new_filesys
        ;
        ; Make sure to not format system drive if system-transfer switch is set
        ;
        CALL        verify_valid_system_drive
        JZ          same_drive_not_supported
        JMP         d_write_new_filesys


;//////////////////////////////////////

d_update_label:
        ;
        ; Overwrite old label with new label
        ;
        LXI         H,data_buffer
        LXI         D,tos_name_str
        MVI         C,13
d_copy_next_label_char:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         C
        JNZ         d_copy_next_label_char
        ;
        ; Write changes back to disk
        ;
        LXI         H,data_buffer
        LXI         B,1*DISK_TRACK + 26*DISK_SECTOR
        LDA         drive_number
        CALL        DDSWRW
        RC
        ;
        ; Print status and quit program
        ;
        LXI         D,label_changed_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

d_write_new_filesys:
        ;
        ; Write new mapfile data to disk
        ;
        MVI         B,0
        CALL        clear_data_buffer
        LXI         H,data_buffer
        MVI         M,0FFH
        INX         H
        MVI         M,0FFH
        INX         H
        MVI         M,0FFH
        LXI         H,data_buffer
        LXI         B,1*DISK_TRACK + 1*DISK_SECTOR
        LDA         drive_number
        CALL        DDSWRW
        RC
        MVI         B,0
        CALL        clear_data_buffer
        LXI         H,data_buffer
        LXI         B,1*DISK_TRACK + 2*DISK_SECTOR
        LDA         drive_number
        CALL        DDSWRW
        RC
        ;
        ; Write new error file link block to disk
        ;
        LXI         D,data_buffer
        LXI         H,dsdd_err_file_linking_data
        MVI         C,24*2
        CALL        copy_memory
        LXI         H,data_buffer
        LXI         B,1*DISK_TRACK + 3*DISK_SECTOR
        LDA         drive_number
        CALL        DDSWRW
        RC
        ;
        ; Write new directory file link block to disk
        ;
        MVI         B,0
        CALL        clear_data_buffer
        LXI         D,data_buffer
        LXI         H,dsdd_dir_file_linking_data
        MVI         C,20*2
        CALL        copy_memory
        LXI         H,data_buffer
        LXI         B,1*DISK_TRACK + 4*DISK_SECTOR
        LDA         drive_number
        CALL        DDSWRW
        RC
        MVI         B,0
        CALL        clear_data_buffer
        LXI         H,data_buffer
        LXI         B,1*DISK_TRACK + 5*DISK_SECTOR
        LDA         drive_number
        CALL        DDSWRW
        RC
        ;
        ; Write new directory file data to disk
        ;
        LXI         H,data_buffer
        LXI         D,020H
        MVI         B,8
d_setup_dir_block_loop:
        MVI         M,07FH
        DAD         D
        DCR         B
        JNZ         d_setup_dir_block_loop
        LXI         B,1*DISK_TRACK + 6*DISK_SECTOR
d_write_next_dir_block:
        LXI         H,data_buffer
        LDA         drive_number
        CALL        DDSWRW
        RC
        INR         C
        MOV         A,C
        CPI         26
        JC          d_write_next_dir_block
        ;
        ; Write new label file data to disk
        ;
        MVI         B,0
        CALL        clear_data_buffer
        LXI         H,tos_name_str
        LXI         D,data_buffer
        MVI         C,13
        CALL        copy_memory
        LXI         D,data_buffer + 011H
        LXI         H,tos_dsdd_signature
        MVI         C,8
        CALL        copy_memory
        LXI         H,data_buffer
        LXI         B,1*DISK_TRACK + 26*DISK_SECTOR
        LDA         drive_number
        CALL        DDSWRW
        RC
        ;
        ; Write new errorfile data to disk
        ;
        LXI         H,d_errorfile_data
        LXI         B,(1 + DISK_HEAD_1)*DISK_TRACK + 1*DISK_SECTOR
        LXI         D,256
d_write_next_err_block:
        LDA         drive_number
        CALL        DDSWRW
        RC
        DAD         D
        INR         C
        MOV         A,C
        CPI         25
        JC          d_write_next_err_block
        ;
        ; Transfer system if system flag set
        ;
        LDA         user_option_flag
        CPI         'S'
        JNZ         non_system_disk_done
        LDA         sys_drive_type
        CPI         'D'
        JNZ         f_transfer_system


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: System transfer from double-sided TOS disk
;//
;//////////////////////////////////////////////////////////////////////////////

d_transfer_system:
        ;
        ; Set up buffer
        ;
        LXI         H,program_end
        SHLD        sys_file_buffer_ptr
        CALL        set_sys_file_buffer_end
        ;
        ; Print copying system status message
        ;
        LXI         D,copying_system_str
        LHLD        CO_FCB
        CALL        PUT
        RC


;//////////////////////////////////////

        ;
        ; Prepare to copy system files to formated disk
        ;
        XRA         A
        STA         directory_iterator
        LDA         sys_drive_number
        STA         directory_iterator + 001H
        ;
        ; Scan through directory for files with the system attribute set
        ;
d_check_next_file:
        ;
        ; Look up next file in directory
        ;
        LXI         H,directory_iterator
        CALL        DNEXTFILE
        JC          d_no_more_files
        SHLD        file_entry_ptr
        ;
        ; Check status byte of file entry
        ;
        MOV         A,M
        ANA         A
        JNZ         d_check_next_file
        CPI         07FH
        JZ          d_transfer_from_disk_complete
        ;
        ; Get file attribute of source file
        ;
        LXI         D,00EH
        DAD         D
        LXI         D,file_attributes
        MVI         C,3
        CALL        copy_memory
        ;
        ; Check file attributes for sys file and not direct-access/format file
        ;
        LDA         file_attributes
        ANI         ATTR_S_DSDD
        JZ          d_check_next_file
        LDA         file_attributes
        ANI         ATTR_X_DSDD
        JNZ         d_check_next_file
        LDA         file_attributes + 002H
        ANI         ATTR_F_DSDD
        JNZ         d_check_next_file
        ;
        ; Read filename from file entry into source file file-control-block
        ;
        LHLD        file_entry_ptr
        INX         H
        LXI         D,SRC_FILE_FCB + FCB_FNAME
        MVI         C,6
        CALL        copy_memory
        LHLD        file_entry_ptr
        LXI         D,009H
        DAD         D
        LXI         D,SRC_FILE_FCB + FCB_FEXT
        MVI         C,3
        CALL        copy_memory
        ;
        ; Set up the rest of source file FCB
        ;
        MVI         A,1 + 008H
        STA         SRC_FILE_FCB + FCB_DRVFMT
        MVI         A,1
        STA         SRC_FILE_FCB + FCB_DEVTYP
        ;
        ; Set up source file-control-block device drivers
        ;
        LHLD        TABTD_PTR
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
        LXI         H,256
        SHLD        SRC_FILE_FCB + FCB_BUFLEN
        LDA         sys_drive_number
        STA         SRC_FILE_FCB + FCB_DRVNR
        ;
        ; Copy file
        ;
        CALL        copy_file
        JC          operation_aborted
        CALL        set_file_copy_attributes
        JMP         d_check_next_file


;//////////////////////////////////////

d_no_more_files:
        ANA         A
        STC
        JNZ         operation_aborted
d_transfer_from_disk_complete:
        LHLD        CO_FCB
        LXI         D,format_sys_disk_ok_str
        CALL        PUT
        RC
        JMP         quit_program


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program: Termination
;//
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

invalid_drive:
        LXI         D,invalid_drive_str
        JMP         print_and_quit


;//////////////////////////////////////

invalid_cli_args:
        LXI         D,invalid_cli_args_str
        JMP         print_and_quit


;//////////////////////////////////////

same_drive_not_supported:
        LXI         D,same_sys_disk_str
        JMP         print_and_quit


;//////////////////////////////////////

label_not_found:
        LXI         D,label_not_found_str

;//////////////////////////////////////

print_and_quit:
        LHLD        CO_FCB
        CALL        PUT
        RC
        JMP         quit_program


;//////////////////////////////////////

non_system_disk_done:
        ;
        ; Format of non-system disk complete, print status and quit
        ;
        LXI         D,non_sys_disk_str
        LHLD        CO_FCB
        CALL        PUT
        RC


;//////////////////////////////////////

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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Copy one particular file from the current source disk to target disk
        ;
copy_file:
        ;
        ; Check destination drive type
        ;
        LDA         drive_type
        CPI         'D'
        JZ          d_copy_file
        ;
        ; Set up destination file-control-block for single-sided floppy disk
        ;
        MVI         A,1
        STA         DEST_FILE_FCB + FCB_DRVFMT
        XRA         A
        STA         DEST_FILE_FCB + FCB_DEVTYP
        LXI         H,128
        SHLD        DEST_FILE_FCB + FCB_BUFLEN
        LHLD        TABIN_PTR
        JMP         dest_fcb_type_ready

d_copy_file:
        ;
        ; Set up destination file-control-block for double-sided floppy disk
        ;
        MVI         A,1 + 008H
        STA         DEST_FILE_FCB + FCB_DRVFMT
        MVI         A,1
        STA         DEST_FILE_FCB + FCB_DEVTYP
        LXI         H,256
        SHLD        DEST_FILE_FCB + FCB_BUFLEN
        LHLD        TABTD_PTR
dest_fcb_type_ready:
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
        ; Save filename needed for setting attributes later
        ;
        LXI         H,SRC_FILE_FCB + FCB_FNAME
        LXI         D,intel_name_str
        MVI         C,9
        CALL        copy_memory
        LXI         H,SRC_FILE_FCB + FCB_FNAME
        LXI         D,tos_name_str
        MVI         C,6
        CALL        copy_memory
        XRA         A
        STAX        D
        INX         D
        STAX        D
        INX         D
        MVI         C,3
        CALL        copy_memory
        XRA         A
        STAX        D
        INX         D
        STAX        D
        ;
        ; Open source file for reading
        ;
        LXI         H,SRC_FILE_FCB
        MVI         A,FM_INPUT
        CALL        OPEN
        JC          copy_file_aborted
        ;
        ; Open destination file for writing
        ;
        LXI         H,DEST_FILE_FCB
        MVI         A,FM_OUTPUT
        CALL        OPEN
        JC          copy_file_aborted
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


;//////////////////////////////////////

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


;//////////////////////////////////////

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
        JNZ         copy_file_error
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
        JC          copy_file_error
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
        JC          copy_file_aborted
        LXI         H,DEST_FILE_FCB
        CALL        CLOSE
        JC          copy_file_aborted
        RET


;//////////////////////////////////////

copy_file_aborted:
        INX         SP
        INX         SP
        JMP         operation_aborted


;//////////////////////////////////////

copy_file_error:
        INX         SP
        INX         SP
        JMP         copy_error


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set attributes of a copied file
        ;
set_file_copy_attributes:
        ;
        ; Check destination drive type to update attributes
        ;
        LDA         drive_type
        CPI         'F'
        JZ          set_single_sided_attributes


;//////////////////////////////////////

        ;
        ; Look up file entry of copy
        ;
        LDA         drive_number
        LXI         H,tos_name_str
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
        LDA         drive_number
        CALL        DDSWRW
        JC          operation_aborted
        RET


;//////////////////////////////////////

set_single_sided_attributes:
        ;
        ; Look up floppy file entry for the file copy
        ;
        LDA         drive_number
        LXI         H,intel_name_str
        CALL        LOCDIR
        JC          operation_aborted
        ;
        ; Set attributes of copy to the same as souce file
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
        LDA         drive_number
        CALL        DSWRW
        JC          operation_aborted
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
        SUB         A
clear_next_byte:
        MOV         M,A
        INX         H
        DCR         B
        JNZ         clear_next_byte
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Subtract program end from TOS start to get buffer length
        ;
set_sys_file_buffer_end:
        LXI         D,program_end
        MOV         A,E
        CMA
        MOV         E,A
        MOV         A,D
        CMA
        MOV         D,A
        INX         D
        LHLD        BUFLIM
        DAD         D
        SHLD        sys_file_buffer_size
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
        DB          'SYSTEM DISKETTE FORMATTING ON SINGLE UNIT NOT ALLOWED',CR
copying_system_str:
        DB          'COPYING SYSTEM FILES',CR
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

f_errorfile_data:
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
        DB          085H,'COM/FNAM LENGTH OUT OF RANGE   '
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
        DB          085H,'DISKETTE CTL.BLK CH.SUM ERROR  '
        DB          085H,'NON RELOCATABLE FORMAT         '
        DB          085H,'UNDEFINED EXTERNALS            '
        DB          085H,'PROM CHECKSUM ERROR            '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE    '
        DB          085H,'IMPROPER DISKETTE FORMAT       '

d_errorfile_data:
        DB          085H,'END OF FILE                                                    '
        DB          085H,'SECTOR MISSING                                                 '
        DB          085H,'CRC ERROR                                                      '
        DB          085H,'TIMING ERROR READ/WRITE XFER                                   '
        DB          085H,'NO ADDRESS MARK                                                '
        DB          085H,'DISKETTE OPERATION TIMEOUT                                     '
        DB          085H,'TIMING ERROR IN READ OPERATION                                 '
        DB          085H,'BUSY-BIT TIMEOUT                                               '
        DB          085H,'DRIVE NOT READY                                                '
        DB          085H,'NAME NOT IN DIR AND DIR FULL                                   '
        DB          085H,'NAME NOT IN DIRECTORY                                          '
        DB          085H,'PROGRAM NAME NOT FOUND                                         '
        DB          085H,'ILLEGAL DIRECTORY ENTRY                                        '
        DB          085H,'DIRECTORY BLOCK ERROR - LOAD                                   '
        DB          085H,'DATA LENGTH ERROR DURING LOAD                                  '
        DB          085H,'DISKETTE MAP MISSING                                           '
        DB          085H,'NON-VALID DISKETTE COMMAND                                     '
        DB          085H,'IMPROPER UNIT SPECIFICATION                                    '
        DB          085H,'CONVERSION TABLE MISSING                                       '
        DB          085H,'DRIVE NUMBER NOT 0-3                                           '
        DB          085H,'FILE PROTECTED                                                 '
        DB          085H,'DE-EDIT NONHEX DIGIT (0-9,A-F)                                 '
        DB          085H,'INPUT FROM NON-INPUT FILE                                      '
        DB          085H,'READ AFTER END-OF-FILE                                         '
        DB          085H,'OUTPUT TO NON-OUTPUT FILE                                      '
        DB          085H,'UNASSIGNED DEVICE                                              '
        DB          085H,'UNKNOWN DEVICE TYPE                                            '
        DB          085H,'COM/FNAM NOT LETTER/DIGIT 1ST                                  '
        DB          085H,'COMMAND OR FILE NAME LENGTH OUT OF RANGE                       '
        DB          085H,'COMMAND UNIT NOT :FN: OR :DN:                                  '
        DB          085H,'TOS NOT LOADED                                                 '
        DB          085H,'COMMAND NOT TERMINATED PROPERLY                                '
        DB          085H,'DELETED DATA RECORD                                            '
        DB          085H,'LOGICAL UNIT NAME UNKNOWN                                      '
        DB          085H,'WRITE ON NON-BLOCK FILE                                        '
        DB          085H,'WRITE/READ MISSING IN CTL-BLK                                  '
        DB          085H,'READ ON FILETYPE OTHER THAN 4,5                                '
        DB          085H,'LINE OVERFLOW                                                  '
        DB          085H,'IMPROPER PARAMETER                                             '
        DB          085H,'FILE ALREADY OPEN                                              '
        DB          085H,'NO OPEN-ROUTINE IN CTL-BLK                                     '
        DB          085H,'CLOSE ON CLOSED FILE                                           '
        DB          085H,'NO CLOSE-ROUTINE IN CTL-BLK                                    '
        DB          085H,'BUFFER CHAIN DESTROYED                                         '
        DB          085H,'BUFFER HEADER IMPROPER                                         '
        DB          085H,'IMPROPER FILE DESIGNATOR                                       '
        DB          085H,'IMPROPER ASSIGNMENT FORMAT                                     '
        DB          085H,'NO ROOM ON DISKETTE                                            '
        DB          085H,'ILLEGAL BUFFER TYPE                                            '
        DB          085H,'NON-EXISTENT FILE NAME - INPUT                                 '
        DB          085H,'OUTPUT FILE ALREADY ON DISKETTE                                '
        DB          085H,'NO ROOM ON DISKETTE                                            '
        DB          085H,'IBM FILENAME > 8 CHARACTERS                                    '
        DB          085H,'TRACK NUMBER > 76                                              '
        DB          085H,'SECTOR NUMBER = 0 OR > 26                                      '
        DB          085H,'BUFFER ADDRESS ZERO                                            '
        DB          085H,'ROUTINE NOT AVAILABLE                                          '
        DB          085H,'DISKETTE CONTROL BLOCK CHECKSUM ERROR                          '
        DB          085H,'NON RELOCATABLE FORMAT                                         '
        DB          085H,'UNDEFINED EXTERNALS                                            '
        DB          085H,'PROM CHECKSUM ERROR                                            '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'UNKNOWN TOS21 ERROR MESSAGE                                    '
        DB          085H,'IMPROPER DISKETTE FORMAT                                       '
        DB          085H,'END-OF-BLOCK (B AND J FILES)                                   '
        DB          085H,'INVALID RANDOM ACCESS                                          '
        DB          085H,'OUTPUT FILE NOT ON DISKETTE                                    '

program_end:
