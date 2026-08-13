; =========================================================================
; Microsoft BASIC for 6502, Version 1.1
; Originally written by Microsoft, 1976-1978
; Translated to ca65 (cc65 toolchain) syntax for a KIM-like target
; with custom ACIA I/O (bw-board).
;
; COPYRIGHT 1976 BY MICROSOFT
;
; Permission is hereby granted, free of charge, to any person obtaining
; a copy of this software and associated documentation files, to deal
; in the Software without restriction, including without limitation the
; rights to use, copy, modify, merge, publish, distribute, sublicense,
; and/or sell copies of the Software, and to permit persons to whom the
; Software is furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included
; in all copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
;
; Target configuration (resolved):
;   REALIO=1 (KIM base), ROMSW=1, KIMROM=1
;   ADDPRC=1 (5-byte FP), INTPRC=1 (integer arrays)
;   LNGERR=0, NULCMD=1, GETCMD=1, RORSW=1
;   EXTIO=0, DISKO=0, TIME=0, BUFPAG=0
;   LINLEN=72, BUFLEN=72
;   ROMLOC=$8000, RAMLOC=$0200
; =========================================================================

; ---------------------
; Constants
; ---------------------
LINLEN   = 72
BUFLEN   = 72
CLMWID   = 14
NCMPOS   = (((LINLEN/CLMWID)-1)*CLMWID)   ; =56
STKEND   = 511
ROMLOC   = $8000
RAMLOC   = $0200
NUMLEV   = 23
STRSIZ   = 3
NUMTMP   = 3
CONTW    = 15              ; ^O character to suppress output
FORSIZ   = 18              ; 2*ADDPRC+16 = 2*1+16

; ACIA registers
ACIA_DATA   = $5000
ACIA_STATUS = $5001
ACIA_CMD    = $5002
ACIA_CTRL   = $5003

; =========================================================================
; ZERO PAGE
; =========================================================================
.segment "ZEROPAGE"

START:   jmp INIT           ; overwritten to JMP READY after init
RDYJSR:  jmp INIT           ; overwritten to JMP STROUT after init
ADRAYI:  .word AYINT        ; address of FAC-to-integer routine
ADRGAY:  .word GIVAYF       ; address of integer-to-FAC routine
USRPOK:  jmp FCERR          ; USR() vector, set up by INIT

; --- General RAM ---
CHARAC:  .res 1             ; delimiting character
INTEGR = CHARAC             ; one-byte integer from QINT
ENDCHR:  .res 1             ; other delimiting character
COUNT:   .res 1             ; general counter

; --- Flags ---
DIMFLG:  .res 1             ; DIM flag
KIMY   = DIMFLG             ; preserve Y during output
VALTYP:  .res 1             ; type: 0=numeric, $FF=string
INTFLG:  .res 1             ; integer flag
DORES:   .res 1             ; crunch flag
GARBFL = DORES              ; garbage collection flag
SUBFLG:  .res 1             ; subscript flag
INPFLG:  .res 1             ; INPUT/READ flag
TANSGN:  .res 1             ; tangent sign
CNTWFL:  .res 1             ; suppress output flag

; --- Terminal handling ---
NULCNT:  .byte 0            ; null count
TRMPOS:  .res 1             ; terminal position
LINWID:  .byte LINLEN       ; line width
NCMWID:  .byte NCMPOS       ; no more comma fields position
LINNUM:  .byte 0            ; line number (2 bytes, before BUF)
         .byte 44           ; comma preload for INPUT
POKER  = LINNUM             ; POKE location alias

; Buffer on page zero (BUFPAG=0)
BUF:     .res BUFLEN        ; input buffer

; --- String temporaries ---
TEMPPT:  .res 1             ; pointer to first free temp descriptor
LASTPT:  .res 2             ; pointer to last-used string temp
TEMPST:  .res STRSIZ*NUMTMP ; 9 bytes for 3 temp descriptors
INDEX1:  .res 2             ; indexes
INDEX  = INDEX1
INDEX2:  .res 2
RESHO:   .res 1             ; result of multiply/divide
RESMOH:  .res 1             ; one more byte (ADDPRC)
RESMO:   .res 1
RESLO:   .res 1
ADDEND = RESMO              ; temp used by UMULT
         .byte 0            ; overflow for RES

; --- Pointers into dynamic data ---
TXTTAB:  .res 2             ; pointer to beginning of text
VARTAB:  .res 2             ; pointer to simple variable space
ARYTAB:  .res 2             ; pointer to array table
STREND:  .res 2             ; end of storage in use
FRETOP:  .res 2             ; top of string free space
FRESPC:  .res 2             ; pointer to new string
MEMSIZ:  .res 2             ; highest memory location

; --- Line numbers and text pointers ---
CURLIN:  .res 2             ; current line number
OLDLIN:  .res 2             ; old line number
OLDTXT:  .res 2             ; old text pointer
DATLIN:  .res 2             ; DATA line number
DATPTR:  .res 2             ; pointer to DATA
INPPTR:  .res 2             ; INPUT pointer

; --- Evaluation stuff ---
VARNAM:  .res 2             ; variable name
VARPNT:  .res 2             ; pointer to variable
FDECPT = VARPNT             ; pointer into FOUT power-of-ten
FORPNT:  .res 2             ; FOR/LET pointer
LSTPNT = FORPNT             ; list string pointer
ANDMSK = FORPNT             ; AND mask for WAIT
EORMSK = FORPNT+1           ; EOR mask for WAIT
OPPTR:   .res 2             ; operator pointer
VARTXT = OPPTR              ; pointer into variable list
OPMASK:  .res 1             ; mask for current operator
DOMASK = TANSGN             ; mask for relational ops
DEFPNT:  .res 2             ; pointer for function definition
GRBPNT = DEFPNT             ; garbage collection pointer
DSCPNT:  .res 2             ; pointer to string descriptor
         .res 1             ; for TEMPF3 (ADDPRC)
FOUR6:   .byte STRSIZ       ; constant used by garbage collect

; --- Et cetera ---
JMPER:   jmp $EA60          ; indirect jump
SIZE   = JMPER+1
OLDOV  = JMPER+2
TEMPF3 = DEFPNT             ; third FAC temp (4 bytes)
TEMPF1:
         .byte 0            ; extra byte for TEMPF1 (ADDPRC)
HIGHDS:  .res 2             ; destination of highest element in BLT
HIGHTR:  .res 2             ; source of highest element
TEMPF2:
         .byte 0            ; extra byte for TEMPF2 (ADDPRC)
LOWDS:   .res 2             ; last byte transferred into
LOWTR:   .res 2             ; last thing to move in BLT
ARYPNT = HIGHDS             ; pointer used in array building
GRBTOP = LOWTR              ; pointer used in garbage collection
DECCNT = LOWDS              ; places before decimal point
TENEXP = LOWDS+1            ; decimal point flag
DPTFLG = LOWTR              ; base ten exponent
EXPSGN = LOWTR+1            ; sign of base ten exponent

; --- Floating Accumulator ---
FAC:
FACEXP:  .byte 0
FACHO:   .byte 0            ; most significant byte
FACMOH:  .byte 0            ; extra byte (ADDPRC)
FACMO:   .byte 0            ; middle order
FACLO:   .byte 0            ; least significant byte
FACSGN:  .byte 0            ; sign (0 or $FF)
SGNFLG:  .byte 0            ; sign preserved by FIN
DEGREE = SGNFLG             ; polynomial degree counter
DSCTMP = FAC                ; temp descriptor built here
INDICE = FACMO              ; indice for QINT
BITS:    .byte 0            ; used by SHIFTR

; --- Floating Argument (unpacked) ---
ARGEXP:  .byte 0
ARGHO:   .byte 0
ARGMOH:  .byte 0            ; extra byte (ADDPRC)
ARGMO:   .byte 0
ARGLO:   .byte 0
ARGSGN:  .byte 0

ARISGN:  .byte 0            ; sign of arithmetic result
FACOV:   .byte 0            ; overflow byte
STRNG1 = ARISGN             ; string pointer

FBUFPT:  .res 2             ; pointer into FBUFFR
BUFPTR = FBUFPT             ; pointer to BUF for CRUNCH
STRNG2 = FBUFPT             ; string pointer
POLYPT = FBUFPT             ; polynomial pointer
CURTOL = FBUFPT             ; absolute linear index

; =========================================================================
; PAGE ZERO RAM CODE - CHRGET subroutine
; This is copied from INITAT during INIT.
; =========================================================================
; CHRGET must be here so TXTPTR is a ZP address
CHRGET:  inc CHRGET+7       ; increment TXTPTR
         bne CHRGOT
         inc CHRGET+8
CHRGOT:  lda $EA60          ; load with extended address (self-modifying)
TXTPTR = CHRGOT+1
         cmp #' '           ; skip spaces
         beq CHRGET
QNUM:    cmp #':'           ; is it ":"?
         bcs CHRRTS         ; >= ":"
         sec
         sbc #'0'           ; chars > '9' already returned
         sec
         sbc #256-'0'       ; set carry if numeric, Z if null
CHRRTS:  rts

RNDX:    .byte 128          ; initial random number seed
         .byte 79
         .byte 199
         .byte 82
         .byte 89           ; extra byte (ADDPRC)

; LOFBUF is at fixed address $FF (last byte of page 0)
LOFBUF = $FF

; =========================================================================
; BSS segment - page 1 (FBUFFR on stack page boundary)
; =========================================================================
.segment "BSS"

FBUFFR:  .res 3+13          ; 16 bytes for FOUT buffer
; Stack occupies rest of page 1 up to STKEND

; =========================================================================
; CODE segment - ROM at $8000
; =========================================================================
.segment "CODE"

