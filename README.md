Source code for various different versions of Tandberg OS, in the form of a GIT history

Reproducability of original binaries have been verified by re-assembling the binaries with https://www.asm80.com/onepage/asm8080.html

One thing to note, the original sources from Tandberg would likely have been split into several parts per program, and linked accordingly. This way, you may have several different releases of the same version of a program, where the only difference is the order of which its parts have been linked.

NOTE: Work in progress. TXW, and SYSTEM are yet to have their dissasemblies cleaned up and annotated. EDIT, ASM, RASM and LINK will likely not be dissasembled due to their larger program sizes.

Also note:
Currently includes TOS21 Versions 1.3, 1.5, 1.51, 1.6, 1.61, 1.7, 1.8 and 1.81. Not all parts of TOS were updated every version, so many of the programs may show an older version-number than the core version of TOS it was inlcuded with.

--------------------------------------------------------------------------------

Main TOS programs

    System: Core

        SYSTEM      TOS system kernel binary

    Tools: System

        ASSIGN      Assign devices for consecutive commands
        EXEC        Run command sequence with assigned devices
        RELEAS      Release devices assigned with ASSIGN
        SYS         Set TOS system switches

    File-system: Basic operations

        ALIAS       Make a new alias for a file
        ATTRIB      Change attributes of a file
        DELETE      Delete files and aliases
        DIR         Directory listing
        MOVE        Move data between sources and destinations
        RENAME      Rename a file

    File-system: Advanced operations

        DIRPAC      Pack remaining entries in directory table
        DROP        Reserve sectors from file-operations on floppy
        REMAP       Regenerate sector map file
        RESCUE      Recover recently deleted file

    Storage devices: Initialization

        DGEN        Copy all files from floppy to floppy
        FORMAT      Initialize new TOS filesystem (soft-formating)
        INIT        Initialize floppy disk for use (low-level formating)
        TPGEN       Copy all files from floppy to tape

    Storage devices: Bulk operations

        ANALYZ      Check floppy disk for errors
        DCONVA      Convert floppy from EBCDIC to ASCII
        DCOPY       Duplicate floppy
        DDUMC       Backup floppy image to tape
        DRSTC       Restore floppy image backup from tape
        MDUP        Duplicate tape

    Applications: Text-editing

    *   EDIT        Text editor
        SEDIT       Line text-editor
        TXW         Render text with page/paragraph-layout coding

    Applications: Software-development

    *   ASM         Tandberg TDV-2100 Simple Assembler
        DEBUG       Set TOS and XMON debug flags
        HEXBIN      Convert Intel HEX file to Intel Absolute Binary format
    *   LINK        Linker for object files assembled by RASM
        MEMDMP      Dump memory-blocks to Intel Absolute Binary format
    *   RASM        Tandberg TDV-2100 Relocatable Assembler
        XREF        Create cross-reference list from ASM/RASM assembly source file

    Tools: Miscellaneous

        ALLOC       Allocate a file record on a disk in IBM 3740 format
        MYLOAD      Load and run a program from a disk in Mycron MYCRO-1 format
        PROM        Interface tool for PROM programmers
        TTY         Operate like a TDV-2115L dumb-terminal


    * = Bigger program, not dissasembled
