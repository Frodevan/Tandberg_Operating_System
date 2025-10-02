;//////////////////////////////////////////////////////////////////////////////
;//
;//     INIT - Initialize floppy disk for use (low-level formating)
;//
;//         Extra parameters:
;//
;//             [$:<Tn>:]
;//
;//                 Tn          Drive type and number, default :F0:
;//
;//                 Drive type T:
;//                     F       Floppy (Interlaced)
;//                     I       Floppy (Non-interlaced)
;//                     J       Floppy (Non-interlaced)
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         Prepares a floppy disk drive from scratch, writing out the low-level
;//         address marks and sectors. This will need to be run before an
;//         unformatted disk can be used.
;//
;//         Despite the option to specify drive type, this will only decide wether
;//         the sectors will be laid out in interlaced order or sequential. The
;//         content is otherwise always a dummy IBM 3740 file-directory in EBCDIC
;//         with a dummy file called DATA on the first index, and deleted files
;//         named DATA9 to DATA26 for the remaining file indices. If the disk is to
;//         be used with TOS/Intel format (drive type :Fn:), then FORMAT will need
;//         to be run on the disk after INIT is done. If IBM format in ASCII is
;//         desirable (drive type :An:), use the DCONVA command on the disk after
;//         running INIT.
;//
;//         There is always a prompt before the initialization starts, giving ample
;//         time to swap from a work-disk to the new disk to be initialized. After
;//         the end of initialization, when returning to TOS, a similar prompt will
;//         ask for a system workdisk to be re-inserted. Later versions will also
;//         prompt the user if they want to initialize more disks before getting
;//         that far.
;//
;//         During the disk initialization process, the tracks are written starting
;//         with track 0 and ending with track 77. A track is written in a single
;//         revolution, and then verified by reading each sector. The data read is
;//         then compared with what was initially written. In the case of any
;//         mismatch, the track will be read and compared up to 5 times in order to
;//         try to get at least one good read. If not successfull in any of these,
;//         the entire track will be re-written and re-verified up to 5 times.
;//
;//
;//         Changelog:
;//
;//             Early-a: Entry at 0xEAF8
;//
;//                 -> First version I have
;//                 -> Has a bug where the verficiation read-attempt count is not
;//                    set at the start of the track-verification process
;//                 -> Has a bug where software-autoscroll is not invoked if it
;//                    should have been
;//                 -> Has a bug where any failure will not try to reload TOS when
;//                    exiting the program, resulting in instability and/or crashes
;//                 -> Introduces a bug where the number in the name of the deleted
;//                    file indices of the file-directory is not properly converted
;//                    to EBCDIC numbers
;//                 -> Introduces a bug where the last character of the label
;//                    record is a T, not W as expected
;//
;//             Early-b: Entry at 0x8000
;//
;//                 -> Requires at least 32KB RAM, instead of only 16KB
;//                 -> Allows for spaces before drive-type command line argument
;//                 -> Adds default drive, in case no drive is specified
;//                 -> Recognizes drive type F, adding interlacing sector-order
;//                 -> Only prints startup-prompt once, instead of also after each
;//                    invalid input
;//                 -> Number of max write-attempts per track reduced from 20 to 5
;//                 -> Fixes the verification attempt-countdown bug from v1.3,
;//                    setting the count for maximum number of read-attempts to 5
;//                 -> Adds prompt to insert a system disk after initialization is
;//                    done if drive 0 was used
;//                 -> Flushes excess input if invalid parameters
;//                 -> Fixes the software-autoscroll bug from v1.3
;//
;//             Early-c: Entry at 0x8000
;//
;//                 -> Recognizes new drive type J
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
ETX         EQU     003H        ; End of text
BEL         EQU     007H        ; Bell (short beep)
LF          EQU     00AH        ; Line Feed
ROLUP       EQU     00CH        ; Scroll screen up one row
CR          EQU     00DH        ; Cartridge Return

;
; IO ports
;
DRIVA_IO    EQU     030H        ; Floppy (SSSD) drive select
RELTA_IO    EQU     031H        ; Floppy (SSSD) relative track
ADDHI_IO    EQU     033H        ; Floppy (SSSD) addres high byte
ADDLO_IO    EQU     034H        ; Floppy (SSSD) addres low byte
CLKBT_IO    EQU     035H        ; Floppy (SSSD) clock byte
DATBT_IO    EQU     036H        ; Floppy (SSSD) data byte
DCMD_IO     EQU     037H        ; Floppy (SSSD) command (W) and status (R)

