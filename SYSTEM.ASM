;//////////////////////////////////////////////////////////////////////////////
;//
;//     SYSTEM - Tandberg Operating System kernel
;//
;//         The main system kernel of the Tandberg Operating System. This contains
;//         several modules for handling both the user-interface of TOS21, file IO,
;//         abstraction layers for various devices and drive types, as well as
;//         providing programs with a system API for accessing facilities in the
;//         operating system.
;//
;//         TOS21 operates on top of XMON, which is the ROM hardware abstraction-
;//         layer of the Tandberg TDV-2100 series of computers.
;//
;//
;//         TOS21 consist of the following modules:
;//
;//             TOS command line
;//                 MAIN    TOS startup and main command line program
;//                 COMI    Command line interpreter
;//                 ASSI    Abstract-file assignement interpreter
;//                 PHYS    Dynamic file control block generator
;//                 BUFR    TOS dynamic buffer management
;//
;//             General file IO
;//                 IO      Common functions for file IO modules
;//                 GET     General file input
;//                 PUT     General file output
;//                 OPEN    Open general file
;//                 CLOS    Close general file
;//
;//             Special file handling
;//                 READ    Read next from line-buffered or block-device file
;//                 WRIT    Write block to block-device file
;//                 INTEL   Intel floppy disk device driver
;//                 IBM     IBM 3740 floppy disk device driver
;//                 CART    Tandberg tape cartridge device driver
;//                 CTAB    Data-tables for EBCDIC-ASCII translation
;//
;//             TOS API and other system facilities
;//                 JTAB    TOS API jump-tables and datastructures
;//                 EDIT    General purpose string-conversion functions
;//                 TIME    Programmable one-shot timer
;//
;//
;//         Changelog:
;//
;//             v1.3: Entry at 0xE000
;//
;//                 -> First version I have
;//                 -> Pre-release version for v1.4
;//                 -> Experimental IBM floppy disk support
;//
;//             v1.4: Entry at 0xE000
;//
;//                 -> Adds device-files :CE: and :RE:
;//                 -> A few bugs are fixed, in particular memory-leaks and
;//                    the EBCDIC translation tables
;//                 -> Some new bugs are introduced, for instance the system
;//                    crashes after writing a file to tape
;//
;//             v1.5a: Entry at 0xDC00
;//
;//                 -> Adds batch-file flag for automatic line-buffered batch-file
;//                    assignment with echo to console
;//                 -> Experimental BLOCKLINE file mode for IBM disks added, along
;//                    with its drive types :Bn: and :Jn:
;//                 -> New PHYSINT system API call for dynamically generating file
;//                    control blocks from file-handle strings added
;//                 -> Fixes some bugs, including the crash from closing a tape
;//                    output file
;//                 -> Adds a few new bugs, in particular for certain uses of the
;//                    new PHYSINT functionality
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; Flag values
;
TRUE        EQU     1           ; Boolean True

;
; ASCII control characters
;
NULL        EQU     000H        ; Null character
ETX         EQU     003H        ; End of text
ERLIN       EQU     004H        ; Erase current line
BEL         EQU     007H        ; Bell (short beep)
CURL        EQU     008H        ; Cursor left
HTAB        EQU     009H        ; Horizontal tabulation
LF          EQU     00AH        ; Line Feed
ROLUP       EQU     00CH        ; Scroll screen up one row
CR          EQU     00DH        ; Cartridge Return
ERPAG       EQU     019H        ; Clear screen
DEL         EQU     07FH        ; Delete

;
; XMON constants
;
CURSOR_ROW  EQU     00100H      ; Multiplier for cursor row
CURSOR_COL  EQU     00001H      ; Multiplier for cursor column
DISK_TRACK  EQU     00100H      ; Multiplier for floppy disk track
DISK_SECTOR EQU     00001H      ; Multiplier for floppy disk sector

;
; XMON system calls
;
RESET       EQU     00000H      ; Reset XMON, can be used to trigger debugger
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
TTONC       EQU     00046H      ; Console output, without control character handling
CURSOR      EQU     00049H      ; Set console cursor position
XMON        EQU     0004CH      ; Run monitor
ERR         EQU     0004FH      ; Throw an error
PRNT        EQU     00052H      ; Printer port output
DTST        EQU     00055H      ; Test disk drive
DCAL        EQU     00058H      ; Reset disk drive
DSRD        EQU     0005BH      ; Read from disk
DSWR        EQU     0005EH      ; Write to disk
DSDL        EQU     00061H      ; Write deleted to disk
DSRDA       EQU     00064H      ; Read from disk and translate EBCDIC to ASCII
DSWRA       EQU     00067H      ; Translate ASCII to EBCDIC and write to disk
INDISP      EQU     0006AH      ; Read character at console cursor
DSWT        EQU     0006DH      ; Wait for floppy disk controller
DCALW       EQU     00070H      ; Reset disk drive with wait
DSRDW       EQU     00073H      ; Read from disk with wait
DSWRW       EQU     00076H      ; Write to disk with wait
DSDLW       EQU     00079H      ; Write deleted to disk with wait
DSRAW       EQU     0007CH      ; Read from disk with wait and translate EBCDIC to ASCII
DSWAW       EQU     0007FH      ; Translate ASCII to EBCDIC and write to disk with wait
RCVI        EQU     00082H      ; Main UART input
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
LOADD       EQU     00088H      ; Load and unpack file from floppy disk to memory
LINKD       EQU     0008BH      ; Load and unpack file from floppy disk to memory, and run it
CTST        EQU     0008EH      ; Test tape cartridge
CCAL        EQU     00091H      ; Reset tape cartridge
CBRD        EQU     00094H      ; Read data from tape cartridge
CBWR        EQU     00097H      ; Write data to tape cartridge
CBBS        EQU     0009AH      ; Backspace one block on tape cartridge
CBTM        EQU     0009DH      ; Write tape mark to tape cartridge
CBSF        EQU     000A0H      ; Search forward on tape cartridge
CBSB        EQU     000A3H      ; Search backwards on tape cartridge
CUN         EQU     000A6H      ; Rewind and unload tape cartridge
CRW         EQU     000A9H      ; Rewind tape cartridge with wait
CWT         EQU     000ACH      ; Wait for tape command complete
CBRDW       EQU     000AFH      ; Read data from tape cartridge with wait
CBWRW       EQU     000B2H      ; Write data to tape cartridge with wait
CBBSW       EQU     000B5H      ; Backspace one block on tape cartridge with wait
CBTMW       EQU     000B8H      ; Write tape mark to tape cartridge with wait
CBSFW       EQU     000BBH      ; Search forward on tape cartridge with wait
CBSBW       EQU     000BEH      ; Search backwards on tape cartridge with wait
CLOCDIR     EQU     000C1H      ; Look up filetable entry of filename on tape
CLOAD       EQU     000C4H      ; Load and unpack file from tape cartridge to memory
CLINK       EQU     000C7H      ; Load and unpack file from tape cartridge to memory, and run it
XMIO        EQU     000CAH      ; Main UART output
RD32        EQU     000CDH      ; Read next 32-byte block from tape cartridge
VERIFY      EQU     000D0H      ; Verify tape cartridge block type

;
; XMON and TOS system data
;
STACK       EQU     025BEH      ; TOS top of stack
BUF2        EQU     02600H      ; Sector data of last filesystem operation
BUF1        EQU     02680H      ; Additional sector data for filesysyem operation
CTLBLK      EQU     02710H      ; Most recent TOS file control block
CISAVE      EQU     0271BH      ; Pending TOS CI file assignement
COSAVE      EQU     0271DH      ; Pending TOS CO file assignement
ROLLSW      EQU     0271FH      ; Cursor line number if no hardware autoscroll
PSTART      EQU     02720H      ; Current program entry pointer
PRGNAM      EQU     02722H      ; TOS current program filename
DEBUG       EQU     0272DH      ; TOS debug flag
BUFLIM      EQU     0272EH      ; Lowest address of current TOS buffers
UNIT        EQU     02730H      ; Unit of last filesystem operation
TRK         EQU     02731H      ; Pointer to block address of next directory data block
NAME        EQU     02733H      ; Pointer to name of current file
MAP1        EQU     02739H      ; Block address of first half of mapfile data
MAP2        EQU     0273BH      ; Block address of last half of mapfile data
UNAM        EQU     0273EH      ; TOS temporary filename pointer
EBCD        EQU     0277CH      ; ASCII to EBCDIC translation table reference
ASCI        EQU     0277EH      ; EBCDIC to ASCII translation table reference
TIMEAD      EQU     027B0H      ; Oneshot-timer routine pointer
EXSW        EQU     027B2H      ; TOS EXEC batch-file assigned switch
TIMER       EQU     027BDH      ; Oneshot-timer countdown in 20ms intervals

;
; TOS Errors
;
ERROR_09    EQU     009H        ; NAME NOT IN DIR AND DIR FULL
ERROR_0A    EQU     00AH        ; NAME NOT IN DIRECTORY
ERROR_0B    EQU     00BH        ; PROGRAM NAME NOT FOUND
ERROR_0C    EQU     00CH        ; ILLEGAL DIRECTORY ENTRY
ERROR_0F    EQU     00FH        ; DISKETTE MAP MISSING
ERROR_11    EQU     011H        ; IMPROPER UNIT SPECIFICATION
ERROR_15    EQU     015H        ; DE-EDIT NONHEX DIGIT (0-9,A-F)
ERROR_16    EQU     016H        ; INPUT FROM NON-INPUT FILE
ERROR_17    EQU     017H        ; READ AFTER END-OF-FILE
ERROR_18    EQU     018H        ; OUTPUT TO NON-OUTPUT FILE
ERROR_19    EQU     019H        ; UNASSIGNED DEVICE
ERROR_1A    EQU     01AH        ; UNKNOWN DEVICE TYPE
ERROR_1B    EQU     01BH        ; COM/FNAM NOT LETTER/DIGIT 1ST
ERROR_1C    EQU     01CH        ; COM/FNAM > 6 OR EXT > 3 CHARS
ERROR_1D    EQU     01DH        ; COMMAND UNIT NOT :FN: OR :MN:
ERROR_1F    EQU     01FH        ; COMMAND NOT TERMINATED PROPERLY
ERROR_20    EQU     020H        ; DELETED DATA RECORD
ERROR_21    EQU     021H        ; LOGICAL UNIT NAME UNKNOWN
ERROR_22    EQU     022H        ; WRITE ON NON-BLOCK FILE
ERROR_23    EQU     023H        ; WRITE/READ MISSING IN CTL-BLK
ERROR_24    EQU     024H        ; READ ON FILETYPE OTHER THAN 4,5
ERROR_25    EQU     025H        ; LINE OVERFLOW
ERROR_27    EQU     027H        ; FILE ALREADY OPEN
ERROR_28    EQU     028H        ; NO OPEN-ROUTINE IN CTL-BLK
ERROR_29    EQU     029H        ; CLOSE ON CLOSED FILE
ERROR_2A    EQU     02AH        ; NO CLOSE-ROUTINE IN CTL-BLK
ERROR_2B    EQU     02BH        ; BUFFER CHAIN DESTROYED
ERROR_2C    EQU     02CH        ; BUFFER HEADER IMPROPER
ERROR_2D    EQU     02DH        ; IMPROPER FILE DESIGNATOR
ERROR_2E    EQU     02EH        ; IMPROPER ASSIGNMENT FORMAT
ERROR_2F    EQU     02FH        ; NO ROOM ON DISKETTE
ERROR_30    EQU     030H        ; ILLEGAL BUFFER TYPE
ERROR_31    EQU     031H        ; NON-EXISTENT FILE NAME - INPUT
ERROR_32    EQU     032H        ; OUTPUT FILE ALREADY ON DISKETTE
ERROR_33    EQU     033H        ; NO ROOM ON DISKETTE
ERROR_34    EQU     034H        ; FILENAME > 8 CHARACTERS
ERROR_3C    EQU     03CH        ; OUTPUT FILE ALREADY ON CARTR.
ERROR_3D    EQU     03DH        ; NO MORE SPACE ON CARTRIDGE
ERROR_3E    EQU     03EH        ; INPUT FILE OVERRUN
ERROR_40    EQU     040H        ; END OF TAPE ERROR
ERROR_48    EQU     048H        ; TAPE MARK DETECTED
ERROR_57    EQU     057H        ; CARTRIDGE EXTRA BLOCKS IN FILE
ERROR_5A    EQU     05AH        ; INCORRECT NAME IN HEADER BLOCK
ERROR_5C    EQU     05CH        ; END-OF-BLOCK (B AND J FILES)

;
; TOS file attributes
;
ATTR_I      EQU     001H        ; Invisible file
ATTR_S      EQU     002H        ; System file
ATTR_W      EQU     004H        ; Write-protected file

;
; TOS File Control Block, block device variables
;
FCB_BUFLEN  EQU     004H        ; Length of block/buffered-device data buffer
FCB_BUFPTR  EQU     006H        ; Pointer to block/buffered-device data buffer
FCB_READ    EQU     008H        ; Device-driver Read API call
FCB_WRITE   EQU     00AH        ; Device-driver Write API call
FCB_OPEN    EQU     00CH        ; Device-driver Open API call
FCB_CLOSE   EQU     00EH        ; Device-driver Close API call
FCB_DRVNR   EQU     011H        ; Drive number
FCB_FNAME   EQU     012H        ; Filename string
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
FM_EXEC_CI  EQU     008H        ; Internal file CI used by EXEC flag
FM_EOF_NEXT EQU     010H        ; Force End of File on next read flag
FM_ASSIGNED EQU     020H        ; Assigned and opened by command line flag
FM_NO_CLOSE EQU     040H        ; Don't close file flag
FM_EOF      EQU     080H        ; End of file flag

;
; FCB media format flags
;
DF_SYSFILE  EQU     004H        ; Write intel disk file with system attributes flag
DF_BLKLINE  EQU     040H        ; IBM disk blockline mode flag
DF_EBCDIC   EQU     080H        ; IBM disk EBCDIC character encoding flag

;
; Chained list item status
;
BUFLST_ACTV EQU     000H        ; Active element of chained list of buffers
BUFLST_HEAD EQU     080H        ; Head element of chained list of buffers
BUFLST_INAC EQU     0FFH        ; Released element of chained list

;
; TOS Device driver tables
;
TAB_OPEN    EQU     000H        ; Device driver open routines
TAB_OPEN_I  EQU     000H        ; Device driver open input routine
TAB_OPEN_O  EQU     003H        ; Device driver open output routine
TAB_READ_I  EQU     006H        ; Device driver read input routine
TAB_WRITE_O EQU     009H        ; Device driver write output routine
TAB_CLOSE   EQU     00CH        ; Device driver close routines


;//////////////////////////////////////////////////////////////////////////////
;//
;//     MAIN module
;//
;//         Tandberg OS main initialization routine and command-line prompt
;//         program, as well as error-handling routines. Boots TOS and sets up
;//         various constant definitions and references in the system, before
;//         starting the main command line prompt. This prompt is the main
;//         interface the user will see when operating TOS21.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//
;//             v1.4:
;//
;//                 -> Clears one-shot timer routine pointer on initialization
;//                 -> Now resets the state of the debug flag after a program ends
;//                    with an error
;//
;//             v1.5a:
;//
;//                 -> Adds a flag and special handling for batch files, which are
;//                    now automatically set up with console echo
;//                 -> Adds a bug where the newly exposed TOSINIT API routine is
;//                    overwritten by buffers
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     TOS initialization routine
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0DC00H
start:
        ;
        ; Init and run main command line prompt program
        ;
        CALL        T_TOSINIT
        JMP         main


;//////////////////////////////////////////////////////////////////////////////

T_TOSINIT:
        ;
        ; Reset one-shot timer routine
        ;
        LXI         H,00000H
        SHLD        TIMEAD
        ;
        ; Set lower memory boundary of TOS
        ;
        LXI         H,buffer_list_next_ptr
        SHLD        BUFLIM
        ;
        ; Try to trigger autoscroll, if active
        ;
        LXI         H,24*CURSOR_ROW + 79*CURSOR_COL
        CALL        CURSOR
        MVI         A,'A'
        CALL        TTO
        ;
        ; Read back same cursor position to check if autoscroll activated
        ;
        CALL        CURSOR
        MVI         A,' '
        CALL        INDISP
        CPI         'A'
        JZ          scroll_mode_found
        SUB         A
scroll_mode_found:
        STA         ROLLSW
        MVI         A,ERPAG
        CALL        TTO
        ;
        ; Set up IBM EBCDIC translation tables for XMON
        ;
        LXI         H,ascii_to_ebcdic_table
        SHLD        EBCD
        LXI         H,ebcdic_to_ascii_table
        SHLD        ASCI
        ;
        ; Clear TOS batch file flag
        ;
        XRA         A
        STA         EXSW
        RET


;//////////////////////////////////////////////////////////////////////////////

buffer_list_next_ptr:
        DW          00000H
buffer_list_tail:
        DB          BUFLST_HEAD


;//////////////////////////////////////////////////////////////////////////////
;//
;//     TOS command line main program
;//
;//////////////////////////////////////////////////////////////////////////////

error_number:
        DB          000H


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Clean up assigned file after use
        ;
cli_close_assigned_file:
        ;
        ; Get and check if file reference is set
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        MOV         A,D
        ORA         E
        RZ
        ;
        ; Check if file is assigned at the command line and if it's locked open
        ;
        INX         D
        LDAX        D               ; FCB + FCB_MODE
        ANI         FM_ASSIGNED + FM_NO_CLOSE
        CPI         FM_ASSIGNED + FM_NO_CLOSE
        RZ
        ;
        ; If not, unassign file
        ;
        MVI         M,000H
        DCX         H
        MVI         M,000H
        XCHG
        ;
        ; Close unassigned file if it was previously assigned from command line
        ;
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_ASSIGNED
        RZ
        DCX         H
        CALL        CLOSE
        CC          T_ERROR
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Main command line interface program entry, ready CI for a new session
        ;
T_MON:
        ;
        ; Check if standard console input is a buffered line device
        ;
        LHLD        CI_FCB
        MOV         A,M
        CPI         4
        JNZ         cli_force_cleanup
        ;
        ; If so, get pointer to next character
        ;
        INX         H
        INX         H
        MOV         C,M             ; FCB + FCB_BUFIDX
        INX         H
        MOV         B,M
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        DAD         B
        ;
        ; Check if CI is at the end of a line
        ;
        MOV         A,M
        CPI         CR
        JZ          cli_force_cleanup
        CPI         LF
        JZ          cli_force_cleanup
        ;
        ; Check if CI is at the start of a line
        ;
        DCX         H
        MOV         A,M
        CPI         CR
        JZ          cli_force_cleanup
        CPI         LF
        JZ          cli_force_cleanup
        ;
        ; Assume CI is currently in the middle of a line, flush the rest of it
        ;
        CALL        flush_ci_input
        CC          T_ERROR
        JMP         cli_force_cleanup


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Run and parse command line prompt
        ;
main:
        ;
        ; Reset TOS stack and debug flag
        ;
        SUB         A
        STA         DEBUG
        LXI         SP,STACK
        ;
        ; Check for if a batch file is running, and skip printing prompt if so
        ;
        LHLD        CI_FCB
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_EXEC_CI
        JNZ         parse_command_line_prompt
        ;
        ; Print title string and command line prompt to console
        ;
        LHLD        CO_FCB
        LXI         D,title_str
        CALL        PUT
        CC          error_tos_print_problem
        LHLD        CO_FCB
        MVI         A,'*'
        CALL        OUTCHAR
        CC          error_tos_print_problem
parse_command_line_prompt:
        ;
        ; Get and parse command line prompt input string
        ;
        CALL        command_line_interpreter
        JNC         cli_prompt_cleanup
        ANA         A
        JNZ         cli_prompt_error
        ;
        ; Verify end of file flag for CI
        ;
        LHLD        CI_FCB
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_EOF
        JZ          cli_prompt_invalid_end_of_file
        ;
        ; Check if it was a batch file that ended
        ;
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_EXEC_CI
        JZ          cli_restore_console_input
        ;
        ; If so, force the flag back off since the fcb structure may get reused
        ;
        MOV         A,M             ; FCB + FCB_MODE
        XRI         FM_EOF
        MOV         M,A
        ;
        ; Set up to close nested input file of batch file
        ;
        LHLD        EXEC_FCB
        SHLD        CI_FCB
cli_restore_console_input:
        ;
        ; Close assigned CI and reset to buffered console with echo
        ;
        LXI         H,CI_FCB
        CALL        cli_close_assigned_file
        LXI         H,DEV_CI_FCB_buffered_echo
        SHLD        CI_FCB
        CALL        reset_file_buffer
        JMP         cli_prompt_cleanup


;//////////////////////////////////////

cli_prompt_invalid_end_of_file:
        SUB         A
cli_prompt_error:
        ;
        ; Print error-message before next prompt
        ;
        CALL        T_ERROR
        JMP         cli_force_cleanup


;//////////////////////////////////////

cli_prompt_cleanup:
        ;
        ; Immediately get next prompt-input if the debug flag is set
        ;
        LDA         DEBUG
        ANA         A
        JNZ         parse_command_line_prompt
        ;
        ; Check EXEC batch file flag
        ;
        LDA         EXSW
        ANA         A
        JZ          cli_force_cleanup
        ;
        ; If set, inject assigned CI into a buffered echo file, and use this
        ;
        LHLD        CI_FCB
        SHLD        EXEC_FCB
        LXI         H,DEV_EXEC_FCB_buffered_echo
        SHLD        CI_FCB
        CALL        reset_file_buffer
        ;
        ; Clear EXEC flag now that the batch file is set up
        ;
        XRA         A
        STA         EXSW
        JMP         parse_command_line_prompt


;//////////////////////////////////////////////////////////////////////////////

DEV_EXEC_FCB_buffered_echo:
        DB          4
        DB          FM_INPUT + FM_EXEC_CI + FM_NO_CLOSE
        DW          0
        DW          128
        DW          DEV_CI_buffer
        DW          DEV_EXEC_FCB_echo


;//////////////////////////////////////

DEV_EXEC_FCB_echo:
        DB          3
        DB          FM_INPUT + FM_NO_CLOSE
EXEC_FCB:
        DW          00000H
        DW          DEV_CO_FCB


;//////////////////////////////////////////////////////////////////////////////

cli_force_cleanup:
        ;
        ; Otherwise clean up abstract-file assignements and run next cli prompt
        ;
        LXI         H,SI_FCB
        CALL        cli_close_assigned_file
        LXI         H,SO_FCB
        CALL        cli_close_assigned_file
        LXI         H,SL_FCB
        CALL        cli_close_assigned_file
        LXI         H,AI_FCB
        CALL        cli_close_assigned_file
        LXI         H,AO_FCB
        CALL        cli_close_assigned_file
        LXI         H,AL_FCB
        CALL        cli_close_assigned_file
        JMP         main


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Empty buffer of buffered file, without triggering a read
        ;
reset_file_buffer:
        ;
        ; Reset index of file buffer
        ;
        INX         H
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        INX         H
        ;
        ; Get pointer to line buffer
        ;
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        ;
        ; Store end-of-line markers at the very start of the buffer
        ;
        MVI         A,LF
        STAX        D
        INX         D
        MVI         A,LF
        STAX        D
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Display an error message for the user
        ;
T_ERROR:
        ;
        ; Check that the error number is valid
        ;
        STA         error_number
        CPI         05CH
        JP          error_msg_unavailable
        ;
        ; Get floppy disk sector containing relevant error message
        ;
        RRC
        RRC
        INR         A
        ANI         03FH
        ;
        ; Read sector containing error message string
        ;
        MOV         C,A
        SUB         A
        MOV         B,A
        LXI         H,BUF1
        CALL        DSRDW
        JC          error_msg_unavailable
        ;
        ; Verify that sector contains error message strings in general
        ;
        LDA         BUF1
        CPI         085H
        JNZ         error_msg_unavailable
        ;
        ; Get message string nr in sector from the error number modulus 4
        ;
        LDA         error_number
        ANI         003H
        ;
        ; Multiply message nr by 32 to get offset into sector of error messages
        ;
        RLC
        RLC
        RLC
        RLC
        RLC
        ANI         0E0H
        MOV         C,A
        MVI         B,000H
        ;
        ; Add offset to sector buffer start to get the error message string
        ;
        LXI         H,BUF1
        DAD         B
        INX         H
        XCHG
        ;
        ; Print generic error number string
        ;
        LDA         error_number
        LXI         H,error_str+6
        CALL        EDBH
        LHLD        CO_FCB
        PUSH        D
        LXI         D,error_str
        CALL        PUTSTR
        POP         D
        JC          error_tos_print_problem
        ;
        ; Print more verbose error message string that was read from disk
        ;
        MVI         A,' '
        CALL        OUTCHAR
        JC          error_tos_print_problem
        MVI         B,31
        CALL        PUTBIN
        JC          error_tos_print_problem
        LXI         D,newline_str
        CALL        PUT
        JC          error_tos_print_problem
        RET

error_msg_unavailable:
        ;
        ; Print generic error number string
        ;
        LDA         error_number
        LXI         H,error_str+6
        CALL        EDBH
        LHLD        CO_FCB
        LXI         D,error_str
        CALL        PUT
        JC          error_tos_print_problem
        RET

error_tos_print_problem:
        ;
        ; Print generic error number string using XMON API
        ;
        LXI         H,error_str
error_print_str_loop:
        MOV         A,M
        INX         H
        CALL        TTO
        CPI         CR
        JNZ         error_print_str_loop
        MVI         A,LF
        CALL        TTO
        LXI         H,DEV_CO_FCB
        SHLD        CO_FCB
        RET


;//////////////////////////////////////////////////////////////////////////////

error_str:
        DB          'ERROR ',NULL,NULL
newline_str:
        DB          CR
title_str:
        DB          'TOS21 VER. 1.5',CR


