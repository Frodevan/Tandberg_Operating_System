;//////////////////////////////////////////////////////////////////////////////
;//
;//     ALIAS - Make a new alias for a file
;//
;//         Extra parameters:
;//
;//             $[:<Tn>:]<filename>,<aliasname>
;//
;//                 filename    Name of file
;//                 aliasname   Name of alias to file
;//                 Tn          Drive type and number, default :F0:
;//
;//                 Drive type T:
;//                     F       Floppy
;//                     M       Tape
;//
;//                 Drive number n:
;//                     0-3
;//
;//
;//         A feature of TOS is that any file can have aliases. That is several
;//         directory-entries with different names, but where each points to the
;//         very same file data. Changing the contents through an alias, will
;//         update the contents of the original file and all other aliases of the
;//         file.
;//
;//         NOTE: Uses XMON API calls for tape and disk operations. For some XMON
;//               versions, the tape API was an optional add-on. For other versions
;//               the API calls previously used by tape may be repurposed for other
;//               things, like a double-sided double-density floppy disk API. Care
;//               should therefore be taken if running this with a tape device.
;//
;//
;//         Changelog:
;//
;//             1.3: Entry at 0xC000
;//
;//                 -> First version I have
;//                 -> Has a bug where any ASCII symbol below 0x30 ('0') will be
;//                    accepted as a valid drive number
;//                 -> Has a bug where the default drive is not :F0:
;//                 -> Has a bug where the pointer to the alias filename to be
;//                    printed if file already exists, is off by one
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> Clears file-entry buffer at program start
;//                 -> Adds support for files on tape
;//                 -> Flushes the remaining console input before program ends
;//                 -> Fixes drive-number check from v1.3
;//                 -> Fixes default-drive bug from v1.3
;//                 -> Fixes off-by-one pointer bug from v1.3
;//                 -> Prints alias name after making alias
;//                 -> Preserves all but the system attribute for the alias file,
;//                    instead of clearing them
;//                 -> Double-buffers alias file-entry before writing to disk
;//                 -> Uses XMON API call for LOCDIR instead of TOS wrapper call
;//                 -> Removes "ALREADY" from the "ALREADY EXISTS" error message
;//                 -> Adds a bug where the last 9 bytes of the tape buffer does
;//                    not get cleared to zero on program start
;//
;//             1.6a: Entry at 0xC000
;//
;//                 -> Version ID written to 0x2700
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
; XMON system calls
;
DSWRW       EQU     00076H      ; Write to disk with wait
LOCDIR      EQU     00085H      ; Look up filetable entry of filename on disk
CCAL        EQU     00091H      ; Reset tape cartridge
CBWRW       EQU     000B2H      ; Write data to tape cartridge with wait
CBBSW       EQU     000B5H      ; Backspace one block on tape cartridge with wait
CBTMW       EQU     000B8H      ; Write tape mark to tape cartridge with wait
CLOCDIR     EQU     000C1H      ; Look up filetable entry of filename on tape

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
GET         EQU     0FD0FH      ; Input string, inclusive CR
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
PUTSTR      EQU     0FD15H      ; Output string of characters, exclusive CR
FILENAME    EQU     0FDCDH      ; Input TOS filename

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_3B    EQU     03BH        ; DIRECTORY BLOCK ERROR
ERROR_48    EQU     048H        ; TAPE MARK DETECTED

;
; TOS file attributes
;
ATTR_S      EQU     002H        ; System file
ATTR_A      EQU     008H        ; Alias file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'ALIAS',NULL
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Clear filename input and tape block buffers to zero
        ;
        LXI         D,filename_input_buffer
        MVI         C,29
        XRA         A
clear_buffers_loop:
        STAX        D
        INX         D
        DCR         C
        JNZ         clear_buffers_loop
        ;
        ; Assess existence of command line arguments
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         previous_input_char
        CPI         CR
        JZ          invalid_input
        ;
        ; Set working drive from arguments
        ;
        CPI         ':'
        JNZ         drive_set
        CALL        INCHAR
        RC
        CALL        to_uppercase
        STA         previous_input_char
        STA         drive_designator_str+1
        CPI         'M'
        JZ          drive_type_set
        CPI         'F'
        JNZ         invalid_drive
drive_type_set:
        CALL        INCHAR
        RC
        STA         previous_input_char
        STA         drive_designator_str+2
        SUI         '0'
        JC          invalid_input
        CPI         4
        JNC         invalid_input
        STA         drive_number
        CALL        INCHAR
        RC
        STA         previous_input_char
        CPI         ':'
        JNZ         invalid_input
        CALL        INCHAR
        RC
drive_set:
        ;
        ; Get original filename and locate its filetable entry
        ;
        LXI         D,filename_input_buffer
        CALL        FILENAME
        RC
        STA         previous_input_char
        CPI         ','
        JNZ         invalid_input
        LXI         H,filename_input_buffer
        CALL        locate_directory
        RC
        JNZ         invalid_filename
        ;
        ; Copy filetable entry data to alias filetable entry and set attributes
        ;
        LXI         D,alias_filetable_entry+00AH
        LXI         B,00AH
        DAD         B
        MVI         C,9
        LDA         drive_designator_str+1
        CPI         'M'
        JZ          file_metadata_length_set
        MVI         C,6
file_metadata_length_set:
        CALL        mem_copy
        LXI         H,alias_filetable_entry+00AH
        LDA         drive_designator_str+1
        CPI         'F'
        JZ          make_alias
        LXI         H,alias_filetable_entry+012H