;
; XMON system calls
;
TTI         EQU     00040H      ; Console input
TTO         EQU     00043H      ; Console output
ERR         EQU     0004FH      ; Throw an error
DCAL        EQU     00058H      ; Reset disk drive
DSWT        EQU     0006DH      ; Wait for floppy disk controller
DSRDW       EQU     00073H      ; Read from disk with wait
LOADD       EQU     00088H      ; Load and unpack file from floppy disk to memory

;
; XMON and TOS system data
;
ROLLSW      EQU     0271FH      ; Cursor line number if no hardware autoscroll
DPROG       EQU     02761H      ; Floppy prog status
DCONT       EQU     02763H      ; Floppy cont address
DTRK        EQU     02767H      ; Floppy track nr
DRETRY      EQU     0276DH      ; Floppy retry address

;
; TOS system calls
;
MON         EQU     0FD00H      ; Restart TOS resident monitor
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         08000H
start:
        ;
        ; Set default drive number to 0
        ;
        XRA         A
        STA         drive_number
        ;
        ; Peek at the next byte of the command line arguments input
        ;
        LHLD        CI_FCB
        INX         H
        INX         H
        MOV         E,M         ; CI_FCB + FCB_BUFIDX
        INX         H
        MOV         D,M
        INX         H
        INX         H
        INX         H
        MOV         C,M         ; CI_FCB + FCB_BUFPTR
        INX         H
        MOV         B,M
        XCHG
        DAD         B
        DCX         H
        MOV         A,M
        ;
        ; Print unit prompt if no cli args have been given
        ;
        CPI         CR
        JNZ         prune_initial_spaces_loop
        LXI         D,unit_prompt_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC
        ;
        ; Skip any leading whitespaces
        ;
prune_initial_spaces_loop:
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ' '
        JZ          prune_initial_spaces_loop
        ;
        ; Set default sector order to that of drive type F (interlaced)
        ;
        LXI         D,interlaced_sector_order
        CPI         CR
        JZ          drive_set
        ;
        ; Parse drive designator from command line arguments
        ;
        CPI         ':'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'J'
        JNZ         ibm_type_j_check_done
        DCR         A
ibm_type_j_check_done:
        CPI         'F'
        JZ          sector_layout_set
        LXI         D,noninterlaced_sector_order
        CPI         'I'
        JNZ         invalid_drive
sector_layout_set:
        CALL        INCHAR
        RC
        SUI         '0'
        JC          invalid_drive
        CPI         4
        JNC         invalid_drive
        STA         drive_number
        CALL        INCHAR
        RC
        CPI         ':'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        CPI         CR
        JNZ         invalid_drive
drive_set:
        XCHG
        SHLD        sector_order_ptr
        ;
        ; Check if drive 0 is to be low-level formatted
        ;
        LDA         drive_number
        ORA         A
        JNZ         format_first_track
        ;
        ; If so, prompt the user so they have time to change disk
        ;
        LXI         D,welcome_prompt_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC
get_next_prompt_input:
        CALL        TTI
        CALL        to_uppercase
        ;
        ; Validate prompt input
        ;
        CPI         'Y'
        JZ          parse_prompt_input
        CPI         'N'
        JNZ         get_next_prompt_input
parse_prompt_input:
        ;
        ; Exit if No was chosen
        ;
        MOV         C,A
        CALL        TTO
        LXI         D,newline_str
        LHLD        CO_FCB
        CALL        PUT
        RC
        MOV         A,C
        CPI         'N'
        JZ          operation_interrupted


;//////////////////////////////////////

        ;
        ; Track 0: Unpack low-level format pattern into one big data-buffer
        ;
format_first_track:
        ;
        ; Reset disk drive
        ;
        LDA         drive_number
        CALL        DCAL
        ;
        ; Set up variables to build the low-level format pattern in buffer
        ;
        XRA         A
        STA         track_number
        LXI         H,noninterlaced_sector_order
        SHLD        next_sector_number_ptr
        LXI         H,write_low_level_track_one
        SHLD        next_track_routine_ptr
        LXI         H,first_track_pattern_set
        SHLD        data_mark_pattern_list_ptr
        LXI         H,track_pattern_buffer
        SHLD        track_pattern_data_ptr
        ;
        ; Start by adding gap4a + index-mark + gap1 to low-level pattern buffer
        ;
        LXI         D,track_header_pattern
        CALL        unpack_pattern_to_buffer