;//////////////////////////////////////////////////////////////////////////////
;//
;//     EDIT module
;//
;//         String editing module, containing helper-functions for string-
;//         conversions.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     ASCII translation functions
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert lower 4 bits of A to an ASCII single hex digit
        ;
nibble_to_ascii_hex:
        ANI         00FH
        ADI         090H
        DAA
        ACI         040H
        DAA
        MOV         M,A
        INX         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert A to an ASCII hex number
        ;
T_EDBH:
        ;
        ; Convert most signifficant hex digit
        ;
        PUSH        PSW
        RRC
        RRC
        RRC
        RRC
        CALL        nibble_to_ascii_hex
        POP         PSW
        ;
        ; Convert least signifficant hex digit
        ;
        PUSH        PSW
        CALL        nibble_to_ascii_hex
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert DE to an ASCII hex number
        ;
T_EDWH:
        ;
        ; Convert upper two digits
        ;
        PUSH        PSW
        MOV         A,D
        CALL        T_EDBH
        ;
        ; Convert lower two digits
        ;
        MOV         A,E
        CALL        T_EDBH
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII hex digit to binary
        ;
ascii_hex_char_to_bin:
        MOV         A,M
        INX         H
        CPI         '0'
        JM          invalid_hex_char
        CPI         'F'+1
        JP          invalid_hex_char
        CPI         '9'+1
        JM          hex_char_is_decimal
        CPI         'A'
        JM          invalid_hex_char
        SUI         '0' + 'A'-('9'+1)
        RET

hex_char_is_decimal:
        SUI         '0'
        RET

invalid_hex_char:
        MVI         A,ERROR_15
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert two ASCII hex characters to binary in A
        ;
T_EDHB:
        ;
        ; Convert first digit
        ;
        CALL        ascii_hex_char_to_bin
        RC
        RLC
        RLC
        RLC
        RLC
        ANI         0F0H
        ;
        ; Convert second digit
        ;
        PUSH        B
        MOV         B,A
        CALL        ascii_hex_char_to_bin
        JC          invalid_hex_byte
        ORA         B
invalid_hex_byte:
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert four ASCII hex characters to binary in DE
        ;
T_EDHW:
        ;
        ; Convert upper two digits
        ;
        PUSH        PSW
        CALL        T_EDHB
        JC          invalid_hex_word
        MOV         D,A
        ;
        ; Convert lower two digits
        ;
        CALL        T_EDHB
        JC          invalid_hex_word
        MOV         E,A
        POP         PSW
        ANA         A
        RET

invalid_hex_word:
        INX         SP
        INX         SP
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Check if ASCII character in A is alphanumeric or not
        ;
check_alphanumeric:
        CPI         '0'
        JM          not_alphanumeric
        CPI         '9'+1
        JM          is_alphanumeric
        CPI         'A'
        JM          not_alphanumeric
        CPI         'Z'+1
        JM          is_alphanumeric
        CPI         'a'
        JM          not_alphanumeric
        CPI         'z'+1
        JP          not_alphanumeric
is_alphanumeric:
        ANA         A
        RET

not_alphanumeric:
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert B character long string at HL to uppercase
        ;
str_to_uppercase:
        PUSH        PSW
        PUSH        B
        PUSH        H
        MVI         C,0
char_to_uppercase:
        ;
        ; Check if character is already uppercase
        ;
        MOV         A,M
        CPI         'a'
        JM          next_char_to_uppercase
        CPI         'z'+1
        JP          next_char_to_uppercase
        ;
        ; If not, convert it and count it
        ;
        ANI         0DFH
        MOV         M,A
        INR         C
next_char_to_uppercase:
        ;
        ; Advance to next character
        ;
        INX         H
        DCR         B
        JNZ         char_to_uppercase
        POP         H
        ;
        ; Check if any characters in string were converted
        ;
        MOV         A,C
        POP         B
        ANA         A
        JZ          no_chars_made_uppercase
        POP         PSW
        ANA         A
        RET

no_chars_made_uppercase:
        POP         PSW
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert character in A to uppercase
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
;//     IO module
;//
;//         Common module with helper-functions used by the other modules for file
;//         handling.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     I/O module common subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Verify that file control block is set, and of known type
        ;
check_file_control_block:
        PUSH        PSW
        MOV         A,H
        ORA         L
        JZ          unassigned_fcb_device
        ;
        ; Accept file type 2 to 6, type 1 (interrupt-driven) is not supported
        ;
        MOV         A,M
        CPI         7
        JNC         unknown_fcb_device_type
        CPI         2
        JC          unknown_fcb_device_type
        POP         PSW
        ANA         A
        RET

unassigned_fcb_device:
        MVI         A,ERROR_19
        JMP         fcb_device_type_error

unknown_fcb_device_type:
        MVI         A,ERROR_1A
fcb_device_type_error:
        INX         SP
        INX         SP
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     GET module
;//
;//         General data-flow routines for input files, both character-based files
;//         and binary files. This will automatically call READ when needed in the
;//         case of block device files and buffered line based files (prompts).
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//
;//             v1.5a:
;//
;//                 -> Adds handling of blockline flag, where an extra end-of-line
;//                    cartridge-return character is injected after the end of
;//                    every block. This enables block-devices to be used as
;//                    nested input files in buffered line files. Simlarly, if
;//                    binary mode is used an exception is generated on block end
;//                    instead of the extra character.
;//                 -> The NULL character is now also ignored when reading from
;//                    block devices in character mode
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File IO routines
;//
;//////////////////////////////////////////////////////////////////////////////

T_INCHAR:
        ;
        ; Verify that the input file is a valid input file, with available data
        ;
        CALL        check_file_control_block
        RC
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        DCX         H
        ANI         FM_INPUT + FM_EOF
        JNZ         inchar_file_is_input
        MVI         A,ERROR_16
        STC
        RET

inchar_file_is_input:
        ANI         FM_EOF
        JZ          inchar_file_has_data
        MVI         A,ERROR_17
        STC
        RET

inchar_file_has_data:
        ;
        ; Prepare to determine file type and particular course of action
        ;
        MOV         A,M             ; FCB + FCB_TYPE
        PUSH        D
        PUSH        H
        INX         H
        INX         H
        MOV         E,M             ; FCB + 002H, content depends on file type
        INX         H
        MOV         D,M

;//////////////////////////////////////

        CPI         2
        JNZ         inchar_test_for_type_3
        ;
        ; INCHAR from polling device: Get input and nothing more
        ; Call input polling routine stored in FCB
        ;
        XCHG                        ; HL => File read routine
        LXI         D,inchar_return
        PUSH        D
        PCHL


;//////////////////////////////////////

        ;
        ; Clean up stack appropriately and return
        ;
inchar_type_4_or_5_return:
        ANA         A
inchar_return:
        POP         H
        POP         D
        RET

inchar_echo_failed:
        POP         D
        JMP         inchar_return


;//////////////////////////////////////

inchar_test_for_type_3:
        CPI         3
        JNZ         inchar_test_for_type_6
        ;
        ; INCHAR from echo file: Get char from input and echo it to output file
        ; Forward inchar call to nested input FCB
        ;
        PUSH        H
        XCHG                        ; HL => Nested input FCB of echo file
        CALL        T_INCHAR
        POP         H
        JC          inchar_return
        ;
        ; Echo input character to nested output FCB
        ;
        PUSH        PSW
        INX         H
        MOV         E,M             ; FCB + 004H, Nested output FCB reference
        INX         H
        MOV         D,M
        XCHG
        CALL        OUTCHAR
        JC          inchar_echo_failed
        POP         PSW
        JMP         inchar_return


;//////////////////////////////////////

inchar_test_for_type_6:
        CPI         6
        JNZ         inchar_type_4_or_5
        ;
        ; INCHAR from linked file: Forward call to the appropriate nested FCB
        ; Check if first nested file is flagged as end-of-file
        ;
        XCHG                        ; HL => First nested FCB of linked file
        INX         H
        MOV         A,M             ; 1st nested FCB + FCB_MODE
        DCX         H
        ANI         FM_EOF
        JNZ         inchar_type_6_end_of_first_file
        ;
        ; If not, get data from first nested file
        ;
        CALL        T_INCHAR
        JNC         inchar_return
        ;
        ; If input exception, check if first file just went into end-of-file
        ;
        ANA         A
        JNZ         inchar_linked_file_end
inchar_type_6_end_of_first_file:
        ;
        ; If first nested file is empty, get pointer to second nested file
        ;
        POP         H
        PUSH        H
        LXI         D,004H
        DAD         D
        MOV         E,M             ; FCB + 004H, Second nested FCB reference
        INX         H
        MOV         D,M
        XCHG                        ; HL => Second nested FCB of linked file
        CALL        T_INCHAR
        JNC         inchar_return
        ;
        ; Check for second file end-of-file if exception
        ;
        POP         H
        PUSH        H
        JMP         inchar_mark_end_of_file


;//////////////////////////////////////

inchar_type_4_or_5:
        ;
        ; Advance index of buffer since we are to remove a byte
        ;
        INX         D
        MOV         M,D             ; FCB + FCB_BUFIDX
        DCX         H
        MOV         M,E
        INX         H
        INX         H
        CPI         4
        JNZ         inchar_type_5
        ;
        ; INCHAR from buffered character file (variable size buffer)
        ; Get pointer to buffer start
        ;
        INX         H
        INX         H
        PUSH        B
        MOV         C,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         B,M
        ;
        ; Add buffer index to FCB buffer start address
        ;
        XCHG
        DAD         B
        POP         B
        ;
        ; Get character at old index and check for end of string
        ;
        DCX         H
        MOV         A,M
        CPI         LF
        JNZ         inchar_type_4_or_5_return


;//////////////////////////////////////

inchar_type_4_or_5_buffer_empty:
        ;
        ; Try to read more data if buffer was empty
        ;
        POP         H
        CALL        READ
        PUSH        H
        JC          inchar_mark_end_of_file
inchar_buffered_files_retry:
        ;
        ; If more data was available, try inchar again with replenished buffer
        ;
        MOV         A,M
        INX         H
        INX         H
        MOV         E,M
        INX         H
        MOV         D,M
        JMP         inchar_test_for_type_6


;//////////////////////////////////////

inchar_type_5:
        ;
        ; INCHAR from block device file (fixed size buffer)
        ; Check for end-of-block in blockline mode marker
        ;
        DCX         H
        MOV         A,M             ; FCB + FCB_BUFIDX (msb)
        CPI         0FFH
        JZ          inchar_type_4_or_5_buffer_empty
        INX         H
        ;
        ; If not, check for end of buffer
        ;
        MOV         A,M             ; FCB + FCB_BUFLEN (lsb)
        INX         H
        INR         A
        CMP         E
        JNZ         inchar_type_5_data_in_buffer
        MOV         A,M             ; FCB + FCB_BUFLEN (msb)
        CMP         D
        JNZ         inchar_type_5_data_in_buffer
        ;
        ; If so, check if blockline mode is set
        ;
        POP         H
        PUSH        H
        PUSH        D
        LXI         D,01BH
        DAD         D
        POP         D
        MOV         A,M             ; FCB + FCB_DRVFMT
        ANI         DF_BLKLINE
        JZ          inchar_type_4_or_5_buffer_empty
        ;
        ; If so, set end-of-block marker for blockline mode
        ;
        POP         H
        PUSH        H
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        INX         H
        INX         H
        MVI         M,0FFH          ; FCB + FCB_BUFIDX (msb)
        ;
        ; Check if binary mode is active, raise end-of-block exception instead
        ;
        ANI         FM_BINARY
        MVI         A,ERROR_5C
        STC
        JNZ         inchar_return
        ;
        ; Otherwise inject end of line at the end of block
        ;
        MVI         A,CR
        JMP         inchar_type_4_or_5_return

inchar_type_5_data_in_buffer:
        ;
        ; Get pointer to buffer start
        ;
        INX         H
        PUSH        B
        MOV         C,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         B,M
        ;
        ; Add buffer index to FCB buffer start address
        ;
        XCHG
        DAD         B
        POP         B
        ;
        ; Get character at old index and check for end of string
        ;
        DCX         H
        MOV         A,M
        ANA         A
        JZ          inchar_type_5_end_of_line
        CPI         LF
        JNZ         inchar_type_4_or_5_return
        ;
        ; If end of string encountered, check for binary mode
        ;
inchar_type_5_end_of_line:
        POP         H
        PUSH        H
        PUSH        PSW
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        DCX         H
        ANI         FM_BINARY
        ;
        ; If binary mode is not active, ignore end of line character
        ;
        JZ          inchar_type_5_retry
        ;
        ; Else if binary mode is active, treat EoL marker as a normal character
        ;
        POP         PSW
        JMP         inchar_type_4_or_5_return

inchar_type_5_retry:
        POP         PSW
        JMP         inchar_buffered_files_retry


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Mark end of file in FCB
        ;
inchar_mark_end_of_file:
        ANA         A
        JNZ         inchar_linked_file_end
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ORI         FM_EOF
        MOV         M,A
        SUB         A
inchar_linked_file_end:
        POP         H
        POP         D
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get an entire string from file HL to string at DE
        ;
T_GET:
        CALL        T_INCHAR
        RC
        STAX        D
        INX         D
        CPI         CR
        JNZ         T_GET
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get B number of binary bytes from file HL to buffer at DE
        ;
T_GETBIN:
        ;
        ; Force binary mode
        ;
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        PUSH        PSW
        ORI         FM_BINARY
        MOV         M,A
        DCX         H
        ;
        ; Get binary data from file
        ;
getbin_fetch_next_byte:
        CALL        T_INCHAR
        JC          getbin_exception
        STAX        D
        INX         D
        DCR         B
        JNZ         getbin_fetch_next_byte
        ;
        ; Restore the old status of the file binary-mode flag
        ;
        INX         H
        POP         PSW
        PUSH        B
        MOV         B,A
        MOV         A,M             ; FCB + FCB_MODE
        ANI         -1-(FM_BINARY)
        ORA         B
        POP         B
        MOV         M,A
        DCX         H
        ANA         A
        RET

getbin_exception:
        INX         SP
        INX         SP
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     PUT module
;//
;//         General data-flow routines for output files, both character-based files
;//         and binary files. This will automatically call WRITE when needed in the
;//         case of block device files.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Has a bug where the stack is off by one item for the return
;//                    if a WRITE call fails, something which is likely to cause a
;//                    system crash should the situation occur
;//
;//             v1.4:
;//
;//                 -> Fixes the WRITE-failure return stack bug from v1.3
;//
;//             v1.5a:
;//
;//                 -> Adds handling of the BLOCKLINE flag, where the current block
;//                    is completed and written to disk immediately on newline
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File IO routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Output a single byte to file
        ;
T_OUTCHAR:
        ;
        ; Verify file type, and that it is open for output
        ;
        CALL        check_file_control_block
        RC
        PUSH        PSW
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        DCX         H
        ANI         FM_OUTPUT
        JNZ         outchar_valid_file_mode
        ;
        ; Assume that echo-files can always take output
        ;
        MOV         A,M             ; FCB + FCB_TYPE
        CPI         3
        JZ          outchar_valid_file_mode
        ;
        ; Otherwise raise an exception
        ;
        INX         SP
        INX         SP
        MVI         A,ERROR_18
        STC
        RET

outchar_valid_file_mode:
        ;
        ; Save variables on stack
        ;
        POP         PSW
        PUSH        H
        PUSH        D
        PUSH        B
        PUSH        PSW
        ;
        ; Check filetype
        ;
        MOV         A,M             ; FCB + FCB_TYPE
        CPI         5
        JZ          outchar_type_5
        INX         H
        INX         H
        CPI         6
        JZ          outchar_type_6
        CPI         2
        JZ          outchar_type_2
        CPI         3
        JZ          outchar_type_3
        ;
        ; Buffered line devices can't take output data, raise exception
        ;
        MVI         A,0FFH
        STC
        JMP         outchar_return


;//////////////////////////////////////

outchar_type_5_end:
        ANA         A
outchar_return:
        POP         B
        POP         D
        POP         H
        RET


;//////////////////////////////////////

outchar_type_2:
        ;
        ; OUTCHAR to polling device: Write output and nothing more
        ; Call output polling routine stored in FCB
        ;
        INX         H
        INX         H
        MOV         E,M             ; FCB + 004H, File write routine
        INX         H
        MOV         D,M
        ;
        ; Set up stack to return to file-write routine and then cleanup code
        ;
        POP         PSW
        LXI         H,outchar_return
        PUSH        H
        PUSH        D
        RET


;//////////////////////////////////////

outchar_type_3:
        ;
        ; OUTCHAR to echo file: Send char directly to echo output file
        ; Forward outchar call to nested echo FCB
        ;
        INX         H
        INX         H               ; FCB + 004H, Nested echo output file
        JMP         outchar_linked_fcb


;//////////////////////////////////////

outchar_type_5:
        ;
        ; OUTCHAR to block device file (fixed size buffer)
        ; Check if blockline mode is active
        ;
        PUSH        H
        LXI         B,01BH
        DAD         B
        MOV         A,M             ; FCB + FCB_DRVFMT
        ANI         DF_BLKLINE
        JZ          outchar_normal_type_5
        ;
        ; If so, check for end of line
        ;
        POP         H
        POP         PSW
        PUSH        PSW
        PUSH        H
        CPI         CR
        JNZ         outchar_normal_type_5
        ;
        ; If so, write the current block as-is
        ;
        POP         H
        PUSH        H
        INX         H
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFLEN
        INX         H
        MOV         D,M
        DCX         H
        DCX         H
        MOV         M,D             ; FCB + FCB_BUFIDX
        DCX         H
        MOV         M,E
        POP         H
        CALL        WRITE
        JNC         outchar_blockline_type_5_end
        INX         SP
        INX         SP
        JMP         outchar_return

outchar_blockline_type_5_end:
        POP         PSW
        JMP         outchar_type_5_end

outchar_normal_type_5:
        ;
        ; Get data index and buffer length
        ;
        POP         H
        PUSH        H
        INX         H
        INX         H
        MOV         C,M             ; FCB + FCB_BUFIDX
        INX         H
        MOV         B,M
        INX         H
        MOV         E,M             ; FCB + FCB_BUFLEN
        INX         H
        MOV         D,M
        INX         H
        ;
        ; Check for end of block
        ;
        MOV         A,C
        CMP         E
        JNZ         outchar_block_not_full
        MOV         A,B
        CMP         D
        JNZ         outchar_block_not_full
        ;
        ; If block is full, write current block to file and add character again
        ;
        POP         H
        CALL        WRITE
        JNC         outchar_type_5
        ;
        ; Otherwise return error
        ;
        INX         SP
        INX         SP
        JMP         outchar_return

outchar_block_not_full:
        ;
        ; Get pointer in block buffer for new character
        ;
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        DAD         B
        POP         D
        ;
        ; Add new character to block buffer
        ;
        POP         PSW
        MOV         M,A
        ;
        ; Increment buffer index
        ;
        XCHG
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFIDX
        INX         H
        MOV         D,M
        INX         D
        MOV         M,D
        DCX         H
        MOV         M,E
        JMP         outchar_type_5_end


;//////////////////////////////////////

outchar_type_6:
        ;
        ; OUTCHAR to linked file: Forward call to both nested FCBs
        ; Get first nested FCB
        ;
        MOV         E,M             ; FCB + 002H, First nested FCB reference
        INX         H
        MOV         D,M
        INX         H
        ;
        ; Output character to first file
        ;
        POP         PSW
        PUSH        PSW
        PUSH        H
        XCHG
        CALL        T_OUTCHAR
        POP         H
        JC          outchar_type_6_exception
outchar_linked_fcb:
        MOV         E,M             ; FCB + 004H, Second nested FCB reference
        INX         H
        MOV         D,M
        ;
        ; Output character to second file
        ;
        XCHG
        POP         PSW
        CALL        T_OUTCHAR
        JMP         outchar_return

outchar_type_6_exception:
        INX         SP
        INX         SP
        JMP         outchar_return


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Output an entire string at DE to file HL
        ;
T_PUTSTR:
        LDAX        D
        CPI         CR
        RZ
        CALL        T_OUTCHAR
        RC
        INX         D
        JMP         T_PUTSTR


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Output B bytes starting at DE to file HL
        ;
T_PUTBIN:
        LDAX        D
        CALL        T_OUTCHAR
        RC
        INX         D
        DCR         B
        JNZ         T_PUTBIN
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Output an entire string at DE to file HL, with newline
        ;
T_PUT:
        CALL        T_PUTSTR
        RC
        MVI         A,CR
        CALL        T_OUTCHAR
        RC
        MVI         A,LF
        CALL        T_OUTCHAR
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     OPEN module
;//
;//         Module for opening file control blocks, before use. This needs to be
;//         called before a new file control block can be used.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Bug where line-buffered file control block is expected to
;//                    have an OPEN-routine pointer at offset 0C, instead of
;//                    propagating the opening operation to linked FCB
;//
;//             v1.4:
;//
;//                 -> Binary mode of linked files now propagates down through the
;//                    nested files
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File IO routines
;//
;//////////////////////////////////////////////////////////////////////////////

open_mode:
        DB          000H


;//////////////////////////////////////

        ;
        ; Open file for a particular mode
        ;
T_OPEN:
        ;
        ; Save file IO mode
        ;
        STA         open_mode
        PUSH        PSW
        ;
        ; Verify that file is valid, and not already open
        ;
        CALL        check_file_control_block
        JC          open_failed
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_ASSIGNED
        JNZ         open_cli_assigned_file
        MOV         A,M
        DCX         H
        ANI         FM_NO_CLOSE
        JNZ         open_failed
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        DCX         H
        ANI         FM_INPUT + FM_OUTPUT + FM_EOF_NEXT + FM_EOF
        JZ          open_file_first_time
        POP         PSW
        MVI         A,ERROR_27
        STC
        RET

open_failed:
        INX         SP
        INX         SP
        RET

open_file_first_time:
        ;
        ; Set file IO mode if not assigned on the command line
        ;
        INX         H
        POP         PSW
        ORA         M
        MOV         M,A             ; FCB + FCB_MODE
        JMP         open_file_test_for_type_2

open_cli_assigned_file:
        ;
        ; Assume that the assignement interpreter already set the file mode
        ;
        INX         SP
        INX         SP


;//////////////////////////////////////

open_file_test_for_type_2:
        ;
        ; If polling device, do nothing since these are always available
        ;
        DCX         H
        MOV         A,M             ; FCB + FCB_TYPE
        CPI         2
        RZ
        PUSH        D
        PUSH        H
        JMP         open_file_test_for_type_3


;//////////////////////////////////////

open_complete:
        POP         H
open_type_4_ok:
        POP         D
        ANA         A
        RET


;//////////////////////////////////////

open_file_test_for_type_3:
        CPI         3
        JNZ         open_file_test_for_type_4
        ;
        ; OPEN echo device: Open both nested files
        ; Open nested input file for reading
        ;
        INX         H
        INX         H
        MOV         E,M             ; FCB + 002H, nested input file reference
        INX         H
        MOV         D,M
        PUSH        H
        XCHG
        MVI         A,FM_INPUT
        CALL        T_OPEN
        ;
        ; Open nested output file if everything went ok
        ;
        JNC         open_linked_output_fcb
        ;
        ; Still open nested output file if nested input file was already open
        ;
        CPI         ERROR_27
        JZ          open_linked_output_fcb
open_file_error:
        POP         H
        POP         H
        POP         D
        STC
        RET


;//////////////////////////////////////

open_file_test_for_type_4:
        CPI         4
        JNZ         open_file_test_for_type_6
        ;
        ; OPEN line buffered file: Open nested input file
        ; Get reference to nested file and verify that it is set
        ;
        LXI         D,FCB_OPEN
        DAD         D
        MOV         E,M             ; Bug: file type 4 doesn't have a FCB_OPEN
        INX         H
        MOV         D,M
        MOV         A,E
        ORA         D
        JZ          file_has_no_open_routine
        ;
        ; Set up stack pointer to jump to pointer taken from unused RAM
        ;
        LXI         H,open_type_4_return
        XTHL
        PUSH        D
        RET

open_type_4_return:
        JNC         open_type_4_ok
        POP         D
        RET


;//////////////////////////////////////

open_linked_output_fcb:
        ;
        ; Open nested output file for writing
        ;
        POP         H
        INX         H
        MOV         E,M             ; FCB + 004H, nested output file reference
        INX         H
        MOV         D,M
        XCHG
        MVI         A,FM_OUTPUT
open_linked_fcb:
        CALL        T_OPEN
        JNC         open_complete
        ;
        ; Waiver exception if the file was already open
        ;
        CPI         ERROR_27
        JZ          open_complete
        POP         H
        POP         D
        STC
        RET


;//////////////////////////////////////

file_has_no_open_routine:
        MVI         A,ERROR_28
        POP         H
        POP         D
        STC
        RET


;//////////////////////////////////////

open_file_test_for_type_6:
        CPI         6
        JNZ         open_file_type_5
        ;
        ; OPEN linked file: Open both nested files
        ; Get current file IO mode
        ;
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_INPUT + FM_OUTPUT
        ;
        ; Get current binary mode flag
        ;
        PUSH        PSW
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_BINARY
        ;
        ; Get reference to the first nested file
        ;
        INX         H
        MOV         E,M             ; FCB + 002H, first nested file
        INX         H
        MOV         D,M
        ;
        ; Make sure that nested file adheres to the current binary mode state
        ;
        XCHG
        INX         H
        ORA         M               ; First nested FCB + FCB_MODE
        MOV         M,A
        DCX         H
        XCHG
        ;
        ; Open first nested file with the same IO mode as this file
        ;
        POP         PSW
        PUSH        H
        PUSH        PSW
        XCHG
        CALL        T_OPEN
        JNC         open_second_linked_fcb
        ;
        ; Waiver if first nested file was already open
        ;
        CPI         ERROR_27
        JZ          open_second_linked_fcb
        INX         SP
        INX         SP
        JMP         open_file_error

