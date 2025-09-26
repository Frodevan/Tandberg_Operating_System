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
;//                 Tn          Drive type and number, default :F1:
;//
;//                 Drive type T:
;//                     F       Floppy
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
;//         NOTE: Uses XMON API calls for disk operations.
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


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Defines
;//
;//////////////////////////////////////////////////////////////////////////////

;
; ASCII control characters
;
CR          EQU     00DH        ; Cartridge Return

;
; XMON system calls
;
DSWRW       EQU     00076H      ; Write to disk with wait

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
LOCDIR      EQU     0FD85H      ; Look up filetable entry of filename
FILENAME    EQU     0FDCDH      ; Input TOS filename

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS file attributes
;
ATTR_A      EQU     008H        ; Alias file


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         0C000H
start:
        ;
        ; Assess existence of command line arguments
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         CR
        JZ          invalid_input
        ;
        ; Set working drive from arguments
        ;
        CPI         ':'
        JNZ         drive_set
        CALL        INCHAR
        RC
        CPI         'F'
        JNZ         invalid_drive
        CALL        INCHAR
        RC
        SUI         '0'
        CPI         4
        JNC         invalid_input
        STA         drive_number
        CALL        INCHAR
        RC
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
        CPI         ','
        JNZ         invalid_input
        LXI         H,filename_input_buffer
        CALL        locate_directory
        RC
        JNZ         invalid_filename
        ;
        ; Copy filetable entry data to alias filetable entry
        ;
        LXI         D,alias_filetable_entry+00AH
        LXI         B,00AH
        DAD         B
        MVI         C,6
        CALL        mem_copy
        ;
        ; Get alias filename and check that it does not exist
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CPI         ':'
        JZ          invalid_input
        LXI         D,alias_filetable_entry+001H
        CALL        FILENAME
        RC
        LXI         H,alias_filetable_entry+001H
        CALL        locate_directory
        RC
        JZ          file_exists
        ;
        ; Copy alias entry into filetable and set file-attribute A
        ;
        MVI         M,000H
        PUSH        H
        INX         H
        MVI         C,15
        LXI         D,alias_filetable_entry+001H
        XCHG
        CALL        mem_copy
        LXI         D,00AH
        POP         H
        DAD         D
        MVI         M,ATTR_A
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
        RET


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


;//////////////////////////////////////

invalid_drive:
        LXI         D,improper_unit_str

print_and_quit:
        ;
        ; Print error-string and quit program
        ;
        LHLD        CO_FCB
        CALL        PUT
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
        LXI         B,alias_filetable_entry
        CALL        print_filename
        RC
        LXI         D,already_exists_str
        JMP         print_and_quit


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

        ;
        ; Locate filetable entry of filename (HL)
        ;
locate_directory:
        LDA         drive_number
        CALL        LOCDIR
        RC
        XRA         A
        ORA         M
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
        LDA         drive_number
        ADI         '0'
        STA         drive_designator_str+2
        LXI         D,drive_designator_str
        LHLD        CO_FCB
        CALL        PUTSTR
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

drive_designator_str:
        DB          ':F0:',CR

improper_unit_str:
        DB          'IMPROPER UNIT SPECIFICATION',CR
improper_parameters_str:
        DB          'IMPROPER PARAMETER LIST',CR
not_found_str:
        DB          '   NOT FOUND',CR
already_exists_str:
        DB          '   ALREADY EXISTS',CR

drive_number:
        DB          1

filename_input_buffer:
        DS          10

alias_filetable_entry:
        DS          16