add_next_track_zero_sector:
        ;
        ; Add address-mark + gap2 for next sector, updating the sector number
        ;
        CALL        get_next_sector_number
        LXI         D,sector_header_pattern
        CALL        unpack_pattern_to_buffer
        LHLD        current_pattern_entry_ptr
        LXI         D,9*2 + 1
        DAD         D
        LDA         sector_number
        MOV         M,A
        ;
        ; Fetch pointer to next pattern to use for data-mark
        ;
        LHLD        data_mark_pattern_list_ptr
        MOV         E,M
        INX         H
        MOV         D,M
        INX         H
        SHLD        data_mark_pattern_list_ptr
        ;
        ; Add selected data-mark + gap3, check if this is a file record sector
        ;
        CALL        unpack_pattern_to_buffer
        LDA         sector_number
        CPI         9
        JC          track_zero_sector_done
        ;
        ; Update number (EBCDIC) of filename in pattern buffer, if file record
        ;
        LHLD        current_pattern_entry_ptr
        LXI         D,16*2 + 1
        DAD         D
        MOV         B,A
        ANI         0F0H
        RRC
        RRC
        RRC
        RRC
        ADI         0F0H
        MOV         M,A
        INX         H
        INX         H
        MOV         A,B
        ANI         00FH
        ADI         0F0H
        MOV         M,A
        MOV         A,B
track_zero_sector_done:
        ;
        ; Check if this is the last sector in the track
        ;
        CPI         26
        JC          add_next_track_zero_sector
        ;
        ; Add gap4b to finalize pattern
        ;
        LXI         D,track_end_padding_pattern
        CALL        unpack_pattern_to_buffer
        JMP         finalize_track_pattern


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Track 1: Empty the content of all sector data-marks from track 0
        ;
write_low_level_track_one:
        ;
        ; Update track number, and which function to call later for track 2
        ;
        MVI         A,1
        STA         track_number
        LHLD        sector_order_ptr
        SHLD        next_sector_number_ptr
        LXI         H,format_bulk_track
        SHLD        next_track_routine_ptr
        ;
        ; Point to start of address-mark of first sector in low-level pattern
        ;
        LXI         H,track_pattern_buffer + 72*2
update_next_track_one_sector:
        ;
        ; Update sector number to use the currently selected interlace order
        ;
        SHLD        track_pattern_data_ptr
        CALL        get_next_sector_number
        LXI         D,9*2 + 1
        DAD         D
        MOV         M,A
        LXI         D,14*2 + 1
        DAD         D
        ;
        ; Overwrite old data-mark pattern with data-mark of an empty sector
        ;
        SHLD        track_pattern_data_ptr
        LXI         D,empty_sector_pattern
        CALL        unpack_pattern_to_buffer
        ;
        ; Check if this is the last sector in the track
        ;
        LHLD        track_pattern_data_ptr
        LDA         sector_number
        CPI         26
        JC          update_next_track_one_sector


;//////////////////////////////////////

finalize_track_pattern:
        ;
        ; Point to first byte in data-mark of first sector in low-level pattern
        ;
        MVI         A,1
        STA         sector_number
        LXI         H,track_pattern_buffer + 102*2
prep_next_sector_data_mark:
        ;
        ; Calculate and add checksum at end of data-mark
        ;
        SHLD        track_pattern_data_ptr
        LXI         D,1 + 128
        CALL        calculate_and_insert_crc
        ;
        ; Check if this is the last sector in the track
        ;
        LDA         sector_number
        CPI         26
        JNC         track_data_marks_done
        ;
        ; Advance to next sector data-mark in pattern
        ;
        INR         A
        STA         sector_number
        LHLD        track_pattern_data_ptr
        LXI         D,188*2
        DAD         D
        JMP         prep_next_sector_data_mark

track_data_marks_done:


;//////////////////////////////////////

        ;
        ; Track 2-76: Just update track nr and checksum of sector address-marks
        ;
format_bulk_track:
        ;
        ; Point to first byte in address-mark of first sector in ll-pattern
        ;
        MVI         A,1
        STA         sector_number
        LXI         H,track_pattern_buffer + 78*2
prep_next_sector_address_mark:
        ;
        ; Update track nr, calculate and add checksum at end of address-mark
        ;
        SHLD        track_pattern_data_ptr
        INX         H
        INX         H
        INX         H
        LDA         track_number
        MOV         M,A
        LXI         D,1 + 4
        CALL        calculate_and_insert_crc
        ;
        ; Check if this is the last sector in the track
        ;
        LDA         sector_number
        CPI         26
        JNC         write_low_level_track
        ;
        ; Advance to next sector address-mark in pattern
        ;
        INR         A
        STA         sector_number
        LHLD        track_pattern_data_ptr
        LXI         D,188*2
        DAD         D
        JMP         prep_next_sector_address_mark


;//////////////////////////////////////

        ;
        ; Format a single track with already set data, retry on error
        ;