open_second_linked_fcb:
        POP         PSW
        POP         H
        ;
        ; Get current binary mode flag
        ;
        PUSH        PSW
        DCX         H
        DCX         H
        MOV         A,M             ; FCB + FCB_MODE
        INX         H
        INX         H
        ANI         FM_BINARY
        ;
        ; Get reference to the second nested file
        ;
        INX         H
        MOV         E,M             ; FCB + 004H, second nested file
        INX         H
        MOV         D,M
        ;
        ; Make sure that nested file adheres to the current binary mode state
        ;
        XCHG
        INX         H
        ORA         M               ; Second nested FCB + FCB_MODE
        MOV         M,A
        DCX         H
        XCHG
        ;
        ; Open second nested file with the same IO mode as this file
        ;
        POP         PSW
        XCHG
        JMP         open_linked_fcb


;//////////////////////////////////////

open_file_type_5:
        ;
        ; OPEN block device file:
        ; Get current file IO mode
        ;
        PUSH        H
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ;
        ; Initialize file data buffer index
        ;
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        ;
        ; Call block device driver open routine
        ;
        POP         H
        PUSH        H
        LXI         D,FCB_OPEN
        DAD         D
        MOV         E,M             ; FCB + FCB_OPEN
        INX         H
        MOV         D,M
        ;
        ; Set up stack to run device driver open routine before continuing
        ;
        LXI         H,open_type_5_continue
        XTHL
        PUSH        D
        RET

open_type_5_continue:
        ;
        ; Read first block of file if everything went well and IO mode is input
        ;
        JC          open_type_5_done
        LDA         open_mode
        ANI         FM_INPUT
        JZ          open_type_5_done
        PUSH        H
        LXI         D,FCB_READ
        DAD         D
        MOV         E,M             ; FCB + FCB_READ
        INX         H
        MOV         D,M
        ;
        ; Set up stack to run device driver read routine before returning
        ;
        LXI         H,open_type_5_first_read_done
        XTHL
        PUSH        D
        RET

open_type_5_first_read_done:
        JNC         open_complete
open_type_5_done:
        POP         H
        POP         D
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     CLOS module
;//
;//         Module for closing a file control block Ensures proper cleanup after a
;//         file is no longer needed, in particular writing the file-entry in the
;//         case of output block device files.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Has a bug where linked files assigned through the command-
;//                    line are not de-allocated automatically on CLOSE
;//
;//             v1.4:
;//
;//                 -> No longer shares return code with OPEN
;//                 -> Fixes the linked-file de-allocation bug from v1.3
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File IO routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Close file after IO
        ;
T_CLOSE:
        ;
        ; Verify file and check that it is not already closed
        ;
        CALL        check_file_control_block
        RC
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        DCX         H
        CPI         FM_NONE
        JNZ         file_to_close_is_open
        MVI         A,ERROR_29
        STC
        RET

file_to_close_is_open:
        ;
        ; Don't close file if it is being held open by the disable closing flag
        ;
        ANI         FM_NO_CLOSE
        RNZ
        ;
        ; Else clear all flags except for the assigned by command line flag
        ;
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_ASSIGNED
        MOV         M,A


;//////////////////////////////////////

        ;
        ; If polling device, do nothing since these are always available
        ;
        DCX         H
        MOV         A,M             ; FCB + FCB_TYPE
        CPI         2
        RZ
        PUSH        D
        PUSH        H


;//////////////////////////////////////

        CPI         3
        JNZ         close_file_test_for_type_4
        ;
        ; CLOSE echo file: Close both nested files
        ; Close nested input file
        ;
        INX         H
        INX         H
        MOV         E,M             ; FCB + 002H, nested input FCB reference
        INX         H
        MOV         D,M
        PUSH        H
        XCHG
        CALL        T_CLOSE
        JNC         close_type_3_output_file
        ;
        ; Waiver exception if it was due to nested input file already closed
        ;
        CPI         ERROR_29
        JZ          close_type_3_output_file
        POP         H
        POP         H
        POP         D
        STC
        RET

close_type_3_output_file:
        ;
        ; Close nested output file
        ;
        POP         H
        INX         H
        MOV         E,M             ; FCB + 004H, nested output FCB reference
        INX         H
        MOV         D,M
        XCHG
        CALL        T_CLOSE
        JNC         close_complete
        ;
        ; Waiver exception if it was due to nested output file already closed
        ;
        CPI         ERROR_29
        JZ          close_complete
        POP         H
        POP         D
        STC
        RET


;//////////////////////////////////////

close_file_test_for_type_4:
        CPI         4
        JNZ         close_file_test_for_type_5
        ;
        ; CLOSE line buffered: Close nested input file
        ;
        LXI         D,008H
        DAD         D
        MOV         E,M             ; FCB + 008H, nested input file
        INX         H
        MOV         D,M
        XCHG
        CALL        T_CLOSE
        JC          close_type_4_end
        ;
        ; Restore registers
        ;
close_complete:
        ANA         A
close_type_4_end:
        POP         H
        POP         D
        RET


;//////////////////////////////////////

close_file_test_for_type_5:
        CPI         5
        JNZ         close_file_type_6
        ;
        ; CLOSE block device file: Close block device driver
        ; Get pointer to device driver close routine and verify that it is set
        ;
        LXI         D,FCB_CLOSE
        DAD         D
        MOV         E,M             ; FCB + FCB_CLOSE
        INX         H
        MOV         D,M
        MOV         A,E
        ORA         D
        JZ          no_close_device_vector
        ;
        ; Set up stack to run device driver close routine and return
        ;
        LXI         H,close_type_5_6_return
        XTHL
        PUSH        D
        RET


;//////////////////////////////////////

close_type_5_6_return:
        JC          close_type_5_6_end
        ANA         A
close_type_5_6_end:
        POP         D
        RET


;//////////////////////////////////////

close_file_type_6:
        ;
        ; CLOSE linked file: Close both nested files
        ; Close first linked file
        ;
        INX         H
        INX         H
        MOV         E,M             ; FCB + 002H, first linked file reference
        INX         H
        MOV         D,M
        INX         H
        PUSH        H
        XCHG
        CALL        T_CLOSE
        POP         H
        ;
        ; Close second linked file
        ;
        PUSH        PSW
        MOV         E,M             ; FCB + 004H, second linked file reference
        INX         H
        MOV         D,M
        XCHG
        CALL        T_CLOSE
        JC          close_type_6_failed
        POP         PSW
        POP         H
        ;
        ; Check if linked file was assigned on the command line
        ;
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        DCX         H
        ANI         FM_ASSIGNED
        JZ          close_type_5_6_return
        ;
        ; If so, de-allocate the linked fcb now
        ;
        CALL        BUFDEALLOC
        JMP         close_type_5_6_return

close_type_6_failed:
        INX         SP
        INX         SP
        JMP         close_file_error


;//////////////////////////////////////

no_close_device_vector:
        MVI         A,ERROR_2A
close_file_error:
        POP         H
        POP         D
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     WRIT module
;//
;//         Module for writing the current block to block device output file. This
;//         will only operate on block devices.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File IO routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write block to block-device
        ;
T_WRITE:
        ;
        ; Verify that the file is ready, and that it is a block-device
        ;
        CALL        check_file_control_block
        RC
        MOV         A,M             ; FCB + FCB_TYPE
        CPI         5
        JNZ         write_not_a_block_device
        ;
        ; Call file device-driver WRITE
        ;
        PUSH        D
        LXI         D,FCB_WRITE
read_write_type_5_driver_call:
        ;
        ; Get selected driver routine from FCB, and verify that it is set
        ;
        PUSH        H
        DAD         D
        MOV         E,M             ; FCB + DE
        INX         H
        MOV         D,M
        MOV         A,D
        ORA         E
        JZ          read_write_routine_not_set
        ;
        ; Set up stack to run delected device driver routine
        ;
        LXI         H,read_write_driver_call_return
        XTHL
        PUSH        D
        RET

read_write_driver_call_return:
        JC          read_write_driver_call_failed
        ;
        ; Reset index of block buffer, since old data has now been written
        ;
        PUSH        H
        INX         H
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        POP         H
        POP         D
        ANA         A
        RET


;//////////////////////////////////////

write_not_a_block_device:
        MVI         A,ERROR_22
        STC
        RET

read_write_routine_not_set:
        POP         H
        POP         D
        MVI         A,ERROR_23
        STC
        RET


;//////////////////////////////////////

read_write_driver_call_failed:
        ;
        ; Check for end of file
        ;
        POP         D
        ANA         A
        JNZ         read_write_return
        ;
        ; If so, mark file as end of file
        ;
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ORI         FM_EOF
        MOV         M,A
        DCX         H
        SUB         A
read_write_return:
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     READ module
;//
;//         Module for reading the next block/line from block devices and buffered
;//         line-based files (prompts).
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Bug where linked files are assumed to be block devices,
;//                    which can result in a call to an undefined pointer and the
;//                    potential system crash
;//                 -> Bug where line-buffered file does not verify that the linked
;//                    file control block is an echo-file before echoing a tab
;//                    ASCII control character input on a READ.
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File IO routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read next from line-buffered or block-device files
        ;
T_READ:
        ;
        ; Verify that the file is valid, and is one of the two supported types
        ;
        CALL        check_file_control_block
        RC
        MOV         A,M
        CPI         4
        JM          read_wrong_file_type
        JZ          read_from_type_4
        ;
        ; Read next block from block-device
        ;
        PUSH        D
        LXI         D,FCB_READ
        JMP         read_write_type_5_driver_call


;//////////////////////////////////////

read_from_type_4:
        PUSH        B
        PUSH        D
read_reset_type_4_buffer:
        ;
        ; Reset line buffer and get buffer definition
        ;
        PUSH        H
        INX         H
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        INX         H
        MOV         C,M             ; FCB + FCB_BUFLEN
        INX         H
        MOV         B,M
        INX         H
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        INX         H
        MOV         A,M             ; FCB + 008H, chained input file reference
        INX         H
        MOV         H,M
        MOV         L,A
read_type_4_get_next_char:
        ;
        ; Get next input character from nested file and parse for special chars
        ;
        CALL        INCHAR
        JC          read_type_4_error
        CPI         CR
        JZ          read_type_4_newline
        CPI         CURL
        JZ          read_type_4_backspace
        CPI         DEL
        JZ          read_type_4_del
        CPI         HTAB
        JZ          read_type_4_tab
        ;
        ; Store ordinary character in buffer, and check for end of buffer
        ;
        STAX        D
        INX         D
        DCX         B
        MOV         A,B
        ORA         C
        JNZ         read_type_4_get_next_char


;//////////////////////////////////////

read_line_overflow:
        MVI         A,ERROR_25
read_type_4_error:
        POP         H
        POP         D
        POP         B
        STC
        RET

read_wrong_file_type:
        MVI         A,ERROR_24
        STC
        RET


;//////////////////////////////////////

read_type_4_newline:
        ;
        ; Store cartridge return char to terminate line
        ;
        STAX        D
        INX         D
        DCX         B
        MOV         A,B
        ORA         C
        JZ          read_line_overflow
        ;
        ; Add linefeed character to buffer as a buffer overrun marker
        ;
        MVI         A,LF
        STAX        D
        MOV         A,M             ; nested_FCB + FCB_TYPE
        CPI         3
        JZ          read_type_4_echo_newline
        ANA         A
read_type_4_end:
        POP         H
        POP         D
        POP         B
        RET

read_type_4_echo_newline:
        ;
        ; Output newline directly to nested echo-file's nested output file
        ;
        INX         H
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; nested_FCB + 004H, output file reference
        INX         H
        MOV         D,M
        XCHG
        MVI         A,LF
        CALL        OUTCHAR
        JMP         read_type_4_end


;//////////////////////////////////////

read_type_4_del:
        ;
        ; Erase the current line in the buffer
        ;
        MOV         A,M
        CPI         3
        JZ          read_type_4_echo_eraseline
        POP         H
        JMP         read_reset_type_4_buffer

read_type_4_echo_eraseline:
        ;
        ; Output erase line to nested echo-file
        ;
        MVI         A,ERLIN
        CALL        OUTCHAR
        JC          read_type_4_end
        POP         H
        JMP         read_reset_type_4_buffer


;//////////////////////////////////////

read_type_4_tab:
        ;
        ; Add space until next 8 character-group boundary
        ;
        MVI         A,' '
read_add_next_tab_space:
        ;
        ; Add space to buffer
        ;
        STAX        D
        INX         D
        DCX         B
        MOV         A,B
        ORA         C
        JZ          read_line_overflow
        MOV         A,C
        ;
        ; Check for buffer index modulus 8
        ;
        ANI         007H
        JZ          read_type_4_get_next_char
        ;
        ; Assume linked file is an echo file, output the added space there too
        ;
        MVI         A,' '
        CALL        OUTCHAR
        JC          read_type_4_end
        JMP         read_add_next_tab_space


;//////////////////////////////////////

read_type_4_backspace:
        ;
        ; Backtrak index and check for buffer underrun marker
        ;
        DCX         D
        LDAX        D
        CPI         0FFH
        JNZ         read_type_4_erase_char
        ;
        ; Go back to start if underrun happened
        ;
        INX         D
        JMP         read_type_4_get_next_char

read_type_4_erase_char:
        ;
        ; Check if nested file is an echo file (presumably on a terminal)
        ;
        INX         B
        MOV         A,M
        CPI         3
        JNZ         read_type_4_get_next_char
        ;
        ; If so, blank the character removed from buffer on the terminal screen
        ;
        MVI         A,' '
        CALL        OUTCHAR
        JC          read_type_4_end
        MVI         A,CURL
        CALL        OUTCHAR
        JC          read_type_4_end
        JMP         read_type_4_get_next_char


;//////////////////////////////////////////////////////////////////////////////
;//
;//     INTEL module
;//
;//         Device driver for Intel floppy block device files. This is the main
;//         disk format used by TOS and XMON, and the module also contains some
;//         helper-functions for handling blocks on Intel-disks.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Has a bug where releasing a block will toggle it being
;//                    reserved or available, instead of guarantee it being
;//                    released
;//                 -> Has a bug where if an Intel output file is closed with it's
;//                    last linking-block (out of several) being empty, it will
;//                    keep the empty linking-block as well
;//                 -> Has a bug where if the last linking-block is full when an
;//                    output file is closed, then the bytepair immediately after
;//                    the linking block buffer will be interpreted as an unused
;//                    data-block address to be released
;//
;//             v1.4:
;//
;//                 -> Fixes the release block bug from v1.3
;//                 -> Clears the linking block address and buffer of an output
;//                    file currently being opened, until the first linking block
;//                    has properly been reserved on disk. If this fails, closing
;//                    the file later will silently abort without writing anything
;//                    to disk.
;//                 -> Adds write-protect attribute for output files to be written
;//                    as system files
;//
;//             v1.5a:
;//
;//                 -> Fixes Intel close on empty linking-block bug from v1.3
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Mapfile handling
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read mapfile from last disk which had a LOCDIR, LINK or LOAD call
        ;
intel_read_mapfile_to_cache:
        ;
        ; Get first half of mapfile into buffer
        ;
        LHLD        MAP1
        MOV         B,H
        MOV         C,L
        LXI         H,BUF2
        LDA         UNIT
        CALL        DSRDW
        RC
        ;
        ; Get second half of mapfile into buffer
        ;
        LHLD        MAP2
        MOV         B,H
        MOV         C,L
        LXI         H,BUF1
        LDA         UNIT
        CALL        DSRDW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write mapfile to last disk which had a LOCDIR, LINK or LOAD call
        ;
intel_write_mapfile_from_cache:
        ;
        ; Write first half of mapfile buffer to disk
        ;
        LHLD        MAP1
        MOV         B,H
        MOV         C,L
        LXI         H,BUF2
        LDA         UNIT
        CALL        DSWRW
        RC
        ;
        ; Write second half of mapfile buffer to disk
        ;
        LHLD        MAP2
        MOV         B,H
        MOV         C,L
        LXI         H,BUF1
        LDA         UNIT
        CALL        DSWRW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert from block address to mapfile byte-pointer and bitmask
        ;
intel_mapfile_bit_lookup:
        ;
        ; Look up block in mapfile pt1: Multiply track nr with 26
        ;
        MVI         H,000H
        MOV         L,B
        DAD         H
        PUSH        H
        DAD         H
        DAD         H
        PUSH        H
        DAD         H
        POP         D
        DAD         D
        POP         D
        DAD         D
        ;
        ; Look up block in mapfile pt2: Add sector nr - 1 to get map bit index
        ;
        LXI         D,000H
        MOV         E,C
        DAD         D
        DCX         H
        ;
        ; Look up block in mapfile pt3: Modulus index by 8 to get bit nr
        ;
        MOV         A,L
        ANI         007H
        MOV         C,A
        ;
        ; Look up block in mapfile pt4: Divide index by 8 to get byte nr
        ;
        MOV         A,H
        RLC
        RLC
        RLC
        RLC
        RLC
        ANI         0E0H
        MOV         B,A
        MOV         A,L
        RRC
        RRC
        RRC
        ANI         01FH
        ORA         B
        MOV         L,A
        MOV         A,H
        RRC
        RRC
        RRC
        ANI         01FH
        MOV         H,A
        ;
        ; Look up block in mapfile pt5: Set up pointer and bit mask
        ;
        LXI         D,BUF2
        DAD         D
        INR         C
        MVI         A,080H
shift_mapfile_bitmask_loop:
        DCR         C
        RZ
        RRC
        ANI         07FH
        JMP         shift_mapfile_bitmask_loop


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Release a given block from mapfile
        ;
T_RELBLK:
        PUSH        PSW
        PUSH        H
        PUSH        D
        PUSH        B
        ;
        ; Read mapfile from disk, release block, and write updates back to disk
        ;
        CALL        intel_read_mapfile_to_cache
        JC          intel_device_driver_error
        POP         B
        PUSH        B
        CALL        intel_mapfile_bit_lookup
        ANA         M
        XRA         M
        MOV         M,A
        CALL        intel_write_mapfile_from_cache
        JC          intel_device_driver_error
intel_mapfile_change_done:
        POP         B
        POP         D
        POP         H
        POP         PSW
        ANA         A
        RET

intel_device_driver_error:
        POP         B
        POP         D
        POP         H
        INX         SP
        INX         SP
        RET


;//////////////////////////////////////////////////////////////////////////////

linking_block_remaining_blocks:
        DB          000H
linking_block_ptr:
        DW          00000H


;//////////////////////////////////////

        ;
        ; Release the next A blocks from buffer starting at HL
        ;
T_RELN:
        PUSH        PSW
        PUSH        H
        PUSH        D
        PUSH        B
        SHLD        linking_block_ptr
        STA         linking_block_remaining_blocks
        ;
        ; Get mapfile from disk
        ;
        CALL        intel_read_mapfile_to_cache
        JC          intel_device_driver_error
intel_release_next_block:
        ;
        ; Get block address and erase from buffer
        ;
        LHLD        linking_block_ptr
        MOV         C,M
        MVI         M,000H
        INX         H
        MOV         B,M
        MVI         M,000H
        INX         H
        SHLD        linking_block_ptr
        ;
        ; Verify that the block is valid, and if so remove it from mapfile
        ;
        MOV         A,B
        ORA         C
        JZ          intel_release_blocks_done
        CALL        intel_mapfile_bit_lookup
        ANA         M
        XRA         M
        MOV         M,A
        ;
        ; Advance to next block in buffer
        ;
        LXI         H,linking_block_remaining_blocks
        DCR         M
        JNZ         intel_release_next_block
intel_release_blocks_done:
        ;
        ; Write changes to mapfile back to disk
        ;
        CALL        intel_write_mapfile_from_cache
        JNC         intel_mapfile_change_done
        JMP         intel_device_driver_error


;//////////////////////////////////////////////////////////////////////////////

intel_mapfile_byte_to_scan_ptr:
        DW          00000H
intel_mapfile_byte_to_scan:
        DB          000H
intel_mapfile_free_block_scan_bitmap:
        DB          000H
intel_next_free_block_addr:
        DW          00000H


;//////////////////////////////////////

        ;
        ; Get the first free block address on disk according to the mapfile
        ;
intel_get_first_free_block:
        LXI         H,BUF2
        LXI         D,DISK_TRACK*0 + DISK_SECTOR*1
intel_check_mapfile_byte:
        ;
        ; Check if next byte of mapfile is completely full
        ;
        MOV         A,M
        CPI         0FFH
        JNZ         intel_scan_mapfile_byte
        ;
        ; If so, advance to next byte, adding 8 sectors to scanning address
        ;
        INX         H
        MOV         A,E
        ADI         8
        MOV         E,A
        ;
        ; Check for end of track passed
        ;
        CPI         27
        JM          intel_check_mapfile_byte
        SUI         26
        MOV         E,A
        INR         D
        ;
        ; Check for end of disk
        ;
        MOV         A,D
        CPI         77
        JM          intel_check_mapfile_byte
intel_no_free_blocks:
        MVI         A,ERROR_2F
        STC
        RET


;//////////////////////////////////////

intel_scan_mapfile_byte:
        ;
        ; Prepare to search through a byte from the mapfile for an unused block
        ;
        SHLD        intel_mapfile_byte_to_scan_ptr
        STA         intel_mapfile_byte_to_scan
        MVI         B,080H
intel_check_mapfile_bit:
        ;
        ; Check current bit in selected mapfile byte
        ;
        ANA         B
        JZ          intel_empty_block_found
intel_continue_mapfile_scan:
        ;
        ; Advance to next block, in effect next sector of scanning address
        ;
        INR         E
        ;
        ; Check for end of track
        ;
        MOV         A,E
        CPI         27
        JNZ         intel_check_next_mapfile_bit
        MVI         E,1
        INR         D
        ;
        ; Check for end of disk
        ;
        MOV         A,D
        CPI         77
        JP          intel_no_free_blocks
intel_check_next_mapfile_bit:
        ;
        ; Advance to check next bit in current byte, checking for end of byte
        ;
        MOV         A,B
        RRC
        ANI         07FH
        JZ          intel_check_next_mapfile_byte
        ;
        ; If not, continue with next bit
        ;
        MOV         B,A
        LDA         intel_mapfile_byte_to_scan
        JMP         intel_check_mapfile_bit

intel_empty_block_found:
        ;
        ; Save block address of empty block, as well as bitmap of mapfile byte
        ;
        XCHG
        SHLD        intel_next_free_block_addr
        XCHG
        LHLD        intel_mapfile_byte_to_scan_ptr
        MOV         A,B
        STA         intel_mapfile_free_block_scan_bitmap
        ANA         A
        RET

        ;
        ; Advance to next byte in mapfile
        ;
intel_check_next_mapfile_byte:
        LHLD        intel_mapfile_byte_to_scan_ptr
        INX         H
        JMP         intel_check_mapfile_byte


;//////////////////////////////////////

        ;
        ; Get next free block address, according to disk mapfile
        ;
intel_get_next_free_block:
        ;
        ; Continue from previous scan
        ;
        LHLD        intel_next_free_block_addr
        XCHG
        LHLD        intel_mapfile_byte_to_scan_ptr
        LDA         intel_mapfile_free_block_scan_bitmap
        MOV         B,A
        JMP         intel_continue_mapfile_scan


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Reserve the next free block in mapfile
        ;
T_GETBLK:
        PUSH        PSW
        PUSH        H
        PUSH        D
        PUSH        B
        ;
        ; Read mapfile from disk and reserve next free block
        ;
        CALL        intel_read_mapfile_to_cache
        JC          intel_device_driver_error
        CALL        intel_get_first_free_block
        JC          intel_device_driver_error
        ORA         M
        MOV         M,A
        ;
        ; Write changes to mapfile back to disk
        ;
        PUSH        D
        CALL        intel_write_mapfile_from_cache
        POP         B
        JC          intel_device_driver_error
        POP         D
        POP         D
        POP         H
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Reserve the A next free blocks in buffer at HL
        ;
T_GETN:
        PUSH        PSW
        PUSH        H
        PUSH        D
        PUSH        B
        SHLD        linking_block_ptr
        STA         linking_block_remaining_blocks
        ;
        ; Read mapfile from disk and reserve next free block
        ;
        CALL        intel_read_mapfile_to_cache
        JC          intel_device_driver_error
        CALL        intel_get_first_free_block
        JC          intel_device_driver_error
intel_reserve_next_block:
        ORA         M
        MOV         M,A
        ;
        ; Add reserved block address to buffer and advance to next buffer entry
        ;
        LHLD        linking_block_ptr
        MOV         M,E
        INX         H
        MOV         M,D
        INX         H
        SHLD        linking_block_ptr
        LDA         linking_block_remaining_blocks
        DCR         A
        STA         linking_block_remaining_blocks
        JZ          intel_reserve_blocks_done
        ;
        ; Claim next free block and check for disk being full
        ;
        CALL        intel_get_next_free_block
        JNC         intel_reserve_next_block
        CPI         ERROR_2F
        JZ          intel_no_more_blocks_to_claim
        STC
        JMP         intel_device_driver_error

intel_no_more_blocks_to_claim:
        ;
        ; If disk is full, clear the rest of the block-address buffer
        ;
        LDA         linking_block_remaining_blocks
        LHLD        linking_block_ptr
intel_abort_remaining_block_claims_loop:
        MVI         M,000H
        INX         H
        MVI         M,000H
        INX         H
        DCR         A
        JNZ         intel_abort_remaining_block_claims_loop
intel_reserve_blocks_done:
        ;
        ; Write mapfile changes back to disk
        ;
        CALL        intel_write_mapfile_from_cache
        JC          intel_device_driver_error
        JMP         intel_mapfile_change_done


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set up registers and variables to handle file
        ;