make_alias:
        MVI         A,ATTR_A
        ORA         M
        ANI         -1-(ATTR_S)
        MOV         M,A
        ;
        ; Get alias filename and check that it does not exist
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        STA         previous_input_char
        CPI         ':'
        JZ          invalid_input
        LXI         D,alias_filetable_entry+001H
        CALL        FILENAME
        RC
        STA         previous_input_char
        LXI         H,alias_filetable_entry+001H
        CALL        locate_directory
        RC
        JZ          file_exists
        ;
        ; Copy alias entry into filetable
        ;
        LDA         drive_designator_str+1
        CPI         'M'
        JZ          update_filetable_on_tape
        MVI         C,16
        LXI         D,alias_filetable_entry
        XCHG
        CALL        mem_copy
        ;
        ; Write updated filetable back to disk
        ;
        LHLD        TRK
        DCX         H
        MOV         B,M
        DCX         H
        MOV         C,M
        LXI         H,BUF2
        LDA         drive_number
        CALL        DSWRW
        RC
        JMP         alias_made


;//////////////////////////////////////

update_filetable_on_tape:
        ;
        ; Verify and save a copy of cartridge usage block
        ;
        MVI         A,07FH
        CMP         M
        MVI         A,ERROR_3B
        STC
        RNZ
        MVI         C,32
        LXI         D,tape_cart_usage_block_buffer
        CALL        mem_copy
        ;
        ; Write new filetable entry for alias to tape cartridge
        ;
        LDA         drive_number
        MVI         B,0
        CALL        CBBSW
        RC
        LXI         H,alias_filetable_entry
        LXI         D,32
        MVI         B,0
        LDA         drive_number
        CALL        CBWRW
        RC
        ;
        ; Append cartridge usage block that was overwritten
        ;
        LXI         H,tape_cart_usage_block_buffer
        LDA         drive_number
        CALL        CBWRW
        RC
        LDA         drive_number
        CALL        CBTMW
        JNC         reset_tape
        CPI         ERROR_48
        STC
        RNZ
reset_tape:
        ;
        ; Rewind tape
        ;
        LDA         drive_number
        CALL        CCAL
        RC

alias_made:
        ;
        ; Print status message and quit program
        ;
        LXI         B,alias_filetable_entry+1
        CALL        print_filename
        RC
        LXI         D,made_alias_str
        JMP         print_and_quit


;//////////////////////////////////////

invalid_drive:
        LXI         D,improper_unit_str

print_and_quit:
        LHLD        (CO_FCB)
        CALL        PUT
        RC
        LDA         (previous_input_char)
        CPI         CR
        RZ
        LHLD        (CI_FCB)
        CALL        GET
        RET


;//////////////////////////////////////

invalid_input:
        LXI         D,improper_parameters_str
        JMP         print_and_quit


;//////////////////////////////////////

invalid_filename:
        LXI         B,filename_input_buffer
        CALL        print_filename
        RC
        LXI         D,not_found_str
        JMP         print_and_quit


;//////////////////////////////////////

file_exists:
        LXI         B,alias_filetable_entry+1
        CALL        print_filename
        RC
        LXI         D,already_exists_str
        JMP         print_and_quit


;//////////////////////////////////////

        ;
        ; Copy memory of length C from (HL) to (DE)
        ;
mem_copy:
        MOV         A,M
        STAX        D
        INX         H
        INX         D
        DCR         C
        JNZ         mem_copy
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Locate filetable entry of filename (HL)
        ;
locate_directory:
        LDA         drive_designator_str+1
        CPI         'M'
        LDA         drive_number
        JZ          locate_directory_tape
        CALL        LOCDIR
        RC
        XRA         A
        ORA         M
        RET


;//////////////////////////////////////

locate_directory_tape:
        CALL        CLOCDIR
        RC
        XRA         A
        ORA         M
        RET


;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Convert char in A to uppercase
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
        ; Print filename at (BC)
        ;
print_filename:
        ;
        ; Add CR string-termination for final part of filename
        ;
        LXI         H,9
        DAD         B
        MVI         M,CR
        ;
        ; Print drive designator
        ;
        LXI         D,drive_designator_str
        LHLD        CO_FCB
        CALL        PUTSTR
        RC
        ;
        ; Check for file extension and prepare to print filename as a string
        ;
        LXI         H,6
        DAD         B
        XRA         A
        ORA         M
        MOV         D,B
        MOV         E,C
        JZ          print_filename_final_part
        MVI         M,CR
        ;
        ; Print filename before file extension
        ;
        PUSH        H
        LHLD        CO_FCB
        CALL        PUTSTR
        POP         H
        MOV         M,A
        MVI         A,'.'
        CALL        OUTCHAR
        RC
        XCHG
print_filename_final_part:
        ;
        ; Print file extension or extensionless filename
        ;
        LHLD        CO_FCB
        CALL        PUTSTR
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

previous_input_char:
        DB          NULL
drive_number:
        DB          0

filename_input_buffer:
        DS          10

tape_cart_usage_block_buffer:
        DS          32

alias_filetable_entry:
        DB          000H
        DS          31

drive_designator_str:
        DB          ':F0:',CR

improper_unit_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
improper_parameters_str:
        DB          'IMPROPER PARAMETER LIST',CR
not_found_str:
        DB          '   NOT FOUND',CR
already_exists_str:
        DB          '   EXISTS',CR
made_alias_str:
        DB          '   MADE ALIAS',CR