write_low_level_track:
        ;
        ; Wait for disk controller to be ready and prepare for write
        ;
        CALL        DSWT
        JC          operation_aborted
        MVI         A,5
        STA         write_retry_countdown
start_formatting_track:
        ;
        ; Prime disk controller for formatting
        ;
        CALL        set_drive_select_reg
        LXI         H,track_pattern_buffer
        MOV         A,H
        OUT         ADDHI_IO
        MOV         A,L
        OUT         ADDLO_IO
        MOV         A,M
        OUT         CLKBT_IO
        INX         H
        MOV         A,M
        OUT         DATBT_IO
        MVI         A,0FFH
        STA         DPROG
        LXI         H,00000H
        SHLD        DCONT
        ;
        ; Send format command to disk controller
        ;
        DI
        MVI         A,0FBH
        OUT         DCMD_IO
        ;
        ; Wait until controller returns to not-busy for consecutive checks
        ;
wait_for_not_busy:
        MVI         C,10
verify_not_busy:
        IN          DCMD_IO
        MOV         B,A
        ANI         001H
        JNZ         wait_for_not_busy
        DCR         C
        JNZ         verify_not_busy
        ;
        ; Check disk controller operation-completed status
        ;
        MOV         A,B
        ANI         080H
        JNZ         verify_formatted_track
        ;
        ; Command did not complete, retry if there are more retries left
        ;
format_track_failed:
        LXI         H,write_retry_countdown
        DCR         M
        JNZ         start_formatting_track
        EI
        JMP         operation_aborted


;//////////////////////////////////////

        ;
        ; Read back all sectors and make sure data matches what was written
        ;
verify_formatted_track:
        ;
        ; Wait for XMON floppy disk API to be ready and prepare to verify track
        ;
        EI
        CALL        DSWT
        JC          operation_aborted
        MVI         A,5
        STA         verification_retry_countdown
start_track_verification:
        ;
        ; Prepare to read all sectors in track, starting on sector 1
        ;
        MVI         C,1
        LXI         H,track_readback_buffer
        LXI         D,128
        LDA         track_number
        MOV         B,A
readback_next_sector:
        ;
        ; Read sector, and check status register for any error-bits
        ;
        LDA         drive_number
        CALL        DSRDW
        IN          DCMD_IO
        ANI         03FH
        JNZ         format_track_failed
        ;
        ; Check for last sector
        ;
        MOV         A,C
        CPI         26
        JNC         track_readback_done
        ;
        ; Advance to next sector
        ;
        INR         C
        DAD         D
        JMP         readback_next_sector

track_readback_done:
        ;
        ; Point to first data-byte of first sector in format pattern
        ;
        LXI         H,track_pattern_buffer + 103*2 + 1
        SHLD        track_pattern_data_ptr
        MVI         C,26
        LXI         D,track_readback_buffer
verify_next_sector:
        MVI         B,128
verify_next_byte:
        ;
        ; Compare data from format pattern with data read back from disk
        ;
        LDAX        D
        CMP         M
        JNZ         verification_failed
        INX         H
        INX         H
        INX         D
        DCR         B
        JNZ         verify_next_byte
        DCR         C
        JZ          verification_complete
        PUSH        D
        LHLD        track_pattern_data_ptr
        LXI         D,188*2
        DAD         D
        SHLD        track_pattern_data_ptr
        POP         D
        JMP         verify_next_sector

verification_failed:
        ;
        ; Retry verification process if any retries left
        ;
        LXI         H,verification_retry_countdown
        DCR         M
        JNZ         start_track_verification
        JMP         format_track_failed

verification_complete:
        ;
        ; Check if this is the last track
        ;
        LDA         track_number
        CPI         76
        JNC         operation_completed
        ;
        ; Advance to format next track
        ;
        INR         A
        STA         track_number
        STA         DTRK
        CALL        set_drive_select_reg
        ;
        ; Prepare disk controller to step one track out
        ;
        MVI         A,081H
        OUT         RELTA_IO
        MVI         A,0FFH
        STA         DPROG
        LXI         H,00000H
        SHLD        DCONT
        SHLD        DRETRY
        ;
        ; Send relative step command to disk controller
        ;
        MVI         A,0E3H
        OUT         DCMD_IO
        ;
        ; Jump to routine for formatting the next track
        ;
        LHLD        next_track_routine_ptr
        PCHL


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Set appropriate drive select bit based on drive number
        ;
set_drive_select_reg:
        LDA         drive_number
        MOV         B,A
        MVI         A,002H
        ;
        ; Note: Drive 0 rotates left 255 times to in effect shift right by 1
        ;