device_driver_set_up_for_file:
        ;
        ; Verify that the file is set up and valid
        ;
        CALL        check_file_control_block
        RC
        ;
        ; Store references to various sections of the file control block
        ;
        SHLD        CTLBLK
        PUSH        PSW
        PUSH        D
        LXI         D,FCB_DRVNR
        DAD         D
        PUSH        H
        LXI         D,01EH - FCB_DRVNR
        DAD         D
        SHLD        current_fcb_plus_01EH
        POP         H
        ;
        ; Store file drive unit number
        ;
        MOV         A,M
        STA         UNIT
        POP         D
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Initialize for operating on intel file file
        ;
intel_set_up_for_file:
        CALL        device_driver_set_up_for_file
        RC
        ;
        ; Locate file on particular disk drive from file control block
        ;
        PUSH        PSW
        MOV         A,M             ; FCB + FCB_DRVNR
        INX         H               ; FCB + FCB_FNAME
        CALL        intel_get_map_ref_and_look_up_file
        JC          intel_return_error
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

intel_operation_end:
        JNC         intel_operation_ok
intel_operation_exception:
        STC
        POP         D
        POP         B
intel_return_error:
        INX         SP
        INX         SP
        LHLD        CTLBLK
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File IO routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Open Intel file at HL for input
        ;
intel_open_input:
        ;
        ; Initialize and look up file
        ;
        CALL        intel_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Verify that file is active and not deleted
        ;
        MOV         A,M
        ANA         A
        JZ          intel_file_to_open_found
        ;
        ; Else raise exception
        ;
        MVI         A,ERROR_31
        STC
        JMP         intel_operation_exception


;//////////////////////////////////////

intel_file_to_open_found:
        ;
        ; Get bytecount of last block
        ;
        LXI         D,00BH
        DAD         D
        MOV         A,M
        ;
        ; Get linking block address
        ;
        INX         H
        INX         H
        INX         H
        MOV         C,M
        INX         H
        MOV         B,M
        ;
        ; Store last block bytecount in file control block
        ;
        LHLD        current_fcb_plus_01EH
        MOV         M,A             ; FCB + 01EH, length of last data block
        ;
        ; Have file control block linking block index point to first entry
        ;
        INX         H
        MVI         M,004H          ; FCB + 01FH, linking block index
        ;
        ; Get pointer to linking block buffer from file control block
        ;
        INX         H
        MOV         E,M             ; FCB + 020H, linking block buffer pointer
        INX         H
        MOV         D,M
        ;
        ; Read linking block of file from disk into buffer
        ;
        XCHG
        LDA         UNIT
        CALL        DSRDW
        JC          intel_operation_exception
        ;
        ; Get data buffer length of file control block
        ;
        LHLD        CTLBLK
        LXI         D,FCB_BUFLEN+1
        DAD         D
        MOV         D,M
        DCX         H
        MOV         E,M             ; FCB + FCB_BUFLEN
        ;
        ; Set index to represent a full block buffer
        ;
        DCX         H
        INX         D
        MOV         M,D
        DCX         H
        MOV         M,E             ; FCB + FCB_BUFIDX
intel_operation_ok:
        ;
        ; Restore registers
        ;
        POP         D
        POP         B
        POP         PSW
        LHLD        CTLBLK
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

current_fcb_plus_01EH:
        DW          00000H
current_linking_block_buffer_ptr:
        DW          00000H
current_data_block_address:
        DW          00000H


;//////////////////////////////////////

        ;
        ; Read next block from Intel input file at HL
        ;
intel_read_input:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Check for forced end-of-file condition
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_EOF_NEXT
        JZ          intel_file_has_more_data
intel_file_out_of_data:
        ;
        ; Set end of file flag
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ORI         FM_EOF
        MOV         M,A
        SUB         A
        STC
        JMP         intel_operation_exception


;//////////////////////////////////////

intel_file_has_more_data:
        ;
        ; Get pointer to next data block address in linking block buffer
        ;
        LHLD        current_fcb_plus_01EH
        INX         H
        MOV         C,M             ; FCB + 01FH, linking block index
        MVI         B,000H
        INX         H
        MOV         E,M             ; FCB + 020H, linking block buffer pointer
        INX         H
        MOV         D,M
        XCHG
        SHLD        current_linking_block_buffer_ptr
        DAD         B
        ;
        ; Get next data block address, and verify that it's set
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        SHLD        current_data_block_address
        MOV         A,D
        ORA         E
        JZ          intel_file_out_of_data
        ;
        ; Advance linking-block index and check for end of linking block buffer
        ;
        LHLD        current_fcb_plus_01EH
        INX         H
        MOV         A,M             ; FCB + 01FH, linking block index
        INR         A
        INR         A
        MOV         M,A
        ANI         080H
        JZ          intel_read_mid_linking_block_data_block
        ;
        ; Index has overrun linking block, get block address to the next one
        ;
        LHLD        current_linking_block_buffer_ptr
        INX         H
        INX         H
        MOV         C,M
        INX         H
        MOV         B,M
        MOV         A,B
        ORA         C
        JZ          intel_read_last_data_block
        ;
        ; Read next linking block and reset index
        ;
        LDA         UNIT
        LHLD        current_linking_block_buffer_ptr
        CALL        DSRDW
        JC          intel_operation_exception
        LHLD        current_fcb_plus_01EH
        INX         H
        MVI         M,004H          ; FCB + 01FH, linking block index
        JMP         intel_read_data_block


;//////////////////////////////////////

intel_read_last_data_block:
        ;
        ; Set data block buffer length to length of last data block in file
        ;
        LHLD        current_fcb_plus_01EH
        MOV         A,M             ; FCB + 01EH, length of last data block
        LHLD        CTLBLK
        LXI         B,FCB_BUFLEN
        DAD         B
        MOV         M,A             ; FCB + FCB_BUFLEN
        INX         H
        MVI         M,000H
        ;
        ; Set early end-of-file flag
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ORI         FM_EOF_NEXT
        MOV         M,A
        JMP         intel_read_data_block


;//////////////////////////////////////

intel_read_mid_linking_block_data_block:
        ;
        ; Verify that next data-block address is valid
        ;
        LHLD        current_data_block_address
        MOV         A,M
        INX         H
        ORA         M
        JZ          intel_read_last_data_block
intel_read_data_block:
        ;
        ; Reset data buffer index of file
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        INX         H
        ;
        ; Read the next data block of file
        ;
        INX         H
        INX         H
        MOV         B,D
        MOV         C,E
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        LDA         UNIT
        CALL        DSRDW
        JMP         intel_operation_end


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Close Intel input file at HL
        ;
intel_close_input:
        ;
        ; Close any block-device input file at HL
        ;
device_driver_close_input_file:
        CALL        check_file_control_block
        RC
device_driver_close_valid_input_file:
        ;
        ; Clear most mode flags of file, to close it
        ;
        PUSH        PSW
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_ASSIGNED
        MOV         M,A
        DCX         H
        ;
        ; Assess if file was assigned at the command line
        ;
        JNZ         device_driver_dealloc_block_file
        POP         PSW
        ANA         A
        RET

device_driver_dealloc_block_file:
        ;
        ; If file was assigned at the command line, de-allocate the fcb now
        ;
        POP         PSW
        CALL        BUFDEALLOC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Open Intel file at HL for output
        ;
intel_open_output:
        ;
        ; Initialize and look up file
        ;
        CALL        intel_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Check if the file already exists
        ;
        MOV         A,M
        ANA         A
        JNZ         intel_create_output_file
intel_output_file_already_exists:
        ;
        ; If file exists, throw an exception
        ;
        MVI         A,ERROR_32
        STC
        JMP         intel_operation_exception


;//////////////////////////////////////

intel_create_output_file:
        ;
        ; Clear current linking block address for the time being
        ;
        LHLD        current_fcb_plus_01EH
        DCX         H
        MVI         M,000H
        DCX         H
        MVI         M,000H          ; FCB + 01CH, current linking block address
        INX         H
        INX         H
        ;
        ; Initialize new empty main linking block for file
        ;
        INX         H
        MVI         M,004H          ; FCB + 01FH, linking block index
        INX         H
        MOV         E,M             ; FCB + 020H, linking block buffer pointer
        INX         H
        MOV         D,M
        XCHG
        SHLD        current_linking_block_buffer_ptr
        ;
        ; Clear linking block buffer
        ;
        MVI         A,128
intel_clear_linking_block_buffer_loop:
        MVI         M,000H
        INX         H
        DCR         A
        JNZ         intel_clear_linking_block_buffer_loop
        ;
        ; Reserve a free block on disk for this linking block
        ;
        LHLD        current_linking_block_buffer_ptr
        CALL        T_GETBLK
        JC          intel_operation_exception
        LHLD        CTLBLK
        LXI         D,01CH
        DAD         D
        MOV         M,C             ; FCB + 01CH, current linking block address
        INX         H
        MOV         M,B
        ;
        ; Initialize forward and backward links of new linking block
        ;
        LHLD        current_linking_block_buffer_ptr
        SUB         A
        MOV         M,A
        INX         H
        MOV         M,A
        INX         H
        MOV         M,A
        INX         H
        MOV         M,A
        INX         H
        ;
        ; Reserve all data-blocks in linking block as long as file is open
        ;
        MVI         A,62
        CALL        T_GETN
        JC          intel_operation_exception
        ;
        ; Reset new output file data index
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        JMP         intel_operation_ok


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write current block to intel file at HL
        ;
intel_write_output:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Get next data block index in linking block
        ;
        LHLD        current_fcb_plus_01EH
        INX         H
        MOV         A,M             ; FCB + 01FH, linking block index
        INX         H
        MOV         E,M             ; FCB + 020H, linking block buffer pointer
        INX         H
        MOV         D,M
        XCHG
        SHLD        current_linking_block_buffer_ptr
        ;
        ; Check for linking block overrun for next data block entry
        ;
        MOV         B,A
        ANI         080H
        MOV         A,B
        JZ          intel_write_has_data_block


;//////////////////////////////////////

        ;
        ; Reserve block for new linking block to chain to file
        ;
        LDA         UNIT
        CALL        intel_ready_disk
        JC          intel_operation_exception
        CALL        T_GETBLK
        JC          intel_operation_exception
        ;
        ; Chain new linking block onto previous linking block forwards pointer
        ;
        LHLD        current_linking_block_buffer_ptr
        INX         H
        INX         H
        MOV         M,C
        INX         H
        MOV         M,B
        ;
        ; Write previous linking block to disk
        ;
        MOV         E,C
        MOV         D,B
        LHLD        current_fcb_plus_01EH
        DCX         H
        MOV         B,M
        DCX         H
        MOV         C,M             ; FCB + 01CH, current linking block address
        LDA         UNIT
        LHLD        current_linking_block_buffer_ptr
        CALL        DSWRW
        JC          intel_operation_exception
        ;
        ; Chain old linking block to new linking block backwards pointer
        ;
        LHLD        current_linking_block_buffer_ptr
        MOV         M,C
        INX         H
        MOV         M,B
        INX         H
        ;
        ; Clear new linking block forward link
        ;
        MVI         M,000H
        INX         H
        MVI         M,000H
        INX         H
        ;
        ; Reserve all data-blocks in new linking block as long as file is open
        ;
        MVI         A,62
        CALL        T_GETN
        JC          intel_operation_exception
        ;
        ; Update data for new linking block in file control block
        ;
        LHLD        current_fcb_plus_01EH
        INX         H
        MVI         M,004H          ; FCB + 01FH, linking block index
        DCX         H
        DCX         H
        MOV         M,D
        DCX         H
        MOV         M,E             ; FCB + 01CH, current linking block address
        ;
        ; Point to first data-block address entry
        ;
        MVI         A,004H


;//////////////////////////////////////

intel_write_has_data_block:
        ;
        ; Get data block address from linking block
        ;
        LHLD        current_linking_block_buffer_ptr
        MOV         E,A
        MVI         D,000H
        DAD         D
        MOV         C,M
        INX         H
        MOV         B,M
        ;
        ; Reset data buffer index
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        INX         H
        ;
        ; Write current block to disk at the given data block address
        ;
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        MOV         A,B
        ORA         C
        JZ          intel_write_disk_full
        LDA         UNIT
        CALL        DSWRW
        JC          intel_operation_exception
        ;
        ; Advance to next linking block
        ;
        LHLD        current_fcb_plus_01EH
        INX         H
        INR         M               ; FCB + 01FH, linking block index
        INR         M
        JMP         intel_operation_ok

intel_write_disk_full:
        MVI         A,ERROR_33
        JMP         intel_operation_exception


;//////////////////////////////////////////////////////////////////////////////

intel_output_file_dir_entry_ptr:
        DW          00000H
intel_output_file_dir_entry_block_addr:
        DW          00000H
intel_file_next_block_in_linking_buffer_ptr:
        DW          00000H
intel_file_total_block_count:
        DW          00000H
intel_file_first_linking_block_addr:
        DW          00000H


;//////////////////////////////////////

        ;
        ; Close Intel output file at HL
        ;
intel_close_output:
        ;
        ; Check if file already exists
        ;
        CALL        intel_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        MOV         A,M
        ANA         A
        JZ          intel_output_file_already_exists
        SHLD        intel_output_file_dir_entry_ptr
        ;
        ; Abort silently if OPEN failed and linking block address is invalid
        ;
        LHLD        current_fcb_plus_01EH
        DCX         H
        MOV         A,M
        DCX         H
        ORA         M               ; FCB + 01CH, current linking block address
        JZ          intel_operation_ok
        ;
        ; Get location of data block containing available file entry
        ;
        LHLD        TRK
        DCX         H
        MOV         D,M
        DCX         H
        MOV         E,M
        XCHG
        SHLD        intel_output_file_dir_entry_block_addr
        ;
        ; Check if linking block is empty
        ;
        LHLD        current_fcb_plus_01EH
        INX         H
        MOV         A,M             ; FCB + FCB_LNKIDX
        CPI         005H
        JNC         intel_write_final_block
        ;
        ; If so, check if this is the first linking block
        ;
        INX         H
        MOV         E,M             ; FCB + FCB_LNKPTR
        INX         H
        MOV         D,M
        XCHG
        MOV         A,M
        INX         H
        ORA         M
        JNZ         intel_write_final_block
        ;
        ; If so, check if file is completely empty
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MOV         A,M             ; FCB + FCB_BUFIDX
        INX         H
        ORA         M
        JNZ         intel_write_final_block
        ;
        ; If so, force block length to zero here as the write will be skipped
        ;
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFLEN
        INX         H
        MVI         M,000H
intel_write_final_block:
        ;
        ; Set block length to index before writing the last block
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFIDX
        INX         H
        MOV         D,M
        INX         H
        MOV         A,D
        ORA         E
        JZ          intel_close_data_write_done
        MOV         M,E             ; FCB + FCB_BUFLEN
        INX         H
        MOV         M,D
        ;
        ; Write data-block to file
        ;
        LHLD        CTLBLK
        CALL        WRITE
        JC          intel_operation_exception
intel_close_data_write_done:


;//////////////////////////////////////

        ;
        ; Set up pointers for state of the linking block based on fcb
        ;
        LHLD        current_fcb_plus_01EH
        INX         H
        MOV         E,M             ; FCB + 01FH, linking block index
        MVI         D,000H
        INX         H
        MOV         A,M             ; FCB + 020H, linking block buffer pointer
        INX         H
        MOV         H,M
        MOV         L,A
        SHLD        current_linking_block_buffer_ptr
        DAD         D
        SHLD        intel_file_next_block_in_linking_buffer_ptr
        ;
        ; Count reserved but unused blocks of output file
        ;
intel_close_count_unused_blocks_loop:
        ;
        ; Check for unreserved data block entry
        ;
        MOV         A,M
        INX         H
        INX         H
        ANA         A
        JZ          intel_unused_blocks_counted
        ;
        ; Count unused reserved data block
        ;
        INR         D
        MOV         A,E
        ADI         002H
        MOV         E,A
        ;
        ; Check for end of linking block
        ;
        ANI         080H
        JZ          intel_close_count_unused_blocks_loop
intel_unused_blocks_counted:
        ;
        ; Release unused pre-reserved data blocks
        ;
        MOV         A,D
        LHLD        intel_file_next_block_in_linking_buffer_ptr
        CALL        T_RELN
        JC          intel_operation_exception
        ;
        ; Set up to write final linking block to disk
        ;
        LHLD        CTLBLK
        LXI         D,01CH
        DAD         D
        MOV         C,M             ; FCB + 01CH, current linking block address
        INX         H
        MOV         B,M
        INX         H
        ;
        ; Set up to calculate total block count
        ;
        INX         H
        MOV         A,M             ; FCB + 01FH, linking block index
        SUI         004H
        RRC
        ANI         07FH
        INR         A
        STA         intel_file_total_block_count
        SUB         A
        STA         intel_file_total_block_count+1
        ;
        ; Write final linking block to disk
        ;
        LHLD        current_linking_block_buffer_ptr
        LDA         UNIT
        CALL        DSWRW
        JC          intel_operation_exception
        ;
        ; Add block count of all full linking blocks to total block count
        ;
intel_count_total_blocks_loop:
        ;
        ; Look up previous linking block reference in current linking block
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        MOV         A,E
        ORA         D
        JZ          intel_total_block_count_found
        ;
        ; Read the previous linking block in chain
        ;
        MOV         B,D
        MOV         C,E
        LDA         UNIT
        LHLD        current_linking_block_buffer_ptr
        CALL        DSRDW
        JC          intel_operation_exception
        ;
        ; Add the data blocks to total count
        ;
        LHLD        intel_file_total_block_count
        LXI         D,62
        DAD         D
        SHLD        intel_file_total_block_count
        LHLD        current_linking_block_buffer_ptr
        JMP         intel_count_total_blocks_loop

intel_total_block_count_found:


;//////////////////////////////////////

        ;
        ; Store block address of first linking block
        ;
        MOV         H,B
        MOV         L,C
        SHLD        intel_file_first_linking_block_addr
        ;
        ; Read back the directory block with the available file entry
        ;
        LHLD        intel_output_file_dir_entry_block_addr
        MOV         B,H
        MOV         C,L
        LXI         H,BUF2
        LDA         UNIT
        CALL        DSRDW
        JC          intel_operation_exception
        ;
        ; Claim available file entry
        ;
        LHLD        intel_output_file_dir_entry_ptr
        XCHG
        SUB         A
        STAX        D
        INX         D
        ;
        ; Copy filename from file control block to newly claimed file entry
        ;
        LXI         B,FCB_FNAME
        LHLD        CTLBLK
        DAD         B
        MVI         B,9
intel_copy_next_filename_char:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         B
        JNZ         intel_copy_next_filename_char
        ;
        ; Check drive format flag to see if file is to have system attributes
        ;
        LHLD        CTLBLK
        LXI         B,FCB_DRVFMT
        DAD         B
        MOV         A,M
        ANI         DF_SYSFILE
        JZ          intel_close_output_no_attr
        MVI         A,ATTR_I + ATTR_S + ATTR_W
        JMP         intel_close_output_update_attr

intel_close_output_no_attr:
        SUB         A
intel_close_output_update_attr:
        STAX        D
        INX         D
        ;
        ; Set file entry length of last block in file
        ;
        LHLD        CTLBLK
        LXI         B,FCB_BUFLEN
        DAD         B
        MOV         A,M
        STAX        D
        INX         D
        ;
        ; Set file entry total block count
        ;
        LHLD        intel_file_total_block_count
        DCX         H
        XCHG
        MOV         M,E
        INX         H
        MOV         M,D
        INX         H
        XCHG
        ;
        ; Set file entry linking block address
        ;
        LHLD        intel_file_first_linking_block_addr
        XCHG
        MOV         M,E
        INX         H
        MOV         M,D
        ;
        ; Write finished new file entry to disk
        ;
        LHLD        intel_output_file_dir_entry_block_addr
        MOV         B,H
        MOV         C,L
        LXI         H,BUF2
        LDA         UNIT
        CALL        DSWRW
        JC          intel_operation_exception
        ;
        ; If file was assigned at the command line, de-allocate the fcb now
        ;
        LHLD        CTLBLK
        CALL        device_driver_close_valid_input_file
        JMP         intel_operation_end


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Verify intel filesystem and look up file on referenced disk drive
        ;
intel_get_map_ref_and_look_up_file:
        SHLD        UNAM
        CALL        intel_ready_disk
        RC
        LHLD        UNAM
        LDA         UNIT
        CALL        LOCDIR
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Verify intel filesystem by looking up and refreshing mapfile metadata
        ;
intel_ready_disk:
        ;
        ; Look up mapfile and check that it exists
        ;
        LXI         H,intel_mapfile_name
        CALL        LOCDIR
        RC
        MOV         A,M
        ANA         A
        JZ          intel_mapfile_found
        ;
        ; If not, throw an exception
        ;
        MVI         A,ERROR_0F
        STC
        RET

intel_mapfile_found:
        ;
        ; Get linking block address of mapfile
        ;
        LXI         D,00EH
        DAD         D
        PUSH        B
        MOV         C,M
        INX         H
        MOV         B,M
        ;
        ; Read mapfile linking block
        ;
        LXI         H,BUF2
        LDA         UNIT
        CALL        DSRDW
        POP         B
        RC
        ;
        ; Update cached mapfile data block addresses
        ;
        LHLD        BUF2 + 004H
        SHLD        MAP1
        LHLD        BUF2 + 006H
        SHLD        MAP2
        ANA         A
        RET


;//////////////////////////////////////

intel_mapfile_name:
        DB          'ISIS',NULL,NULL
        DB          'MAP'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     TIME module
;//
;//         A one-shot timer that can be set to trigger at a set time into the
;//         future. This is a simple-to-use wrapper for the XMON timer function.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Timer setup
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set oneshot-timer routine to HL and countdown to DE frames (50Hz)
        ;
T_STIMER:
        DI
        SHLD        TIMEAD
        XCHG
        SHLD        TIMER
        XCHG
        EI
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     IBM module
;//
;//         Device driver for block device files on IBM 3740 floppy disks. This
;//         enables TOS to use floppy disks on floppy-disks written on IBM systems.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Bug where the file mode byte is used instead of the format
;//                    flag for determining ASCII or EBCDIC for write-operations of
;//                    IBM files
;//                 -> Bug where IBM EOE and EOD sector numbers are treated as
;//                    inclusive, not exclusive as per the format definition
;//
;//             v1.4:
;//
;//                 -> Less shared cleanup code with Intel device driver
;//                 -> Introduces a bug where the binary file mode flag is used in
;//                    place of the detect EOF file mode flag
;//
;//             v1.5a:
;//
;//                 -> Clears block data-buffer entirely after WRITE and OPEN
;//                 -> Checks for IBM end-of-file on OPEN, in case of empty file,
;//                    but this implementation does not assume data in the file
;//                    index record can be invalid
;//                 -> Fixes the ASCII/EBCDIC flag bug from v1.3
;//                 -> Fixes the EOE/EOD sector off-by-one bug from v1.3
;//                 -> Fixes the EOF flag bug from v1.4
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert the value in A into a 2-digit ASCII number in string at DE
        ;
bin_to_2_digit_ascii_decimal:
        ;
        ; Divide by 10 to separate the two decimal digits
        ;
        PUSH        B
        MVI         B,0
decimal_division_loop:
        CPI         10
        JM          decimal_division_done
        SUI         10
        INR         B
        JMP         decimal_division_loop

decimal_division_done:
        MOV         C,A
        ;
        ; Convert each digit from BCD to ASCII
        ;
        MOV         A,B
        ADI         '0'
        STAX        D
        INX         D
        MOV         A,C
        ADI         '0'
        STAX        D
        INX         D
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert a 2 digit ASCII number at DE to binary value in A
        ;
ascii_decimal_2_digit_to_bin:
        ;
        ; Get most signifficant digit
        ;
        PUSH        B
        CALL        ascii_decimal_digit_to_bin
        JC          ascii_decimal_conversion_done
        ;
        ; Multiply digit value with 10
        ;
        ADD         A
        MOV         B,A
        ADD         A
        ADD         A
        ADD         B
        ;
        ; Get least signifficant digit and add to value
        ;
        MOV         B,A
        CALL        ascii_decimal_digit_to_bin
        ADD         B
        ANA         A
ascii_decimal_conversion_done:
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert single ASCII digit at DE to binary value in A
        ;
ascii_decimal_digit_to_bin:
        ;
        ; Skip up to one leading space
        ;
        LDAX        D
        INX         D
        CPI         ' '
        JNZ         ascii_digit_ready
        MVI         A,'0'
ascii_digit_ready:
        ;
        ; Verify and convert digit
        ;
        CPI         '0'
        JM          ascii_digit_not_numeric
        CPI         '9'+1
        JP          ascii_digit_not_numeric
        SUI         '0'
        RET

ascii_digit_not_numeric:
        MVI         A,ERROR_0C
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert a 3 digit ASCII number at DE into HL
        ;
ascii_decimal_3_digit_to_bin:
        ;
        ; Convert two most signifficant digits to binary first
        ;
        PUSH        B
        CALL        ascii_decimal_2_digit_to_bin
        JC          ascii_decimal_conversion_done
        PUSH        H
        MOV         L,A
        MVI         H,000H
        ;
        ; Multiply current value by 10
        ;
        DAD         H
        PUSH        H
        POP         B
        DAD         H
        DAD         H
        DAD         B
        ;
        ; Get least signifficant digit and add to value
        ;
        CALL        ascii_decimal_digit_to_bin
        JC          ascii_3_digit_decimal_conversion_done
        MOV         C,A
        MVI         B,000H
        DAD         B
        XCHG
        ;
        ; Restore registers
        ;
        POP         H
        POP         B
        ANA         A
        RET

ascii_3_digit_decimal_conversion_done:
        POP         H
        POP         B
        RET


;//////////////////////////////////////////////////////////////////////////////

ibm_current_file_sector:
        DB          000H
