;//////////////////////////////////////////////////////////////////////////////
;//
;//     FORMAT - Initialize new TOS filesystem (soft-formating)
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<labelname>[,S]
;//
;//                 Tn          Drive type and number to format, default :F0:
;//                 labelname   Label of new disk
;//                 S           Make bootable TOS system disk/tape switch
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
;//         If the S argument is given, any system files from drive :F0: will
;//         be looked up, but since the S argument is only partially implemented in
;//         this version no actual copying of these files will take place.
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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Flag values
;
FALSE       EQU     0           ; Boolean False

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

;
; XMON system calls
;
CCAL        EQU     00091H      ; Reset tape cartridge
CUN         EQU     000A6H      ; Rewind and unload tape cartridge
CBWRW       EQU     000B2H      ; Write data to tape cartridge with wait
CBTMW       EQU     000B8H      ; Write tape mark to tape cartridge with wait

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
DCALW       EQU     0FD70H      ; Reset disk drive with wait
DSRDW       EQU     0FD73H      ; Read from disk with wait
DSWRW       EQU     0FD76H      ; Write to disk with wait
LOCDIR      EQU     0FD85H      ; Look up filetable entry of filename on disk
FILENAME    EQU     0FDCDH      ; Input TOS filename

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
ATTR_F      EQU     080H        ; Format file


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
        DB          'SYSTEM DISKETTE FORMATTING UNIT=0',CR

sys_transfer_dir_block:
        DW          0*DISK_TRACK + 0*DISK_SECTOR
sys_transfer_file_entry_ptr:
        DW          00000H
sys_transfer_file_entry_countdown:
        DB          0
drive_number:
        DB          0
system_disk_flag:
        DB          FALSE
        DB          000H

intel_dir_filename_str:
        DB          'ISIS',NULL,NULL
        DB          'DIR'
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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

invalid_drive:
        LXI         D,invalid_drive_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

invalid_cli_args:
        LXI         D,invalid_cli_args_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

same_drive_not_supported:
        LXI         D,same_sys_disk_str
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

quit_program:
        ANA         A
        RET


;//////////////////////////////////////

beginning:
        ;
        ; Set default disk drive to drive :F0:
        ;
        SUB         A
        STA         drive_number
        STA         system_disk_flag
        ;
        ; Parse drive designator from command line args, if any
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         use_intel_drive
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'F'
        JNZ         check_other_drive_types
        CALL        INCHAR
        RC
        CPI         '0'
        JM          invalid_drive
        CPI         '4'
        JP          invalid_drive
        SUI         '0'
        STA         drive_number
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
use_intel_drive:
        ;
        ; Parse disk label from command line args
        ;
        LXI         D,intel_label_str
        CALL        FILENAME
        RC
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
        CPI         'S'
        JNZ         invalid_cli_args
        STA         system_disk_flag
        ;
        ; Make sure to not format system drive if system-transfer switch is set
        ;
        LDA         drive_number
        CPI         0
        JZ          same_drive_not_supported
        ;
        ; Make sure there is no more command line args after this
        ;
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         invalid_cli_args


;//////////////////////////////////////

format_intel_disk:
        ;
        ; Check if there is already an Intel filesystem on the disk
        ;
        LXI         H,intel_dir_filename_str
        LDA         drive_number
        CALL        LOCDIR
        JC          write_new_intel_filesys
        MOV         A,M
        CPI         000H
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
        CPI         'Y'
        JNZ         quit_program
        LHLD        CI_FCB
        CALL        INCHAR
        RC
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
        ; Transfer system if system flag set
        ;
        LDA         system_disk_flag
        ANA         A
        JNZ         transfer_intel_system
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
        LDA         system_disk_flag
        ANA         A
        JNZ         transfer_intel_system
        ;
        ; Format of non-system disk complete, print status and quit
        ;
        LHLD        CO_FCB
        LXI         D,non_sys_disk_str
        CALL        PUT
        RET