shift_bitfield_loop:
        DCR         B
        JZ          bitfield_ready
        RLC
        JMP         shift_bitfield_loop

bitfield_ready:
        OUT         DRIVA_IO
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Gets the next sector number of the selected sector order in A
        ;
get_next_sector_number:
        PUSH        H
        LHLD        next_sector_number_ptr
        MOV         A,M
        STA         sector_number
        INX         H
        SHLD        next_sector_number_ptr
        POP         H
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Unpack a pattern pointed to by DE and append to track format buffer
        ;
unpack_pattern_to_buffer:
        ;
        ; Save entry pointer to current pattern
        ;
        LHLD        track_pattern_data_ptr
        SHLD        current_pattern_entry_ptr
        ;
        ; Get number of RLE clock-data bytepair segments in pattern
        ;
        XCHG
        MOV         A,M
        STA         pattern_segments
unpack_pattern_segment:
        ;
        ; Get number of repetitions of RLE clock-data bytepair segment
        ;
        INX         H
        MOV         A,M
        STA         segment_repetitions
        ;
        ; Save pointer to RLE segment
        ;
        INX         H
        SHLD        pattern_segment_data_ptr
add_pattern_segment:
        ;
        ; Copy clock-data bytepair into buffer once
        ;
        LHLD        pattern_segment_data_ptr
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        MOV         A,M
        STAX        D
        INX         D
        ;
        ; Check if there's more repetitions of segment
        ;
        LDA         segment_repetitions
        DCR         A
        STA         segment_repetitions
        JNZ         add_pattern_segment
        ;
        ; Check if there's more segments in pattern
        ;
        LDA         pattern_segments
        DCR         A
        STA         pattern_segments
        JZ          pattern_unpacked
        ;
        ; Advance to next segment of pattern
        ;
        LHLD        pattern_segment_data_ptr
        INX         H
        JMP         unpack_pattern_segment

pattern_unpacked:
        ;
        ; Update track format buffer next-byte pointer
        ;
        XCHG
        SHLD        track_pattern_data_ptr
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Calculate and insert the CRC of the next DE bytes from data pointer
        ;
calculate_and_insert_crc:
        ;
        ; Prepare for CRC, with initial value 0FFFFH
        ;
        XCHG
        SHLD        crc_remaining_bytes
        LXI         B,0FFFFH
        LHLD        track_pattern_data_ptr
crc_next_byte:
        ;
        ; Get data byte from track format-data
        ;
        INX         H
        PUSH        H
        MOV         A,M
        ;
        ; Simulates 8 bitshifts at once by using XORs and a translation table
        ;
        XRA         B
        MOV         E,A
        MVI         D,000H
        LXI         H,next_crc_high_byte
        DAD         D
        MOV         A,M
        XRA         C
        MOV         B,A
        INR         H
        MOV         C,M
        ;
        ; Check if there are more bytes left to add to CRC
        ;
        LHLD        crc_remaining_bytes
        DCX         H
        SHLD        crc_remaining_bytes
        MOV         A,L
        ORA         H
        POP         H
        INX         H
        JNZ         crc_next_byte
        ;
        ; Inject CRC into the next two data-bytes in track format-pattern
        ;
        INX         H
        MOV         M,B
        INX         H
        INX         H
        MOV         M,C
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Data
;//
;//////////////////////////////////////////////////////////////////////////////

noninterlaced_sector_order:
        DB          1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26
interlaced_sector_order:
        DB          1,14,2,15,3,16,4,17,5,18,6,19,7,20,8,21,9,22,10,23,11,24,12,25,13,26

first_track_pattern_set:
        DW          blank_sector_pattern
        DW          blank_sector_pattern
        DW          blank_sector_pattern
        DW          blank_sector_pattern
        DW          ermap_sector_pattern
        DW          blank_sector_pattern
        DW          label_record_pattern
        DW          dumy_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern
        DW          deleted_file_record_pattern

blank_sector_pattern:
        DB            6
        DB            6, 0FFH, 000H
        DB            1, 0C7H, 0FBH
        DB           80, 0FFH, 040H
        DB           48, 0FFH, 000H
        DB            2, 0FFH, 000H
        DB           27, 0FFH, 0FFH

ermap_sector_pattern:
        DB           11
        DB            6, 0FFH, 000H
        DB            1, 0C7H, 0FBH
        DB            1, 0FFH, 0C5H
        DB            1, 0FFH, 0D9H
        DB            1, 0FFH, 0D4H
        DB            1, 0FFH, 0C1H
        DB            1, 0FFH, 0D7H
        DB           75, 0FFH, 040H
        DB           48, 0FFH, 000H
        DB            2, 0FFH, 000H
        DB           27, 0FFH, 0FFH