ibm_bad_track_list:
        DB          000H, 000H


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read record from IBM 3740 disk in the appropriate character encoding
        ;
read_ibm_disk_record:
        ;
        ; Get disk format byte
        ;
        PUSH        H
        LHLD        CTLBLK
        PUSH        D
        LXI         D,FCB_DRVFMT
        DAD         D
        POP         D
        MOV         A,M             ; FCB + FCB_DRVFMT
        POP         H
        ;
        ; Check for EBCDIC disk flag and use appropriate disk read call
        ;
        ANI         DF_EBCDIC
        LDA         UNIT
        JNZ         read_ibm_ebcdic_sector
        CALL        DSRDW
        RET

read_ibm_ebcdic_sector:
        CALL        DSRAW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write record from IBM 3740 disk in the appropriate character encoding
        ;
write_ibm_disk_record:
        ;
        ; Get disk format byte
        ;
        PUSH        H
        LHLD        CTLBLK
        PUSH        D
        LXI         D,FCB_DRVFMT
        DAD         D
        POP         D
        MOV         A,M             ; FCB + FCB_DRVFMT
        POP         H
        ;
        ; Check for EBCDIC disk flag and use appropriate disk write call
        ;
        ANI         DF_EBCDIC
        LDA         UNIT
        JNZ         write_ibm_ebcdic_sector
        CALL        DSWRW
        JMP         ibm_write_prepare_buffer

write_ibm_ebcdic_sector:
        CALL        DSWAW


;//////////////////////////////////////

ibm_write_prepare_buffer:
        ;
        ; Save registers
        ;
        PUSH        PSW
        PUSH        H
        PUSH        D
        ;
        ; Point to block buffer
        ;
        LXI         D,FCB_BUFPTR
        LHLD        CTLBLK
        DAD         D
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        ;
        ; Clear IBM entire output buffer
        ;
        MVI         E,128
ibm_write_clear_buffer_loop:
        MVI         M,NULL
        INX         H
        DCR         E
        JNZ         ibm_write_clear_buffer_loop
        ;
        ; Recover registers
        ;
        POP         D
        POP         H
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Look up file with filename at HL on IBM 3740 floppy disk unit A
        ;
find_ibm_file_index:
        ;
        ; Save file info and reset disk drive
        ;
        SHLD        NAME
        STA         UNIT
        CALL        DCALW
        RC
        ;
        ; Read in record containint info about bad tracks
        ;
        LXI         B,DISK_TRACK*0 + DISK_SECTOR*5
        LXI         H,BUF1
        CALL        read_ibm_disk_record
        RC
        LXI         D,BUF1 + 006H
        CALL        ascii_decimal_2_digit_to_bin
        RC
        STA         ibm_bad_track_list
        LXI         D,BUF1 + 00AH
        CALL        ascii_decimal_2_digit_to_bin
        RC
        STA         ibm_bad_track_list+1
        ;
        ; Scan through IBM disk file records for a file matching requested name
        ;
        LXI         B,DISK_TRACK*0 + DISK_SECTOR*8
check_ibm_file_index_loop:
        LXI         H,BUF1
        CALL        read_ibm_disk_record
        JC          ibm_file_index_error
        ;
        ; Compare file record name with requested filename
        ;
        LXI         D,BUF1 + 005H
        LHLD        NAME
        MVI         B,8
ibm_compare_filename_loop:
        LDAX        D
        CMP         M
        JNZ         not_this_ibm_file_index
        INX         D
        INX         H
        DCR         B
        JNZ         ibm_compare_filename_loop
        ;
        ; File found, set record sector number
        ;
        MOV         A,C
        STA         ibm_current_file_sector
        ANA         A
        RET

not_this_ibm_file_index:
        ;
        ; Have B represent track number before continuing
        ;
        MVI         B,0
check_next_ibm_file_index:
        ;
        ; Advance to next file index record
        ;
        INR         C
        MOV         A,C
        CPI         27
        JNZ         check_ibm_file_index_loop
        MVI         A,ERROR_0A
        STC
        RET


;//////////////////////////////////////

ibm_file_index_error:
        ;
        ; Waiver exception for deleted file entries
        ;
        CPI         ERROR_20
        JZ          check_next_ibm_file_index
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

ibm_check_for_file_end:
        ;
        ; Get block address of next data block
        ;
        LHLD        current_fcb_plus_01EH
        DCX         H
        DCX         H
        MOV         C,M             ; FCB + 01CH, sector of next data record
        INX         H
        MOV         B,M             ; FCB + 01DH, track of next data record
        INX         H
        ;
        ; Check if at last block address of file
        ;
        MOV         A,M             ; FCB + 01EH, sector number of file tail
        INX         H
        CMP         C
        RNZ
        MOV         A,M             ; FCB + 01FH, track number of file tail
        CMP         B
        RNZ
        ;
        ; If so, set pending end-of-file flag
        ;
        PUSH        H
        LHLD        CTLBLK
        INX         H
        MOV         A,M
        ORI         FM_EOF_NEXT
        MOV         M,A
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Ready IBM file for IO operations
        ;
ibm_set_up_for_file:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Locate file on disk
        ;
        MOV         A,M             ; FCB + FCB_UNIT
        INX         H
        CALL        find_ibm_file_index
ibm_operation_end:
        JC          ibm_operation_exception
ibm_operation_ok:
        ;
        ; Recover registers and return
        ;
        POP         D
        POP         B
        POP         PSW
        ANA         A
        LHLD        CTLBLK
        RET


;//////////////////////////////////////

ibm_operation_exception:
        ;
        ; Recover registers other than exception, and return
        ;
        STC
        POP         D
        POP         B
        INX         SP
        INX         SP
        LHLD        CTLBLK
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Device driver routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Open IBM file for input
        ;
ibm_open_input:
        ;
        ; Open any IBM file
        ;
ibm_open_file:
        ;
        ; Set up file control block and save registers
        ;
        CALL        ibm_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Get buffer length from file record
        ;
        LXI         D,BUF1 + 018H
        CALL        ascii_decimal_3_digit_to_bin
        JC          ibm_operation_exception
        LHLD        CTLBLK
        LXI         B,FCB_BUFLEN
        DAD         B
        MOV         M,E
        INX         H
        MOV         M,D
        ;
        ; Get block address of next data-block in file record in
        ;
        LHLD        current_fcb_plus_01EH
        DCX         H
        LXI         D,BUF1 + 01CH
        CALL        ascii_decimal_2_digit_to_bin
        JC          ibm_operation_exception
        MOV         M,A             ; FCB + 01DH, track of next data record
        DCX         H
        INX         D
        CALL        ascii_decimal_2_digit_to_bin
        JC          ibm_operation_exception
        MOV         M,A             ; FCB + 01CH, sector of next data record
        INX         H
        INX         H
        INX         H
        ;
        ; Get tailing file data block address, EOE for input, EOD for output
        ;
        LXI         D,BUF1 + 04AH
        PUSH        H
        LHLD        CTLBLK
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        POP         H
        ANI         FM_INPUT
        JNZ         ibm_open_set_file_tail
        LXI         D,BUF1 + 022H
ibm_open_set_file_tail:
        ;
        ; Set selected field as tailing file data block in fcb
        ;
        CALL        ascii_decimal_2_digit_to_bin
        JC          ibm_operation_exception
        MOV         M,A             ; FCB + 01FH, track number of file tail
        DCX         H
        INX         D
        CALL        ascii_decimal_2_digit_to_bin
        JC          ibm_operation_exception
        MOV         M,A             ; FCB + 01EH, sector number of file tail
        ;
        ; Use block before tailing block since fcb tailing block is inclusvie
        ;
        DCR         M
        JNZ         ibm_open_file_tail_ready
        MVI         M,26
        INX         H
        DCR         M
        DCX         H
ibm_open_file_tail_ready:
        INX         H
        INX         H
        ;
        ; Set bad tracks in file control block
        ;
        XCHG
        LHLD        ibm_bad_track_list
        XCHG
        MOV         M,E             ; FCB + 020H, first IBM disk error track
        INX         H
        MOV         M,D             ; FCB + 021H, second IBM disk error track
        INX         H
        ;
        ; Set file index sector in file control block
        ;
        LDA         ibm_current_file_sector
        MOV         M,A             ; FCB + 022H, sector number of file index
        ;
        ; Get pointer to block data buffer
        ;
        LHLD        CTLBLK
        LXI         D,FCB_BUFPTR
        DAD         D
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        ;
        ; Clear IBM block buffer
        ;
        MVI         C,128
        XRA         A
ibm_open_clear_buffer_loop:
        STAX        D
        INX         D
        DCR         C
        JNZ         ibm_open_clear_buffer_loop
        ;
        ; Do final checks on opened file
        ;
        CALL        ibm_check_for_file_end
        JMP         ibm_operation_ok


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Open IBM file for output
        ;
ibm_open_output:
        CALL        ibm_open_file
        RC
        ;
        ; Increase file tailing block nr, as this is exclusive for output files
        ;
        PUSH        H
        PUSH        D
        PUSH        PSW
        LXI         D,01EH
        DAD         D
        INR         M               ; FCB + 01EH, sector number of file tail
        MOV         A,M
        CPI         27
        JC          ibm_open_next_block_ready
        MVI         M,1
        INX         H
        INR         M               ; FCB + 01FH, track number of file tail
ibm_open_next_block_ready:
        POP         PSW
        POP         D
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Advance to next data block in IBM 3740 type file
        ;
ibm_advance_to_next_block:
        CALL        ibm_check_for_file_end
        ;
        ; Advance to next data-block in file and handle track overrun if needed
        ;
        PUSH        B
        DCX         H
        DCX         H
        INR         C
        MOV         A,C
        CPI         27
        JNZ         ibm_next_data_block_ready
        MVI         C,1
        INR         B
ibm_next_data_block_ready:
        MOV         M,B             ; FCB + 01DH, track of next data record
        DCX         H
        MOV         M,C             ; FCB + 01CH, sector of next data record
        INX         H
        INX         H
        POP         B
        ;
        ; Check if record is on an error-track
        ;
        INX         H
        INX         H
        MOV         A,M             ; FCB + 020H, first IBM disk error track
        CMP         B
        JNZ         not_first_error_track
        ;
        ; Use track 75 instead of error track 1
        ;
        MVI         B,75
        JMP         error_track_check_done

not_first_error_track:
        INX         H
        MOV         A,M             ; FCB + 021H, second IBM disk error track
        CMP         B
        JNZ         error_track_check_done
        ;
        ; Use track 76 instead of error track 2
        ;
        MVI         B,76
error_track_check_done:
        ;
        ; Get pointer to block data buffer
        ;
        LHLD        CTLBLK
        LXI         D,FCB_BUFPTR
        DAD         D
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read input from IBM file
        ;
ibm_read_input:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Get file mode and reset block index
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        ;
        ; Check if the current block was the last block of the file
        ;
        ANI         FM_EOF_NEXT
        JZ          ibm_not_end_of_file
ibm_end_of_file:
        ;
        ; If so, set end of file flag
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ORI         FM_EOF
        MOV         M,A
        SUB         A
        STC
        JMP         ibm_operation_exception


;//////////////////////////////////////

ibm_not_end_of_file:
        ;
        ; If not, continue to read the next block
        ;
        CALL        ibm_advance_to_next_block
        CALL        read_ibm_disk_record
        JMP         ibm_operation_end


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write output to IBM file
        ;
ibm_write_output:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Get file mode and reset block index
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        ;
        ; Check if the current block was the last block of the file
        ;
        ANI         FM_EOF_NEXT
        JNZ         ibm_end_of_file
        ;
        ; If not, write current block and continue to the next block
        ;
        CALL        ibm_advance_to_next_block
        CALL        write_ibm_disk_record
        JMP         ibm_operation_end


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Close IBM input file
        ;
ibm_close_input:
        JMP         device_driver_close_input_file


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Close IBM output file
        ;
ibm_close_output:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Check if current block buffer is empty
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MOV         A,M             ; FCB + FCB_BUFIDX
        INX         H
        ORA         M
        JZ          ibm_data_write_done
        ;
        ; If not, write block buffer to disk
        ;
        LHLD        CTLBLK
        CALL        WRITE
        JC          ibm_operation_exception
ibm_data_write_done:


;//////////////////////////////////////

        ;
        ; Read back file index record
        ;
        LHLD        CTLBLK
        LXI         D,022H
        DAD         D
        MOV         C,M             ; FCB + 022H, sector number of file index
        MOV         A,C
        STA         ibm_current_file_sector
        MVI         B,000H
        LXI         H,BUF1
        CALL        read_ibm_disk_record
        JC          ibm_operation_exception
        ;
        ; Get sector and track of file data end
        ;
        LHLD        CTLBLK
        LXI         D,01CH
        DAD         D
        MOV         E,M             ; FCB + 01CH, sector of next data record
        INX         H
        MOV         D,M             ; FCB + 01DH, track of next data record
        ;
        ; Update EOE of file to reflect end of file data
        ;
        XCHG
        MOV         A,H
        LXI         D,BUF1 + 04AH
        CALL        bin_to_2_digit_ascii_decimal
        MVI         A,'0'
        STAX        D
        INX         D
        MOV         A,L
        CALL        bin_to_2_digit_ascii_decimal
        ;
        ; Write changes of file index record back to disk
        ;
        LDA         ibm_current_file_sector
        MOV         C,A
        MVI         B,000H
        LXI         H,BUF1
        CALL        write_ibm_disk_record
        JC          ibm_operation_exception
        ;
        ; Recover registers and continue to close file fcb
        ;
        POP         D
        POP         B
        POP         PSW
        LHLD        CTLBLK
        JMP         device_driver_close_input_file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     CART module
;//
;//         Device driver for block-device files using the XMON/CD tape cartridge
;//         interface.
;//
;//         To use this, a cartridge controller and a TDC-3000 tape drive is
;//         requred, as well as the XMON/CD ROM kernel (varieties /D and /F are not
;//         supported).
;//
;//         NOTE: Only one single file can be open per tape drive at any time.
;//               Opening multiple files on the same tape drive will lead to issues
;//               with reading/writing from/to the appropriate locations on the
;//               tape.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Bug where the Tape driver will treat the tape-full status as
;//                    a hard fault, preventing further use of the tape (including
;//                    opening files for reading)
;//
;//             v1.4:
;//
;//                 -> Less shared cleanup code with Intel device driver
;//                 -> Immediately closes an output file if tape track becomes full
;//                 -> Introduces a bug where the binary file mode flag is used in
;//                    place of the detect EOF file mode flag
;//                 -> Introduces a bug where closure of a tape output file does
;//                    not restore the stack, and returns to an addres from a data
;//                    register. This will likely cause a crash.
;//
;//             v1.5a:
;//
;//                 -> Fixes EOF flag bug from v1.4
;//                 -> Fixes the output file CLOSE bug from v1.4
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Device driver routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Open tape cartridge file for input
        ;
tape_open_input:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Look up file on tape and verify that it exists
        ;
        MOV         A,M
        INX         H
        CALL        CLOCDIR
        JC          tape_operation_exception
        MOV         A,M
        ANA         A
        JZ          tape_input_file_found
        MVI         A,ERROR_31
        JMP         tape_operation_exception


;//////////////////////////////////////

tape_input_file_found:
        ;
        ; Reset tape drive
        ;
        LDA         UNIT
        CALL        CCAL
        JC          tape_operation_exception
        ;
        ; Get and store track number of file in file control block
        ;
        LXI         D,00AH
        DAD         D
        XCHG
        LHLD        current_fcb_plus_01EH
        LDAX        D
        MOV         M,A             ; FCB + 01EH, current track
        MOV         B,A
        ;
        ; Get file number in track and scan forward on tape until file start
        ;
        INX         D
        LDAX        D
        DCR         A
        JZ          tape_input_file_seek_done
        ADD         A
        MOV         C,A
        LDA         UNIT
        CALL        CBSFW
        JNC         tape_input_file_seek_done
        CPI         ERROR_48
        JNZ         tape_operation_exception
tape_input_file_seek_done:


;//////////////////////////////////////

        ;
        ; Set block count in file control block
        ;
        INX         D
        INX         D
        INX         D
        INX         H
        LDAX        D
        MOV         M,A             ; FCB + 01FH, block counter
        INX         D
        INX         H
        LDAX        D
        MOV         M,A
        ;
        ; Reset current filesegment
        ;
        INX         H
        MVI         M,000H          ; FCB + 021H, current filesegment number
        ;
        ; Set number of bytes in last block
        ;
        INX         H
        INX         D
        LDAX        D
        MOV         M,A             ; FCB + 022H, number of bytes in last block
        INX         H
        INX         D
        LDAX        D
        MOV         M,A
        ;
        ; Read and validate first data-segment of file
        ;
        LHLD        current_fcb_plus_01EH
        MOV         B,M             ; FCB + 01EH, current track
        CALL        RD32
        JC          tape_operation_exception
        MVI         A,'('
        CALL        VERIFY
        JNC         tape_operation_ok


;//////////////////////////////////////

tape_operation_exception:
        ;
        ; Recover registers other than exception, and return
        ;
        STC
        POP         D
        POP         B
        INX         SP
        INX         SP
        LHLD        CTLBLK
        RET


;//////////////////////////////////////

tape_operation_ok:
        ;
        ; Recover registers and return
        ;
        POP         D
        POP         B
        POP         PSW
        LHLD        CTLBLK
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Close tape cartridge input file
        ;
tape_close_input:
        ;
        ; Set up file control block and save registers
        ;
        CALL        check_file_control_block
        RC
        PUSH        PSW
        PUSH        D
        ;
        ; Reset tape drive
        ;
        SHLD        CTLBLK
        LXI         D,FCB_DRVNR
        DAD         D
        MOV         A,M
        CALL        CCAL
        JC          tape_close_error
        ;
        ; Restore registers and close file control block
        ;
        POP         D
        POP         PSW
        LHLD        CTLBLK
        JMP         device_driver_close_input_file

tape_close_error:
        POP         D
        INX         SP
        INX         SP
        RET


;//////////////////////////////////////////////////////////////////////////////

tape_output_open_file_nr:
        DS          1
tape_file_track_use_data_ptr:
tape_file_track_use_file_nr_ptr:
current_fcb_plus_022H:
        DS          2


;//////////////////////////////////////

        ;
        ; Open tape cartridge file for output
        ;
tape_open_output:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Try to look up file on tape, then rewind
        ;
        MOV         A,M
        INX         H
        CALL        CLOCDIR
        JC          tape_operation_exception
        LDA         UNIT
        CALL        CCAL
        JC          tape_operation_exception
        ;
        ; Verify that the file does not exist in tape directory
        ;
        MOV         A,M
        ANA         A
        JNZ         tape_verify_usage_block
tape_output_file_already_exists:
        MVI         A,ERROR_3C
        JMP         tape_operation_exception


;//////////////////////////////////////

tape_verify_usage_block:
        CPI         07FH
        JNZ         tape_output_file_already_exists
        ;
        ; Prepare pointers for later
        ;
        INX         H
        XCHG
        LHLD        CTLBLK
        LXI         B,024H
        DAD         B               ; FCB + 024H, cartridge usage information
        SHLD        tape_file_track_use_data_ptr
        ;
        ; Copy usage information for all data-tracks on tape
        ;
        MVI         B,15
copy_tape_cart_usage_block_loop:
        LDAX        D
        MOV         M,A
        INX         H
        INX         D
        DCR         B
        JNZ         copy_tape_cart_usage_block_loop
        ;
        ; Scan through track usage info to determine a fitting track for file
        ;
        LHLD        tape_file_track_use_data_ptr
        MVI         B,1
        MVI         C,000H
        MVI         D,07FH
tape_check_track_usage:
        ;
        ; Check track-full flag
        ;
        MOV         A,M
        ANA         A
        JZ          tape_output_track_not_full
        ;
        ; If not, check next track, checking for last track along the way
        ;
        INX         H
tape_check_next_track_usage_1:
        INX         H
tape_check_next_track_usage_2:
        INX         H
        INX         H
        INX         H
        INR         B
        MOV         A,B
        CPI         4
        JNZ         tape_check_track_usage
        ;
        ; Check if one of the data-tracks have been choosen as best candidate
        ;
        MOV         A,C
        ANA         A
        JNZ         tape_output_fitting_track_found
        MVI         A,ERROR_3D
        JMP         tape_operation_exception

tape_output_track_not_full:
        ;
        ; Check if nr of blocks used is roughly less than best candidate track
        ;
        INX         H
        INX         H
        MOV         A,M
        CMP         D
        JP          tape_check_next_track_usage_2
        ;
        ; If so, set up for current track as new best candidate
        ;
        INX         H
        MOV         A,M
        STA         tape_output_open_file_nr
        SHLD        tape_file_track_use_file_nr_ptr
        ;
        ; Get exact number of blocks used of new best candidate track
        ;
        DCX         H
        MOV         C,B
        MOV         D,M
        DCX         H
        MOV         E,M
        JMP         tape_check_next_track_usage_1


;//////////////////////////////////////

tape_output_fitting_track_found:
        ;
        ; Increase nr of files in file control block copy of track usage data
        ;
        LHLD        tape_file_track_use_file_nr_ptr
        LDA         tape_output_open_file_nr
        INR         A
        MOV         M,A
        ;
        ; Store location info on file start in file control block
        ;
        LXI         D,023H
        LHLD        CTLBLK
        DAD         D
        MOV         M,A             ; FCB + 023H, file number in track
        DCX         H
        MOV         M,C             ; FCB + 022H, track number of file start
        SHLD        current_fcb_plus_022H
        ;
        ; Set current track and reset block counter
        ;
        LHLD        current_fcb_plus_01EH
        MOV         M,C             ; FCB + 01EH, current track
        INX         H
        MVI         M,000H          ; FCB + 01FH, block counter
        INX         H
        MVI         M,000H


;//////////////////////////////////////

        ;
        ; Wind tape to proposed start of file
        ;
        MOV         B,C
        DCR         A
        JZ          tape_open_output_at_start_of_file
        ADD         A
        MOV         C,A
        LDA         UNIT
        CALL        CBSFW
        JNC         tape_open_output_at_start_of_file
        CPI         ERROR_48
        JNZ         tape_operation_exception
tape_open_output_at_start_of_file:
        ;
        ; Check for existing data-track end block where file will start on tape
        ;
        CALL        RD32
        JC          tape_operation_exception
        LDA         BUF2
        CPI         '/'
        JNZ         tape_open_output_not_track_end_block
        ;
        ; Backspace one block to prepare for overwriting tape-end block
        ;
        LDA         UNIT
        LHLD        current_fcb_plus_022H
        MOV         B,M             ; FCB + 022H, track number of file start
        CALL        CBBSW
        JC          tape_operation_exception
        ;
        ; Copy filename of file into new file header block
        ;
        LHLD        CTLBLK
        LXI         D,FCB_FNAME
        DAD         D
        LXI         D,file_header_block + 001H
        MVI         B,9
tape_open_output_copy_filename_loop:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         tape_open_output_copy_filename_loop
        ;
        ; Overwrite track-end block with file header block of the new file
        ;
        LHLD        current_fcb_plus_022H
        MOV         B,M             ; FCB + 022H, track number of file start
        LXI         D,32
        LXI         H,file_header_block
        LDA         UNIT
        CALL        CBWRW
        JC          tape_operation_exception
tape_open_output_finalize_index:
        ;
        ; Reset new output file data index
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        JMP         tape_operation_ok

;//////////////////////////////////////

tape_open_output_not_track_end_block:
        MVI         A,ERROR_5A
        JMP         tape_operation_exception


;//////////////////////////////////////

file_header_block:
        DB          '('
        DS          9
        DB          000H, 080H, 000H, 000H, 000H, 000H, 000H, 000H
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H
        DB          000H, 000H, 000H, 000H, 000H, 000H


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Close tape cartridge output file
        ;
tape_close_output:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Copy filename to file trailer block
        ;
        INX         H
        MVI         B,9
        LXI         D,file_trailer_block + 001H
tape_trailer_block_copy_filename_loop:
        MOV         A,M
        STAX        D
        INX         D
        INX         H
        DCR         B
        JNZ         tape_trailer_block_copy_filename_loop
        ;
        ; Get file buffer state
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFIDX
        INX         H
        MOV         D,M
        INX         H
        ;
        ; Check if buffer is empty
        ;
        MOV         A,D             ; FCB + FCB_BUFLEN
        ORA         E
        JZ          tape_close_no_more_data_to_write
        ;
        ; Set buffer length to data size and write final data-block of file
        ;
        MOV         M,E
        INX         H
        MOV         M,D
        LHLD        CTLBLK
        CALL        WRITE
        JC          tape_operation_exception
tape_close_no_more_data_to_write:
        ;
        ; Write tape mark after final data-block block
        ;
        LDA         UNIT
        LHLD        current_fcb_plus_01EH
        MOV         B,M
        CALL        CBTMW
        JNC         end_of_data_tape_mark_exists
        CPI         ERROR_48
        JNZ         tape_operation_exception
end_of_data_tape_mark_exists:
        ;
        ; Write file trailer block
        ;
        LXI         H,file_trailer_block
        LXI         D,32
        LDA         UNIT
        CALL        CBWRW
        JC          tape_operation_exception
        ;
        ; Write tape mark after file trailer block
        ;
        LDA         UNIT
        CALL        CBTMW
        JNC         file_trailer_block_tape_mark_exists
        CPI         ERROR_48
        JNZ         tape_operation_exception
file_trailer_block_tape_mark_exists:
        ;
        ; Write new track-end block, and rewind tape
        ;
        LXI         H,track_end_block
        LDA         UNIT
        CALL        CBWRW
        JC          tape_operation_exception
        LDA         UNIT
        CALL        CCAL
        JC          tape_operation_exception


