Source code for various different versions of Tandberg OS, in the form of a GIT history

Disassembly from 8080-binaries by Frode van der Meeren, 2025. Reproducability of original binaries have been verified by re-assembling the binaries with https://www.asm80.com/onepage/asm8080.html

If you want to understand these, it can be a good idea to have the user-manual at hand. An early version is available at http://heim.bitraf.no/tingo/files/tandberg/Tandberg_TOS_21_Users_Guide_1977-01.pdf , although this was still preliminary and there are some minor changes between this and the versions you see here.

There are a few bugs in all of the versions of TOS, to varying degrees. v1.4 in particular is unusable with tape due to a breaking bug that was fixed in v1.5, v1.5 introduced a complete rewrite of the PHYS module for file control block generation that introduced many bugs which were not properly sorted out until v1.61, and the IBM 3740 file system driver was not properly out of experimental before v1.61 as well.

Features like 54KB of User-RAM, as well as the TOS-provided start of memory reference constant require v1.7. v1.7 is also needed for programs using files in EXTEND-data mode. v1.8 enables using multiple files simultaneously on the same tape drive, but added some bugs in some of the tools and these can be quite bad or annoying if encountered. v1.8 also uses a lot of resident RAM due to the size of the SYSTEM binary itself, and this can be a problem for certain programs. If you don't strictly need to use tape-drives, my recommendation is therefore to stick with either v1.61 or v1.7 depending on the memory-needs of the programs you expect to run.

--------------------------------------------------------------------------------

**Main features**

* v1.0: _(1977)_
  * First version, probably only with Intel file system support
* v1.1 _(1977)_
  * Unknown feature set
* v1.2 _(1977)_
  * Partial IBM 3740 file system support
  * Full tape support
* v1.3 _(1977?)_
  * Preview version of v1.4
* v1.4 _(1978)_
  * Selection of utility programs is finalized
  * New text editor and new relocatable assembler/linker
* v1.5 _(1978?)_
  * Improved simple-to-use batch file feature
  * BLOCKLINE access mode for IBM 3740 disks
* v1.51 _(1978?)_
  * Bugfix-release of v1.5
* v1.6 _(1979?)_
  * General improvements and major bugfixes
* v1.61 _(1979?)_
  * Bugfix-release of v1.6
* v1.7 _(1979)_
  * 54KB User-RAM support
* v1.8 _(1980?)_
  * Multiple open files on the same tape-drive support
* v1.81 _(1980)_
  * Small tweaks and minor improvements in some of the utilities

--------------------------------------------------------------------------------

The original sources from Tandberg would likely have been split into several parts per program, and linked accordingly. This way, you may have several different releases of the same version of a program, where the only difference is the order of which its parts have been linked. This is reflected here by having separate commits that only contains these differences due to changes in the linking orders.

NOTE:
EDIT, ASM and RASM will likely not be dissasembled due to their larger program sizes.

Also note:
Currently includes TOS21 Versions 1.3, 1.4*, 1.5, 1.51, 1.6, 1.61, 1.7, 1.8 and 1.81. Not all parts of TOS were updated every version, so many of the programs may show an older version-number than the core version of TOS it was inlcuded with.

(* SYSTEM only for v1.4, the disk did not include any of the additional tools)

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
        LINK        Linker for object files assembled by RASM
        MEMDMP      Dump memory-blocks to Intel Absolute Binary format
    *   RASM        Tandberg TDV-2100 Relocatable Assembler
        XREF        Create cross-reference list from ASM/RASM assembly source file

    Tools: Miscellaneous

        ALLOC       Allocate a file record on a disk in IBM 3740 format
        MYLOAD      Load and run a program from a disk in Mycron MYCRO-1 format
        PROM        Interface tool for PROM programmers
        TTY         Operate like a TDV-2115L dumb-terminal


    * = Bigger program, not dissasembled