label_record_pattern:
        DB           17
        DB            6, 0FFH, 000H
        DB            1, 0C7H, 0FBH
        DB            1, 0FFH, 0E5H
        DB            1, 0FFH, 0D6H
        DB            1, 0FFH, 0D3H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 0C9H
        DB            1, 0FFH, 0C2H
        DB            1, 0FFH, 0D4H
        DB            1, 0FFH, 0C9H
        DB            1, 0FFH, 0D9H
        DB            1, 0FFH, 0C4H
        DB           69, 0FFH, 040H
        DB            1, 0FFH, 0E3H
        DB           48, 0FFH, 000H
        DB            2, 0FFH, 000H
        DB           27, 0FFH, 0FFH

dumy_file_record_pattern:
        DB           37
        DB            6, 0FFH, 000H
        DB            1, 0C7H, 0FBH
        DB            1, 0FFH, 0C8H
        DB            1, 0FFH, 0C4H
        DB            1, 0FFH, 0D9H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 040H
        DB            1, 0FFH, 0C4H
        DB            1, 0FFH, 0C1H
        DB            1, 0FFH, 0E3H
        DB            1, 0FFH, 0C1H
        DB           15, 0FFH, 040H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F8H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 040H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 040H
        DB            1, 0FFH, 0F7H
        DB            1, 0FFH, 0F3H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F2H
        DB            1, 0FFH, 0F6H
        DB           35, 0FFH, 040H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 040H
        DB           48, 0FFH, 000H
        DB            2, 0FFH, 000H
        DB           27, 0FFH, 0FFH

deleted_file_record_pattern:
        DB           39
        DB            6, 0FFH, 000H
        DB            1, 0C7H, 0F8H
        DB            1, 0FFH, 0C4H
        DB            1, 0FFH, 0C4H
        DB            1, 0FFH, 0D9H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 040H
        DB            1, 0FFH, 0C4H
        DB            1, 0FFH, 0C1H
        DB            1, 0FFH, 0E3H
        DB            1, 0FFH, 0C1H
        DB            1, 0FFH, 000H
        DB            1, 0FFH, 000H
        DB           13, 0FFH, 040H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F8H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 040H
        DB            1, 0FFH, 0F7H
        DB            1, 0FFH, 0F4H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 040H
        DB            1, 0FFH, 0F7H
        DB            1, 0FFH, 0F3H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F2H
        DB            1, 0FFH, 0F6H
        DB           35, 0FFH, 040H
        DB            1, 0FFH, 0F7H
        DB            1, 0FFH, 0F4H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F0H
        DB            1, 0FFH, 0F1H
        DB            1, 0FFH, 040H
        DB           48, 0FFH, 000H
        DB            2, 0FFH, 000H
        DB           27, 0FFH, 0FFH

empty_sector_pattern:
        DB            5
        DB            6, 0FFH, 000H
        DB            1, 0C7H, 0FBH
        DB          128, 0FFH, 0E5H
        DB            2, 0FFH, 000H
        DB           27, 0FFH, 0FFH

sector_header_pattern:
        DB            8
        DB            6, 0FFH, 000H
        DB            1, 0C7H, 0FEH
        DB            1, 0FFH, 000H
        DB            1, 0FFH, 000H
        DB            1, 0FFH, 000H
        DB            1, 0FFH, 000H
        DB            2, 0FFH, 000H
        DB           11, 0FFH, 0FFH

track_end_padding_pattern:
        DB            3
        DB          247, 0FFH, 0FFH
        DB          100, 0FFH, 0FFH
        DB          190, 0FFH, 0FFH

track_header_pattern:
        DB            4
        DB           39, 0FFH, 0FFH
        DB            6, 0FFH, 000H
        DB            1, 0D7H, 0FCH
        DB           26, 0FFH, 0FFH