;//////////////////////////////////////

        ;
        ; Try to look up directory entry for file
        ;
        LHLD        CTLBLK
        LXI         D,FCB_FNAME
        DAD         D
        LDA         UNIT
        CALL        CLOCDIR
        JC          tape_operation_exception
        ;
        ; Verify that it does not exist, and that we got the track usage block
        ;
        MOV         A,M
        CPI         07FH
        JNZ         tape_output_file_already_exists
        ;
        ; Backspace to prepare to overwrite track usage block with dir entry
        ;
        LDA         UNIT
        MVI         B,0
        CALL        CBBSW
        JC          tape_operation_exception
        SHLD        cart_usage_block_ptr
        ;
        ; Update cartridge usage information with copy from file control block
        ;
        XCHG
        LHLD        CTLBLK
        LXI         B,024H
        DAD         B               ; FCB + 024H, cartridge usage information
        MVI         B,15
        INX         D
tape_close_output_copy_cart_use_block_loop:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         B
        JNZ         tape_close_output_copy_cart_use_block_loop
        ;
        ; Copy filename to file directory block of new file
        ;
        LHLD        CTLBLK
        LXI         D,FCB_FNAME
        DAD         D
        LXI         D,file_directory_block+1
        MVI         B,9
tape_dir_block_copy_filename_loop:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         B
        JNZ         tape_dir_block_copy_filename_loop
        ;
        ; Set file start information in directory block
        ;
        LHLD        CTLBLK
        LXI         B,022H
        DAD         B
        MOV         A,M             ; FCB + 022H, track number of file start
        STAX        D
        INX         D
        INX         H
        MOV         A,M             ; FCB + 023H, file number in track
        STAX        D
        INX         D
        ;
        ; Set block count of file in directory block
        ;
        INX         D
        INX         D
        LHLD        current_fcb_plus_01EH
        INX         H
        MOV         A,M             ; FCB + 01FH, block counter
        STAX        D
        INX         D
        INX         H
        MOV         A,M
        STAX        D
        INX         D
        ;
        ; Set bytes in last data-block of file in directory block
        ;
        LHLD        CTLBLK
        LXI         B,FCB_BUFLEN
        DAD         B
        MOV         A,M             ; FCB + FCB_BUFLEN
        STAX        D
        INX         H
        INX         D
        MOV         A,M
        STAX        D
        INX         D
        ;
        ; Clear attributes of file in directory block
        ;
        SUB         A
        STAX        D
        ;
        ; Overwrite old cartridge usage block with new directory entry
        ;
        LXI         H,file_directory_block
        LXI         D,32
        MVI         B,0
        LDA         UNIT
        CALL        CBWRW
        JC          tape_operation_exception
        ;
        ; Write new updated cartridge usage block
        ;
        LHLD        cart_usage_block_ptr
        LDA         UNIT
        CALL        CBWRW
        JC          tape_operation_exception
        ;
        ; Write tape mark following cartridge usage block
        ;
        LDA         UNIT
        CALL        CBTMW
        JNC         file_directory_block_tape_mark_exists
        CPI         ERROR_48
        JNZ         tape_operation_exception
file_directory_block_tape_mark_exists:
        ;
        ; Rewind tape and finish closing file control block
        ;
        LDA         UNIT
        CALL        CCAL
        JC          tape_operation_exception
        ;
        ; Restore registers
        ;
        POP         D
        POP         B
        POP         PSW
        LHLD        CTLBLK
        JMP         device_driver_close_input_file


;//////////////////////////////////////

file_trailer_block:
        DB          ')'
        DS          9
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H
        DB          000H, 000H, 000H, 000H, 000H, 000H

        DB          000H, 000H, 000H, 000H, 000H

track_end_block:
        DB          '/'
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H

cart_usage_block_ptr:
        DS          2

file_directory_block:
        DB          000H
        DS          9
        DS          1
        DS          1
        DW          128
        DS          2
        DS          2
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H
        DB          000H, 000H, 000H, 000H, 000H, 000H, 000H


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Write to tape cartridge output file
        ;
tape_write_output:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Get current track
        ;
        LHLD        current_fcb_plus_01EH
        MOV         B,M             ; FCB + 01EH, current track
        INX         H
        ;
        ; Advance to next block
        ;
        MOV         E,M             ; FCB + 01FH, block counter
        INX         H
        MOV         D,M
        INX         D
        MOV         M,D
        DCX         H
        MOV         M,E
        ;
        ; Point to track usage block count
        ;
        LHLD        CTLBLK
        LXI         D,024H + 001H
        DAD         D               ; FCB + 025H, track 1 usage block count
        MOV         A,B
point_to_track_usage_loop:
        DCR         A
        JZ          tape_write_track_usage_ptr_ready
        LXI         D,005H
        DAD         D
        JMP         point_to_track_usage_loop

tape_write_track_usage_ptr_ready:
        ;
        ; Increase track usage block-count to include the new data-block
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        INX         D
        MOV         M,D
        DCX         H
        MOV         M,E
        ;
        ; Reset data buffer index
        ;
        LHLD        CTLBLK
        INX         H
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        INX         H
        ;
        ; Write new data-block to tape cartridge
        ;
        INX         H
        INX         H
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        LXI         D,128
        LDA         UNIT
        CALL        CBWRW
        JNC         tape_operation_ok
        ;
        ; On error, check for end of tape status
        ;
        CPI         ERROR_40
        JNZ         tape_operation_exception
        ;
        ; If so, rewind one block and close output file immediately
        ;
        LDA         UNIT
        CALL        CBBSW
        JC          tape_operation_exception
        POP         D
        POP         B
        POP         PSW
        LHLD        CTLBLK
        JMP         tape_close_output


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Read from tape cartridge input file
        ;
tape_read_input:
        ;
        ; Set up file control block and save registers
        ;
        CALL        device_driver_set_up_for_file
        RC
        PUSH        PSW
        PUSH        B
        PUSH        D
        ;
        ; Check for pending end of file
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M
        ANI         FM_EOF_NEXT
        JNZ         tape_read_detect_eof
        DCX         H
        ;
        ; Set read overrun buffer markers
        ;
        LXI         D,FCB_OVRPTR
        DAD         D
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        MVI         M,0AAH
        INX         H
        MVI         M,0AAH
        XCHG
        INX         H
        ;
        ; Read next data-block from tape
        ;
        MOV         B,M
        LHLD        CTLBLK
        LXI         D,FCB_BUFPTR
        DAD         D
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        LDA         UNIT
        CALL        CBRDW
        JC          tape_operation_exception
        ;
        ; Verify that tape overrun markers were untouched
        ;
        LHLD        CTLBLK
        LXI         D,FCB_OVRPTR
        DAD         D
        MOV         E,M
        INX         H
        MOV         D,M
        LDAX        D
        CPI         0AAH
        JNZ         tape_read_overrun
        INX         D
        LDAX        D
        CPI         0AAH
        JNZ         tape_read_overrun
        INX         H
        ;
        ; Decrease block counter, as the next block has been read
        ;
        INX         H
        MOV         E,M             ; FCB + 01FH, block counter
        INX         H
        MOV         D,M
        DCX         D
        MOV         M,D
        DCX         H
        MOV         M,E
        ;
        ; Check if the read block is the last data-block in file
        ;
        MOV         A,D
        ORA         E
        JNZ         tape_open_output_finalize_index
        ;
        ; If so, set pending end of file flag in file control block
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M
        ORI         FM_EOF_NEXT
        MOV         M,A
        DCX         H
        ;
        ; Change length of buffer to match number of bytes in last data-block
        ;
        LXI         D,022H
        DAD         D
        MOV         E,M             ; FCB + 022H, number of bytes in last block
        INX         H
        MOV         D,M
        LXI         B,FCB_BUFLEN
        LHLD        CTLBLK
        DAD         B
        MOV         M,E             ; FCB + FCB_BUFLEN
        INX         H
        MOV         M,D
        JMP         tape_open_output_finalize_index


;//////////////////////////////////////

tape_read_overrun:
        MVI         A,ERROR_3E
        JMP         tape_operation_exception


;//////////////////////////////////////

tape_read_detect_eof:
        ;
        ; Verify tape-mark after file end
        ;
        LHLD        current_fcb_plus_01EH
        MOV         B,M
        LDA         UNIT
        LHLD        CTLBLK
        LXI         D,FCB_BUFPTR
        DAD         D
        MOV         E,M             ; FCB + FCB_BUFPTR
        INX         H
        MOV         D,M
        XCHG
        CALL        CBRDW
        JNC         tape_read_no_end_when_expected
        CPI         ERROR_48
        JNZ         tape_operation_exception
        ;
        ; Set end of file flag
        ;
        LHLD        CTLBLK
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ORI         FM_EOF
        MOV         M,A
        SUB         A
        STC
        JMP         tape_operation_exception

tape_read_no_end_when_expected:
        MVI         A,ERROR_57
        JMP         tape_operation_exception


;//////////////////////////////////////////////////////////////////////////////
;//
;//     BUFR module
;//
;//         Module for handling dynamic buffers. This is used by, for instance, the
;//         assignement interpreter when generating file control blocks.
;//
;//         It is important that all buffers assigned by a host program are all
;//         released before the program ends. Failure to do so may cause unused
;//         orphaned buffers to still reserve memory, leaving less memory for other
;//         programs run afterwards.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//
;//             v1.5a:
;//
;//                 -> Returns error 30H instead of 2CH if a buffer entry type is
;//                    not set correctly when buffer deallocation is run
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Buffer-handling routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Allocate a new buffer onto the buffer chained list
        ;
T_BUFALLOC:
        PUSH        B
        PUSH        D
        PUSH        H
        ;
        ; Scan to head of buffers chained list
        ;
        LXI         H,buffer_list_tail
alloc_check_buffer_list_item:
        ;
        ; Check if this item is the head of the buffers chained list
        ;
        MOV         A,M
        CPI         BUFLST_HEAD
        JZ          add_new_buffer
        ;
        ; Otherwise verify item status and go on to check next item in list
        ;
        ANA         A
        JZ          alloc_check_next_buffer_list_item
        CPI         BUFLST_INAC
        JZ          alloc_check_next_buffer_list_item
buffer_error:
        ;
        ; On error, reset the entire buffer list, de-allocating everything
        ;
        MVI         A,ERROR_2B
        STC
        LXI         H,buffer_list_tail
        MVI         M,BUFLST_HEAD
        DCX         H
        MVI         M,000H
        DCX         H
        MVI         M,000H
bufalloc_end:
        POP         H
        POP         D
        POP         B
        RET

alloc_check_next_buffer_list_item:
        ;
        ; Get pointer to next item in the chained list
        ;
        DCX         H
        MOV         D,M
        DCX         H
        MOV         E,M
        XCHG
        JMP         alloc_check_buffer_list_item


;//////////////////////////////////////

add_new_buffer:
        ;
        ; Convert previous buffer head item into a regular active item
        ;
        MVI         M,BUFLST_ACTV
        ;
        ; Point to last byte of forwards-reference in old head item
        ;
        DCX         H
        ;
        ; Recover buffer size and save pointer to forwards-reference
        ;
        POP         B
        PUSH        H
        ;
        ; Point to last byte of data-area in new buffer list item
        ;
        DCX         H
        DCX         H
        ;
        ; Subtract buffer size to point to first byte of new data buffer
        ;
        MOV         A,B
        CMA
        MOV         B,A
        MOV         A,C
        CMA
        MOV         C,A
        INX         B
        DAD         B
        ;
        ; Recover forward-reference pointer, save pointer to new data buffer
        ;
        POP         D
        PUSH        H
        ;
        ; Point to byte just before data buffer: status byte of new list entry
        ;
        DCX         H
        ;
        ; Have forward-reference of previous list item point to new entry
        ;
        XCHG
        MOV         M,D
        DCX         H
        MOV         M,E
        XCHG
        ;
        ; Make new list entry the chained list head
        ;
        MVI         M,BUFLST_HEAD
        DCX         H
        MVI         M,000H
        DCX         H
        MVI         M,000H
        DCX         H
        ;
        ; Update start-of-TOS-buffers reference to reflect new start of buffers
        ;
        SHLD        BUFLIM
        ANA         A
        JMP         bufalloc_end


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Deallocate a buffer from the buffer chained list
        ;
T_BUFDEALLOC:
        PUSH        B
        PUSH        D
        PUSH        H
        ;
        ; Get and check status-byte of buffer to release
        ;
        DCX         H
        MOV         A,M
        ANA         A
        JZ          release_in_chain_buffer
        CPI         BUFLST_HEAD
        JZ          release_chain_head_buffer
        ;
        ; Raise exception if list entry status of buffer was not proper
        ;
        MVI         A,ERROR_30
        JMP         bufdealloc_exception
        MVI         A,ERROR_2C
bufdealloc_exception:
        STC
bufdealloc_end:
        POP         H
        POP         D
        POP         B
        RET

release_in_chain_buffer:
        ;
        ; Set in-chain buffer entry to inactive and nothing more
        ;
        MVI         M,BUFLST_INAC
        ANA         A
        JMP         bufdealloc_end


;//////////////////////////////////////

release_chain_head_buffer:
        ;
        ; Scan to head of buffers chained list
        ;
        LXI         H,buffer_list_tail
        LXI         B,buffer_list_tail
release_alloc_check_buffer_list_item:
        ;
        ; Check if the current entry is a regular active entry
        ;
        MOV         A,M
        ANA         A
        JNZ         release_check_entry
        ;
        ; If so, save a pointer to it for later
        ;
        MOV         B,H
        MOV         C,L
release_check_next_buffer_list_item:
        ;
        ; Advance to the next entry in chained list of buffers
        ;
        DCX         H
        MOV         D,M
        DCX         H
        MOV         E,M
        XCHG
        JMP         release_alloc_check_buffer_list_item

release_check_entry:
        ;
        ; Check if entry is truly the head entry of the chained list
        ;
        CPI         BUFLST_INAC
        JZ          release_check_next_buffer_list_item
        CPI         BUFLST_HEAD
        JNZ         buffer_error
        ;
        ; Make last active list entry into the chained list head
        ;
        MOV         H,B
        MOV         L,C
        MVI         M,BUFLST_HEAD
        DCX         H
        MVI         M,000H
        DCX         H
        MVI         M,000H
        DCX         H
        ;
        ; Update start-of-TOS-buffers reference to reflect released buffers
        ;
        SHLD        BUFLIM
        ANA         A
        JMP         bufdealloc_end


;//////////////////////////////////////////////////////////////////////////////
;//
;//     JTAB module, part 1
;//
;//         API jump-tables for Tandberg OS device drivers
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Device driver jump tables
;//
;//////////////////////////////////////////////////////////////////////////////

T_TABTC:
        JMP         tape_open_input
        JMP         tape_open_output
        JMP         tape_read_input
        JMP         tape_write_output
        JMP         tape_close_input
        JMP         tape_close_output

T_TABIB:
        JMP         ibm_open_input
        JMP         ibm_open_output
        JMP         ibm_read_input
        JMP         ibm_write_output
        JMP         ibm_close_input
        JMP         ibm_close_output

T_TABIN:
        JMP         intel_open_input
        JMP         intel_open_output
        JMP         intel_read_input
        JMP         intel_write_output
        JMP         intel_close_input
        JMP         intel_close_output


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; TOS file load, from drive nr A (0-3 floppy or 4-7 tape), name at HL
        ;
T_LOAD:
        CPI         4
        JM          T_LOADD
        SUI         4
        JMP         T_CLOAD


;//////////////////////////////////////////////////////////////////////////////
;//
;//     PHYS module
;//
;//         This module will generate one file control block based on a string
;//         definint its structure. It can be anything between a simple device-file
;//         to a complex linked file with several layers.
;//
;//         Files generated by PHYS is explicitly meant for the assigned abstract
;//         files, and will have this flag set. To generate general files from a
;//         file-handle string, call PHYSINT instead.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//
;//             v1.4:
;//
;//                 -> Adds the :CE: and :RE: files to the list of system devices
;//                    available for use
;//
;//             v1.5a:
;//
;//                 -> Complete rewrite. Splits into a general part which creates a
;//                    new file control block from a file-handle string, and a more
;//                    specific part that prepares and validates the file-handle
;//                    from the command line arguments
;//                 -> Adds block-devices type :Bn: and :Jn: for IBM 3740 BLOCKLINE
;//                    files
;//                 -> Has a bug that PHYSINT will use the floppy/tape drive type
;//                    byte in place of device format byte when generating a new
;//                    block-device file control block
;//                 -> Has a bug in PHYSINT where IBM files will pad out the ninth
;//                    unused byte of the fcb filename field with a sequence of 256
;//                    zeroes, overwriting a lot more memory than what is allocated
;//                    to the file control block
;//                 -> Has a bug in PHYSINT where the stack is not recovered before
;//                    returning from an invalid filename, something that is likely
;//                    to crash the system should the situation occur
;//                 -> Has a bug where the filename overrun check for IBM filenames
;//                    will not check the right character if the filename uses the
;//                    full available filename length
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data and device file tables
;//
;//////////////////////////////////////////////////////////////////////////////

system_device_list:
        DB          'CI'
        DW          DEV_CI_FCB
        DB          'CO'
        DW          DEV_CO_FCB
        DB          'BB'
        DW          DEV_BB_FCB
        DB          'NF'
        DW          DEV_NF_FCB
        DB          'LP'
        DW          DEV_LP_FCB
        DB          'CE'
        DW          DEV_CE_FCB
        DB          'RE'
        DW          DEV_RE_FCB
        DB          'XM'
        DW          DEV_XM_FCB
        DB          'RC'
        DW          DEV_RC_FCB
        DB          NULL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parameter sets for the different supported block-device formats
        ;
        ; 000H      Drive designator identifier
        ; 001H      File control block core size (excluding data buffers)
        ; 002H      Combined length of all additional data buffers needed
        ; 004H      Reference to device driver jump-table
        ; 006H      Drive type (0 floppy, 1 tape)
        ; 007H      Drive format (1 Intel or tape, 2 IBM 3740)
        ; 008H      Reference to fcb setup-shim routine for PHYSINT
        ;
block_device_params_list:

        ;
        ; Intel floppy
        ;
        DB          'F'
        DB          022H
        DW          2*128
        DW          TABIN
        DB          0
        DB          1
        DW          intel_physint_setup

        ;
        ; IBM 3740 EBCDIC
        ;
        DB          'I'
        DB          023H
        DW          128
        DW          TABIB
        DB          0
        DB          2 + DF_EBCDIC
        DW          ibm_physint_setup

        ;
        ; Tape Cartridge
        ;
        DB          'M'
        DB          035H
        DW          128 + 2
        DW          TABTC
        DB          1
        DB          1
        DW          tape_physint_setup

        ;
        ; IBM 3740 ASCII
        ;
        DB          'A'
        DB          023H
        DW          128
        DW          TABIB
        DB          0
        DB          2
        DW          ibm_physint_setup

        ;
        ; IBM 3740 ASCII Blockline
        ;
        DB          'B'
        DB          023H
        DW          128
        DW          TABIB
        DB          0
        DB          2 + DF_BLKLINE
        DW          ibm_physint_setup

        ;
        ; IBM 3740 EBCDIC Blockline
        ;
        DB          'J'
        DB          023H
        DW          128
        DW          TABIB
        DB          0
        DB          2 + DF_BLKLINE + DF_EBCDIC
        DW          ibm_physint_setup

        DB          NULL


;//////////////////////////////////////////////////////////////////////////////
;//
;//     File contro block deallocation routines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Deallocate file control block at HL
        ;
deallocate_assigned_file:
        ;
        ; Check that file was assigned on the command line
        ;
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        DCX         H
        ANI         FM_ASSIGNED
        RZ
        ;
        ; If so, check if the file has nested files
        ;
        MOV         A,M             ; FCB + FCB_TYPE
        CPI         3
        JZ          deallocate_linked_files
        CPI         6
        JZ          deallocate_linked_files
deallocate_root_file:
        CALL        BUFDEALLOC
        RET


;//////////////////////////////////////

deallocate_linked_files:
        ;
        ; Get reference to first linked file
        ;
        PUSH        H
        INX         H
        INX         H
        MOV         E,M             ; FCB + 002H, first nested file reference
        INX         H
        MOV         D,M
        ;
        ; Check if it is set, and deallocate it if so
        ;
        XCHG
        MOV         A,H
        ORA         L
        CNZ         deallocate_assigned_file
        POP         H
        ;
        ; Get reference to second linked file
        ;
        PUSH        H
        INX         H
        INX         H
        INX         H
        INX         H
        MOV         E,M             ; FCB + 004H, second nested file reference
        INX         H
        MOV         D,M
        ;
        ; Check if it is set, and deallocate it if so
        ;
        XCHG
        MOV         A,H
        ORA         L
        CNZ         deallocate_assigned_file
        POP         H
        JMP         deallocate_root_file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assignment file contro block generation routines
;//
;//////////////////////////////////////////////////////////////////////////////

phys_file_nesting_layer_nr:
        DS          1
phys_file_handle_str:
        DS          80
phys_current_char:
        DS          1
phys_fcb_ptr:
        DS          2


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse file assignement string to generate a file-handle for PHYSINT,
        ; which in turn generates the file. The file-handle is sanity-checked
        ; as it is put together, and can be a file containing nested files,
        ; in a tree-like structure.
        ;
phys_generate_fcb_from_handle:
        ;
        ; Initialize local variables
        ;
        LXI         H,00000H
        SHLD        phys_fcb_ptr
        LXI         H,phys_file_nesting_layer_nr
        MVI         M,000H
        LXI         D,phys_file_handle_str
        ;
        ; Parse out a file-handle from cli arguments string and generate file
        ;
phys_parse_char:
        ;
        ; Check next character for special meaning at the command line
        ;
        CPI         ','
        JZ          phys_append_file
        CPI         CR
        JZ          phys_fcb_ready
        CPI         ' '
        JC          phys_invalid_drive_error
        CPI         '$'
        JZ          phys_fcb_ready
        CPI         '&'
        JZ          phys_flush_ci_input
phys_add_filehandle_char:
        ;
        ; Add character to file handle if it does not have special meaning
        ;
        STAX        D
        INX         D
        CPI         '('
        JZ          phys_increase_linked_depth
        CPI         ')'
        JZ          phys_decrease_linked_depth
phys_parse_next_char:
        ;
        ; Get next character from command line arguments
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         phys_parse_char

phys_increase_linked_depth:
        ;
        ; Increase current nested layer of the file handle
        ;
        LXI         H,phys_file_nesting_layer_nr
        INR         M
        JMP         phys_parse_next_char

phys_decrease_linked_depth:
        ;
        ; Decrease current nested layer of the file handle
        ;
        LXI         H,phys_file_nesting_layer_nr
        MOV         A,M
        DCR         M
        ;
        ; Check for underrun, all closing brackets must have an opening bracket
        ;
        ANA         A
        JNZ         phys_parse_next_char
phys_invalid_drive_error:
        MVI         A,ERROR_2D
        STC
        RET

phys_flush_ci_input:
        ;
        ; Flush the remaining line from console input
        ;
phys_flush_next_char:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         phys_flush_next_char
        ;
        ; Get next character from command line arguments
        ;
        CALL        INCHAR
        RC
        JMP         phys_parse_char

phys_append_file:
        ;
        ; Verify we are inside a linked file before specifying nested files
        ;
        LXI         H,phys_file_nesting_layer_nr
        MOV         A,M
        ANA         A
        MVI         A,','
        JZ          phys_fcb_ready
        JMP         phys_add_filehandle_char

phys_fcb_ready:
        STA         phys_current_char
        ;
        ; Verify that all linked files in file handle have been proper closures
        ;
        LXI         H,phys_file_nesting_layer_nr
        MOV         A,M
        ANA         A
        JNZ         phys_invalid_drive_error
        ;
        ; Terminate file handle string with a cartridge return
        ;
        MVI         A,CR
        STAX        D
        LXI         H,phys_file_handle_str
        ;
        ; Get open mode of file, depending on the current abstract file number
        ;
        LDA         current_tos_abstract_file_nr
        CPI         1
        JZ          fcb_for_input_file
        CPI         3
        JZ          fcb_for_input_file
        CPI         6
        JZ          fcb_for_input_file
        MVI         A,1
        JMP         phys_file_mode_ready

fcb_for_input_file:
        SUB         A
phys_file_mode_ready:
        ;
        ; Generate file from prepared file handle, using PHYSINT
        ;
        CALL        T_PHYSINT
        RC
        SHLD        phys_fcb_ptr
        ;
        ; Verify that the whole file handle was parsed to generate the file
        ;
        LDA         physint_current_char
        CPI         CR
        JNZ         phys_incomplete_file_handle
        LDA         phys_current_char
        ANA         A
        RET

phys_incomplete_file_handle:
        ;
        ; If only parts of handle was used to make the file, abort making it
        ;
        CALL        deallocate_assigned_file
        JMP         phys_invalid_drive_error


;//////////////////////////////////////////////////////////////////////////////
;//
;//     General purpose file contro block generation routines
;//
;//////////////////////////////////////////////////////////////////////////////

physint_file_handle_ptr:
        DS          2
physint_file_open_mode:
        DS          1
physint_drive_number:
        DS          1
physint_current_char:
        DS          1
block_device_params_list_ptr:
        DS          2
physint_device_format:
        DS          1
physint_recursion_counter:
        DS          1


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII character in A to uppercase
        ;
physint_to_uppercase:
        CPI         'a'
        RC
        CPI         'z'+1
        RNC
        SUI         'a' - 'A'
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get next character from file handle string
        ;
get_next_filehandle_char:
        ;
        ; Get next character from file handle, after any potential whitespace
        ;
        PUSH        H
        LHLD        physint_file_handle_ptr
file_handle_skip_whitespace_loop:
        MOV         A,M
        INX         H
        CPI         ' '
        JZ          file_handle_skip_whitespace_loop
        SHLD        physint_file_handle_ptr
        STA         physint_current_char
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Generate a file control block from a file handle string at HL
        ;
