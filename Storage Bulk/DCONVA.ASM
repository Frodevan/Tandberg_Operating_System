;//////////////////////////////////////////////////////////////////////////////
;//
;//     DCONVA - Convert floppy from EBCDIC to ASCII
;//
;//         Extra parameters:
;//
;//             [$Y]
;//
;//                 Y       Immediately start the conversion
;//
;//
;//         Goes through every sector on floppy-disk in unit 0, and converts every
;//         byte from EBCDIC to ASCII. This tool is likely to only be used with
;//         disks in IBM 3740 EBCDIC format, since this may cause issues for disks
;//         with non-text binary structures.
;//
;//         A conversion will stop prematurely if a bad sector is encountered. This
;//         is regardless of if only part of the disk has been converted or not.
;//         Care should therefore be taken to make sure the disk is in good working
;//         order before a conversion is started.
;//
;//         The pointer to the lookup-table used for the conversion is taken from
;//         memory at location 0x277E. Otherwise, all calls to the floppy API are
;//         the TOS aliases of the XMON API, except for the write-deleted-sector
;//         calls that goes to XMON directly. Deleted sectors are also converted.
;//
;//
;//         Changelog:
;//
;//             1.5: Entry at 0xC000
;//
;//                 -> First version I have
;//
;//             1.6: Entry at 0xC000
;//
;//                 -> Version ID written to 0x2700
;//
;//             1.7: Entry at 0x8000
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
DSDLW       EQU     00079H      ; Write deleted to disk with wait

;
; XMON and TOS system data
;
SIGNATURE   EQU     02700H      ; Program signature
ASCI        EQU     0277EH      ; EBCDIC to ASCII translation table reference

;
; TOS system calls
;
INCHAR      EQU     0FD09H      ; Input single character
PUT         EQU     0FD12H      ; Output string of characters, inclusive CR
DCALW       EQU     0FD70H      ; Reset disk drive with wait
DSRDW       EQU     0FD73H      ; Read from disk with wait
DSWRW       EQU     0FD76H      ; Write to disk with wait

;
; TOS standard files
;
CI_FCB      EQU     0FF00H      ; Console input abstract file FCB pointer
CO_FCB      EQU     0FF02H      ; Console output abstract file FCB pointer

;
; TOS Errors
;
ERROR_20    EQU     020H        ; DELETED DATA RECORD


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Signature
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         SIGNATURE
        DB          'DCONVA'
        DB          '106'


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Main program
;//
;//////////////////////////////////////////////////////////////////////////////

        ORG         08000H
start:
        ;
        ; Print welcome prompt string
        ;
        LHLD        CO_FCB
        LXI         D,welcome_prompt_str
        CALL        PUT
        RC
        ;
        ; Expecy a Y to continue, otherwise exit program
        ;
        LHLD        CI_FCB
        CALL        INCHAR
        RC
        CALL        to_uppercase
        CPI         'Y'
        RNZ
        ;
        ; Reset disk drive and get ready to start from track zero
        ;
        SUB         A
        CALL        DCALW
        RC
        MVI         B,0
        ;
        ; Convert a whole track from EBCDIC to ASCII
        ;
convert_next_track:
        ;
        ; Reset pointers and get ready to start from sector one
        ;
        LXI         H,sector_type_list
        SHLD        sector_type_list_ptr
        LXI         H,track_data_buffer
        MVI         C,1
read_next_sector:
        ;
        ; Read sector and check if it's marked as deleted or not
        ;
        SUB         A
        CALL        DSRDW
        JNC         read_ok
        CPI         ERROR_20
        JZ          read_ok
        STC
        JMP         abort_conversion

read_ok:
        ;
        ; Save sector normal/deleted status
        ;
        XCHG
        LHLD        sector_type_list_ptr
        MOV         M,A
        INX         H
        SHLD        sector_type_list_ptr
        XCHG
        ;
        ; Advance pointers and sector count for next sector
        ;
        LXI         D,128
        DAD         D
        MOV         A,C
        ADI         1
        MOV         C,A
        CPI         27
        JM          read_next_sector
        ;
        ; Set up bytecount and pointers for converting the entire track
        ;
        PUSH        B
        LXI         B,26*128
        LHLD        ASCI
        XCHG
        LXI         H,track_data_buffer
translate_sector_loop:
        ;
        ; Fetch EBCDIC byte value and look it up in translation table
        ;
        PUSH        H
        MOV         L,M
        MVI         H,000H
        DAD         D
        MOV         A,M
        POP         H
        ;
        ; Store translated ASCII byte in place of EBCDIC original
        ;
        MOV         M,A
        INX         H
        ;
        ; Advance to next byte to translate
        ;
        DCX         B
        MOV         A,B
        ORA         C
        JNZ         translate_sector_loop
        POP         B
        ;
        ; Prepare to write sectors in track back to disk
        ;
        LXI         H,sector_type_list
        SHLD        sector_type_list_ptr
        LXI         H,track_data_buffer
        MVI         C,1
write_next_sector:
        ;
        ; Get normal/deleted sector state
        ;
        XCHG
        LHLD        sector_type_list_ptr
        MOV         A,M
        INX         H
        SHLD        sector_type_list_ptr
        XCHG
        ;
        ; Write sector back retaining the original sector state
        ;
        ANA         A
        JZ          normal_sector
        SUB         A
        CALL        DSDLW
        JC          abort_conversion
        JMP         sector_written

normal_sector:
        SUB         A
        CALL        DSWRW
        JC          abort_conversion
sector_written:
        ;
        ; Advance to next sector to be written
        ;
        LXI         D,128
        DAD         D
        MOV         A,C
        ADI         1
        MOV         C,A
        CPI         27
        JM          write_next_sector
        ;
        ; Advance to next track to be translated
        ;
        INR         B
        MOV         A,B
        CPI         77
        JNZ         convert_next_track
        RET


;//////////////////////////////////////

abort_conversion:
        PUSH        PSW
        LXI         D,aborted_str
        LHLD        CO_FCB
        CALL        PUT
        POP         PSW
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Subroutines
;//
;//////////////////////////////////////////////////////////////////////////////

to_uppercase:
        CPI         'a'
        RM
        CPI         'z'+1
        RP
        ANI         0DFH
        RET


;//////////////////////////////////////////////////////////////////////////////
;//
;//     Strings and data
;//
;//////////////////////////////////////////////////////////////////////////////

sector_type_list_ptr:
        DS          2
sector_type_list:
        DS          26
track_data_buffer:
        DS          26*128
        DS          26*128

welcome_prompt_str:
        DB          'CONVERT FROM EBCDIC TO ASCII (UNIT 0) - TYPE Y TO START',CR
aborted_str:
        DB          'DISKETTE IS ONLY PARTLY CONVERTED',CR