next_crc_high_byte:
        DB          000H,010H,020H,030H,040H,050H,060H,070H,081H,091H,0A1H,0B1H,0C1H,0D1H,0E1H,0F1H
        DB          012H,002H,032H,022H,052H,042H,072H,062H,093H,083H,0B3H,0A3H,0D3H,0C3H,0F3H,0E3H
        DB          024H,034H,004H,014H,064H,074H,044H,054H,0A5H,0B5H,085H,095H,0E5H,0F5H,0C5H,0D5H
        DB          036H,026H,016H,006H,076H,066H,056H,046H,0B7H,0A7H,097H,087H,0F7H,0E7H,0D7H,0C7H
        DB          048H,058H,068H,078H,008H,018H,028H,038H,0C9H,0D9H,0E9H,0F9H,089H,099H,0A9H,0B9H
        DB          05AH,04AH,07AH,06AH,01AH,00AH,03AH,02AH,0DBH,0CBH,0FBH,0EBH,09BH,08BH,0BBH,0ABH
        DB          06CH,07CH,04CH,05CH,02CH,03CH,00CH,01CH,0EDH,0FDH,0CDH,0DDH,0ADH,0BDH,08DH,09DH
        DB          07EH,06EH,05EH,04EH,03EH,02EH,01EH,00EH,0FFH,0EFH,0DFH,0CFH,0BFH,0AFH,09FH,08FH
        DB          091H,081H,0B1H,0A1H,0D1H,0C1H,0F1H,0E1H,010H,000H,030H,020H,050H,040H,070H,060H
        DB          083H,093H,0A3H,0B3H,0C3H,0D3H,0E3H,0F3H,002H,012H,022H,032H,042H,052H,062H,072H
        DB          0B5H,0A5H,095H,085H,0F5H,0E5H,0D5H,0C5H,034H,024H,014H,004H,074H,064H,054H,044H
        DB          0A7H,0B7H,087H,097H,0E7H,0F7H,0C7H,0D7H,026H,036H,006H,016H,066H,076H,046H,056H
        DB          0D9H,0C9H,0F9H,0E9H,099H,089H,0B9H,0A9H,058H,048H,078H,068H,018H,008H,038H,028H
        DB          0CBH,0DBH,0EBH,0FBH,08BH,09BH,0ABH,0BBH,04AH,05AH,06AH,07AH,00AH,01AH,02AH,03AH
        DB          0FDH,0EDH,0DDH,0CDH,0BDH,0ADH,09DH,08DH,07CH,06CH,05CH,04CH,03CH,02CH,01CH,00CH
        DB          0EFH,0FFH,0CFH,0DFH,0AFH,0BFH,08FH,09FH,06EH,07EH,04EH,05EH,02EH,03EH,00EH,01EH

next_crc_low_byte:
        DB          000H,021H,042H,063H,084H,0A5H,0C6H,0E7H,008H,029H,04AH,06BH,08CH,0ADH,0CEH,0EFH
        DB          031H,010H,073H,052H,0B5H,094H,0F7H,0D6H,039H,018H,07BH,05AH,0BDH,09CH,0FFH,0DEH
        DB          062H,043H,020H,001H,0E6H,0C7H,0A4H,085H,06AH,04BH,028H,009H,0EEH,0CFH,0ACH,08DH
        DB          053H,072H,011H,030H,0D7H,0F6H,095H,0B4H,05BH,07AH,019H,038H,0DFH,0FEH,09DH,0BCH
        DB          0C4H,0E5H,086H,0A7H,040H,061H,002H,023H,0CCH,0EDH,08EH,0AFH,048H,069H,00AH,02BH
        DB          0F5H,0D4H,0B7H,096H,071H,050H,033H,012H,0FDH,0DCH,0BFH,09EH,079H,058H,03BH,01AH
        DB          0A6H,087H,0E4H,0C5H,022H,003H,060H,041H,0AEH,08FH,0ECH,0CDH,02AH,00BH,068H,049H
        DB          097H,0B6H,0D5H,0F4H,013H,032H,051H,070H,09FH,0BEH,0DDH,0FCH,01BH,03AH,059H,078H
        DB          088H,0A9H,0CAH,0EBH,00CH,02DH,04EH,06FH,080H,0A1H,0C2H,0E3H,004H,025H,046H,067H
        DB          0B9H,098H,0FBH,0DAH,03DH,01CH,07FH,05EH,0B1H,090H,0F3H,0D2H,035H,014H,077H,056H
        DB          0EAH,0CBH,0A8H,089H,06EH,04FH,02CH,00DH,0E2H,0C3H,0A0H,081H,066H,047H,024H,005H
        DB          0DBH,0FAH,099H,0B8H,05FH,07EH,01DH,03CH,0D3H,0F2H,091H,0B0H,057H,076H,015H,034H
        DB          04CH,06DH,00EH,02FH,0C8H,0E9H,08AH,0ABH,044H,065H,006H,027H,0C0H,0E1H,082H,0A3H
        DB          07DH,05CH,03FH,01EH,0F9H,0D8H,0BBH,09AH,075H,054H,037H,016H,0F1H,0D0H,0B3H,092H
        DB          02EH,00FH,06CH,04DH,0AAH,08BH,0E8H,0C9H,026H,007H,064H,045H,0A2H,083H,0E0H,0C1H
        DB          01FH,03EH,05DH,07CH,09BH,0BAH,0D9H,0F8H,017H,036H,055H,074H,093H,0B2H,0D1H,0F0H