T_PHYSINT:
        ;
        ; Set up pointers and reset nested file depth
        ;
        SHLD        physint_file_handle_ptr
        PUSH        PSW
        SUB         A
        STA         physint_recursion_counter
        POP         PSW
recursive_linked_file_call:
        ;
        ; Increase nested file depth and swap to requested file open mode
        ;
        MOV         B,A
        LDA         physint_recursion_counter
        INR         A
        STA         physint_recursion_counter
        LDA         physint_file_open_mode
        PUSH        PSW
        MOV         A,B
        STA         physint_file_open_mode
        ;
        ; Get the first character of file handle, check for linked file
        ;
        CALL        get_next_filehandle_char
        CPI         '('
        JNZ         physint_non_linked_file
        ;
        ; If so, generate the first nested file
        ;
        LDA         physint_file_open_mode
        CALL        recursive_linked_file_call
        JC          physint_exception
        XCHG
        ;
        ; Validate linked file deliminator
        ;
        LDA         physint_current_char
        CPI         '/'
        JZ          physint_valid_linked_file
        CPI         ','
        JZ          physint_valid_linked_file
        ;
        ; Invalid linked file deliminator, cancel file generation
        ;
        XCHG
physint_exception_after_alloc:
        ;
        ; Error parsing file handle, release the buffers claimed this far
        ;
        CALL        deallocate_assigned_file
physint_exception:
        POP         PSW
        STA         physint_file_open_mode
        MVI         A,ERROR_2D
        STC
        RET

physint_valid_linked_file:
        PUSH        D
        PUSH        PSW
        ;
        ; Check linked file deliminator for the file being a normal linked file
        ;
        CPI         ','
        LDA         physint_file_open_mode
        JZ          second_linked_file_mode_ready
        ;
        ; If not, assume echo file: Prepare the second linked file as an output
        ;
        MVI         A,1
second_linked_file_mode_ready:
        ;
        ; Generate the second linked file
        ;
        CALL        recursive_linked_file_call
        JNC         physint_linked_files_valid
physint_linked_file_failed:
        ;
        ; On failure here, release the first nested file that still was made
        ;
        POP         H
        POP         H
        JMP         physint_exception_after_alloc

physint_linked_files_valid:
        ;
        ; Validate linked file closure in the file handle and advance cursor
        ;
        PUSH        H
        LDA         physint_current_char
        CPI         ')'
        JNZ         invalid_linked_file_handle
        CALL        get_next_filehandle_char
        ;
        ; Allocate buffer for the linked file
        ;
        LXI         H,006H
        CALL        BUFALLOC
        JNC         assemble_linked_file_fcb
invalid_linked_file_handle:
        ;
        ; Error making linked file, release both nested files that were made
        ;
        POP         H
        POP         PSW
        PUSH        PSW
        CALL        deallocate_assigned_file
        POP         H
        JMP         physint_linked_file_failed

assemble_linked_file_fcb:
        ;
        ; Set second nested file of linked file control block
        ;
        LXI         D,005H
        DAD         D
        POP         B
        MOV         M,B             ; FCB + 005H, second nested file (msb)
        DCX         H
        MOV         M,C
        DCX         H
        ;
        ; Set first nested file of linked file control block
        ;
        POP         PSW
        POP         B
        MOV         M,B             ; FCB + 003H, first nested file (msb)
        DCX         H
        MOV         M,C
        DCX         H
        ;
        ; Set file mode
        ;
        PUSH        PSW
        LDA         physint_file_open_mode
        INR         A
        ORI         FM_ASSIGNED
        MOV         M,A             ; FCB + FCB_MODE
        POP         PSW
        ;
        ; Set linked file type depending on deliminator
        ;
        DCX         H
        MVI         B,6
        CPI         ','
        JZ          linked_file_fcb_type_ready
        MVI         B,3
linked_file_fcb_type_ready:
        MOV         M,B
        POP         PSW
        JMP         physint_fcb_made


;//////////////////////////////////////

physint_non_linked_file:
        ;
        ; Set default drive number to drive 0
        ;
        SUB         A
        STA         physint_drive_number
        ;
        ; Check first character of file handle to determine course of action
        ;
        LDA         physint_current_char
        CPI         '/'
        JZ          physint_get_referenced_file
        CPI         ':'
        JNZ         physint_default_drive_block_device
        ;
        ; Device designator or device file specified, get it into BC
        ;
        CALL        get_next_filehandle_char
        CALL        physint_to_uppercase
        MOV         B,A
        CALL        get_next_filehandle_char
        CALL        physint_to_uppercase
        MOV         C,A
        ;
        ; Scan through list of known device files and scan for device
        ;
        LXI         H,system_device_list
check_device_file:
        ;
        ; Check for end of known device files list
        ;
        MOV         A,M
        INX         H
        ANA         A
        JZ          physint_not_device_file
        ;
        ; Compare first character of name
        ;
        CMP         B
        JNZ         check_next_device_file
        ;
        ; Compare second character of name
        ;
        MOV         A,M
        CMP         C
        JZ          device_file_found
check_next_device_file:
        ;
        ; Not match, check against next known file from the list
        ;
        LXI         D,003H
        DAD         D
        JMP         check_device_file

device_file_found:
        ;
        ; Verify closing semicolon at the end of device file in file handle
        ;
        CALL        get_next_filehandle_char
        CPI         ':'
        JNZ         physint_exception
        CALL        get_next_filehandle_char
        ;
        ; Get and select pointer to device file
        ;
        INX         H
get_file_from_reference:
        ;
        ; Get pre-existing file from reference
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        XCHG
        POP         PSW
        STA         physint_file_open_mode
        JMP         physint_fcb_made


;//////////////////////////////////////

physint_not_device_file:
        ;
        ; Scan list of block-device formats for the appropriate parameter set
        ;
        LXI         H,block_device_params_list
physint_get_device_type_specs_loop:
        ;
        ; Check for end of the list
        ;
        MOV         A,M
        ANA         A
        JZ          physint_exception
        ;
        ; Check if this is the parameter set for the format specified
        ;
        CMP         B
        JZ          physint_block_device_format_ready
        ;
        ; Advance to next item in list of block-device format parameter-sets
        ;
        LXI         D,00AH
        DAD         D
        JMP         physint_get_device_type_specs_loop

physint_default_drive_block_device:
        ;
        ; Select first format of parameter set list as default (Intel floppy)
        ;
        LXI         H,block_device_params_list
        SHLD        block_device_params_list_ptr
        JMP         physint_block_device

physint_block_device_format_ready:
        SHLD        block_device_params_list_ptr
        ;
        ; Verify closing semicolon at the end of drive designator in handle
        ;
        CALL        get_next_filehandle_char
        CPI         ':'
        JNZ         physint_exception
        ;
        ; Parse and verify drive number
        ;
        MOV         A,C
        CPI         '0'
        JC          physint_exception
        CPI         '4'
        JNC         physint_exception
        SUI         '0'
        STA         physint_drive_number
        CALL        get_next_filehandle_char


;//////////////////////////////////////

physint_block_device:
        ;
        ; Get size of file control block core structure
        ;
        LHLD        block_device_params_list_ptr
        INX         H
        MOV         C,M
        INX         H
        ;
        ; Get block length
        ;
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        SHLD        block_device_params_list_ptr
        ;
        ; Reserve a buffer for core file structure and one block data-buffer
        ;
        XCHG
        MVI         B,000H
        DAD         B
        CALL        BUFALLOC
        JNC         physint_assemble_block_device_fcb
        INX         SP
        INX         SP
        STC
        RET

physint_assemble_block_device_fcb:
        ;
        ; Set fields of block-device file control block
        ;
        PUSH        H
        MVI         M,5             ; FCB + FCB_TYPE
        INX         H
        LDA         physint_file_open_mode
        INR         A
        ORI         FM_ASSIGNED
        MOV         M,A             ; FCB + FCB_MODE
        INX         H
        MVI         M,000H          ; FCB + FCB_BUFIDX
        INX         H
        MVI         M,000H
        INX         H
        MVI         M,128           ; FCB + FCB_BUFLEN
        INX         H
        MVI         M,000H
        INX         H
        ;
        ; Add file control block size to start of fcb for start of data buffer
        ;
        XCHG
        POP         H
        PUSH        H
        DAD         B
        XCHG
        MOV         M,E             ; FCB + FCB_BUFPTR
        INX         H
        MOV         M,D
        INX         H
        ;
        ; Get pointer to reference of the appropriate device driver jump table
        ;
        XCHG
        LHLD        block_device_params_list_ptr
        MOV         C,M
        INX         H
        MOV         B,M
        INX         H
        SHLD        block_device_params_list_ptr
        MOV         H,B
        MOV         L,C
        ;
        ; Get reference to the appropriate device driver jump table
        ;
        MOV         C,M
        INX         H
        MOV         B,M
        ;
        ; Set file control block READ device driver call
        ;
        LXI         H,TAB_READ_I
        DAD         B
        XCHG
        MOV         M,E             ; FCB + FCB_READ
        INX         H
        MOV         M,D
        INX         H
        XCHG
        ;
        ; Set file control block WRITE device driver call
        ;
        LXI         H,TAB_WRITE_O
        DAD         B
        XCHG
        MOV         M,E             ; FCB + FCB_WRITE
        INX         H
        MOV         M,D
        INX         H
        XCHG
        ;
        ; Set file control block OPEN device driver call
        ;
        LXI         H,TAB_OPEN_O
        LDA         physint_file_open_mode
        ANA         A
        JNZ         physint_open_routine_ready
        LXI         H,TAB_OPEN_I
physint_open_routine_ready:
        DAD         B
        XCHG
        MOV         M,E             ; FCB + FCB_OPEN
        INX         H
        MOV         M,D
        INX         H
        XCHG
        ;
        ; Set file control block CLOSE device driver call
        ;
        LXI         B,TAB_CLOSE - TAB_OPEN
        DAD         B
        XCHG
        MOV         M,E             ; FCB + FCB_CLOSE
        INX         H
        MOV         M,D
        INX         H
        XCHG
        ;
        ; Set device type
        ;
        LHLD        block_device_params_list_ptr
        MOV         A,M
        INX         H
        SHLD        block_device_params_list_ptr
        STAX        D               ; FCB + FCB_DEVTYP
        STA         physint_device_format
        INX         D
        ;
        ; Set device number
        ;
        LDA         physint_drive_number
        STAX        D               ; FCB + FCB_DRVNR
        INX         D               ; FCB + FCB_FNAME
        ;
        ; Select filename length depending on device format (Intel/Tape vs IBM)
        ;
        LXI         B,00603H
        LDA         physint_device_format
        ANI         002H
        JZ          physint_get_fiename
        LXI         B,00800H
physint_get_fiename:
        ;
        ; Parse and validate filename
        ;
        LDA         physint_current_char
check_filename_char:
        ;
        ; Check for the end of the first part of the filename
        ;
        CPI         '.'
        JZ          physint_main_filename_ready
        CPI         '/'
        JZ          physint_non_ext_filename_ready
        CPI         ','
        JZ          physint_non_ext_filename_ready
        CPI         ')'
        JZ          physint_non_ext_filename_ready
        CPI         CR
        JZ          physint_non_ext_filename_ready
        ;
        ; Validate filename character
        ;
        CPI         '0'
        JC          physint_invalid_filename
        CPI         '9'+1
        JC          physint_valid_filename_char
        CPI         'A'
        JC          physint_invalid_filename
        CPI         'Z'+1
        JC          physint_valid_filename_char
        CPI         'a'
        JC          physint_invalid_filename
        CPI         'z'+1
        JC          physint_valid_filename_char
physint_invalid_filename:
        JMP         physint_exception_after_alloc

physint_valid_filename_char:
        ;
        ; Add main filename character to the file control block filename
        ;
        STAX        D
        ;
        ; Advance to the next character and check if main filename is full
        ;
        INX         D
        DCR         B
        JZ          physint_main_filename_full
        CALL        get_next_filehandle_char
        JMP         check_filename_char

physint_main_filename_full:
        ;
        ; Check if a filename extension is expected
        ;
        LDA         physint_device_format
        ANI         002H
        JNZ         physint_no_filename_ext
        ;
        ; If so, check if a filename extension is specified in the file handle
        ;
        CALL        get_next_filehandle_char
        CPI         '.'
        JZ          physint_check_file_extension_char
physint_no_filename_ext:
        ;
        ; Verify proper file handle syntax after filename
        ;
        CPI         ','
        JZ          physint_filename_ready
        CPI         ')'
        JZ          physint_filename_ready
        CPI         '/'
        JZ          physint_filename_ready
        CPI         CR
        JZ          physint_filename_ready
        JMP         physint_invalid_filename

physint_main_filename_ready:
        ;
        ; Pad out remaining characters in main part of filename
        ;
physint_pad_filename_loop:
        MVI         A,NULL
        STAX        D
        INX         D
        DCR         B
        JNZ         physint_pad_filename_loop
        ;
        ; Parse and validate filename extension
        ;
physint_check_file_extension_char:
        CALL        get_next_filehandle_char
        ;
        ; Check for the end of the filename extension
        ;
        CPI         ','
        JZ          physint_filename_ready
        CPI         '/'
        JZ          physint_filename_ready
        CPI         ')'
        JZ          physint_filename_ready
        CPI         CR
        ;
        ; Validate filename extension character
        ;
        JZ          physint_filename_ready
        CPI         '0'
        JC          physint_invalid_filename
        CPI         '9'+1
        JC          physint_valid_file_ext_char
        CPI         'A'
        JC          physint_invalid_filename
        CPI         'Z'+1
        JC          physint_valid_file_ext_char
        CPI         'a'
        JC          physint_invalid_filename
        CPI         'z'+1
        JNC         physint_invalid_filename
physint_valid_file_ext_char:
        ;
        ; Add filename extension character to the file control block filename
        ;
        STAX        D
        ;
        ; Advance to the next character and check if filename extension is full
        ;
        INX         D
        DCR         C
        JNZ         physint_check_file_extension_char
        CALL        get_next_filehandle_char
        JMP         physint_file_extension_full

physint_non_ext_filename_ready:
        ;
        ; Pad out remaining characters in extensionless filename
        ;
physint_pad_non_ext_filename_loop:
        MVI         A,NULL
        STAX        D
        INX         D
        DCR         B
        JNZ         physint_pad_non_ext_filename_loop
physint_filename_ready:
        ;
        ; Pad out remaining characters in file extension
        ;
physint_pad_file_extension_loop:
        MVI         A,NULL
        STAX        D
        INX         D
        DCR         C
        JNZ         physint_pad_file_extension_loop
physint_file_extension_full:
        ;
        ; Verify proper file handle syntax after filename
        ;
        LDA         physint_current_char
        CPI         ','
        JZ          physint_filename_done
        CPI         '/'
        JZ          physint_filename_done
        CPI         ')'
        JZ          physint_filename_done
        CPI         CR
        JZ          physint_filename_done
        JMP         physint_invalid_filename

physint_filename_done:
        ;
        ; Setup stack for format specific setup shim routine call
        ;
        LXI         H,physint_device_setup_return
        PUSH        H
        ;
        ; Set drive format
        ;
        LHLD        block_device_params_list_ptr
        MOV         A,M
        STAX        D               ; FCB + FCB_DRVFMT
        INX         D
        INX         H
        ;
        ; Get setup shim routine pointer, push it and call it from stack
        ;
        MOV         C,M
        INX         H
        MOV         H,M
        MOV         L,C
        PUSH        H
        XCHG
        RET

physint_device_setup_return:
        POP         H
        POP         PSW
        JMP         physint_fcb_made


;//////////////////////////////////////

physint_get_referenced_file:
        ;
        ; Get coarse index for abstract file based on first character of name
        ;
        MVI         C,0
        CALL        get_next_filehandle_char
        CALL        physint_to_uppercase
        CPI         'C'
        JZ          reference_console_file
        MVI         C,2
        CPI         'S'
        JZ          reference_standard_file
        MVI         C,5
        CPI         'A'
        JNZ         physint_exception

reference_standard_file:
        ;
        ; Get final index for abstract file based on second character of name
        ;
        CALL        get_next_filehandle_char
        CALL        physint_to_uppercase
        CPI         'I'
        JZ          reference_input_file
        INR         C
        CPI         'O'
        JZ          reference_output_file
        INR         C
        CPI         'L'
        JNZ         physint_exception


;//////////////////////////////////////

reference_output_file:
        ;
        ; Verify that file open mode is indeed output
        ;
        LDA         physint_file_open_mode
        CPI         1
        JNZ         physint_exception
get_assignment_reference_ptr:
        ;
        ; Get pointer to previously assigned abstract file
        ;
        MOV         L,C
        MVI         H,000H
        DAD         H
        LXI         D,DEVTAB
        DAD         D
        JMP         get_file_from_reference

reference_input_file:
        ;
        ; Verify that file open mode is indeed input
        ;
        LDA         physint_file_open_mode
        ANA         A
        JNZ         physint_exception
        JMP         get_assignment_reference_ptr


;//////////////////////////////////////

reference_console_file:
        ;
        ; Get coarse index for abstract file based on first character of name
        ;
        CALL        get_next_filehandle_char
        CALL        physint_to_uppercase
        CPI         'I'
        JZ          reference_input_file
        INR         C
        CPI         'O'
        JZ          reference_output_file
        JMP         physint_exception


;//////////////////////////////////////

physint_fcb_made:
        ;
        ; Decrease nested file depth and check if this is the root node file
        ;
        PUSH        PSW
        LDA         physint_recursion_counter
        DCR         A
        STA         physint_recursion_counter
        JNZ         physint_success
        ;
        ; If root node, verify that the whole file-handle has been parsed
        ;
        LDA         physint_current_char
        CPI         CR
        JZ          physint_success
        ;
        ; Otherwise release buffers of file and raise an exception
        ;
        CALL        deallocate_assigned_file
        POP         PSW
        MVI         A,ERROR_2D
        STC
        RET

physint_success:
        ;
        ; Recover file open mode for parent file
        ;
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

intel_physint_setup:
        ;
        ; Set pointer to linking block buffer
        ;
        INX         H
        INX         H
        INX         H
        INX         H
        XCHG
        LXI         H,128 + (022H - FCB_LNKPTR)
        DAD         D
        XCHG
        MOV         M,E             ; FCB + FCB_LNKPTR
        INX         H
        MOV         M,D
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

ibm_physint_setup:
        ;
        ; Replace any null characters in IBM filename with spaces
        ;
        LXI         D,FCB_FNAME - (FCB_DRVFMT+1)
        DAD         D
        MVI         B,9
ibm_physint_prep_filename_loop:
        MOV         A,M
        ANA         A
        JNZ         ibm_physint_filename_char_ready
        MVI         M,' '
ibm_physint_filename_char_ready:
        DCR         B
        INX         H
        JNZ         ibm_physint_prep_filename_loop
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

tape_physint_setup:
        ;
        ; Set pointer to data-buffer overrun markers
        ;
        XCHG
        LXI         H,(128-2) + (035H - FCB_OVRPTR)
        DAD         D
        XCHG
        MOV         M,L             ; FCB + FCB_OVRPTR
        INX         H
        MOV         M,L
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     ASSI module
;//
;//         This module will interpret the assignement strings, and assign files to
;//         the TOS standard abstract files based on these strings. The module also
;//         contain definitions for the static device-files provided by TOS, as
;//         well as a bunch of mostly internal helper-functions for filename and
;//         file handling.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Bug where the no-autoscroll line counter does not reset when
;//                    a clear-screen or cursor-home control char is sent to :CO:
;//
;//             v1.4:
;//
;//                 -> Now also checks for line-break continuation sign, and treats
;//                    it as a valid deliminator between assignments
;//                 -> If there is an error opening the newly assigned file, then
;//                    the file in question will now immediately be unasigned
;//                 -> Adds :RE: and :CE: device files for UART and console input
;//                    with end-of-file on Ctrl-C
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Assignement interpreter routine
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Flush any remaining characters of the current line from CI
        ;
flush_ci_input:
        CPI         CR
        RZ
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         flush_ci_input


;//////////////////////////////////////////////////////////////////////////////

current_tos_abstract_file_nr:
        DB          000H
assignement_abstract_file_ptr:
        DS          2


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse assignement string from the command line
        ;
assignement_interpreter:
        ;
        ; Reset pending CI/CO assignements
        ;
        LXI         H,00000H
        SHLD        CISAVE
        SHLD        COSAVE


;//////////////////////////////////////

assign_next_file:
        ;
        ; Assume next input is the name of an abstract file to be assigned
        ;
        CALL        get_tos_abstract_file_nr
        RC
        ANA         A
        JNZ         valid_assignement_file
        MVI         A,'$'
        RET

valid_assignement_file:
        STA         current_tos_abstract_file_nr
        ;
        ; Verify that the character following the file name is an equal sign
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         '='
        JNZ         assignment_error
        ;
        ; Get first character of file handle and generate file control block
        ;
        CALL        INCHAR
        RC
        CPI         '/'
        JZ          assign_none
        CPI         ','
        JZ          assign_none
        CPI         '$'
        JZ          assign_none
        CPI         CR
        JZ          assign_none
        CALL        phys_generate_fcb_from_handle
        RC
        ;
        ; Check if valid deliminator is provided between assignments
        ;
        CPI         ','
        JZ          assign_file
        CPI         '$'
        JZ          assign_file
        CPI         CR
        JZ          assign_file
assignment_error:
        CALL        flush_ci_input
        MVI         A,ERROR_2E
        STC
        RET


;//////////////////////////////////////

assign_none:
        ;
        ; Set up to clear assignement
        ;
        LXI         H,00000H
        SHLD        phys_fcb_ptr
assign_file:
        ;
        ; Prepare tp set abstract file assignement
        ;
        LHLD        phys_fcb_ptr
        PUSH        PSW
        ;
        ; Assigning CI/CO has special handling not to break assignement parsing
        ;
        LDA         current_tos_abstract_file_nr
        CPI         1
        JZ          assign_ci
        CPI         2
        JZ          assign_co
        ;
        ; Get pointer to current abstract file reference
        ;
        SUI         1
        XCHG
        LXI         B,000H
        MOV         C,A
        LXI         H,DEVTAB
        DAD         B
        DAD         B
        SHLD        assignement_abstract_file_ptr
        ;
        ; Assign abstract file by having it reference the newly created fcb
        ;
        MOV         M,E
        INX         H
        MOV         M,D
open_assigned_file:
        ;
        ; Verify that the assigned file is set
        ;
        LHLD        phys_fcb_ptr
        MOV         A,H
        ORA         L
        JZ          assign_file_done
        ;
        ; Input mode for input type abstract file, otherwise select output mode
        ;
        MVI         B,FM_INPUT
        LDA         current_tos_abstract_file_nr
        CPI         1
        JZ          assigned_file_open_mode_ready
        CPI         3
        JZ          assigned_file_open_mode_ready
        CPI         6
        JZ          assigned_file_open_mode_ready
        MVI         B,FM_OUTPUT
assigned_file_open_mode_ready:
        ;
        ; Open file in selected mode
        ;
        MOV         A,B
        CALL        OPEN
        JNC         assign_file_done
        ;
        ; On error, de-allocate file if assigned from the command line
        ;
        PUSH        PSW
        LHLD        phys_fcb_ptr
        INX         H
        MOV         A,M             ; FCB + FCB_MODE
        ANI         FM_ASSIGNED
        JZ          abort_assignement
        DCX         H
        CALL        T_BUFDEALLOC
abort_assignement:
        LHLD        assignement_abstract_file_ptr
        MVI         M,000H
        INX         H
        MVI         M,000H
        POP         H
        POP         PSW
        PUSH        H
        CALL        flush_ci_input
        POP         PSW
        RET

assign_file_done:
        ;
        ; Check if this is the final assignement or not
        ;
        POP         PSW
        CPI         ','
        JNZ         assignements_done
        JMP         assign_next_file


;//////////////////////////////////////

assign_ci:
        SHLD        CISAVE
        JMP         open_assigned_file

assign_co:
        SHLD        COSAVE
        JMP         open_assigned_file


;//////////////////////////////////////

assignements_done:
        PUSH        PSW
        ;
        ; Check for pending CI assignement, if so assign CI properly now
        ;
        LHLD        CISAVE
        MOV         A,H
        ORA         L
        JZ          ci_assignement_done
        SHLD        CI_FCB
ci_assignement_done:
        ;
        ; Check for pending CO assignement, if so assign CO properly now
        ;
        LHLD        COSAVE
        MOV         A,H
        ORA         L
        JZ          co_assignement_done
        SHLD        CO_FCB
co_assignement_done:
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse and verify drive number in device designator from CI, to A
        ;
parse_device_nr:
        ;
        ; Get and verify device number
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         '0'
        JM          invalid_drive_nr
        CPI         '4'
        JP          invalid_drive_nr
        SUI         '0'
        ;
        ; Verify that the device designator closes with a semicolon as expected
        ;
        MOV         B,A
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_drive_nr
        MOV         A,B
        ANA         A
        RET

invalid_drive_nr:
        CALL        flush_ci_input
        MVI         A,ERROR_11
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse Intel/Tape filename from file CI, to string at HL
        ;
T_FILENAME:
        ;
        ; Clear filename buffer
        ;
        PUSH        D
        MVI         B,9
        XCHG
filname_clear_buffer:
        MVI         M,NULL
        INX         H
        DCR         B
        JNZ         filname_clear_buffer
        POP         D
        ;
        ; Get and store first part of filename, up to 6 characters
        ;
        LHLD        CI_FCB
        CALL        check_alphanumeric
        JC          filename_error
        MVI         B,6
filename_get_next_char:
        STAX        D
        INX         D
        DCR         B
        JZ          filename_first_part_done
        CALL        INCHAR
        RC
        CALL        check_alphanumeric
        JNC         filename_get_next_char
        ;
        ; Check for file extension deliminator, point to file extension if so
        ;
        CPI         '.'
        JNZ         filename_done