; -------------------------
; Statement dispatch table
; -------------------------
STMDSP:  .word END_-1
         .word FOR-1
         .word NEXT-1
         .word DATA-1
         ; (no INPUT# - EXTIO=0)
         .word INPUT-1
         .word DIM-1
         .word READ-1
         .word LET-1
         .word GOTO-1
         .word RUN-1
         .word IF_-1
         .word RESTOR-1
         .word GOSUB-1
         .word RETURN_-1
         .word REM-1
         .word STOP-1
         .word ONGOTO-1
         .word NULL_-1       ; NULCMD=1
         .word FNWAIT-1
         ; (no LOAD/SAVE - DISKO=0)
         .word DEF-1
         .word POKE-1
         ; (no PRINT# - EXTIO=0)
         .word PRINT_-1
         .word CONT-1
         .word LIST-1
         .word CLEAR-1
         ; (no CMD/SYS/OPEN/CLOSE - EXTIO=0)
         .word GET-1         ; GETCMD=1
         .word SCRATH-1

; -------------------------
; Function dispatch table
; -------------------------
FUNDSP:  .word SGN_
         .word INT_
         .word ABS_
USRLOC:  .word USRPOK        ; USR function -> USRPOK (ROM build)
         .word FRE
         .word POS
         .word SQR_
         .word RND_
         .word LOG_
         .word EXP_
         ; COS/SIN/TAN/ATN -> FCERR (KIMROM=1)
         .word FCERR
         .word FCERR
         .word FCERR
         .word FCERR
         .word PEEK_
         .word LEN_
         .word STR_
         .word VAL_
         .word ASC_
         .word CHR_
         .word LEFT_
         .word RIGHT_
         .word MID_

; -------------------------
; Operator table
; -------------------------
OPTAB:   .byte 121
         .word FADDT-1
         .byte 121
         .word FSUBT-1
         .byte 123
         .word FMULTT-1
         .byte 123
         .word FDIVT-1
         .byte 127
         .word FPWRT-1
         .byte 80
         .word ANDOP-1
         .byte 70
         .word OROP-1
NEGTAB:  .byte 125
         .word NEGOP-1
NOTTAB:  .byte 90
         .word NOTOP-1
PTDORL:  .byte 100           ; precedence for relational
         .word DOREL-1

; =========================================================================
; Token values
; =========================================================================
; Tokens start at $80 (128). Order must match RESLST and dispatch tables.
ENDTK    = 128
FORTK    = 129
;NEXTTK  = 130
DATATK   = 131
;INPUTTK = 132
;DIMTK   = 133
;READTK  = 134
;LETTK   = 135
GOTOTK   = 136
;RUNTK   = 137
;IFTK    = 138
;RESTORETK = 139
GOSUTK   = 140
;RETURNTK = 141
REMTK    = 142
;STOPTK  = 143
;ONTK    = 144
;NULLTK  = 145
;WAITTK  = 146
;DEFTK   = 147
;POKETK  = 148
PRINTK   = 149
;CONTTK  = 150
;LISTTK  = 151
;CLEARTK = 152
;GETTK   = 153
SCRATK   = 154
; non-statement tokens follow:
TABTK    = 155
TOTK     = 156
FNTK     = 157
SPCTK    = 158
THENTK   = 159
NOTTK    = 160
STEPTK   = 161
PLUSTK   = 162
MINUTK   = 163
;STARTK  = 164
;SLASHTK = 165
;CARTK   = 166
;ANDTK   = 167
;ORTK    = 168
GREATK   = 169
EQULTK   = 170
LESSTK   = 171
; functions:
ONEFUN   = 172   ; SGN
;INTTK   = 173
;ABSTK   = 174
;USRTK   = 175
;FRETK   = 176
;POSTK   = 177
;SQRTK   = 178
;RNDTK   = 179
;LOGTK   = 180
;EXPTK   = 181
;COSTK   = 182
;SINTK   = 183
;TANTK   = 184
;ATNTK   = 185
;PEEKTK  = 186
;LENTK   = 187
;STRTK   = 188
;VALTK   = 189
;ASCTK   = 190
;CHRTK   = 191
LASNUM   = 191
;LEFTTK  = 192
;RIGHTTK = 193
;MIDTK   = 194
GOTK     = 195

; =========================================================================
; Reserved word list (DCI encoding: last char has bit 7 set)
; =========================================================================
RESLST:
         ; Statements
         .byte "EN", 'D'+$80           ; END
         .byte "FO", 'R'+$80           ; FOR
         .byte "NEX", 'T'+$80          ; NEXT
         .byte "DAT", 'A'+$80          ; DATA
         ; (no INPUT# - EXTIO=0)
         .byte "INPU", 'T'+$80         ; INPUT
         .byte "DI", 'M'+$80           ; DIM
         .byte "REA", 'D'+$80          ; READ
         .byte "LE", 'T'+$80           ; LET
         .byte "GOT", 'O'+$80          ; GOTO
         .byte "RU", 'N'+$80           ; RUN
         .byte "I", 'F'+$80            ; IF
         .byte "RESTOR", 'E'+$80       ; RESTORE
         .byte "GOSU", 'B'+$80         ; GOSUB
         .byte "RETUR", 'N'+$80        ; RETURN
         .byte "RE", 'M'+$80           ; REM
         .byte "STO", 'P'+$80          ; STOP
         .byte "O", 'N'+$80            ; ON
         .byte "NUL", 'L'+$80          ; NULL (NULCMD=1)
         .byte "WAI", 'T'+$80          ; WAIT
         ; (no LOAD/SAVE - DISKO=0)
         .byte "DE", 'F'+$80           ; DEF
         .byte "POK", 'E'+$80          ; POKE
         ; (no PRINT# - EXTIO=0)
         .byte "PRIN", 'T'+$80         ; PRINT
         .byte "CON", 'T'+$80          ; CONT
         .byte "LIS", 'T'+$80          ; LIST
         .byte "CLEA", 'R'+$80         ; CLEAR
         ; (no CMD/SYS/OPEN/CLOSE - EXTIO=0)
         .byte "GE", 'T'+$80           ; GET (GETCMD=1)
         .byte "NE", 'W'+$80           ; NEW
         ; End of statement list

         ; Non-statement tokens
         .byte "TAB", '('+$80          ; TAB(
         .byte "T", 'O'+$80            ; TO
         .byte "F", 'N'+$80            ; FN
         .byte "SPC", '('+$80          ; SPC(
         .byte "THE", 'N'+$80          ; THEN
         .byte "NO", 'T'+$80           ; NOT
         .byte "STE", 'P'+$80          ; STEP
         .byte '+'+$80                 ; +
         .byte '-'+$80                 ; -
         .byte '*'+$80                 ; *
         .byte '/'+$80                 ; /
         .byte '^'+$80                 ; ^
         .byte "AN", 'D'+$80           ; AND
         .byte "O", 'R'+$80            ; OR
         .byte '>'+$80                 ; >
         .byte '='+$80                 ; =
         .byte '<'+$80                 ; <

         ; Functions
         .byte "SG", 'N'+$80           ; SGN
         .byte "IN", 'T'+$80           ; INT
         .byte "AB", 'S'+$80           ; ABS
         .byte "US", 'R'+$80           ; USR
         .byte "FR", 'E'+$80           ; FRE
         .byte "PO", 'S'+$80           ; POS
         .byte "SQ", 'R'+$80           ; SQR
         .byte "RN", 'D'+$80           ; RND
         .byte "LO", 'G'+$80           ; LOG
         .byte "EX", 'P'+$80           ; EXP
         .byte "CO", 'S'+$80           ; COS
         .byte "SI", 'N'+$80           ; SIN
         .byte "TA", 'N'+$80           ; TAN
         .byte "AT", 'N'+$80           ; ATN
         .byte "PEE", 'K'+$80          ; PEEK
         .byte "LE", 'N'+$80           ; LEN
         .byte "STR", '$'+$80          ; STR$
         .byte "VA", 'L'+$80           ; VAL
         .byte "AS", 'C'+$80           ; ASC
         .byte "CHR", '$'+$80          ; CHR$
         ; multi-arg functions
         .byte "LEFT", '$'+$80         ; LEFT$
         .byte "RIGHT", '$'+$80        ; RIGHT$
         .byte "MID", '$'+$80          ; MID$
         ; GO token (for "GO TO" parsing)
         .byte "G", 'O'+$80            ; GO
         .byte 0                       ; end of list

; =========================================================================
; Error table (short 2-char form, LNGERR=0)
; =========================================================================
ERRNF    = 0                ; NEXT WITHOUT FOR
ERRSN    = 2                ; SYNTAX
ERRRG    = 4                ; RETURN WITHOUT GOSUB
ERROD    = 6                ; OUT OF DATA
ERRFC    = 8                ; ILLEGAL QUANTITY
ERROV    = 10               ; OVERFLOW
ERROM    = 12               ; OUT OF MEMORY
ERRUS    = 14               ; UNDEFINED STATEMENT
ERRBS    = 16               ; BAD SUBSCRIPT
ERRDD    = 18               ; REDIMENSIONED ARRAY
ERRDV0   = 20               ; DIVISION BY ZERO
ERRID    = 22               ; ILLEGAL DIRECT
ERRTM    = 24               ; TYPE MISMATCH
ERRLS    = 26               ; STRING TOO LONG
; (no FILE DATA - EXTIO=0)
ERRST    = 28               ; FORMULA TOO COMPLEX
ERRCN    = 30               ; CAN'T CONTINUE
ERRUF    = 32               ; UNDEFINED FUNCTION

ERRTAB:
         .byte 'N','F'+$80  ; NF
         .byte 'S','N'+$80  ; SN
         .byte 'R','G'+$80  ; RG
         .byte 'O','D'+$80  ; OD
         .byte 'F','C'+$80  ; FC
         .byte 'O','V'+$80  ; OV
         .byte 'O','M'+$80  ; OM
         .byte 'U','S'+$80  ; US
         .byte 'B','S'+$80  ; BS
         .byte 'D','D'+$80  ; DD
         .byte '/','0'+$80  ; /0
         .byte 'I','D'+$80  ; ID
         .byte 'T','M'+$80  ; TM
         .byte 'L','S'+$80  ; LS
         .byte 'S','T'+$80  ; ST
         .byte 'C','N'+$80  ; CN
         .byte 'U','F'+$80  ; UF

; =========================================================================
; Text messages
; =========================================================================
ERR_MSG: .byte " ERROR", 0
INTXT:   .byte " IN ", 0
REDDY:   .byte 13, 10
         .byte "OK"
         .byte 13, 10, 0
BRKTXT:  .byte 13, 10
         .byte "BREAK", 0

; =========================================================================
; GENERAL STORAGE MANAGEMENT ROUTINES
; =========================================================================

; Find FOR entry on stack via VARPNT/FORPNT
FNDFOR:  tsx
         inx
         inx
         inx
         inx
FFLOOP:  lda 257,x
         cmp #FORTK
         bne FFRTS
         lda FORPNT+1
         bne CMPFOR
         lda 258,x
         sta FORPNT
         lda 259,x
         sta FORPNT+1
CMPFOR:  cmp 259,x
         bne ADDFRS
         lda FORPNT
         cmp 258,x
         beq FFRTS
ADDFRS:  txa
         clc
         adc #FORSIZ
         tax
         bne FFLOOP
FFRTS:   rts

; Block transfer routine (BLTU)
BLTU:    jsr REASON
         sta STREND
         sty STREND+1
BLTUC:   sec
         lda HIGHTR
         sbc LOWTR
         sta INDEX
         tay
         lda HIGHTR+1
         sbc LOWTR+1
         tax
         inx
         tya
         beq DECBLT
         lda HIGHTR
         sec
         sbc INDEX
         sta HIGHTR
         bcs BLT1
         dec HIGHTR+1
         sec
BLT1:    lda HIGHDS
         sbc INDEX
         sta HIGHDS
         bcs MOREN1
         dec HIGHDS+1
         bcc MOREN1         ; always
BLTLP:   lda (HIGHTR),y
         sta (HIGHDS),y
MOREN1:  dey
         bne BLTLP
         lda (HIGHTR),y
         sta (HIGHDS),y
DECBLT:  dec HIGHTR+1
         dec HIGHDS+1
         dex
         bne MOREN1
         rts

; Check stack space
GETSTK:  asl a
         adc #2*NUMLEV+3+13  ; 2*23+3+13 = 62
         bcs OMERR
         sta INDEX
         tsx
         cpx INDEX
         bcc OMERR
         rts

; Check that [Y,A] < FRETOP
REASON:  cpy FRETOP+1
         bcc REARTS
         bne TRYMOR
         cmp FRETOP
         bcc REARTS
TRYMOR:  pha
         ldx #9              ; 8+ADDPRC
         tya
REASAV:  pha
         lda HIGHDS-1,x
         dex
         bpl REASAV
         jsr GARBA2
         ldx #<(256-9)       ; 256-8-ADDPRC
REASTO:  pla
         sta HIGHDS+9,x      ; HIGHDS+8+ADDPRC
         inx
         bmi REASTO
         pla
         tay
         pla
         cpy FRETOP+1
         bcc REARTS
         bne OMERR
         cmp FRETOP
         bcs OMERR
REARTS:  rts

; =========================================================================
; ERROR HANDLER, READY, TERMINAL INPUT, CRUNCH, NEW, REINIT
; =========================================================================
OMERR:   ldx #ERROM
ERROR:
         lsr CNTWFL          ; force output
ERRCRD:  jsr CRDO
         jsr OUTQST
         ; Short error messages (LNGERR=0)
         lda ERRTAB,x
         jsr OUTDO
         lda ERRTAB+1,x
         jsr OUTDO
TYPERR:  jsr STKINI
         lda #<ERR_MSG
         ldy #>ERR_MSG
ERRFIN:  jsr STROUT
         ldy CURLIN+1
         iny
         beq READY
         jsr INPRT
READY:
         lsr CNTWFL
         lda #<REDDY
         ldy #>REDDY
         jsr RDYJSR
MAIN:    jsr INLIN
         stx TXTPTR
         sty TXTPTR+1
         jsr CHRGET
         tax
         beq MAIN
         ldx #255
         stx CURLIN+1
         bcc MAIN1
         jsr CRUNCH
         jmp GONE
MAIN1:   jsr LINGET
         jsr CRUNCH
         sty COUNT
         jsr FNDLIN
         bcc NODEL
         ldy #1
         lda (LOWTR),y
         sta INDEX1+1
         lda VARTAB
         sta INDEX1
         lda LOWTR+1
         sta INDEX2+1
         lda LOWTR
         dey
         sbc (LOWTR),y       ; C is set from FNDLIN
         clc
         adc VARTAB
         sta VARTAB
         sta INDEX2
         lda VARTAB+1
         adc #255
         sta VARTAB+1
         sbc LOWTR+1
         tax
         sec
         lda LOWTR
         sbc VARTAB
         tay
         bcs QDECT1
         inx
         dec INDEX2+1
QDECT1:  clc
         adc INDEX1
         bcc MLOOP
         dec INDEX1+1
         clc
MLOOP:   lda (INDEX1),y
         sta (INDEX2),y
         iny
         bne MLOOP
         inc INDEX1+1
         inc INDEX2+1
         dex
         bne MLOOP
NODEL:   jsr RUNC
         jsr LNKPRG
         lda BUF
         beq GOMAIN
         clc
         lda VARTAB
         sta HIGHTR
         adc COUNT
         sta HIGHDS
         ldy VARTAB+1
         sty HIGHTR+1
         bcc NODELC
         iny
NODELC:  sty HIGHDS+1
         jsr BLTU
         lda STREND
         ldy STREND+1
         sta VARTAB
         sty VARTAB+1
         ldy COUNT
         dey
STOLOP:  lda BUF-4,y
         sta (LOWTR),y
         dey
         bpl STOLOP
FINI:    jsr RUNC
         jsr LNKPRG
GOMAIN:  jmp MAIN

LNKPRG:  lda TXTTAB
         ldy TXTTAB+1
         sta INDEX
         sty INDEX+1
         clc
; Fix up program links
CHEAD:   ldy #1
         lda (INDEX),y
         beq LNKRTS
         ldy #4
CZLOOP:  iny
         lda (INDEX),y
         bne CZLOOP
         iny
         tya
         adc INDEX
         tax
         ldy #0
         sta (INDEX),y
         lda INDEX+1
         adc #0
         iny
         sta (INDEX),y
         stx INDEX
         sta INDEX+1
         bcc CHEAD           ; always
LNKRTS:  rts

; -------------------------
; Terminal input routine
; -------------------------
LINLIN:
         dex
         bpl INLINC
INLINN:
         jsr CRDO
INLIN:   ldx #0
INLINC:  jsr INCHR
         cmp #7              ; bell?
         beq GOODCH
         cmp #13             ; CR?
         beq FININ1
         cmp #32
         bcc INLINC
         cmp #125
         bcs INLINC
         cmp #'@'            ; line delete?
         beq INLINN
         cmp #'_'            ; char delete?
         beq LINLIN
GOODCH:
         cpx #BUFLEN-1
         bcs OUTBEL
         sta BUF,x
         inx
         bne INLINC
OUTBEL:  lda #7
         jsr OUTDO
         bne INLINC          ; always
FININ1:  jmp FININL

; INCHR - read character from ACIA
INCHR:   jsr ACIA_INCHR      ; our custom I/O
         cmp #CONTW           ; suppress output char?
         bne INCRTS
         pha
         lda CNTWFL
         eor #$FF
         sta CNTWFL
         pla
INCRTS:  rts

; -------------------------
; CRUNCH - tokenize input line
; -------------------------
BUFOFS = 0                   ; offset since BUFPAG=0
CRUNCH:  ldx TXTPTR
         ldy #4
         sty DORES
KLOOP:   lda BUFOFS,x
CMPSPC:  cmp #' '
         beq STUFFH
         sta ENDCHR
         cmp #34             ; quote?
         beq STRNG
         bit DORES
         bvs STUFFH
         cmp #'?'
         bne KLOOP1
         lda #PRINTK
         bne STUFFH
KLOOP1:  cmp #'0'
         bcc MUSTCR
         cmp #60             ; ':' and ';' go straight
         bcc STUFFH
MUSTCR:  sty BUFPTR
         ldy #0
         sty COUNT
         dey
         stx TXTPTR
         dex
RESER:   iny
RESPUL:  inx
RESCON:  lda BUFOFS,x
         sec
         sbc RESLST,y
         beq RESER
         cmp #128
         bne NTHIS
         ora COUNT
GETBPT:  ldy BUFPTR
STUFFH:  inx
         iny
         sta BUF-5,y
         lda BUF-5,y
         beq CRDONE
         sec
         sbc #':'
         beq COLIS
         cmp #DATATK-':'
         bne NODATT
COLIS:   sta DORES
NODATT:  sec
         sbc #REMTK-':'
         bne KLOOP
         sta ENDCHR
STR1:    lda BUFOFS,x
         beq STUFFH
         cmp ENDCHR
         beq STUFFH
STRNG:   iny
         sta BUF-5,y
         inx
         bne STR1
NTHIS:   ldx TXTPTR
         inc COUNT
NTHIS1:  iny
         lda RESLST-1,y
         bpl NTHIS1
         lda RESLST,y
         bne RESCON
         lda BUFOFS,x
         bpl GETBPT          ; always
CRDONE:  sta BUF-3,y
         lda #<(BUF)-1
         sta TXTPTR
LISTRT:  rts

; -------------------------
; FNDLIN - find line by number
; -------------------------
FNDLIN:  lda TXTTAB
         ldx TXTTAB+1
FNDLNC:  ldy #1
         sta LOWTR
         stx LOWTR+1
         lda (LOWTR),y
         beq FLINRT
         iny
         iny
         lda LINNUM+1
         cmp (LOWTR),y
         bcc FLNRTS
         beq FNDLO1
         dey
         bne AFFRTS         ; always
FNDLO1:  lda LINNUM
         dey
         cmp (LOWTR),y
         bcc FLNRTS
         beq FLNRTS
AFFRTS:  dey
         lda (LOWTR),y
         tax
         dey
         lda (LOWTR),y
         bcs FNDLNC         ; always
FLINRT:  clc
FLNRTS:  rts

; -------------------------
; NEW command
; -------------------------
SCRATH:  bne FLNRTS
SCRTCH:  lda #0
         tay
         sta (TXTTAB),y
         iny
         sta (TXTTAB),y
         lda TXTTAB
         clc
         adc #2
         sta VARTAB
         lda TXTTAB+1
         adc #0
         sta VARTAB+1
RUNC:    jsr STXTPT
         lda #0

; CLEAR command
CLEAR:   bne STKRTS
CLEARC:  lda MEMSIZ
         ldy MEMSIZ+1
         sta FRETOP
         sty FRETOP+1
         lda VARTAB
         ldy VARTAB+1
         sta ARYTAB
         sty ARYTAB+1
         sta STREND
         sty STREND+1
FLOAD:   jsr RESTOR

; Reset stack
STKINI:  ldx #TEMPST
         stx TEMPPT
         pla
         tay
         pla
         ldx #STKEND-257
         txs
         pha
         tya
         pha
         lda #0
         sta OLDTXT+1
         sta SUBFLG
STKRTS:  rts

STXTPT:  clc
         lda TXTTAB
         adc #255
         sta TXTPTR
         lda TXTTAB+1
         adc #255
         sta TXTPTR+1
         rts

; =========================================================================
; LIST command
; =========================================================================
LIST:    bcc GOLST
         beq GOLST
         cmp #MINUTK
         bne STKRTS
GOLST:   jsr LINGET
         jsr FNDLIN
         jsr CHRGOT
         beq LSTEND
         cmp #MINUTK
         bne @err
         jsr CHRGET
         jsr LINGET
         bne @err
         beq LSTEND
@err:    jmp FLNRTS          ; syntax error via fall-thru

LSTEND:  pla
         pla
         lda LINNUM
         ora LINNUM+1
         bne LIST4
         lda #255
         sta LINNUM
         sta LINNUM+1
LIST4:   ldy #1
         lda (LOWTR),y
         beq GRODY
         jsr ISCNTC
         jsr CRDO
         iny
         lda (LOWTR),y
         tax
         iny
         lda (LOWTR),y
         cmp LINNUM+1
         bne TSTDUN
         cpx LINNUM
         beq TYPLIN
TSTDUN:  bcs GRODY
TYPLIN:  sty LSTPNT
         jsr LINPRT
         lda #' '
PRIT4:   ldy LSTPNT
         and #127
PLOOP:   jsr OUTDO
PLOOP1:  iny
         beq GRODY
         lda (LOWTR),y
         bne QPLOP
         tay
         lda (LOWTR),y
         tax
         iny
         lda (LOWTR),y
         stx LOWTR
         sta LOWTR+1
         bne LIST4
GRODY:   jmp READY
QPLOP:   bpl PLOOP
         sec
         sbc #127
         tax
         sty LSTPNT
         ldy #255
RESRCH:  dex
         beq PRIT3
RESCR1:  iny
         lda RESLST,y
         bpl RESCR1
         bmi RESRCH
PRIT3:   iny
         lda RESLST,y
         bmi PRIT4
         jsr OUTDO
         bne PRIT3

; =========================================================================
; FOR statement
; =========================================================================
FOR:     lda #128
         sta SUBFLG
         jsr LET
         jsr FNDFOR
         bne NOTOL
         txa
         adc #FORSIZ-3
         tax
         txs
NOTOL:   pla
         pla
         lda #9              ; 8+ADDPRC
         jsr GETSTK
         jsr DATAN
         clc
         tya
         adc TXTPTR
         pha
         lda TXTPTR+1
         adc #0
         pha
         ; PSHWD CURLIN
         lda CURLIN+1
         pha
         lda CURLIN
         pha
         ; SYNCHK TOTK
         lda #TOTK
         jsr SYNCHR
         jsr CHKNUM
         jsr FRMNUM
         lda FACSGN
         ora #127
         and FACHO
         sta FACHO
         lda #<LDFONE
         ldy #>LDFONE
         sta INDEX1
         sty INDEX1+1
         jmp FORPSH

LDFONE:  lda #<FONE
         ldy #>FONE
         jsr MOVFM
         jsr CHRGOT
         cmp #STEPTK
         bne ONEON
         jsr CHRGET
         jsr FRMNUM
ONEON:   jsr SIGN_
         jsr PUSHF
         ; PSHWD FORPNT
         lda FORPNT+1
         pha
         lda FORPNT
         pha
NXTCON:  lda #FORTK
         pha

; =========================================================================
; NEWSTT - new statement fetcher
; =========================================================================
NEWSTT:  jsr ISCNTC
         lda TXTPTR
         ldy TXTPTR+1
         beq DIRCON
         sta OLDTXT
         sty OLDTXT+1
DIRCON:  ldy #0
         lda (TXTPTR),y
         bne MORSTS
         ldy #2
         lda (TXTPTR),y
         clc
         bne :+
         jmp ENDCON
:        iny
         lda (TXTPTR),y
         sta CURLIN
         iny
         lda (TXTPTR),y
         sta CURLIN+1
         tya
         adc TXTPTR
         sta TXTPTR
         bcc GONE
         inc TXTPTR+1
GONE:    jsr CHRGET
         jsr GONE3
         jmp NEWSTT
GONE3:   beq ISCRTS
GONE2:   sbc #ENDTK
         bcc GLET
         cmp #SCRATK-ENDTK+1
         bcs SNERRX
         asl a
         tay
         lda STMDSP+1,y
         pha
         lda STMDSP,y
         pha
         jmp CHRGET
GLET:    jmp LET
MORSTS:  cmp #':'
         beq GONE
SNERR1:  jmp SNERR
SNERRX:  cmp #GOTK-ENDTK
         bne SNERR1
         jsr CHRGET
         lda #TOTK
         jsr SYNCHR
         jmp GOTO

; =========================================================================
; RESTORE, STOP, END, CONTINUE, NULL, CLEAR
; =========================================================================
RESTOR:  sec
         lda TXTTAB
         sbc #1
         ldy TXTTAB+1
         bcs RESFIN
         dey
RESFIN:  sta DATPTR
         sty DATPTR+1
ISCRTS:  rts

ISCNTC:  jsr ACIA_CHECK      ; check for Ctrl-C at ACIA
         bcc @nokey           ; no char available
         cmp #3               ; Ctrl-C?
         bne @nokey
         sec                  ; carry set = Ctrl-C detected
         bcs STOPC            ; always taken -> handle break
@nokey:  rts

STOP:    bcs STOPC
END_:    clc
STOPC:   bne CONTRT
         lda TXTPTR
         ldy TXTPTR+1
         beq DIRIS
         sta OLDTXT
         sty OLDTXT+1
STPEND:  lda CURLIN
         ldy CURLIN+1
         sta OLDLIN
         sty OLDLIN+1
DIRIS:   pla
         pla
ENDCON:  lda #<BRKTXT
         ldy #>BRKTXT
         ldx #0
         stx CNTWFL
         bcc GORDY
         jmp ERRFIN
GORDY:   jmp READY

CONT:    bne CONTRT
         ldx #ERRCN
         ldy OLDTXT+1
         bne :+
         jmp ERROR
:        lda OLDTXT
         sta TXTPTR
         sty TXTPTR+1
         lda OLDLIN
         ldy OLDLIN+1
         sta CURLIN
         sty CURLIN+1
CONTRT:  rts

NULL_:   jsr GETBYT
         bne CONTRT
         inx
         cpx #240
         bcs FCERR1
         dex
         stx NULCNT
         rts
FCERR1:  jmp FCERR

; =========================================================================
; RUN, GOTO, GOSUB, RETURN
; =========================================================================
RUN:     bne :+
         jmp RUNC
:        jsr CLEARC
         jmp RUNC2

GOSUB:   lda #3
         jsr GETSTK
         ; PSHWD TXTPTR
         lda TXTPTR+1
         pha
         lda TXTPTR
         pha
         ; PSHWD CURLIN
         lda CURLIN+1
         pha
         lda CURLIN
         pha
         lda #GOSUTK
         pha
RUNC2:   jsr CHRGOT
         jsr GOTO
         jmp NEWSTT

GOTO:    jsr LINGET
         jsr REMN
         lda CURLIN+1
         cmp LINNUM+1
         bcs LUK4IT
         tya
         sec
         adc TXTPTR
         ldx TXTPTR+1
         bcc LUKALL
         inx
         bcs LUKALL          ; always
LUK4IT:  lda TXTTAB
         ldx TXTTAB+1
LUKALL:  jsr FNDLNC
QFOUND:  bcc USERR
         lda LOWTR
         sbc #1
         sta TXTPTR
         lda LOWTR+1
         sbc #0
         sta TXTPTR+1
GORTS:   rts

RETURN_: bne GORTS
         lda #255
         sta FORPNT+1
         jsr FNDFOR
         txs
         cmp #GOSUTK
         beq RETU1
         ldx #ERRRG
         .byte $2C           ; SKIP2
USERR:   ldx #ERRUS
         jmp ERROR
SNERR2:  jmp SNERR
RETU1:   pla
         ; PULWD CURLIN
         pla
         sta CURLIN
         pla
         sta CURLIN+1
         ; PULWD TXTPTR
         pla
         sta TXTPTR
         pla
         sta TXTPTR+1
DATA:    jsr DATAN
ADDON:   tya
         clc
         adc TXTPTR
         sta TXTPTR
         bcc REMRTS
         inc TXTPTR+1
REMRTS:  rts

DATAN:   ldx #':'
         .byte $2C           ; SKIP2
REMN:    ldx #0
         stx CHARAC
         ldy #0
         sty ENDCHR
EXCHQT:  lda ENDCHR
         ldx CHARAC
         sta CHARAC
         stx ENDCHR
REMER:   lda (TXTPTR),y
         beq REMRTS
         cmp ENDCHR
         beq REMRTS
         iny
         cmp #34             ; quote?
         bne REMER
         beq EXCHQT          ; always

; =========================================================================
; IF ... THEN
; =========================================================================
IF_:     jsr FRMEVL
         jsr CHRGOT
         cmp #GOTOTK
         beq OKGOTO
         lda #THENTK
         jsr SYNCHR
OKGOTO:  lda FACEXP
         bne DOCOND
REM:     jsr REMN
         beq ADDON           ; always
DOCOND:  jsr CHRGOT
         bcs DOCO
         jmp GOTO
DOCO:    jmp GONE3

; =========================================================================
; ON ... GOTO/GOSUB
; =========================================================================
ONGOTO:  jsr GETBYT
         pha
         cmp #GOSUTK
         beq ONGLOP
SNERR3:  cmp #GOTOTK
         bne SNERR2
ONGLOP:  dec FACLO
         bne ONGLP1
         pla
         jmp GONE2
ONGLP1:  jsr CHRGET
         jsr LINGET
         cmp #44             ; comma?
         beq ONGLOP
         pla
ONGRTS:  rts

; =========================================================================
; LINGET - read line number into LINNUM
; =========================================================================
LINGET:  ldx #0
         stx LINNUM
         stx LINNUM+1
MORLIN:  bcs ONGRTS
         sbc #'0'-1          ; -1 since C=0
         sta CHARAC
         lda LINNUM+1
         sta INDEX
         cmp #25
         bcs SNERR3
         lda LINNUM
         asl a
         rol INDEX
         asl a
         rol INDEX
         adc LINNUM
         sta LINNUM
         lda INDEX
         adc LINNUM+1
         sta LINNUM+1
         asl LINNUM
         rol LINNUM+1
         lda LINNUM
         adc CHARAC
         sta LINNUM
         bcc NXTLGC
         inc LINNUM+1
NXTLGC:  jsr CHRGET
         jmp MORLIN

; =========================================================================
; LET statement
; =========================================================================
LET:     jsr PTRGET
         sta FORPNT
         sty FORPNT+1
         ; SYNCHK EQULTK
         lda #EQULTK
         jsr SYNCHR
         lda INTFLG
         pha
         lda VALTYP
         pha
         jsr FRMEVL
         pla
         rol a
         jsr CHKVAL
         bne COPSTR
COPNUM:
         pla
QINTGR:  bpl COPFLT
         jsr ROUND
         jsr AYINT
         ldy #0
         lda FACMO
         sta (FORPNT),y
         iny
         lda FACLO
         sta (FORPNT),y
         rts
COPFLT:  jmp MOVVF

COPSTR:
         pla                 ; remove INTFLG
INPCOM:
         ; (TIME=0, no TI$ handling)
GETSPT:  ldy #2
         lda (FACMO),y
         cmp FRETOP+1
         bcc DNTCPY
         bne QVARIA
         dey
         lda (FACMO),y
         cmp FRETOP
         bcc DNTCPY
QVARIA:  ldy FACLO
         cpy VARTAB+1
         bcc DNTCPY
         bne COPY_
         lda FACMO
         cmp VARTAB
         bcs COPY_
DNTCPY:  lda FACMO
         ldy FACMO+1
         jmp COPYZC
COPY_:   ldy #0
         lda (FACMO),y
         jsr STRINI
         lda DSCPNT
         ldy DSCPNT+1
         sta STRNG1
         sty STRNG1+1
         jsr MOVINS
         lda #<DSCTMP
         ldy #>DSCTMP
COPYZC:  sta DSCPNT
         sty DSCPNT+1
         jsr FRETMS
         ldy #0
         lda (DSCPNT),y
         sta (FORPNT),y
         iny
         lda (DSCPNT),y
         sta (FORPNT),y
         iny
         lda (DSCPNT),y
         sta (FORPNT),y
         rts

; =========================================================================
; PRINT
; =========================================================================
STRDON:  jsr STRPRT
NEWCHR:  jsr CHRGOT
PRINT_:  beq CRDO
PRINTC:  beq PRTRTS
         cmp #TABTK
         beq TABER
         cmp #SPCTK
         clc
         beq TABER
         cmp #44             ; comma?
         beq COMPRT
         cmp #59             ; semicolon?
         beq NOTABR
         jsr FRMEVL
         bit VALTYP
         bmi STRDON
         jsr FOUT
         jsr STRLIT
         ldy #0
         lda (FACMO),y
         clc
         adc TRMPOS
         cmp LINWID
         bcc LINCHK
         jsr CRDO
LINCHK:  jsr STRPRT
         jsr OUTSPC
         bne NEWCHR          ; always

FININL:  ldy #0
         sty BUF,x
         ldx #<(BUF-1)

CRDO:
         lda #13
         sta TRMPOS
         jsr OUTDO
         lda #10
         jsr OUTDO
CRFIN:
         txa
         pha
         ldx NULCNT
         beq CLRPOS
         lda #0
PRTNUL:  jsr OUTDO
         dex
         bne PRTNUL
CLRPOS:  stx TRMPOS
         pla
         tax
PRTRTS:  rts

COMPRT:  lda TRMPOS
         cmp NCMWID
         bcc MORCOM
         jsr CRDO
         jmp NOTABR
MORCOM:  sec
MORCO1:  sbc #CLMWID
         bcs MORCO1
         eor #255
         adc #1
         bne ASPAC

TABER:   php
         jsr GTBYTC
         cmp #41             ; ')'
         bne SNERR4
         plp
         bcc XSPAC
         txa
         sbc TRMPOS
         bcc NOTABR
ASPAC:   tax
XSPAC:   inx
XSPAC2:  dex
         bne XSPAC1
NOTABR:  jsr CHRGET
         jmp PRINTC
XSPAC1:  jsr OUTSPC
         bne XSPAC2          ; always

; Print string at [Y,A]
STROUT:  jsr STRLIT
STRPRT:  jsr FREFAC
         tax
         ldy #0
         inx
STRPR2:  dex
         beq PRTRTS
         lda (INDEX),y
         jsr OUTDO
         iny
         cmp #13
         bne STRPR2
         jsr CRFIN
         jmp STRPR2

; Output routines
OUTSPC:
         lda #' '
         .byte $2C           ; SKIP2
OUTQST:  lda #'?'
OUTDO:
         bit CNTWFL
         bmi OUTRTS
         pha
         cmp #32
         bcc TRYOUT
         lda TRMPOS
         cmp LINWID
         bne OUTDO1
         jsr CRDO
OUTDO1:
INCTRM:  inc TRMPOS
TRYOUT:  pla
         sty KIMY
OUTLOC:  jsr OUTCH
         ldy KIMY
OUTRTS:  and #255            ; set Z=0
GETRTS:  rts

; =========================================================================
; INPUT and READ code
; =========================================================================
TRMNOK:  lda INPFLG
         beq TRMNO1
         bmi GETDTL
         ldy #255
         bne STCURL          ; always
GETDTL:  lda DATLIN
         ldy DATLIN+1
STCURL:  sta CURLIN
         sty CURLIN+1
SNERR4:  jmp SNERR
TRMNO1:
DOAGIN:  lda #<TRYAGN
         ldy #>TRYAGN
         jsr STROUT
         lda OLDTXT
         ldy OLDTXT+1
         sta TXTPTR
         sty TXTPTR+1
         rts

GET:     jsr ERRDIR
GETTTY:  ldx #<(BUF+1)
         ldy #>(BUF+1)
         sty BUF+1
         lda #64             ; turn on V-bit
         jsr INPCO1
         rts

INPUT:
         lsr CNTWFL
         cmp #34             ; quote?
         bne NOTQTI
         jsr STRTXT
         lda #59
         jsr SYNCHR
         jsr STRPRT
NOTQTI:  jsr ERRDIR
         lda #44
         sta BUF-1
GETAGN:  jsr QINLIN
         lda BUF
         bne INPCON
         clc
         jmp STPEND

QINLIN:
         jsr OUTQST
         jsr OUTSPC
GINLIN:  jmp INLIN

READ:    ldx DATPTR
         ldy DATPTR+1
         .byte $A9           ; LDA # (skip TYA)
INPCON:  tya
INPCO1:  sta INPFLG
         stx INPPTR
         sty INPPTR+1
INLOOP:  jsr PTRGET
         sta FORPNT
         sty FORPNT+1
         lda TXTPTR
         ldy TXTPTR+1
         sta VARTXT
         sty VARTXT+1
         ldx INPPTR
         ldy INPPTR+1
         stx TXTPTR
         sty TXTPTR+1
         jsr CHRGOT
         bne DATBK1
         bit INPFLG
         bvc QDATA
         jsr CZGETL
         sta BUF
         ldx #<(BUF-1)
         ldy #>(BUF-1)
         beq DATBK           ; always (BUF on page 0)
QDATA:   bmi DATLOP
         jsr OUTQST
GETNTH:  jsr QINLIN
DATBK:   stx TXTPTR
         sty TXTPTR+1
DATBK1:  jsr CHRGET
         bit VALTYP
         bpl NUMINS
         bit INPFLG
         bvc SETQUT
         inx
         stx TXTPTR
         lda #0
         sta CHARAC
         beq RESETC          ; always
SETQUT:  sta CHARAC
         cmp #34
         beq NOWGET
         lda #':'
         sta CHARAC
         lda #44
RESETC:  clc
NOWGET:  sta ENDCHR
         lda TXTPTR
         ldy TXTPTR+1
         adc #0
         bcc NOWGE1
         iny
NOWGE1:  jsr STRLT2
         jsr ST2TXT
         jsr INPCOM
         jmp STRDN2
NUMINS:  jsr FIN
         lda INTFLG
         jsr QINTGR
STRDN2:  jsr CHRGOT
         beq TRMOK
         cmp #44
         bne @trmnok
         beq TRMOK
@trmnok: jmp TRMNOK
TRMOK:   lda TXTPTR
         ldy TXTPTR+1
         sta INPPTR
         sty INPPTR+1
         lda VARTXT
         ldy VARTXT+1
         sta TXTPTR
         sty TXTPTR+1
         jsr CHRGOT
         beq VAREND
         jsr CHKCOM
         jmp INLOOP

DATLOP:  jsr DATAN
         iny
         tax
         bne NOWLIN
         ldx #ERROD
         iny
         lda (TXTPTR),y
         beq ERRGO5
         iny
         lda (TXTPTR),y
         sta DATLIN
         iny
         lda (TXTPTR),y
         iny
         sta DATLIN+1
NOWLIN:  lda (TXTPTR),y
         tax
         jsr ADDON
         cpx #DATATK
         bne DATLOP
         jmp DATBK1

VAREND:  lda INPPTR
         ldy INPPTR+1
         ldx INPFLG
         bpl VARY0
         jmp RESFIN
VARY0:   ldy #0
         lda (INPPTR),y
         beq INPRTS
         lda #<EXIGNT
         ldy #>EXIGNT
         jmp STROUT
INPRTS:  rts

EXIGNT:  .byte "?EXTRA IGNORED", 13, 10, 0
TRYAGN:  .byte "?REDO FROM START", 13, 10, 0

; CZGETL - get one character (for GET command)
CZGETL:  jsr ACIA_INCHR
         rts

; =========================================================================
; NEXT statement
; =========================================================================
NEXT:    bne GETFOR
         ldy #0
         beq STXFOR          ; always
GETFOR:  jsr PTRGET
STXFOR:  sta FORPNT
         sty FORPNT+1
         jsr FNDFOR
         beq HAVFOR
         ldx #ERRNF
ERRGO5:  beq ERRGO4
HAVFOR:  txs
         txa
         clc
         adc #4
         pha
         adc #6              ; 5+ADDPRC
         sta INDEX2
         pla
         ldy #1
         jsr MOVFM
         tsx
         lda 265,x           ; 257+7+ADDPRC
         sta FACSGN
         lda FORPNT
         ldy FORPNT+1
         jsr FADD
         jsr MOVVF
         ldy #1
         jsr FCOMPN
         tsx
         sec
         sbc 265,x           ; 257+7+ADDPRC
         beq LOOPDN
         lda 271,x           ; 2*ADDPRC+12+257 = 271
         sta CURLIN
         lda 272,x           ; 257+13+2*ADDPRC = 272
         sta CURLIN+1
         lda 274,x           ; 2*ADDPRC+15+257 = 274
         sta TXTPTR
         lda 273,x           ; 2*ADDPRC+14+257 = 273
         sta TXTPTR+1
NEWSGO:  jmp NEWSTT
LOOPDN:  txa
         adc #17             ; 2*ADDPRC+15 = 17, +carry=18
         tax
         txs
         jsr CHRGOT
         cmp #44
         bne NEWSGO
         jsr CHRGET
         jsr GETFOR

; =========================================================================
; FORMULA EVALUATION
; =========================================================================
FRMNUM:  jsr FRMEVL
CHKNUM:  clc
         .byte $24           ; SKIP1 (BIT zp)
CHKSTR:  sec
CHKVAL:  bit VALTYP
         bmi DOCSTR
         bcs CHKERR
CHKOK:   rts
DOCSTR:  bcs CHKOK
CHKERR:  ldx #ERRTM
ERRGO4:  jmp ERROR

FRMEVL:  ldx TXTPTR
         bne FRMEV1
         dec TXTPTR+1
FRMEV1:  dec TXTPTR
         ldx #0
         .byte $24           ; SKIP1
LPOPER:  pha
         txa
         pha
         lda #1
         jsr GETSTK
         jsr EVAL
         lda #0
         sta OPMASK
TSTOP:   jsr CHRGOT
LOPREL:  sec
         sbc #GREATK
         bcc ENDREL
         cmp #LESSTK-GREATK+1
         bcs ENDREL
         cmp #1
         rol a
         eor #1
         eor OPMASK
         cmp OPMASK
         bcc SNERR5
         sta OPMASK
         jsr CHRGET
         jmp LOPREL
ENDREL:  ldx OPMASK
         bne FINREL
         bcs QOP
         adc #GREATK-PLUSTK
         bcc QOP
         adc VALTYP           ; C=1
         bne :+
         jmp CAT
:        adc #$FF
         sta INDEX1
         asl a
         adc INDEX1
         tay
QPREC:   pla
         cmp OPTAB,y
         bcs QCHNUM
         jsr CHKNUM
DOPREC:  pha
NEGPRC:  jsr DOPRE1
         pla
         ldy OPPTR
         bpl QPREC1
         tax
         beq QOPGO
         bne PULSTK
FINREL:  lsr VALTYP
         txa
         rol a
         ldx TXTPTR
         bne FINRE2
         dec TXTPTR+1
FINRE2:  dec TXTPTR
         ldy #PTDORL-OPTAB
         sta OPMASK
         bne QPREC           ; always
QPREC1:  cmp OPTAB,y
         bcs PULSTK
         bcc DOPREC
DOPRE1:  lda OPTAB+2,y
         pha
         lda OPTAB+1,y
         pha
         jsr PUSHF1
         lda OPMASK
         jmp LPOPER
SNERR5:  jmp SNERR
PUSHF1:  lda FACSGN
         ldx OPTAB,y
PUSHF:   tay
         pla
         sta INDEX1
         inc INDEX1
         pla
         sta INDEX1+1
         tya
         pha
FORPSH:  jsr ROUND
         lda FACLO
         pha
         lda FACMO
         pha
         lda FACMOH
         pha
         lda FACHO
         pha
         lda FACEXP
         pha
         jmp (INDEX1)
QOP:     ldy #255
         pla
QOPGO:   beq QOPRTS
QCHNUM:  cmp #100
         beq UNPSTK
         jsr CHKNUM
UNPSTK:  sty OPPTR
PULSTK:  pla
         lsr a
         sta DOMASK
         pla
         sta ARGEXP
         pla
         sta ARGHO
         pla
         sta ARGMOH
         pla
         sta ARGMO
         pla
         sta ARGLO
         pla
         sta ARGSGN
         eor FACSGN
         sta ARISGN
QOPRTS:  lda FACEXP
UNPRTS:  rts

; EVAL - read a lexeme
EVAL:    lda #0
         sta VALTYP
EVAL0:   jsr CHRGET
         bcs EVAL2
EVAL1:   jmp FIN
EVAL2:   jsr ISLETC
         bcs ISVAR
QDOT:    cmp #'.'
         beq EVAL1
         cmp #MINUTK
         beq DOMIN
         cmp #PLUSTK
         beq EVAL0
         cmp #34             ; quote?
         bne EVAL3
STRTXT:  lda TXTPTR
         ldy TXTPTR+1
         adc #0              ; C=1 from CMP
         bcc STRTX2
         iny
STRTX2:  jsr STRLIT
         jmp ST2TXT
EVAL3:   cmp #NOTTK
         bne EVAL4
         ldy #NOTTAB-OPTAB
         bne GONPRC
NOTOP:   jsr AYINT
         lda FACLO
         eor #255
         tay
         lda FACMO
         eor #255
         jmp GIVAYF
EVAL4:   cmp #FNTK
         bne :+
         jmp FNDOER
:        cmp #ONEFUN
         bcc PARCHK
         jmp ISFUN

PARCHK:  jsr CHKOPN
         jsr FRMEVL
CHKCLS:  lda #41             ; ')'
         .byte $2C           ; SKIP2
CHKOPN:  lda #40             ; '('
         .byte $2C           ; SKIP2
CHKCOM:  lda #44             ; ','

SYNCHR:  ldy #0
         cmp (TXTPTR),y
         bne SNERR
CHRGO5:  jmp CHRGET
SNERR:   ldx #ERRSN
         jmp ERROR

DOMIN:   ldy #NEGTAB-OPTAB
GONPRC:  pla
         pla
         jmp NEGPRC

ISVAR:   jsr PTRGET
ISVRET:  sta FACMO
         sty FACMO+1
         ldx VALTYP
         beq GOOO
         ldx #0
         stx FACOV
STRRTS:  rts
GOOO:
         ldx INTFLG
         bpl GOOOOO
         ldy #0
         lda (FACMO),y
         tax
         iny
         lda (FACMO),y
         tay
         txa
         jmp GIVAYF
GOOOOO:
         lda FACMO
         ldy FACMO+1
         jmp MOVFM

ISFUN:   asl a
         pha
         tax
         jsr CHRGET
         cpx #2*LASNUM-256+1
         bcc OKNORM
         jsr CHKOPN
         jsr FRMEVL
         jsr CHKCOM
         jsr CHKSTR
         pla
         tax
         ; PSHWD FACMO
         lda FACMO+1
         pha
         lda FACMO
         pha
         txa
         pha
         jsr GETBYT
         pla
         tay
         txa
         pha
         jmp FINGO
OKNORM:  jsr PARCHK
         pla
         tay
FINGO:   lda FUNDSP-2*ONEFUN+256,y
         sta JMPER+1
         lda FUNDSP-2*ONEFUN+257,y
         sta JMPER+2
         jsr JMPER
         jmp CHKNUM

; AND/OR operators
OROP:    ldy #255
         .byte $2C           ; SKIP2
ANDOP:   ldy #0
         sty COUNT
         jsr AYINT
         lda FACMO
         eor COUNT
         sta INTEGR
         lda FACLO
         eor COUNT
         sta INTEGR+1
         jsr MOVFA
         jsr AYINT
         lda FACLO
         eor COUNT
         and INTEGR+1
         eor COUNT
         tay
         lda FACMO
         eor COUNT
         and INTEGR
         eor COUNT
         jmp GIVAYF

; Relational operators
DOREL:   jsr CHKVAL
         bcs STRCMP
         lda ARGSGN
         ora #127
         and ARGHO
         sta ARGHO
         lda #<ARGEXP
         ldy #>ARGEXP
         jsr FCOMP
         tax
         jmp QCOMP
STRCMP:   lda #0
         sta VALTYP
         dec OPMASK
         jsr FREFAC
         sta DSCTMP
         stx DSCTMP+1
         sty DSCTMP+2
         lda ARGMO
         ldy ARGMO+1
         jsr FRETMP
         stx ARGMO
         sty ARGMO+1
         tax
         sec
         sbc DSCTMP
         beq STASGN
         lda #1
         bcc STASGN
         ldx DSCTMP
         lda #$FF
STASGN:  sta FACSGN
         ldy #255
         inx
NXTCMP:  iny
         dex
         bne GETCMP
         ldx FACSGN
QCOMP:   bmi DOCMP
         clc
         bcc DOCMP           ; always
GETCMP:  lda (ARGMO),y
         cmp (DSCTMP+1),y
         beq NXTCMP
         ldx #$FF
         bcs DOCMP
         ldx #1
DOCMP:   inx
         txa
         rol a
         and DOMASK
         beq GOFLOT
         lda #$FF
GOFLOT:  jmp FLOAT

; =========================================================================
; DIMENSION AND VARIABLE SEARCHING
; =========================================================================
DIM3:    jsr CHKCOM
DIM:     tax
DIM1:    jsr PTRGT1
DIMCON:  jsr CHRGOT
         bne DIM3
         rts

PTRGET:  ldx #0
         jsr CHRGOT
PTRGT1:  stx DIMFLG
PTRGT2:  sta VARNAM
         jsr CHRGOT
         jsr ISLETC
         bcs PTRGT3
INTERR:  jmp SNERR
PTRGT3:  ldx #0
         stx VALTYP
         stx INTFLG
         jsr CHRGET
         bcc ISSEC
         jsr ISLETC
         bcc NOSEC
ISSEC:   tax
EATEM:   jsr CHRGET
         bcc EATEM
         jsr ISLETC
         bcs EATEM
NOSEC:   cmp #'$'
         bne NOTSTR
         lda #$FF
         sta VALTYP
         bne TURNON          ; always
NOTSTR:  cmp #'%'
         bne STRNAM
         lda SUBFLG
         bne INTERR
         lda #128
         sta INTFLG
         ora VARNAM
         sta VARNAM
TURNON:  txa
         ora #128
         tax
         jsr CHRGET
STRNAM:  stx VARNAM+1
         sec
         ora SUBFLG
         sbc #40
         bne :+
         jmp ISARY
:        lda #0
         sta SUBFLG
         lda VARTAB
         ldx VARTAB+1
         ldy #0
STXFND:  stx LOWTR+1
LOPFND:  sta LOWTR
         cpx ARYTAB+1
         bne LOPFN
         cmp ARYTAB
         beq NOTFNS
LOPFN:   lda VARNAM
         cmp (LOWTR),y
         bne NOTIT
         lda VARNAM+1
         iny
         cmp (LOWTR),y
         beq FINPTR
         dey
NOTIT:   clc
         lda LOWTR
         adc #7              ; 6+ADDPRC
         bcc LOPFND
         inx
         bne STXFND          ; always

ISLETC:  cmp #'A'
         bcc ISLRTS
         sbc #'Z'+1
         sec
         sbc #256-'Z'-1
ISLRTS:  rts

NOTFNS:  pla
         pha
         cmp #<(ISVRET-1)
         bne NOTEVL
         tsx
         lda 258,x
         cmp #>(ISVRET-1)
         bne NOTEVL
LDZR:    lda #<ZERO
         ldy #>ZERO
         rts

NOTEVL:
VAROK:   lda ARYTAB
         ldy ARYTAB+1
         sta LOWTR
         sty LOWTR+1
         lda STREND
         ldy STREND+1
         sta HIGHTR
         sty HIGHTR+1
         clc
         adc #7              ; 6+ADDPRC
         bcc NOTEVE
         iny
NOTEVE:  sta HIGHDS
         sty HIGHDS+1
         jsr BLTU
         lda HIGHDS
         ldy HIGHDS+1
         iny
         sta ARYTAB
         sty ARYTAB+1
         ldy #0
         lda VARNAM
         sta (LOWTR),y
         iny
         lda VARNAM+1
         sta (LOWTR),y
         lda #0
         iny
         sta (LOWTR),y
         iny
         sta (LOWTR),y
         iny
         sta (LOWTR),y
         iny
         sta (LOWTR),y
         iny
         sta (LOWTR),y       ; 7th byte (ADDPRC)
FINPTR:  lda LOWTR
         clc
         adc #2
         ldy LOWTR+1
         bcc FINNOW
         iny
FINNOW:  sta VARPNT
         sty VARPNT+1
         rts

; =========================================================================
; ARRAY CODE
; =========================================================================
FMAPTR:  lda COUNT
         asl a
         adc #5
         adc LOWTR
         ldy LOWTR+1
         bcc JSRGM
         iny
JSRGM:   sta ARYPNT
         sty ARYPNT+1
         rts

N32768:  .byte 144,128,0,0   ; -32768

INTIDX:  jsr CHRGET
         jsr FRMEVL
POSINT:  jsr CHKNUM
         lda FACSGN
         bmi NONONO
AYINT:   lda FACEXP
         cmp #144
         bcc QINTGO
         lda #<N32768
         ldy #>N32768
         jsr FCOMP
NONONO:  bne FCERR
QINTGO:  jmp QINT

ISARY:   lda DIMFLG
         ora INTFLG
         pha
         lda VALTYP
         pha
         ldy #0
INDLOP:  tya
         pha
         ; PSHWD VARNAM
         lda VARNAM+1
         pha
         lda VARNAM
         pha
         jsr INTIDX
         ; PULWD VARNAM
         pla
         sta VARNAM
         pla
         sta VARNAM+1
         pla
         tay
         tsx
         lda 258,x
         pha
         lda 257,x
         pha
         lda INDICE
         sta 258,x
         lda INDICE+1
         sta 257,x
         iny
         jsr CHRGOT
         cmp #44
         beq INDLOP
         sty COUNT
         jsr CHKCLS
         pla
         sta VALTYP
         pla
         sta INTFLG
         and #127
         sta DIMFLG
         ldx ARYTAB
         lda ARYTAB+1
LOPFDA:  stx LOWTR
         sta LOWTR+1
         cmp STREND+1
         bne LOPFDV
         cpx STREND
         beq NOTFDD
LOPFDV:  ldy #0
         lda (LOWTR),y
         iny
         cmp VARNAM
         bne NMARY1
         lda VARNAM+1
         cmp (LOWTR),y
         beq GOTARY
NMARY1:  iny
         lda (LOWTR),y
         clc
         adc LOWTR
         tax
         iny
         lda (LOWTR),y
         adc LOWTR+1
         bcc LOPFDA          ; always
BSERR:   ldx #ERRBS
         .byte $2C           ; SKIP2
FCERR:   ldx #ERRFC
ERRGO3:  jmp ERROR
GOTARY:  ldx #ERRDD
         lda DIMFLG
         bne ERRGO3
         jsr FMAPTR
         lda COUNT
         ldy #4
         cmp (LOWTR),y
         bne BSERR
         jmp GETDEF

; Build new array entry
NOTFDD:  jsr FMAPTR
         jsr REASON
         lda #0
         tay
         sta CURTOL+1
         ldx #5              ; ADDPRC: 5 for float
         lda VARNAM
         sta (LOWTR),y
         bpl NOTFLT
         dex
NOTFLT:  iny
         lda VARNAM+1
         sta (LOWTR),y
         bpl STOMLT
         dex
         dex
STOMLT:  stx CURTOL
         lda COUNT
         iny
         iny
         iny
         sta (LOWTR),y
LOPPTA:  ldx #11
         lda #0
         bit DIMFLG
         bvc NOTDIM
         pla
         clc
         adc #1
         tax
         pla
         adc #0
NOTDIM:  iny
         sta (LOWTR),y
         iny
         txa
         sta (LOWTR),y
         jsr UMULT
         stx CURTOL
         sta CURTOL+1
         ldy INDEX
         dec COUNT
         bne LOPPTA
         adc ARYPNT+1
         bcs OMERR1
         sta ARYPNT+1
         tay
         txa
         adc ARYPNT
         bcc GREASE
         iny
         beq OMERR1
GREASE:  jsr REASON
         sta STREND
         sty STREND+1
         lda #0
         inc CURTOL+1
         ldy CURTOL
         beq DECCUR
ZERITA:  dey
         sta (ARYPNT),y
         bne ZERITA
DECCUR:  dec ARYPNT+1
         dec CURTOL+1
         bne ZERITA
         inc ARYPNT+1
         sec
         lda STREND
         sbc LOWTR
         ldy #2
         sta (LOWTR),y
         lda STREND+1
         iny
         sbc LOWTR+1
         sta (LOWTR),y
         lda DIMFLG
         bne DIMRTS
         iny

GETDEF:  lda (LOWTR),y
         sta COUNT
         lda #0
         sta CURTOL
INLPNM: sta CURTOL+1
         iny
         pla
         tax
         sta INDICE
         pla
         sta INDICE+1
         cmp (LOWTR),y
         bcc INLPN2
         bne BSERR7
         iny
         txa
         cmp (LOWTR),y
         bcc INLPN1
BSERR7:  jmp BSERR
OMERR1:  jmp OMERR
INLPN2:  iny
INLPN1:  lda CURTOL+1
         ora CURTOL
         clc
         beq ADDIND
         jsr UMULT
         txa
         adc INDICE
         tax
         tya
         ldy INDEX1
ADDIND:  adc INDICE+1
         stx CURTOL
         dec COUNT
         bne INLPNM
         sta CURTOL+1
         ldx #5              ; ADDPRC: 5 for float
         lda VARNAM
         bpl NOTFL1
         dex
NOTFL1:  lda VARNAM+1
         bpl STOML1
         dex
         dex
STOML1:  stx ADDEND
         lda #0
         jsr UMULTD
         txa
         adc ARYPNT
         sta VARPNT
         tya
         adc ARYPNT+1
         sta VARPNT+1
         tay
         lda VARPNT
DIMRTS:  rts

; Integer multiply for arrays
UMULT:   sty INDEX
         lda (LOWTR),y
         sta ADDEND
         dey
         lda (LOWTR),y
UMULTD:  sta ADDEND+1
         lda #16
         sta DECCNT
         ldx #0
         ldy #0
UMULTC:  txa
         asl a
         tax
         tya
         rol a
         tay
         bcs OMERR1
         asl CURTOL
         rol CURTOL+1
         bcc UMLCNT
         clc
         txa
         adc ADDEND
         tax
         tya
         adc ADDEND+1
         tay
         bcs OMERR1
UMLCNT:  dec DECCNT
         bne UMULTC
UMLRTS:  rts

; =========================================================================
; FRE function and integer-to-float
; =========================================================================
FRE:     lda VALTYP
         beq NOFREF
         jsr FREFAC
NOFREF:  jsr GARBA2
         sec
         lda FRETOP
         sbc STREND
         tay
         lda FRETOP+1
         sbc STREND+1

GIVAYF:  ldx #0
         stx VALTYP
         sta FACHO
         sty FACHO+1
         ldx #144
         jmp FLOATS

POS:     ldy TRMPOS
SNGFLT:  lda #0
         beq GIVAYF

; =========================================================================
; USER-DEFINED FUNCTIONS (DEF FN)
; =========================================================================
ERRDIR:  ldx CURLIN+1
         inx
         bne DIMRTS
         ldx #ERRID
         .byte $2C           ; SKIP2
ERRGUF:  ldx #ERRUF
ERRGO1:  jmp ERROR

DEF:     jsr GETFNM
         jsr ERRDIR
         jsr CHKOPN
         lda #128
         sta SUBFLG
         jsr PTRGET
         jsr CHKNUM
         jsr CHKCLS
         lda #EQULTK
         jsr SYNCHR
         pha                 ; ADDPRC byte
         ; PSHWD VARPNT
         lda VARPNT+1
         pha
         lda VARPNT
         pha
         ; PSHWD TXTPTR
         lda TXTPTR+1
         pha
         lda TXTPTR
         pha
         jsr DATA
         jmp DEFFIN

GETFNM:  lda #FNTK
         jsr SYNCHR
         ora #128
         sta SUBFLG
         jsr PTRGT2
         sta DEFPNT
         sty DEFPNT+1
         jmp CHKNUM

FNDOER:  jsr GETFNM
         ; PSHWD DEFPNT
         lda DEFPNT+1
         pha
         lda DEFPNT
         pha
         jsr PARCHK
         jsr CHKNUM
         ; PULWD DEFPNT
         pla
         sta DEFPNT
         pla
         sta DEFPNT+1
         ldy #2
         lda (DEFPNT),y
         sta VARPNT
         tax
         iny
         lda (DEFPNT),y
         beq ERRGUF
         sta VARPNT+1
         iny                 ; ADDPRC
DEFSTF:  lda (VARPNT),y
         pha
         dey
         bpl DEFSTF
         ldy VARPNT+1
         jsr MOVMF
         ; PSHWD TXTPTR
         lda TXTPTR+1
         pha
         lda TXTPTR
         pha
         lda (DEFPNT),y
         sta TXTPTR
         iny
         lda (DEFPNT),y
         sta TXTPTR+1
         ; PSHWD VARPNT
         lda VARPNT+1
         pha
         lda VARPNT
         pha
         jsr FRMNUM
         ; PULWD DEFPNT
         pla
         sta DEFPNT
         pla
         sta DEFPNT+1
         jsr CHRGOT
         bne @snerr
         beq :+
@snerr:  jmp SNERR
:        ; PULWD TXTPTR
         pla
         sta TXTPTR
         pla
         sta TXTPTR+1
DEFFIN:  ldy #0
         pla
         sta (DEFPNT),y
         pla
         iny
         sta (DEFPNT),y
         pla
         iny
         sta (DEFPNT),y
         pla
         iny
         sta (DEFPNT),y
         pla
         iny
         sta (DEFPNT),y      ; ADDPRC
DEFRTS:  rts

; =========================================================================
; STRING FUNCTIONS
; =========================================================================
STR_:    jsr CHKNUM
         ldy #0
         jsr FOUTC
         pla
         pla
TIMSTR:  lda #<LOFBUF
         ldy #>LOFBUF
         beq STRLIT          ; always

STRINI:  ldx FACMO
         ldy FACMO+1
         stx DSCPNT
         sty DSCPNT+1
STRSPA:  jsr GETSPA
         stx DSCTMP+1
         sty DSCTMP+2
         sta DSCTMP
         rts

STRLIT:  ldx #34
         stx CHARAC
         stx ENDCHR
STRLT2:  sta STRNG1
         sty STRNG1+1
         sta DSCTMP+1
         sty DSCTMP+2
         ldy #255
STRGET:  iny
         lda (STRNG1),y
         beq STRFI1
         cmp CHARAC
         beq STRFIN
         cmp ENDCHR
         bne STRGET
STRFIN:  cmp #34
         beq STRFI2
STRFI1:  clc
STRFI2:  sty DSCTMP
         tya
         adc STRNG1
         sta STRNG2
         ldx STRNG1+1
         bcc STRST2
         inx
STRST2:  stx STRNG2+1
         lda STRNG1+1
         bne PUTNEW          ; not page 0 -> no copy
STRCP:   tya
         jsr STRINI
         ldx STRNG1
         ldy STRNG1+1
         jsr MOVSTR
PUTNEW:  ldx TEMPPT
         cpx #TEMPST+STRSIZ*NUMTMP
         bne PUTNW1
         ldx #ERRST
ERRGO2:  jmp ERROR
PUTNW1:  lda DSCTMP
         sta 0,x
         lda DSCTMP+1
         sta 1,x
         lda DSCTMP+2
         sta 2,x
         ldy #0
         stx FACMO
         sty FACMO+1
         sty FACOV
         dey
         sty VALTYP
         stx LASTPT
         inx
         inx
         inx
         stx TEMPPT
         rts

; Get string space
GETSPA:  lsr GARBFL
TRYAG2:  pha
         eor #255
         sec
         adc FRETOP
         ldy FRETOP+1
         bcs TRYAG3
         dey
TRYAG3:  cpy STREND+1
         bcc GARBAG
         bne STRFRE
         cmp STREND
         bcc GARBAG
STRFRE:  sta FRETOP
         sty FRETOP+1
         sta FRESPC
         sty FRESPC+1
         tax
         pla
         rts
GARBAG:  ldx #ERROM
         lda GARBFL
         bmi ERRGO2
         jsr GARBA2
         lda #128
         sta GARBFL
         pla
         bne TRYAG2          ; always

GARBA2:  ldx MEMSIZ
         lda MEMSIZ+1
FNDVAR_: stx FRETOP
         sta FRETOP+1
         ldy #0
         sty GRBPNT+1
         sty GRBPNT
         lda STREND
         ldx STREND+1
         sta GRBTOP
         stx GRBTOP+1
         lda #<TEMPST
         ldx #>TEMPST
         sta INDEX1
         stx INDEX1+1
TVAR:    cmp TEMPPT
         beq SVARS
         jsr DVAR
         beq TVAR
SVARS:   lda #7              ; 6+ADDPRC
         sta FOUR6
         lda VARTAB
         ldx VARTAB+1
         sta INDEX1
         stx INDEX1+1
SVAR:    cpx ARYTAB+1
         bne SVARGO
         cmp ARYTAB
         beq ARYVAR
SVARGO:  jsr DVARS
         beq SVAR
ARYVAR:  sta ARYPNT
         stx ARYPNT+1
         lda #STRSIZ
         sta FOUR6
ARYVA2:  lda ARYPNT
         ldx ARYPNT+1
ARYVA3:  cpx STREND+1
         bne ARYVGO
         cmp STREND
         bne :+
         jmp GRBPAS
:
ARYVGO:  sta INDEX1
         stx INDEX1+1
         ldy #0
         lda (INDEX1),y
         tax
         iny
         lda (INDEX1),y
         php
         iny
         lda (INDEX1),y
         adc ARYPNT
         sta ARYPNT
         iny
         lda (INDEX1),y
         adc ARYPNT+1
         sta ARYPNT+1
         plp
         bpl ARYVA2
         txa
         bmi ARYVA2
         iny
         lda (INDEX1),y
         ldy #0
         asl a
         adc #5
         adc INDEX1
         sta INDEX1
         bcc ARYGET
         inc INDEX1+1
ARYGET:  ldx INDEX1+1
ARYSTR:  cpx ARYPNT+1
         bne GOGO
         cmp ARYPNT
         beq ARYVA3
GOGO:    jsr DVAR
         beq ARYSTR
DVARS:
         lda (INDEX1),y
         bmi DVARTS
         iny
         lda (INDEX1),y
         bpl DVARTS
         iny
DVAR:    lda (INDEX1),y
         beq DVARTS
         iny
         lda (INDEX1),y
         tax
         iny
         lda (INDEX1),y
         cmp FRETOP+1
         bcc DVAR2
         bne DVARTS
         cpx FRETOP
         bcs DVARTS
DVAR2:   cmp GRBTOP+1
         bcc DVARTS
         bne DVAR3
         cpx GRBTOP
         bcc DVARTS
DVAR3:   stx GRBTOP
         sta GRBTOP+1
         lda INDEX1
         ldx INDEX1+1
         sta GRBPNT
         stx GRBPNT+1
         lda FOUR6
         sta SIZE
DVARTS:  lda FOUR6
         clc
         adc INDEX1
         sta INDEX1
         bcc GRBRTS
         inc INDEX1+1
GRBRTS:  ldx INDEX1+1
         ldy #0
         rts

GRBPAS:  lda GRBPNT+1
         ora GRBPNT
         beq GRBRTS
         lda SIZE
         and #4
         lsr a
         tay
         sta SIZE
         lda (GRBPNT),y
         adc LOWTR
         sta HIGHTR
         lda LOWTR+1
         adc #0
         sta HIGHTR+1
         lda FRETOP
         ldx FRETOP+1
         sta HIGHDS
         stx HIGHDS+1
         jsr BLTUC
         ldy SIZE
         iny
         lda HIGHDS
         sta (GRBPNT),y
         tax
         inc HIGHDS+1
         lda HIGHDS+1
         iny
         sta (GRBPNT),y
         jmp FNDVAR_

; String concatenation
CAT:     lda FACLO
         pha
         lda FACMO
         pha
         jsr EVAL
         jsr CHKSTR
         pla
         sta STRNG1
         pla
         sta STRNG1+1
         ldy #0
         lda (STRNG1),y
         clc
         adc (FACMO),y
         bcc SIZEOK
         ldx #ERRLS
         jmp ERROR
SIZEOK:  jsr STRINI
         jsr MOVINS
         lda DSCPNT
         ldy DSCPNT+1
         jsr FRETMP
         jsr MOVDO
         lda STRNG1
         ldy STRNG1+1
         jsr FRETMP
         jsr PUTNEW
         jmp TSTOP

MOVINS:  ldy #0
         lda (STRNG1),y
         pha
         iny
         lda (STRNG1),y
         tax
         iny
         lda (STRNG1),y
         tay
         pla
MOVSTR:  stx INDEX
         sty INDEX+1
MOVDO:   tay
         beq MVDONE
         pha
MOVLP:   dey
         lda (INDEX),y
         sta (FRESPC),y
QMOVE:   tya
         bne MOVLP
         pla
MVDONE:  clc
         adc FRESPC
         sta FRESPC
         bcc MVSTRT
         inc FRESPC+1
MVSTRT:  rts

; Free string temps
FRESTR:  jsr CHKSTR
FREFAC:  lda FACMO
         ldy FACMO+1
FRETMP:  sta INDEX
         sty INDEX+1
         jsr FRETMS
         php
         ldy #0
         lda (INDEX),y
         pha
         iny
         lda (INDEX),y
         tax
         iny
         lda (INDEX),y
         tay
         pla
         plp
         bne FRETRT
         cpy FRETOP+1
         bne FRETRT
         cpx FRETOP
         bne FRETRT
         pha
         clc
         adc FRETOP
         sta FRETOP
         bcc FREPLA
         inc FRETOP+1
FREPLA:  pla
FRETRT:  stx INDEX
         sty INDEX+1
         rts
FRETMS:  cpy LASTPT+1
         bne FRERTS
         cmp LASTPT
         bne FRERTS
         sta TEMPPT
         sbc #STRSIZ
         sta LASTPT
         ldy #0
FRERTS:  rts

; CHR$ function
CHR_:    jsr CONINT
         txa
         pha
         lda #1
         jsr STRSPA
         pla
         ldy #0
         sta (DSCTMP+1),y
         pla
         pla
RLZRET:  jmp PUTNEW

; LEFT$ function
LEFT_:   jsr PREAM
         cmp (DSCPNT),y
         tya
RLEFT:   bcc RLEFT1
         lda (DSCPNT),y
         tax
         tya
RLEFT1:  pha
RLEFT2:  txa
RLEFT3:  pha
         jsr STRSPA
         lda DSCPNT
         ldy DSCPNT+1
         jsr FRETMP
         pla
         tay
         pla
         clc
         adc INDEX
         sta INDEX
         bcc PULMOR
         inc INDEX+1
PULMOR:  tya
         jsr MOVDO
         jmp PUTNEW

; RIGHT$ function
RIGHT_:  jsr PREAM
         clc
         sbc (DSCPNT),y
         eor #255
         jmp RLEFT

; MID$ function
MID_:    lda #255
         sta FACLO
         jsr CHRGOT
         cmp #41             ; ')'
         beq MID2
         jsr CHKCOM
         jsr GETBYT
MID2:    jsr PREAM
         beq GOFUC
         dex
         txa
         pha
         clc
         ldx #0
         sbc (DSCPNT),y
         bcs RLEFT2
         eor #255
         cmp FACLO
         bcc RLEFT3
         lda FACLO
         bcs RLEFT3

PREAM:   jsr CHKCLS
         pla
         tay
         pla
         sta JMPER+1
         pla
         pla
         pla
         tax
         ; PULWD DSCPNT
         pla
         sta DSCPNT
         pla
         sta DSCPNT+1
         lda JMPER+1
         pha
         tya
         pha
         ldy #0
         txa
         rts

; LEN function
LEN_:    jsr LEN1
         jmp SNGFLT
LEN1:    jsr FRESTR
         ldx #0
         stx VALTYP
         tay
         rts

; ASC function
ASC_:    jsr LEN1
         beq GOFUC
         ldy #0
         lda (INDEX1),y
         tay
         jmp SNGFLT
GOFUC:   jmp FCERR

GTBYTC:  jsr CHRGET
GETBYT:  jsr FRMNUM
CONINT:  jsr POSINT
         ldx FACMO
         bne GOFUC
         ldx FACLO
CHRGO2:  jmp CHRGOT

; VAL function
VAL_:    jsr LEN1
         bne :+
         jmp ZEROFC
:        ldx TXTPTR
         ldy TXTPTR+1
         stx STRNG2
         sty STRNG2+1
         ldx INDEX1
         stx TXTPTR
         clc
         adc INDEX1
         sta INDEX2
         ldx INDEX1+1
         stx TXTPTR+1
         bcc VAL2
         inx
VAL2:    stx INDEX2+1
         ldy #0
         lda (INDEX2),y
         pha
         lda #0
         sta (INDEX2),y
         jsr CHRGOT
         jsr FIN
         pla
         ldy #0
         sta (INDEX2),y
ST2TXT:  ldx STRNG2
         ldy STRNG2+1
         stx TXTPTR
         sty TXTPTR+1
VALRTS:  rts

; =========================================================================
; PEEK, POKE, WAIT
; =========================================================================
GETNUM:  jsr FRMNUM
         jsr GETADR
COMBYT:  jsr CHKCOM
         jmp GETBYT
GETADR:  lda FACSGN
         bmi GOFUC
         lda FACEXP
         cmp #145
         bcs GOFUC
         jsr QINT
         lda FACMO
         ldy FACMO+1
         sty POKER
         sta POKER+1
         rts

PEEK_:   lda POKER
         pha
         lda POKER+1
         pha
         jsr GETADR
         ldy #0
GETCON:  lda (POKER),y
         tay
DOSGFL:  pla
         sta POKER+1
         pla
         sta POKER
         jmp SNGFLT

POKE:    jsr GETNUM
         txa
         ldy #0
         sta (POKER),y
         rts

FNWAIT:  jsr GETNUM
         stx ANDMSK
         ldx #0
         jsr CHRGOT
         beq ZSTORDO
         jsr COMBYT
ZSTORDO:
STORDO:  stx EORMSK
         ldy #0
WAITER:  lda (POKER),y
         eor EORMSK
         and ANDMSK
         beq WAITER
ZERRTS:  rts

; =========================================================================
; FLOATING POINT MATH PACKAGE
; =========================================================================
; NOTE: Original uses RADIX 8 (octal) throughout math package.
; All constants converted to decimal/hex for ca65.

; --- Addition and Subtraction ---
FADDH:   lda #<FHALF
         ldy #>FHALF
         jmp FADD

FSUB:    jsr CONUPK
FSUBT:   lda FACSGN
         eor #$FF
         sta FACSGN
         eor ARGSGN
         sta ARISGN
         lda FACEXP
         jmp FADDT

FADD5:   jsr SHIFTR
         bcc FADD4
FADD:    jsr CONUPK
FADDT:   bne :+
         jmp MOVFA
:        ldx FACOV
         stx OLDOV
         ldx #ARGEXP
         lda ARGEXP
FADDC:   tay
         beq ZERRTS
         sec
         sbc FACEXP
         beq FADD4
         bcc FADDA
         sty FACEXP
         ldy ARGSGN
         sty FACSGN
         eor #$FF
         adc #0
         ldy #0
         sty OLDOV
         ldx #FAC
         bne FADD1
FADDA:   ldy #0
         sty FACOV
FADD1:   cmp #<(256-7)       ; -7 as unsigned
         bmi FADD5
         tay
         lda FACOV
         lsr 1,x
         jsr ROLSHF
FADD4:   bit ARISGN
         bpl FADD2
FADD3:   ldy #FACEXP
         cpx #ARGEXP
         beq SUBIT
         ldy #ARGEXP
SUBIT:   sec
         eor #$FF
         adc OLDOV
         sta FACOV
         lda 4,y             ; 3+ADDPRC
         sbc 4,x
         sta FACLO
         lda 3,y             ; 2+ADDPRC
         sbc 3,x
         sta FACMO
         lda 2,y
         sbc 2,x
         sta FACMOH
         lda 1,y
         sbc 1,x
         sta FACHO
FADFLT:  bcs NORMAL
         jsr NEGFAC
NORMAL:  ldy #0
         tya
         clc
NORM3:   ldx FACHO
         bne NORM1
         ldx FACHO+1
         stx FACHO
         ldx FACMOH+1
         stx FACMOH
         ldx FACMO+1
         stx FACMO
         ldx FACOV
         stx FACLO
         sty FACOV
         adc #8              ; octal 10 = decimal 8
         cmp #40             ; 10*ADDPRC+30 = 10+30=40
         bne NORM3
ZEROFC:  lda #0
ZEROF1:  sta FACEXP
ZEROML:  sta FACSGN
         rts

FADD2:   adc OLDOV
         sta FACOV
         lda FACLO
         adc ARGLO
         sta FACLO
         lda FACMO
         adc ARGMO
         sta FACMO
         lda FACMOH
         adc ARGMOH
         sta FACMOH
         lda FACHO
         adc ARGHO
         sta FACHO
         jmp SQUEEZ

NORM2:   adc #1
         asl FACOV
         rol FACLO
         rol FACMO
         rol FACMOH
         rol FACHO
NORM1:   bpl NORM2
         sec
         sbc FACEXP
         bcs ZEROFC
         eor #$FF
         adc #1
         sta FACEXP
SQUEEZ:  bcc RNDRTS
RNDSHF:  inc FACEXP
         beq OVERR
         ror FACHO
         ror FACMOH
         ror FACMO
         ror FACLO
         ror FACOV
RNDRTS:  rts

NEGFAC:  lda FACSGN
         eor #$FF
         sta FACSGN
NEGFCH:  lda FACHO
         eor #$FF
         sta FACHO
         lda FACMOH
         eor #$FF
         sta FACMOH
         lda FACMO
         eor #$FF
         sta FACMO
         lda FACLO
         eor #$FF
         sta FACLO
         lda FACOV
         eor #$FF
         sta FACOV
         inc FACOV
         bne INCFRT
INCFAC:  inc FACLO
         bne INCFRT
         inc FACMO
         bne INCFRT
         inc FACMOH
         bne INCFRT
         inc FACHO
INCFRT:  rts

OVERR:   ldx #ERROV
         jmp ERROR

; Shift routines
MULSHF:  ldx #RESHO-1
SHFTR2:  ldy 4,x             ; 3+ADDPRC
         sty FACOV
         ldy 3,x
         sty 4,x
         ldy 2,x
         sty 3,x
         ldy 1,x
         sty 2,x
         ldy BITS
         sty 1,x
SHIFTR:  adc #8               ; octal 10 = 8
         bmi SHFTR2
         beq SHFTR2
         sbc #8
         tay
         lda FACOV
         bcs SHFTRT
SHFTR3:  asl 1,x
         bcc SHFTR4
         inc 1,x
SHFTR4:  ror 1,x
         ror 1,x             ; yes, two of them (RORSW=1)
ROLSHF:
         ror 2,x
         ror 3,x
         ror 4,x             ; ADDPRC
         ror a
SHFTR7:  iny
         bne SHFTR3
SHFTRT:  clc
         rts

; =========================================================================
; NATURAL LOG
; =========================================================================
FONE:    .byte 129            ; 1.0
         .byte 0
         .byte 0
         .byte 0
         .byte 0              ; ADDPRC

; Log polynomial coefficients (ADDPRC=1, 5-byte FP)
LOGCN2:  .byte 3              ; degree-1
         .byte $7F,$5E,$56,$CB,$79   ; .43425594188
         .byte $80,$13,$9B,$0B,$64   ; .57658454134
         .byte $80,$76,$38,$93,$16   ; .96180075921
         .byte $82,$38,$AA,$3B,$20   ; 2.8853900728

SQRHLF:  .byte $80,$35,$04,$F3,$34   ; SQR(0.5)
SQRTWO:  .byte $81,$35,$04,$F3,$34   ; SQR(2.0)
NEGHLF:  .byte $80,$80,$00,$00,$00   ; -0.5
LOG2:    .byte $80,$31,$72,$17,$F8   ; LN(2)

LOG_:    jsr SIGN_
         beq LOGERR
         bpl LOG1
LOGERR:  jmp FCERR
LOG1:    lda FACEXP
         sbc #$7F             ; remove bias (carry off)
         pha
         lda #$80
         sta FACEXP
         lda #<SQRHLF
         ldy #>SQRHLF
         jsr FADD
         lda #<SQRTWO
         ldy #>SQRTWO
         jsr FDIV
         lda #<FONE
         ldy #>FONE
         jsr FSUB
         lda #<LOGCN2
         ldy #>LOGCN2
         jsr POLYX
         lda #<NEGHLF
         ldy #>NEGHLF
         jsr FADD
         pla
         jsr FINLOG
MULLN2:  lda #<LOG2
         ldy #>LOG2

; =========================================================================
; MULTIPLICATION AND DIVISION
; =========================================================================
FMULT:   jsr CONUPK
FMULTT:  beq MULTRT
         jsr MULDIV
         lda #0
         sta RESHO
         sta RESMOH
         sta RESMO
         sta RESLO
         lda FACOV
         jsr MLTPLY
         lda FACLO
         jsr MLTPLY
         lda FACMO
         jsr MLTPLY
         lda FACMOH
         jsr MLTPLY
         lda FACHO
         jsr MLTPL1
         jmp MOVFR

MLTPLY:  bne :+
         jmp MULSHF
:
MLTPL1:  lsr a
         ora #$80
MLTPL2:  tay
         bcc MLTPL3
         clc
         lda RESLO
         adc ARGLO
         sta RESLO
         lda RESMO
         adc ARGMO
         sta RESMO
         lda RESMOH
         adc ARGMOH
         sta RESMOH
         lda RESHO
         adc ARGHO
         sta RESHO
MLTPL3:  ror RESHO
         ror RESMOH
         ror RESMO
         ror RESLO
         ror FACOV
         tya
         lsr a
         bne MLTPL2
MULTRT:  rts

; Unpack memory into ARG
CONUPK:  sta INDEX1
         sty INDEX1+1
         ldy #4              ; 3+ADDPRC
         lda (INDEX1),y
         sta ARGLO
         dey
         lda (INDEX1),y
         sta ARGMO
         dey
         lda (INDEX1),y
         sta ARGMOH
         dey
         lda (INDEX1),y
         sta ARGSGN
         eor FACSGN
         sta ARISGN
         lda ARGSGN
         ora #$80
         sta ARGHO
         dey
         lda (INDEX1),y
         sta ARGEXP
         lda FACEXP
         rts

; Check special cases, add exponents
MULDIV:  lda ARGEXP
MLDEXP:  beq ZEREMV
         clc
         adc FACEXP
         bcc TRYOFF
         bmi GOOVER
         clc
         .byte $2C           ; SKIP2
TRYOFF:  bpl ZEREMV
         adc #$80
         sta FACEXP
         bne :+
         jmp ZEROML
:        lda ARISGN
         sta FACSGN
         rts
MLDVEX:  lda FACSGN
         eor #$FF
         bmi GOOVER
ZEREMV:  pla
         pla
         jmp ZEROFC
GOOVER:  jmp OVERR

; Multiply by 10
MUL10:   jsr MOVAF
         tax
         beq MUL10R
         clc
         adc #2
         bcs GOOVER
FINML6:  ldx #0
         stx ARISGN
         jsr FADDC
         inc FACEXP
         beq GOOVER
MUL10R:  rts

; Divide by 10
TENZC:   .byte $84,$20,$00,$00,$00   ; 10.0

DIV10:   jsr MOVAF
         lda #<TENZC
         ldy #>TENZC
         ldx #0
FDIVF:   stx ARISGN
         jsr MOVFM
         jmp FDIVT

FDIV:    jsr CONUPK
FDIVT:   beq DV0ERR
         jsr ROUND
         lda #0
         sec
         sbc FACEXP
         sta FACEXP
         jsr MULDIV
         inc FACEXP
         beq GOOVER
         ldx #<(256-4)       ; 256-3-ADDPRC
         lda #1
DIVIDE:  ldy ARGHO
         cpy FACHO
         bne SAVQUO
         ldy ARGMOH
         cpy FACMOH
         bne SAVQUO
         ldy ARGMO
         cpy FACMO
         bne SAVQUO
         ldy ARGLO
         cpy FACLO
SAVQUO:  php
         rol a
         bcc QSHFT
         inx
         sta RESLO,x
         beq LD100
         bpl DIVNRM
         lda #1
QSHFT:   plp
         bcs DIVSUB
SHFARG:  asl ARGLO
         rol ARGMO
         rol ARGMOH
         rol ARGHO
         bcs SAVQUO
         bmi DIVIDE
         bpl SAVQUO
DIVSUB:  tay
         lda ARGLO
         sbc FACLO
         sta ARGLO
         lda ARGMO
         sbc FACMO
         sta ARGMO
         lda ARGMOH
         sbc FACMOH
         sta ARGMOH
         lda ARGHO
         sbc FACHO
         sta ARGHO
         tya
         jmp SHFARG
LD100:   lda #$40             ; octal 100 = 64
         bne QSHFT
DIVNRM:  asl a
         asl a
         asl a
         asl a
         asl a
         asl a
         sta FACOV
         plp
         jmp MOVFR
DV0ERR:  ldx #ERRDV0
         jmp ERROR

; =========================================================================
; FLOATING POINT MOVEMENT ROUTINES
; =========================================================================
MOVFR:   lda RESHO
         sta FACHO
         lda RESMOH
         sta FACMOH
         lda RESMO
         sta FACMO
         lda RESLO
         sta FACLO
         jmp NORMAL

MOVFM:   sta INDEX1
         sty INDEX1+1
         ldy #4              ; 3+ADDPRC
         lda (INDEX1),y
         sta FACLO
         dey
         lda (INDEX1),y
         sta FACMO
         dey
         lda (INDEX1),y
         sta FACMOH
         dey
         lda (INDEX1),y
         sta FACSGN
         ora #$80
         sta FACHO
         dey
         lda (INDEX1),y
         sta FACEXP
         sty FACOV
         rts

MOV2F:   ldx #TEMPF2
         .byte $2C           ; SKIP2
MOV1F:   ldx #TEMPF1
MOVML:   ldy #0
         beq MOVMF
MOVVF:   ldx FORPNT
         ldy FORPNT+1
MOVMF:   jsr ROUND
         stx INDEX1
         sty INDEX1+1
         ldy #4              ; 3+ADDPRC
         lda FACLO
         sta (INDEX),y
         dey
         lda FACMO
         sta (INDEX),y
         dey
         lda FACMOH
         sta (INDEX),y
         dey
         lda FACSGN
         ora #$7F
         and FACHO
         sta (INDEX),y
         dey
         lda FACEXP
         sta (INDEX),y
         sty FACOV
         rts

MOVFA:   lda ARGSGN
MOVFA1:  sta FACSGN
         ldx #5              ; 4+ADDPRC
MOVFAL:  lda ARGEXP-1,x
         sta FACEXP-1,x
         dex
         bne MOVFAL
         stx FACOV
         rts

MOVAF:   jsr ROUND
MOVEF:   ldx #6              ; 5+ADDPRC
MOVAFL:  lda FACEXP-1,x
         sta ARGEXP-1,x
         dex
         bne MOVAFL
         stx FACOV
MOVRTS:  rts

ROUND:   lda FACEXP
         beq MOVRTS
         asl FACOV
         bcc MOVRTS
INCRND:  jsr INCFAC
         bne MOVRTS
         jmp RNDSHF

; =========================================================================
; SIGN, SGN, FLOAT, ABS
; =========================================================================
SIGN_:   lda FACEXP
         beq SIGNRT
FCSIGN:  lda FACSGN
FCOMPS:  rol a
         lda #$FF
         bcs SIGNRT
         lda #1
SIGNRT:  rts

SGN_:    jsr SIGN_

FLOAT:   sta FACHO
         lda #0
         sta FACHO+1
         ldx #$88            ; octal 210 = 136 = $88

FLOATS:  lda FACHO
         eor #$FF
         rol a
FLOATC:  lda #0
         sta FACLO
         sta FACMO
FLOATB:  stx FACEXP
         sta FACOV
         sta FACSGN
         jmp FADFLT

ABS_:    lsr FACSGN
         rts

; =========================================================================
; COMPARE TWO NUMBERS
; =========================================================================
FCOMP:   sta INDEX2
FCOMPN:  sty INDEX2+1
         ldy #0
         lda (INDEX2),y
         iny
         tax
         beq SIGN_
         lda (INDEX2),y
         eor FACSGN
         bmi FCSIGN
FOUTCP:  cpx FACEXP
         bne FCOMPC
         lda (INDEX2),y
         ora #$80
         cmp FACHO
         bne FCOMPC
         iny
         lda (INDEX2),y
         cmp FACMOH
         bne FCOMPC
         iny
         lda (INDEX2),y
         cmp FACMO
         bne FCOMPC
         iny
         lda #$7F
         cmp FACOV
         lda (INDEX2),y
         sbc FACLO
         beq QINTRT
FCOMPC:  lda FACSGN
         bcc FCOMPD
         eor #$FF
FCOMPD:  jmp FCOMPS

; =========================================================================
; GREATEST INTEGER FUNCTION
; =========================================================================
QINT:
         lda FACEXP
         beq CLRFAC
         sec
         sbc #160             ; $A0: octal 240 = 8*1+octal 230 = 160
         bit FACSGN
         bpl QISHFT
         tax
         lda #$FF
         sta BITS
         jsr NEGFCH
         txa
QISHFT:  ldx #FAC
         cmp #<(256-7)
         bpl QINT1
         jsr SHIFTR
         sty BITS
QINTRT:  rts
QINT1:   tay
         lda FACSGN
         and #$80
         lsr FACHO
         ora FACHO
         sta FACHO
         jsr ROLSHF
         sty BITS
         rts

INT_:    lda FACEXP
         cmp #160             ; $A0
         bcs INTRTS
         jsr QINT
         sty FACOV
         lda FACSGN
         sty FACSGN
         eor #$80
         rol a
         lda #160             ; $A0
         sta FACEXP
         lda FACLO
         sta INTEGR
         jmp FADFLT
CLRFAC:  sta FACHO
         sta FACMOH
         sta FACMO
         sta FACLO
         tay
INTRTS:  rts

; =========================================================================
; FLOATING POINT INPUT (FIN)
; =========================================================================
FIN:     ldy #0
         ldx #12              ; 11+ADDPRC
FINZLP:  sty DECCNT,x
         dex
         bpl FINZLP
         bcc FINDGQ
         cmp #'-'
         bne QPLUS
         stx SGNFLG
         beq FINC
QPLUS:   cmp #'+'
         bne FIN1
FINC:    jsr CHRGET
FINDGQ:  bcc FINDIG
FIN1:    cmp #'.'
         beq FINDP
         cmp #'E'
         bne FINE
         jsr CHRGET
         bcc FNEDG1
         cmp #MINUTK
         beq FINEC1
         cmp #'-'
         beq FINEC1
         cmp #PLUSTK
         beq FINEC
         cmp #'+'
         beq FINEC
         bne FINEC2
FINEC1:  ror EXPSGN
FINEC:   jsr CHRGET
FNEDG1:  bcc FINEDG
FINEC2:  bit EXPSGN
         bpl FINE
         lda #0
         sec
         sbc TENEXP
         jmp FINE1
FINDP:   ror DPTFLG
         bit DPTFLG
         bvc FINC
FINE:    lda TENEXP
FINE1:   sec
         sbc DECCNT
         sta TENEXP
         beq FINQNG
         bpl FINMUL
FINDIV:  jsr DIV10
         inc TENEXP
         bne FINDIV
         beq FINQNG
FINMUL:  jsr MUL10
         dec TENEXP
         bne FINMUL
FINQNG:  lda SGNFLG
         bmi NEGXQS
         rts
NEGXQS:  jmp NEGOP

FINDIG:  pha
         bit DPTFLG
         bpl FINDG1
         inc DECCNT
FINDG1:  jsr MUL10
         pla
         sec
         sbc #'0'
         jsr FINLOG
         jmp FINC

FINLOG:  pha
         jsr MOVAF
         pla
         jsr FLOAT
         lda ARGSGN
         eor FACSGN
         sta ARISGN
         ldx FACEXP
         jmp FADDT

FINEDG:  lda TENEXP
         cmp #10              ; octal 12 = 10
         bcc MLEX10
         lda #100             ; octal 144 = 100
         bit EXPSGN
         bmi MLEXMI
         jmp OVERR
MLEX10:  asl a
         asl a
         clc
         adc TENEXP
         asl a
         clc
         ldy #0
         adc (TXTPTR),y
         sec
         sbc #'0'
MLEXMI:  sta TENEXP
         jmp FINEC

; =========================================================================
; FLOATING POINT OUTPUT (FOUT)
; =========================================================================
; Constants for FOUT (ADDPRC=1, 5-byte FP)
NZ0999:  .byte $9B,$3E,$BC,$1F,$FD  ; 99999999.9499
NZ9999:  .byte $9E,$6E,$6B,$27,$FD  ; 999999999.499
NZMIL:   .byte $9E,$6E,$6B,$28,$00  ; 10^9

INPRT:   lda #<INTXT
         ldy #>INTXT
         jsr STROU2
         lda CURLIN+1
         ldx CURLIN
LINPRT:  sta FACHO
         stx FACHO+1
         ldx #$90            ; octal 220 = 144 = $90
         sec
         jsr FLOATC
         jsr FOUT
STROU2:  jmp STROUT

FOUT:    ldy #1
FOUTC:   lda #' '
         bit FACSGN
         bpl FOUT1
         lda #'-'
FOUT1:   sta FBUFFR-1,y
         sta FACSGN
         sty FBUFPT
         iny
         lda #'0'
         ldx FACEXP
         bne :+
         jmp FOUT19
:        lda #0
         cpx #$80
         beq FOUT37
         bcs FOUT7
FOUT37:  lda #<NZMIL
         ldy #>NZMIL
         jsr FMULT
         lda #<(256-9)       ; 256-3*ADDPRC-6 = 256-9 = 247
FOUT7:   sta DECCNT
FOUT4:   lda #<NZ9999
         ldy #>NZ9999
         jsr FCOMP
         beq BIGGES
         bpl FOUT9
FOUT3:   lda #<NZ0999
         ldy #>NZ0999
         jsr FCOMP
         beq FOUT38
         bpl FOUT5
FOUT38:  jsr MUL10
         dec DECCNT
         bne FOUT3
FOUT9:   jsr DIV10
         inc DECCNT
         bne FOUT4

FOUT5:   jsr FADDH
BIGGES:  jsr QINT
         ldx #1
         lda DECCNT
         clc
         adc #10              ; 3*ADDPRC+7 = 10
         bmi FOUTPI
         cmp #13              ; 3*ADDPRC+10 = 13
         bcs FOUT6
         adc #$FF
         tax
         lda #2
FOUTPI:  sec
FOUT6:   sbc #2
         sta TENEXP
         stx DECCNT
         txa
         beq FOUT39
         bpl FOUT8
FOUT39:  ldy FBUFPT
         lda #'.'
         iny
         sta FBUFFR-1,y
         txa
         beq FOUT16
         lda #'0'
         iny
         sta FBUFFR-1,y
FOUT16:  sty FBUFPT
FOUT8:   ldy #0
FOUTIM:  ldx #$80
FOUT2:   lda FACLO
         clc
         adc FOUTBL+3,y      ; 2+ADDPRC
         sta FACLO
         lda FACMO
         adc FOUTBL+2,y      ; 1+ADDPRC
         sta FACMO
         lda FACMOH
         adc FOUTBL+1,y
         sta FACMOH
         lda FACHO
         adc FOUTBL,y
         sta FACHO
         inx
         bcs FOUT41
         bpl FOUT2
         bmi FOUT40
FOUT41:  bmi FOUT2
FOUT40:  txa
         bcc FOUTYP
         eor #$FF
         adc #10              ; octal 12 = 10
FOUTYP:  adc #'0'-1
         iny
         iny
         iny
         iny                  ; 3+ADDPRC = 4
         sty FDECPT
         ldy FBUFPT
         iny
         tax
         and #$7F
         sta FBUFFR-1,y
         dec DECCNT
         bne STXBUF
         lda #'.'
         iny
         sta FBUFFR-1,y
STXBUF:  sty FBUFPT
         ldy FDECPT
FOUTCM:  txa
         eor #$FF
         and #$80
         tax
         cpy #FDCEND-FOUTBL
         bne FOUT2
FOULDY:  ldy FBUFPT
FOUT11:  lda FBUFFR-1,y
         dey
         cmp #'0'
         beq FOUT11
         cmp #'.'
         beq FOUT12
         iny
FOUT12:  lda #'+'
         ldx TENEXP
         beq FOUT17
         bpl FOUT14
         lda #0
         sec
         sbc TENEXP
         tax
         lda #'-'
FOUT14:  sta FBUFFR+1,y
         lda #'E'
         sta FBUFFR,y
         txa
         ldx #'0'-1
         sec
FOUT15:  inx
         sbc #10
         bcs FOUT15
         adc #'0'+10
         sta FBUFFR+3,y
         txa
         sta FBUFFR+2,y
         lda #0
         sta FBUFFR+4,y
         beq FOUT20          ; always
FOUT19:  sta FBUFFR-1,y
FOUT17:  lda #0
         sta FBUFFR,y
FOUT20:  lda #<FBUFFR
         ldy #>FBUFFR
FPWRRT:  rts

FHALF:   .byte $80,$00       ; 0.5
ZERO:    .byte $00,$00
         .byte $00            ; ADDPRC

; Power of ten table (ADDPRC=1)
FOUTBL:  .byte $FA,$0A,$1F,$00  ; -100,000,000
         .byte $00,$98,$96,$80  ; 10,000,000
         .byte $FF,$F0,$BD,$C0  ; -1,000,000
         .byte $00,$01,$86,$A0  ; 100,000
         .byte $FF,$FF,$D8,$F0  ; -10,000
         .byte $00,$00,$03,$E8  ; 1000
         .byte $FF,$FF,$FF,$9C  ; -100
         .byte $00,$00,$00,$0A  ; 10
         .byte $FF,$FF,$FF,$FF  ; -1
FDCEND:

; =========================================================================
; EXPONENTIATION AND SQUARE ROOT
; =========================================================================
SQR_:    jsr MOVAF
         lda #<FHALF
         ldy #>FHALF
         jsr MOVFM

FPWRT:   beq EXP_
         lda ARGEXP
         bne FPWRT1
         jmp ZEROF1
FPWRT1:  ldx #<TEMPF3
         ldy #>TEMPF3
         jsr MOVMF
         lda ARGSGN
         bpl FPWR1
         jsr INT_
         lda #<TEMPF3
         ldy #>TEMPF3
         jsr FCOMP
         bne FPWR1
         tya
         ldy INTEGR
FPWR1:   jsr MOVFA1
         tya
         pha
         jsr LOG_
         lda #<TEMPF3
         ldy #>TEMPF3
         jsr FMULT
         jsr EXP_
         pla
         lsr a
         bcc NEGRTS
NEGOP:   lda FACEXP
         beq NEGRTS
         lda FACSGN
         eor #$FF
         sta FACSGN
NEGRTS:  rts

; =========================================================================
; EXP function
; =========================================================================
LOGEB2:  .byte $81,$38,$AA,$3B,$29  ; LOG(E) BASE 2

EXPCON:  .byte 7              ; degree-1
         .byte $71,$34,$58,$3E,$56  ; 2.1498763697E-5
         .byte $74,$16,$7E,$B3,$1B  ; 1.4352314036E-4
         .byte $77,$2F,$EE,$E3,$85  ; 1.3422634824E-3
         .byte $7A,$1D,$84,$1C,$2A  ; 9.6140170119E-3
         .byte $7C,$63,$59,$58,$0A  ; 5.5505126860E-2
         .byte $7E,$75,$FD,$E7,$C6  ; 2.4022638462E-1
         .byte $80,$31,$72,$18,$10  ; 6.9314718608E-1
         .byte $81,$00,$00,$00,$00  ; 1.0

EXP_:    lda #<LOGEB2
         ldy #>LOGEB2
         jsr FMULT
         lda FACOV
         adc #$50             ; octal 120 = 80 = $50
         bcc STOLD
         jsr INCRND
STOLD:   sta OLDOV
         jsr MOVEF
         lda FACEXP
         cmp #$88             ; octal 210 = 136 = $88
         bcc EXP1
GOMLDV:  jsr MLDVEX
EXP1:    jsr INT_
         lda INTEGR
         clc
         adc #$81             ; octal 201 = 129 = $81
         beq GOMLDV
         sec
         sbc #1
         pha
         ldx #5              ; 4+ADDPRC
SWAPLP:  lda ARGEXP,x
         ldy FACEXP,x
         sta FACEXP,x
         sty ARGEXP,x
         dex
         bpl SWAPLP
         lda OLDOV
         sta FACOV
         jsr FSUBT
         jsr NEGOP
         lda #<EXPCON
         ldy #>EXPCON
         jsr POLY
         lda #0
         sta ARISGN
         pla
         jsr MLDEXP
         rts

; =========================================================================
; POLYNOMIAL EVALUATOR
; =========================================================================
POLYX:   sta POLYPT
         sty POLYPT+1
         jsr MOV1F
         lda #TEMPF1
         jsr FMULT
         jsr POLY1
         lda #<TEMPF1
         ldy #>TEMPF1
         jmp FMULT

POLY:    sta POLYPT
         sty POLYPT+1
POLY1:   jsr MOV2F
         lda (POLYPT),y
         sta DEGREE
         ldy POLYPT
         iny
         tya
         bne POLY3
         inc POLYPT+1
POLY3:   sta POLYPT
         ldy POLYPT+1
POLY2:   jsr FMULT
         lda POLYPT
         ldy POLYPT+1
         clc
         adc #5              ; 4+ADDPRC
         bcc POLY4
         iny
POLY4:   sta POLYPT
         sty POLYPT+1
         jsr FADD
         lda #<TEMPF2
         ldy #>TEMPF2
         dec DEGREE
         bne POLY2
RANDRT:  rts

; =========================================================================
; RANDOM NUMBER GENERATOR
; =========================================================================
RMULZC:  .byte $98,$35,$44,$7A
RADDZC:  .byte $68,$28,$B1,$46

RND_:    jsr SIGN_
         tax
         bmi RND1
QSETNR:  lda #<RNDX
         ldy #>RNDX
         jsr MOVFM
         txa
         beq RANDRT
         lda #<RMULZC
         ldy #>RMULZC
         jsr FMULT
         lda #<RADDZC
         ldy #>RADDZC
         jsr FADD
RND1:    ldx FACLO
         lda FACHO
         sta FACLO
         stx FACHO
STRNEX:  lda #0
         sta FACSGN
         lda FACEXP
         sta FACOV
         lda #$80
         sta FACEXP
         jsr NORMAL
         ldx #<RNDX
         ldy #>RNDX
GMOVMF:  jmp MOVMF

; =========================================================================
; COS/SIN/TAN/ATN are stubbed out (KIMROM=1, dispatch goes to FCERR)
; =========================================================================

; =========================================================================
; INITIALIZATION CODE
; =========================================================================

; ROM copy of CHRGET (copied to ZP during INIT)
INITAT:  inc CHRGET+7
         bne CHZGOT
         inc CHRGET+8
CHZGOT:  lda $EA60            ; placeholder address
         cmp #':'
         bcs CHZRTS
         cmp #' '
         beq INITAT
         sec
         sbc #'0'
         sec
         sbc #<(256-'0')
CHZRTS:  rts

         .byte 128            ; initial RND seed
         .byte 79
         .byte 199
         .byte 82
         .byte 88             ; ADDPRC

INIT:
         ldx #255
         stx CURLIN+1
         txs
         ; Set up START and RDYJSR to point to INIT initially
         lda #<INIT
         ldy #>INIT
         sta START+1
         sty START+2
         sta RDYJSR+1
         sty RDYJSR+2
         ; Store AYINT and GIVAYF addresses
         lda #<AYINT
         ldy #>AYINT
         sta ADRAYI
         sty ADRAYI+1
         lda #<GIVAYF
         ldy #>GIVAYF
         sta ADRGAY
         sty ADRGAY+1
         ; JMP opcodes
         lda #$4C             ; JMP opcode
         sta START
         sta RDYJSR
         sta JMPER
         sta USRPOK
         lda #<FCERR
         ldy #>FCERR
         sta USRPOK+1
         sty USRPOK+2
         ; Terminal dimensions
         lda #LINLEN
         sta LINWID
         lda #NCMPOS
         sta NCMWID

         ; Copy CHRGET routine from ROM to ZP
         ldx #RNDX+4-CHRGET
MOVCHG:  lda INITAT-1,x
         sta CHRGET-1,x
         dex
         bne MOVCHG

         ; Initialize constants
         lda #STRSIZ
         sta FOUR6
         txa                  ; X=0 after loop
         sta BITS
         sta LASTPT+1
         sta NULCNT
         pha                  ; zero at bottom of stack for FNDFOR
         sta CNTWFL

         ; Initialize ACIA
         jsr ACIA_INIT

         jsr CRDO
         ldx #TEMPST
         stx TEMPPT

         ; Memory size prompt
         lda #<MEMORY
         ldy #>MEMORY
         jsr STROUT
         jsr QINLIN
         stx TXTPTR
         sty TXTPTR+1
         jsr CHRGET
         tay
         bne USEDE9

         ; Default: use RAMLOC for TXTTAB
         lda #<RAMLOC
         ldy #>RAMLOC
         sta TXTTAB
         sty TXTTAB+1
         sta LINNUM
         sty LINNUM+1
         ldy #0
         ; Probe memory
LOOPMM:  inc LINNUM
         bne LOOPM1
         inc LINNUM+1
LOOPM1:  lda #85
         sta (LINNUM),y
         cmp (LINNUM),y
         bne USEDEC
         asl a
         sta (LINNUM),y
         cmp (LINNUM),y
         bne USEDEC
         beq LOOPMM

USEDE9:  jsr CHRGOT
         jsr LINGET
         tay
         beq USEDEC
         jmp SNERR

USEDEC:  lda LINNUM
         ldy LINNUM+1
         sta MEMSIZ
         sty MEMSIZ+1
         sta FRETOP
         sty FRETOP+1

         ; Terminal width prompt
TTYW:    lda #<TTYWID
         ldy #>TTYWID
         jsr STROUT
         jsr QINLIN
         stx TXTPTR
         sty TXTPTR+1
         jsr CHRGET
         tay
         beq ASKAGN
         jsr LINGET
         lda LINNUM+1
         bne TTYW
         lda LINNUM
         cmp #16
         bcc TTYW
         sta LINWID
MORCPS:  sbc #CLMWID
         bcs MORCPS
         eor #255
         sbc #CLMWID-2
         clc
         adc LINWID
         sta NCMWID

ASKAGN:
         ; Set TXTTAB for ROM build
         ldx #<RAMLOC
         ldy #>RAMLOC
         stx TXTTAB
         sty TXTTAB+1

         ldy #0
         tya
         sta (TXTTAB),y
         inc TXTTAB
         bne QROOM
         inc TXTTAB+1
QROOM:   lda TXTTAB
         ldy TXTTAB+1
         jsr REASON

         jsr CRDO
         lda MEMSIZ
         sec
         sbc TXTTAB
         tax
         lda MEMSIZ+1
         sbc TXTTAB+1
         jsr LINPRT
         lda #<WORDS
         ldy #>WORDS
         jsr STROUT
         jsr SCRTCH

         ; Finalize: set RDYJSR to STROUT, START to READY
         lda #<STROUT
         ldy #>STROUT
         sta RDYJSR+1
         sty RDYJSR+2
         lda #<READY
         ldy #>READY
         sta START+1
         sty START+2
         jmp (START+1)

; Text messages for INIT
MEMORY:  .byte "MEMORY SIZE", 0
TTYWID:  .byte "WIDTH", 0
WORDS:   .byte " BYTES FREE", 13, 10, 13, 10
         .byte "MICROSOFT BASIC V1.1", 13, 10
         .byte "COPYRIGHT 1978 MICROSOFT", 13, 10
         .byte 0

; =========================================================================
; I/O SHIM - Custom ACIA routines replacing KIM ROM
; =========================================================================

; Initialize ACIA
ACIA_INIT:
         lda #$00
         sta ACIA_STATUS     ; programmed reset
         lda #$0B
         sta ACIA_CMD        ; DTR active, RX IRQ disabled, TX IRQ disabled, no parity
         lda #$1E
         sta ACIA_CTRL       ; 1 stop, 8 data, 9600 baud
         rts

; Output character in A to ACIA
; Emulated ACIA is always ready, no polling needed.
OUTCH:   sta ACIA_DATA
         rts

; Read character from ACIA (poll until ready)
ACIA_INCHR:
@wait:   lda ACIA_STATUS
         and #$08             ; bit 3 = RDRF
         beq @wait
         lda ACIA_DATA
         and #$7F             ; mask to 7-bit ASCII
         rts

; Check if Ctrl-C is available at ACIA
; Returns: C=1 if char available and it's checked, A=char
;          C=0 if no char
ACIA_CHECK:
         lda ACIA_STATUS
         and #$08
         beq @none
         lda ACIA_DATA
         and #$7F
         cmp #3               ; Ctrl-C?
         beq @gotit
         sec                  ; have char but not Ctrl-C - still return it
         rts
@gotit:  sec
         rts
@none:   clc
         rts

; =========================================================================
; VECTORS segment
; =========================================================================
.segment "VECTORS"
         .word $0000          ; NMI - not used
         .word INIT           ; RESET
         .word $0000          ; IRQ - not used