track_number:
        DS          1
sector_number:
        DS          1
drive_number:
        DS          1
segment_repetitions:
        DS          1
pattern_segments:
        DS          1
pattern_segment_data_ptr:
track_pattern_data_ptr:
        DS          2
        DS          4
current_pattern_entry_ptr:
        DS          2
data_mark_pattern_list_ptr:
        DS          2
crc_remaining_bytes:
        DS          2
verification_retry_countdown:
        DS          1
write_retry_countdown:
        DS          1
next_track_routine_ptr:
        DS          2
sector_order_ptr:
        DS          2
next_sector_number_ptr:
        DS          2
track_readback_buffer:
        DS          26*128


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Program termination
;//
;//////////////////////////////////////////////////////////////////////////////

operation_completed:
        ;
        ; Print status message
        ;
        LXI         D,operation_completed_str
print_and_quit:
        CALL        print_str
        ;
        ; Check if a non-system drive was formatted
        ;
        LDA         drive_number
        ORA         A
        JNZ         reload_system_and_exit
        ;
        ; Prompt for system disk before reloading TOS
        ;
        LXI         D,sys_disk_prompt_str
        CALL        print_str
system_disk_prompt:
        CALL        TTI
        CPI         'C'
        JZ          reload_system_and_exit
        CPI         'c'
        JZ          reload_system_and_exit
        MVI         A,BEL
        CALL        TTO
        JMP         system_disk_prompt

reload_system_and_exit:
        ;
        ; Make sure to reload TOS before quitting program
        ;
        XRA         A
        LXI         H,system_filename_str
        CALL        LOADD
        JC          ERR
        JMP         MON


;//////////////////////////////////////

operation_aborted:
        LXI         D,operation_aborted_str
        JMP         print_and_quit


;//////////////////////////////////////////////////////////////////////////////

invalid_drive:
        ;
        ; Flush any remaining command line arguments
        ;
flush_remaining_args_loop:
        CPI         CR
        JZ          args_flushed
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        JMP         flush_remaining_args_loop

args_flushed:
        ;
        ; Print status and quit program
        ;
        LXI         D,invalid_drive_str
print_and_ret:
        LHLD        CO_FCB
        CALL        PUT
        RET


;//////////////////////////////////////

operation_interrupted:
        LXI         D,operation_interrupted_str
        JMP         print_and_ret


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert ASCII character in A into uppercase
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
        ; Print string pointed to by DE
        ;
print_str:
        LDAX        D
        CPI         CR
        JZ          print_str_newline
        CPI         ETX
        RZ
print_next_char:
        CALL        TTO
        INX         D
        JMP         print_str


;//////////////////////////////////////

        ;
        ; Handle new-line cases
        ;
print_str_newline:
        CALL        TTO
        ;
        ; Check autoscroll flag for line number if no autoscroll
        ;
        LDA         ROLLSW
        ORA         A
        JZ          print_str_has_autoscroll
        ;
        ; Manually scroll if cursor is at the very last line
        ;
        CPI         'Y'
        JC          print_str_no_need_to_scroll
        MVI         A,ROLUP
        JMP         print_next_char

print_str_no_need_to_scroll:
        ;
        ; Update autoscroll flag line number
        ;
        INR         A
        STA         ROLLSW
print_str_has_autoscroll:
        ;
        ; Move cursor to next line
        ;
        MVI         A,LF
        JMP         print_next_char


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings
;//
;//////////////////////////////////////////////////////////////////////////////

unit_prompt_str:
        DB          'UNIT: ',CR
invalid_drive_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR,ETX
operation_aborted_str:
        DB          'OPERATION ABORTED'
newline_str:
        DB          CR,ETX
welcome_prompt_str:
        DB          'INITIALIZE DISKETTE IN DRIVE 0  (Y/N): ',CR
operation_interrupted_str:
        DB          'OPERATION INTERRUPTED',CR,ETX
operation_completed_str:
        DB          'OPERATION COMPLETED',CR,ETX
sys_disk_prompt_str:
        DB          'CHANGE TO SYSTEM DISKETTE, TYPE "C" TO CONTINUE',BEL,CR,ETX

system_filename_str:
        DB          'SYSTEM'
        DB          NULL,NULL,NULL


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Track pattern
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
track_pattern_buffer:
        DS          72*2 + 26*(24*2 + 164*2) + 537*2