filename_point_to_ext_loop:
        INX         D
        DCR         B
        JNZ         filename_point_to_ext_loop
        JMP         filename_get_ext

filename_first_part_done:
        ;
        ; Expect a period as filename extension deliminator if
        ;
        CALL        INCHAR
        RC
        CALL        check_alphanumeric
        JNC         filename_too_long
        CPI         '.'
        JNZ         filename_done
filename_get_ext:
        ;
        ; Get and store filename extension, up to 3 characters
        ;
        MVI         B,3
filename_ext_get_next_char:
        CALL        INCHAR
        RC
        CALL        check_alphanumeric
        JC          filename_done
        STAX        D
        INX         D
        DCR         B
        JNZ         filename_ext_get_next_char
        ;
        ; Verify that there is no more characters after the filename end
        ;
        CALL        INCHAR
        RC
        CALL        check_alphanumeric
        JNC         filename_too_long
        ANA         A
        RET

filename_done:
        ANA         A
        RET


;//////////////////////////////////////

filename_error:
        CALL        flush_ci_input
        MVI         A,ERROR_1B
        STC
        RET

filename_too_long:
        CALL        flush_ci_input
        MVI         A,ERROR_1C
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Parse IBM 3740 filename from file CI, to string at HL
        ;
T_IBFIL:
        ;
        ; Clear filename buffer
        ;
        PUSH        PSW
        PUSH        D
        MVI         B,9
        MVI         A,' '
ibm_filename_clear_buffer:
        STAX        D
        INX         D
        DCR         B
        JNZ         ibm_filename_clear_buffer
        POP         D
        POP         PSW
        ;
        ; Get and store filename, up to 8 characters
        ;
        LHLD        CI_FCB
        CALL        check_alphanumeric
        JC          filename_error
        MVI         B,8
ibm_filename_get_next_char:
        STAX        D
        INX         D
        DCR         B
        JZ          ibm_filename_done
        CALL        INCHAR
        RC
        CALL        check_alphanumeric
        JNC         ibm_filename_get_next_char
        ;
        ; Assume end of filename at the first non-alphanumeric character
        ;
        ANA         A
        RET

ibm_filename_done:
        ;
        ; Verify that there is no more characters after the filename end
        ;
        CALL        INCHAR
        RC
        CALL        check_alphanumeric
        JNC         ibm_filename_too_long
        ANA         A
        RET


;//////////////////////////////////////

ibm_filename_too_long:
        CALL        flush_ci_input
        MVI         A,ERROR_34
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Get abstract file number from abstract-file name from CI
        ;
get_tos_abstract_file_nr:
        ;
        ; Skip any leading whitespace and get the first character of name
        ;
        LHLD        CI_FCB
std_file_skip_whitespace_loop:
        CALL        INCHAR
        RC
        CPI         CR
        JZ          std_file_skip_whitespace_loop
        CPI         '/'
        JZ          std_file_none
        CPI         ' '
        JZ          std_file_skip_whitespace_loop
        CPI         '$'
        JZ          std_file_none
        ;
        ; Check first character of the filename and coarsely set file number
        ;
        CALL        to_uppercase
        MVI         B,1
        CPI         'C'
        JZ          std_file_console
        MVI         B,3
        CPI         'S'
        JZ          std_file_nonconsole
        MVI         B,6
        CPI         'A'
        JZ          std_file_nonconsole
std_file_error:
        CALL        flush_ci_input
        MVI         A,ERROR_21
        STC
        RET


;//////////////////////////////////////

std_file_nonconsole:
        ;
        ; Check second character of abstract-file name, non-console
        ;
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'L'
        JNZ         std_file_check_i_or_o
        ;
        ; Add fine subdivision to file number based on second character
        ;
        INR         B
std_file_nr_add_1:
        INR         B
std_file_nr_add_0:
        MOV         A,B
        ANA         A
        RET

std_file_console:
        ;
        ; Check second character of abstract-file name
        ;
        CALL        INCHAR
        RC
        CALL        to_uppercase
std_file_check_i_or_o:
        CPI         'I'
        JZ          std_file_nr_add_0
        CPI         'O'
        JZ          std_file_nr_add_1
        JMP         std_file_error


;//////////////////////////////////////

std_file_none:
        SUB         A
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Device files
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Main UART output
        ;
DEV_XM_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_OUTPUT
        DW          00000H
        DW          XMIO


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Main UART input
        ;
DEV_RC_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_INPUT
        DW          RCVI
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Null file input
        ;
DEV_NF_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_INPUT
        DW          DEV_NF_routine
        DW          00000H


;//////////////////////////////////////

DEV_NF_routine:
        ;
        ; Always return end-of-file status
        ;
        SUB         A
        STC
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Null file output
        ;
DEV_BB_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_OUTPUT
        DW          00000H
        DW          DEV_BB_routine


;//////////////////////////////////////

DEV_BB_routine:
        ;
        ; Discard data and always return success
        ;
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Console output
        ;
DEV_CO_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_OUTPUT
        DW          00000H
        DW          DEV_CO_routine


;//////////////////////////////////////

DEV_CO_routine:
        ;
        ; Send character to console
        ;
        CALL        TTO
        ;
        ; Make sure to pay extra attention to linefeeds
        ;
        CPI         LF
        JZ          co_emulate_autoscroll
        ANA         A
        RET

co_emulate_autoscroll:
        ;
        ; Check if autoscroll is enabled in hardware
        ;
        PUSH        PSW
        LDA         ROLLSW
        ANA         A
        JZ          co_autoscroll_done
        ;
        ; Emulate autoscroll in case of newline from last line
        ;
        CPI         'Y'
        JZ          co_add_scroll
        ;
        ; Otherwise increase row number
        ;
        INR         A
        STA         ROLLSW
        JMP         co_autoscroll_done

co_add_scroll:
        MVI         A,ROLUP
        CALL        TTO
co_autoscroll_done:
        POP         PSW
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Printer UART output
        ;
DEV_LP_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_OUTPUT
        DW          00000H
        DW          PRNT


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Console buffered line input, with echo on console output
        ;
DEV_CI_FCB_buffered_echo:
        DB          4
        DB          FM_NO_CLOSE + FM_INPUT
        DW          0
        DW          128
        DW          DEV_CI_buffer
        DW          DEV_CI_FCB_echo


;//////////////////////////////////////

        ;
        ; Console input, with echo on console output
        ;
DEV_CI_FCB_echo:
        DB          3
        DB          FM_NO_CLOSE + FM_INPUT
        DW          DEV_CI_FCB
        DW          DEV_CO_FCB


;//////////////////////////////////////

        ;
        ; Console input
        ;
DEV_CI_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_INPUT
        DW          TTI
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Main UART input, with end-of-data Ctrl-C
        ;
DEV_RE_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_INPUT
        DW          serial_text_polling_routine
        DW          00000H


;//////////////////////////////////////

        ;
        ; Console input, with end-of-data on Ctrl-C
        ;
DEV_CE_FCB:
        DB          2
        DB          FM_NO_CLOSE + FM_INPUT
        DW          console_text_polling_routine
        DW          00000H


;//////////////////////////////////////

serial_text_polling_routine:
        CALL        RCVI
        JMP         check_for_end_of_text


;//////////////////////////////////////

console_text_polling_routine:
        CALL        TTI


;//////////////////////////////////////

check_for_end_of_text:
        ;
        ; Raise end-of-file on Ctrl-C
        ;
        CPI         ETX
        JNZ         not_end_of_text
        SUB         A
        STC
        RET

not_end_of_text:
        ANA         A
        RET


;//////////////////////////////////////////////////////////////////////////////

        DB          0FFH
DEV_CI_buffer:
        DB          LF,LF
        DS          126


;//////////////////////////////////////////////////////////////////////////////
;//
;//     CTAB module
;//
;//         Translation tables for converting between EBCDIC and ASCII
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//
;//             v1.4:
;//
;//                 -> Corrects ASCII to EBCDIC table index 07H, 3CH, 60H, C3H
;//                 -> Corrects EBCDIC to ASCII table index 4AH, 58H, 79H
;//
;//             v1.5a:
;//
;//                 -> Corrects ASCII to EBCDIC table index 5CH, 7BH, 7DH, E7H,
;//                    EEH, F5H
;//                 -> Corrects EBCDIC to ASCII table index AAH, ACH, C0H, D0H,
;//                    E0H, EBH
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     EBCDIC Translation tables
;//
;//////////////////////////////////////////////////////////////////////////////

ascii_to_ebcdic_table:
        DB          000H, 001H, 002H, 003H, 037H, 02DH, 02EH, 02FH
        DB          016H, 005H, 025H, 00BH, 00CH, 00DH, 00EH, 00FH
        DB          010H, 011H, 012H, 013H, 03CH, 03DH, 032H, 026H
        DB          018H, 019H, 03FH, 027H, 01CH, 01DH, 01EH, 01FH
        DB          040H, 05AH, 07FH, 07BH, 05BH, 06CH, 050H, 07DH
        DB          04DH, 05DH, 05CH, 04EH, 06BH, 060H, 04BH, 061H
        DB          0F0H, 0F1H, 0F2H, 0F3H, 0F4H, 0F5H, 0F6H, 0F7H
        DB          0F8H, 0F9H, 07AH, 05EH, 04CH, 07EH, 06EH, 06FH
        DB          07CH, 0C1H, 0C2H, 0C3H, 0C4H, 0C5H, 0C6H, 0C7H
        DB          0C8H, 0C9H, 0D1H, 0D2H, 0D3H, 0D4H, 0D5H, 0D6H
        DB          0D7H, 0D8H, 0D9H, 0E2H, 0E3H, 0E4H, 0E5H, 0E6H
        DB          0E7H, 0E8H, 0E9H, 0EAH, 0E0H, 0ECH, 05FH, 06DH
        DB          079H, 081H, 082H, 083H, 084H, 085H, 086H, 087H
        DB          088H, 089H, 091H, 092H, 093H, 094H, 095H, 096H
        DB          097H, 098H, 099H, 0A2H, 0A3H, 0A4H, 0A5H, 0A6H
        DB          0A7H, 0A8H, 0A9H, 0C0H, 0ABH, 0D0H, 04FH, 007H
        DB          004H, 006H, 008H, 009H, 00AH, 014H, 015H, 017H
        DB          01AH, 01BH, 020H, 021H, 022H, 023H, 024H, 028H
        DB          029H, 02AH, 02BH, 02CH, 030H, 031H, 033H, 034H
        DB          035H, 036H, 038H, 039H, 03AH, 03BH, 03EH, 041H
        DB          042H, 043H, 044H, 045H, 046H, 047H, 048H, 049H
        DB          051H, 052H, 053H, 054H, 055H, 056H, 057H, 058H
        DB          059H, 062H, 063H, 064H, 065H, 066H, 067H, 068H
        DB          069H, 06AH, 070H, 071H, 072H, 073H, 074H, 075H
        DB          076H, 077H, 078H, 04AH, 080H, 08AH, 08BH, 08CH
        DB          08DH, 08EH, 08FH, 090H, 09AH, 09BH, 09CH, 09DH
        DB          09EH, 09FH, 0A0H, 0A1H, 0ADH, 0AEH, 0AFH, 0B0H
        DB          0B1H, 0B2H, 0B3H, 0B4H, 0B5H, 0B6H, 0B7H, 0B8H
        DB          0B9H, 0BAH, 0BBH, 0BCH, 0BDH, 0BEH, 0BFH, 0AAH
        DB          0CAH, 0CBH, 0CCH, 0CDH, 0CEH, 0CFH, 0ACH, 0DAH
        DB          0DBH, 0DCH, 0DDH, 0DEH, 0DFH, 0EBH, 0E1H, 0EDH
        DB          0EEH, 0EFH, 0FAH, 0FBH, 0FCH, 0FDH, 0FEH, 0FFH

ebcdic_to_ascii_table:
        DB          000H, 001H, 002H, 003H, 080H, 009H, 081H, 07FH
        DB          082H, 083H, 084H, 00BH, 00CH, 00DH, 00EH, 00FH
        DB          010H, 011H, 012H, 013H, 085H, 086H, 008H, 087H
        DB          018H, 019H, 088H, 089H, 01CH, 01DH, 01EH, 01FH
        DB          08AH, 08BH, 08CH, 08DH, 08EH, 00AH, 017H, 01BH
        DB          08FH, 090H, 091H, 092H, 093H, 005H, 006H, 007H
        DB          094H, 095H, 016H, 096H, 097H, 098H, 099H, 004H
        DB          09AH, 09BH, 09CH, 09DH, 014H, 015H, 09EH, 01AH
        DB          020H, 09FH, 0A0H, 0A1H, 0A2H, 0A3H, 0A4H, 0A5H
        DB          0A6H, 0A7H, 0C3H, 02EH, 03CH, 028H, 02BH, 07EH
        DB          026H, 0A8H, 0A9H, 0AAH, 0ABH, 0ACH, 0ADH, 0AEH
        DB          0AFH, 0B0H, 021H, 024H, 02AH, 029H, 03BH, 05EH
        DB          02DH, 02FH, 0B1H, 0B2H, 0B3H, 0B4H, 0B5H, 0B6H
        DB          0B7H, 0B8H, 0B9H, 02CH, 025H, 05FH, 03EH, 03FH
        DB          0BAH, 0BBH, 0BCH, 0BDH, 0BEH, 0BFH, 0C0H, 0C1H
        DB          0C2H, 060H, 03AH, 023H, 040H, 027H, 03DH, 022H
        DB          0C4H, 061H, 062H, 063H, 064H, 065H, 066H, 067H
        DB          068H, 069H, 0C5H, 0C6H, 0C7H, 0C8H, 0C9H, 0CAH
        DB          0CBH, 06AH, 06BH, 06CH, 06DH, 06EH, 06FH, 070H
        DB          071H, 072H, 0CCH, 0CDH, 0CEH, 0CFH, 0D0H, 0D1H
        DB          0D2H, 0D3H, 073H, 074H, 075H, 076H, 077H, 078H
        DB          079H, 07AH, 0E7H, 07CH, 0EEH, 0D4H, 0D5H, 0D6H
        DB          0D7H, 0D8H, 0D9H, 0DAH, 0DBH, 0DCH, 0DDH, 0DEH
        DB          0DFH, 0E0H, 0E1H, 0E2H, 0E3H, 0E4H, 0E5H, 0E6H
        DB          07BH, 041H, 042H, 043H, 044H, 045H, 046H, 047H
        DB          048H, 049H, 0E8H, 0E9H, 0EAH, 0EBH, 0ECH, 0EDH
        DB          07DH, 04AH, 04BH, 04CH, 04DH, 04EH, 04FH, 050h
        DB          051H, 052H, 0EFH, 0F0H, 0F1H, 0F2H, 0F3H, 0F4H
        DB          05CH, 0F6H, 053H, 054H, 055H, 056H, 057H, 058H
        DB          059H, 05AH, 05BH, 0F5H, 05DH, 0F7H, 0F8H, 0F9H
        DB          030H, 031H, 032H, 033H, 034H, 035H, 036H, 037H
        DB          038H, 039H, 0FAH, 0FBH, 0FCH, 0FDH, 0FEH, 0FFH


;//////////////////////////////////////////////////////////////////////////////
;//
;//     JTAB module, part 2
;//
;//         API jump-tables for interfacing with Tandberg OS, as well as some
;//         constants and lists for use. There is also a jump-table with aliases
;//         to the XMON API.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//
;//             v1.4:
;//
;//                 -> Quick-references to :LP:, :XM: and :RC: added
;//                 -> Non-maintained constants removed
;//
;//             v1.5a:
;//
;//                 -> New PHYSINT API-call for creating FCB from file handle
;//                 -> New API-call added for clean restart of TOS
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     TOS system calls
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0FD00H
MON:
        JMP         T_MON
ERROR:
        JMP         T_ERROR
LOAD:
        JMP         T_LOAD
INCHAR:
        JMP         T_INCHAR
OUTCHAR:
        JMP         T_OUTCHAR
GET:
        JMP         T_GET
PUT:
        JMP         T_PUT
PUTSTR:
        JMP         T_PUTSTR
GETBIN:
        JMP         T_GETBIN
PUTBIN:
        JMP         T_PUTBIN
OPEN:
        JMP         T_OPEN
READ:
        JMP         T_READ
WRITE:
        JMP         T_WRITE
CLOSE:
        JMP         T_CLOSE
EDBH:
        JMP         T_EDBH
EDWH:
        JMP         T_EDWH
EDHB:
        JMP         T_EDHB
EDHW:
        JMP         T_EDHW
BUFALLOC:
        JMP         T_BUFALLOC
BUFDEALLOC:
        JMP         T_BUFDEALLOC
STIMER:
        JMP         T_STIMER


;//////////////////////////////////////////////////////////////////////////////

        ORG         0FD40H
T_TTI:
        JMP         TTI
T_TTO:
        JMP         TTO
T_TTONC:
        JMP         TTONC
T_CURSOR:
        JMP         CURSOR
T_XMON:
        JMP         XMON
T_ERR:
        JMP         ERR
T_PRNT:
        JMP         PRNT
T_DTST:
        JMP         DTST
T_DCAL:
        JMP         DCAL
T_DSRD:
        JMP         DSRD
T_DSWR:
        JMP         DSWR
T_DSDL:
        JMP         DSDL
T_DSRDA:
        JMP         DSRDA
T_DSWRA:
        JMP         DSWRA
T_INDISP:
        JMP         INDISP
T_DSWT:
        JMP         DSWT
T_DCALW:
        JMP         DCALW
T_DSRDW:
        JMP         DSRDW
T_DSWRW:
        JMP         DSWRW
T_DSDLW:
        JMP         DSDLW
T_DSRAW:
        JMP         DSRAW
T_DSWAW:
        JMP         DSWAW
T_RCVI:
        JMP         RCVI
T_LOCDIR:
        JMP         LOCDIR
T_LOADD:
        JMP         LOADD
T_LINKD:
        JMP         LINKD
T_CTST:
        JMP         CTST
T_CCAL:
        JMP         CCAL
T_CBRD:
        JMP         CBRD
T_CBWR:
        JMP         CBWR
T_CBBS:
        JMP         CBBS
T_CBTM:
        JMP         CBTM
T_CBSF:
        JMP         CBSF
T_CBSB:
        JMP         CBSB
T_CUN:
        JMP         CUN
T_CRW:
        JMP         CRW
T_CWT:
        JMP         CWT
T_CBRDW:
        JMP         CBRDW
T_CBWRW:
        JMP         CBWRW
T_CBBSW:
        JMP         CBBSW
T_CBTMW:
        JMP         CBTMW
T_CBSFW:
        JMP         CBSFW
T_CBSBW:
        JMP         CBSBW
T_CLOCDIR:
        JMP         CLOCDIR
T_CLOAD:
        JMP         CLOAD
T_CLINK:
        JMP         CLINK
T_XMIO:
        JMP         XMIO


;//////////////////////////////////////////////////////////////////////////////

FILENAME:
        JMP         T_FILENAME
IBFIL:
        JMP         T_IBFIL
RELN:
        JMP         T_RELN
RELBLK:
        JMP         T_RELBLK
GETN:
        JMP         T_GETN
GETBLK:
        JMP         T_GETBLK
PHYSINT:
        JMP         T_PHYSINT
TOSINIT:
        JMP         T_TOSINIT


;//////////////////////////////////////////////////////////////////////////////
;//
;//     TOS constants
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0FDE6H
TABTC:
        DW          T_TABTC
TABIB:
        DW          T_TABIB
TABIN:
        DW          T_TABIN
        DW          00000H
DEV_LP:
        DW          DEV_LP_FCB
DEV_NF:
        DW          DEV_NF_FCB
DEV_BB:
        DW          DEV_BB_FCB
DEV_CO:
        DW          DEV_CO_FCB
DEV_CI:
        DW          DEV_CI_FCB_buffered_echo
DEV_XM:
        DW          DEV_XM_FCB
DEV_RC:
        DW          DEV_RC_FCB


;//////////////////////////////////////////////////////////////////////////////
;//
;//     TOS standard files
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0FF00H
DEVTAB:
CI_FCB:
        DW          DEV_CI_FCB_buffered_echo
CO_FCB:
        DW          DEV_CO_FCB
SI_FCB:
        DW          00000H
SO_FCB:
        DW          00000H
SL_FCB:
        DW          00000H
AI_FCB:
        DW          00000H
AO_FCB:
        DW          00000H
AL_FCB:
        DW          00000H


;//////////////////////////////////////////////////////////////////////////////
;//
;//     COMI module
;//
;//         The command line argument interpreter. This will identify and parse the
;//         different parts and arguments of the command line input string. In
;//         general the string consists of three parts, a command filename, the
;//         abstract file assignements, and the arguments which will remain in CI
;//         for the program to be run to parse.
;//
;//         If the TOS debug flag is set, the program will be loaded, and the XMON
;//         debugger in ROM will be started with the program-entry preset.
;//
;//
;//         Changelog:
;//
;//             v1.3:
;//
;//                 -> First version I have
;//                 -> Has a bug where a full directory prevents extended handling
;//                    of program-loading issues.
;//
;//             v1.4:
;//
;//                 -> Beeps when linebreak-continuation character is used
;//                 -> Verifies the value of the debug flag, it is ignored if not
;//                    set to exactly the right value
;//                 -> Fixes the file-loading handling bug from v1.3
;//
;//             v1.5a:
;//
;//                 -> Program loader will only accept one line-continuation with
;//                    the / character at the end of the commnand filename
;//


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Command line interpreter routine
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0FE00H
loading_drive_number:
        DB          000H
cli_next_char:
        DB          000H


;//////////////////////////////////////

        ;
        ; Parse the different parts of the command line
        ;
command_line_interpreter:
        ;
        ; Skip any leading whitespace of command line input
        ;
skip_cli_whitespace:
        ;
        ; Set default load drive to :F0:
        ;
        SUB         A
        STA         loading_drive_number
        ;
        ; Get first character of command line content
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          skip_cli_whitespace
        CPI         CR
        JZ          skip_cli_whitespace
        ;
        ; Check if a drive designator is provided, otherwise assume default
        ;
        CPI         ':'
        JNZ         cli_get_program_filename
        ;
        ; Parse drive designator
        ;
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'M'
        JNZ         cli_not_tape_drive
        CALL        parse_device_nr
        RC
        ADI         4
        STA         loading_drive_number
        JMP         cli_drive_number_ready

cli_not_tape_drive:
        CPI         'F'
        JNZ         invalid_drive_type
        CALL        parse_device_nr
        RC
        STA         loading_drive_number
cli_drive_number_ready:
        ;
        ; Get first character of program name, after drive designator
        ;
        CALL        INCHAR
        RC
cli_get_program_filename:
        ;
        ; Save program filename
        ;
        LXI         D,PRGNAM
        CALL        FILENAME
        RC
        STA         cli_next_char
        ;
        ; Load program file to run
        ;
        LXI         H,PRGNAM
        LDA         loading_drive_number
        CALL        LOAD
        JC          cli_load_error
cli_check_start_of_args:
        LDA         cli_next_char
        ;
        ; Check if the character after command name is a linebreak continuation
        ;
        CPI         '/'
        JZ          cli_args_on_next_line
cli_check_next_arg_char:
        ;
        ; Check first character of next part of command line arguments
        ;
        CPI         CR
        JZ          run_program
        CPI         '$'
        JZ          run_program
        CPI         ' '
        JZ          cli_interpret_assignment
        ;
        ; If invalid character, raise an error
        ;
        CALL        flush_ci_input
        MVI         A,ERROR_1F
        STC
        RET


;//////////////////////////////////////

        ;
        ; Assign standard abstract files
        ;
cli_interpret_assignment:
        CALL        assignement_interpreter
        RC
        JMP         cli_check_next_arg_char


;//////////////////////////////////////

        ;
        ; Run a loaded program
        ;
run_program:
        LHLD        PSTART
        ;
        ; Check if TOS debug mode is active
        ;
        LDA         DEBUG
        ANA         A
        JNZ         run_with_debug
        ;
        ; If not, run program as-is
        ;
        PCHL

run_with_debug:
        ;
        ; Else, verify TOS debug flag
        ;
        CPI         TRUE
        JNZ         invalid_debug_flag
        ;
        ; Clear flag and start right into XMON ROM debugger if set correctly
        ;
        SUB         A
        STA         DEBUG
        PUSH        H
        JMP         RESET

invalid_debug_flag:
        ;
        ; If the TOS debug flag has been set incorrectly, ignore and reset it
        ;
        SUB         A
        STA         DEBUG
        JMP         command_line_interpreter


;//////////////////////////////////////

        ;
        ; Error loading program handler
        ;
cli_load_error:
        ;
        ; Check for program not found
        ;
        CPI         ERROR_09
        JZ          retry_uppercase_load
        CPI         ERROR_0B
        JZ          retry_uppercase_load
        STC
        RET

retry_uppercase_load:
        ;
        ; Convert filename to uppercase
        ;
        LXI         H,PRGNAM
        MVI         B,9
        CALL        str_to_uppercase
        RC
        ;
        ; Try to load program again
        ;
        LDA         loading_drive_number
        CALL        LOAD
        JNC         cli_check_start_of_args
        ;
        ; If still not found, flush CI input and return with exception
        ;
        PUSH        PSW
        LDA         cli_next_char
        CALL        flush_ci_input
        POP         PSW
        RET


;//////////////////////////////////////

        ;
        ; Abstract file assignements starts on next line
        ;
cli_args_on_next_line:
        ;
        ; Beep and flush the remaining characters of current line
        ;
cli_flush_remaining_line:
        MVI         A,BEL
        CALL        TTO
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         cli_flush_remaining_line
        ;
        ; Parse assignements of abstract files
        ;
        JMP         cli_interpret_assignment


;//////////////////////////////////////

invalid_drive_type:
        CALL        flush_ci_input
        MVI         A,ERROR_1D
        STC
        RET