;//////////////////////////////////////

transfer_intel_system:
        ;
        ; Begin transfer by pointing to block before start of directory
        ;
        LXI         H,1*DISK_TRACK + 1*DISK_SECTOR
        SHLD        sys_transfer_dir_block
        ;
        ; Scan through directory for files with the system attribute set
        ;
check_next_intel_dir_block:
        ;
        ; Advance block address and read next system disk directory block
        ;
        LHLD        sys_transfer_dir_block
        INX         H
        SHLD        sys_transfer_dir_block
        MOV         B,H
        MOV         C,L
        MOV         A,C
        CPI         27
        JZ          system_transfer_complete
        LXI         H,data_buffer
        SUB         A
        CALL        DSRDW
        RC
        ;
        ; Set up pointers to check all file entries in block
        ;
        LXI         H,data_buffer
        SHLD        sys_transfer_file_entry_ptr
        MVI         A,8
        STA         sys_transfer_file_entry_countdown
        ;
        ; Transfer file if system-attribute is set
        ;
check_intel_file:
        ;
        ; Check attributes of file
        ;
        LXI         D,00AH
        DAD         D
        MOV         A,M
        ANI         ATTR_S
        JNZ         non_system_intel_file
        ;
        ; NOTE: Copying of system files is not implemented in this version
        ;
check_next_intel_file:
        ;
        ; Advance to next file entry in block
        ;
        LHLD        sys_transfer_file_entry_ptr
        LXI         D,010H
        DAD         D
        SHLD        sys_transfer_file_entry_ptr
        LDA         sys_transfer_file_entry_countdown
        DCR         A
        STA         sys_transfer_file_entry_countdown
        JNZ         check_intel_file
        JMP         check_next_intel_dir_block

non_system_intel_file:
        JMP         check_next_intel_file

system_transfer_complete:
        ;
        ; Format of system disk complete, print status and quit
        ;
        LHLD        CO_FCB
        LXI         D,format_sys_disk_ok_str
        CALL        PUT
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
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
;//     Main program - Tape
;//
;//////////////////////////////////////////////////////////////////////////////

check_other_drive_types:
        ;
        ; Verify non-intel drive designator from command line args
        ;
        CPI         'M'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        CPI         '0'
        JM          invalid_drive
        CPI         '4'
        JP          invalid_drive
        SUI         '0'
        STA         drive_number
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        ;
        ; Parse tape label from command line args
        ;
        LXI         D,tape_label_str
        CALL        FILENAME
        RC
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
        ; Tape formatting complete, rewind and unload tape
        ;
        LDA         drive_number
        CALL        CUN
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     ISIS.ERR data
;//
;//////////////////////////////////////////////////////////////////////////////

errorfile_data:
        DB          085H,'**********END OF FILE**********'
        DB          085H,'********SECTOR MISSING*********'
        DB          085H,'***********CRC ERROR***********'
        DB          085H,'TIMING ERROR READ/WRITE XFER***'
        DB          085H,'********NO ADDRESS MARK********'
        DB          085H,'***DISKETTE OPERATION TIMEOUT**'
        DB          085H,'*TIMING ERROR IN READ OPERATION'
        DB          085H,'********BUSY-BIT TIMEOUT*******'
        DB          085H,'********DRIVE NOT READY********'
        DB          085H,'**NAME NOT IN DIR AND DIR FULL*'
        DB          085H,'*****NAME NOT IN DIRECTORY*****'
        DB          085H,'*****PROGRAM NAME NOT FOUND****'
        DB          085H,'*****ILLEGAL DIRECTORY ENTRY***'
        DB          085H,'**DIRECTORY BLOCK ERROR - LOAD*'
        DB          085H,'*DATA LENGTH ERROR DURING LOAD*'
        DB          085H,'******DISKETTE MAP MISSING*****'
        DB          085H,'***NON-VALID DISKETTE COMMAND**'
        DB          085H,'**IMPROPER UNIT SPECIFICATION**'
        DB          085H,'****CONVERSION TABLE MISSING***'
        DB          085H,'******DRIVE NUMBER NOT 0-3*****'
        DB          085H,'-----UNUSED--------------------'
        DB          085H,'*DE-EDIT NONHEX DIGIT (0-9,A-F)'
        DB          085H,'***INPUT FROM NON-INPUT FILE***'
        DB          085H,'*****READ AFTER END-OF-FILE****'
        DB          085H,'***OUTPUT TO NON-OUTPUT FILE***'
        DB          085H,'*******UNASSIGNED DEVICE*******'
        DB          085H,'******UNKNOWN DEVICE TYPE******'
        DB          085H,'*COM/FNAM NOT LETTER/DIGIT 1ST*'
        DB          085H,'*COM/FNAM > 6 OR EXT > 3 CHARS*'
        DB          085H,'COMMAND UNIT NOT :FN: OR :MN:  '
        DB          085H,'********TOS NOT LOADED*********'
        DB          085H,'COMMAND NOT TERMINATED PROPERLY'
        DB          085H,'******DELETED DATA RECORD******'
        DB          085H,'***LOGICAL UNIT NAME UNKNOWN***'
        DB          085H,'****WRITE ON NON-BLOCK FILE****'
        DB          085H,'*WRITE/READ MISSING IN CTL-BLK*'
        DB          085H,'READ ON FILETYPE OTHER THAN 4,5'
        DB          085H,'*********LINE OVERFLOW*********'
        DB          085H,'-----UNUSED--------------------'
        DB          085H,'*******FILE ALREADY OPEN*******'
        DB          085H,'***NO OPEN-ROUTINE IN CTL-BLK**'
        DB          085H,'******CLOSE ON CLOSED FILE*****'
        DB          085H,'**NO CLOSE-ROUTINE IN CTL-BLK**'
        DB          085H,'*****BUFFER CHAIN DESTROYED****'
        DB          085H,'*****BUFFER HEADER IMPROPER****'
        DB          085H,'****IMPROPER FILE DESIGNATOR***'
        DB          085H,'***IMPROPER ASSIGNMENT FORMAT**'
        DB          085H,'******NO ROOM ON DISKETTE******'
        DB          085H,'-----UNUSED-----------30H------'
        DB          085H,'*NON-EXISTENT FILE NAME - INPUT'
        DB          085H,'OUTPUT FILE ALREADY ON DISKETTE'
        DB          085H,'******NO ROOM ON DISKETTE******'
        DB          085H,'FILENAME > 8 CHARACTERS--------'
        DB          085H,'TRACK NUMBER > 76--------------'
        DB          085H,'SECTOR NUMBER = 0 OR > 26------'
        DB          085H,'BUFFER ADDRESS ZERO------------'
        DB          085H,'ROUTINE NOT AVAILABLE----------'
        DB          085H,':MN: DIR BLOCK NOT 32 BYTES----'
        DB          085H,'VOLUME HEADER MISSING----------'
        DB          085H,'DIRECTORY BLOCK ERROR----------'
        DB          085H,'OUTPUT FILE ALREADY ON CARTR.--'
        DB          085H,'NO MORE SPACE ON CARTRIDGE-----'
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
        DB          085H,'-----UNUSED-----------59H------'
        DB          085H,'-----UNUSED-----------5AH------'
        DB          085H,'-----UNUSED-----------5BH------'
        DB          085H,'-----UNUSED-----------5CH------'
        DB          085H,'-----UNUSED-----------5DH------'
        DB          085H,'-----UNUSED-----------5EH------'
        DB          085H,'-----UNUSED-----------5FH------'
        DB          085H,'-----UNUSED-----------60H------'
        DB          085H,'-----UNUSED-----------61H------'
        DB          085H,'-----UNUSED-----------62H------'
        DB          085H,'-----UNUSED-----------63H------'
