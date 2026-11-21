; =============================================================
;  VEINTIUNA ENHANCED v5  -  VIC-20 sense expansio, PAL
;  Joc del Pontoon de "INPUT Juegos", en codi maquina i en catala
;  Assemblar:  acme -f cbm -o veintiuna_enhanced.prg veintiuna_enhanced.asm
; =============================================================
!cpu 6502

; ---------- pantalla 28x31 a $1c00, color a $9400 ----------
SCREEN  = $1c00
COLRAM  = $9400
WIDTH   = 28
HEIGHT  = 31
MROW    = 1             ; primera de les files de missatges
CTOP    = 11            ; fila superior de les cartes
FAN0    = (WIDTH-19)/2  ; columna de la primera carta (ventall de 5)
PILEC   = (WIDTH-7)/2   ; columna de la pila al remenar
STOP    = 10            ; fila superior de la pila

; ---------- sistema ----------
JIFFY   = $a2
NKEYS   = $c6
SHFLAG  = $0291
GETIN   = $ffe4
VOICE_H = $900c
VOICE_N = $900d
VOLUME  = $900e

BLACK=0 : RED=2 : PURPLE=4 : GREEN=5 : BLUE=6

; ---------- temps, en unitats de 2 jiffies (1/30 s) ----------
D_STEP  = 1             ; cada pas d'una carta lliscant
D_TYPE  = 1             ; cada lletra dels missatges
D_CLAC  = 1             ; "clac" en caure a la pila
D_CARD  = 10            ; despres de dibuixar una carta
D_BANK  = 40            ; la banca "pensa" abans de demanar
D_MSG   = 90            ; temps per llegir un missatge
D_RUIN  = 150           ; "T'HAS ARRUINAT!"

; ---------- capcalera de missatge (1 byte) ----------
; bit 0 = segueix un byte de columna, bits 1-2 color (coltab), bits 3-7 fila
C_RED=0 : C_PUR=2 : C_GRN=4 : C_BLU=6 : HCOL=1
!macro hdr .row, .col { !byte (.row<<3)|.col }

; ---------- pagina zero (zona de BASIC) ----------
sp      = $10           ; punter pantalla (2)
cp      = $12           ; punter color (2)
cx      = $14           ; columna del cursor
curcol  = $15
mptr    = $16           ; (2)
rng     = $18           ; (2)
num     = $1a           ; (2)
mu      = $1c           ; fitxes (2)
be      = $1e           ; aposta inicial (2)
tu      = $20           ; total amb l'as = 1  -.
nu      = $21           ; cartes del torn      | a 0 cada torn
t2      = $22           ; hi ha as            -'
tb      = $23           ; aposta total (2)    -.
eb      = $25           ; ja ha demanat carta  | a 0 cada ma
gg      = $26           ; premi: 0, 1 o 2      |
pl      = $27           ; 0 jugador, 1 banca  -'
best    = $28           ; puntuacio: tu+10 si l'as val 11; 30/25/0
yy      = $29           ; puntuacio del jugador
tcol    = $2a           ; columna de la carta
rank    = $2b
ccol    = $2c           ; color de la carta
key     = $2d           ; caracter del pal
tmp     = $2e
cnt     = $2f
tbase   = $30
sidx    = $31
candbl  = $33
z       = $35           ; cartes usades de la baralla
pat     = $36           ; patro de pips (2)
mask    = $38

; =============================================================
        * = $1001
        !word +, 10
        !byte $9e
        !text "4109"
        !byte 0
+       !word 0
; ------------------------------------------------------------- $100d
        ldx #15                 ; registres del VIC: pantalla, so, colors
-       lda vicini,x
        sta $9000,x
        dex
        bpl -
        lda #$80
        sta SHFLAG              ; no deixar canviar a minuscules
        lda $9124               ; llavor: temporitzador de la VIA
        sta rng
        lda $9125
        ora #1
        sta rng+1
restart ldx #51                 ; baralla ordenada
-       txa
        sta deck,x
        dex
        bpl -
        inx
        stx mu+1
        lda #100
        sta mu

; ---------- remenat: les cartes llisquen cap a la pila ----------
shuffle jsr cls                 ; (torna amb X=0)
        stx sidx
        jsr pmsg
        +hdr MROW+2, C_RED|HCOL
        !byte (WIDTH-17)/2
        !scr "vint-i-u enhanced",0
        jsr pmsg
        +hdr STOP+13, C_PUR|HCOL
        !byte (WIDTH-11)/2
        !scr "barrejant...",0
        lda #PILEC
        sta tcol
        jsr draw_back
shuf_lp jsr rnd                 ; deck(sidx) <-> deck(0..51 a l'atzar)
        and #$3f
        cmp #52
        bcs shuf_lp
        tay
        ldx sidx
        lda deck,x
        pha
        lda deck,y
        sta deck,x
        pla
        sta deck,y
        inc sidx
        lda sidx                ; dues barreges per carta que llisca
        lsr
        bcs shuf_lp
        lsr                     ; alternant: des de l'esquerra o la dreta
        lda #0
        bcc +
        lda #PILEC*2
+       sta tcol
slide   jsr draw_back
        lda tcol                ; "frrr" que canvia amb la posicio
        asl
        ora #$c0
        sta VOICE_N
        ldx #D_STEP
        jsr delay
        lda tcol                ; esborrar la columna del darrere i avancar
        cmp #PILEC
        beq landed
        bcs +
        jsr clrcol              ; cap a la dreta: columna tcol
        inc tcol
        bne slide               ; (sempre)
+       adc #5                  ; cap a l'esquerra: columna tcol+6 (C=1)
        jsr clrcol
        dec tcol
        bne slide               ; (sempre)
landed  lda #$f8                ; "clac"
        sta VOICE_N
        lda #12
        sta VOLUME
        ldx #D_CLAC
        jsr delay               ; (torna amb X=0)
        stx VOICE_N
        lda #5
        sta VOLUME
        lda sidx
        cmp #52
        bne shuf_lp
        stx z
newhand lda z                   ; remenar quan queda un terc de baralla
        cmp #37
        bcc round
        jmp shuffle

; ---------- nova ma / nou torn ----------
round   ldx #pl-tu
        !byte $2c               ; (BIT abs: salta el LDX)
turn    ldx #t2-tu
        lda #0
-       sta tu,x
        dex
        bpl -
        lda #FAN0-3
        sta tcol
        jsr cls                 ; tapet
        ldx #WIDTH*8            ; 16 files de tapet negre i 2 de franja blava
-       lda #$ef
        sta SCREEN+(CTOP+4)*WIDTH-1,x
        sta SCREEN+(CTOP+12)*WIDTH-1,x
        lda #BLACK
        sta COLRAM+(CTOP+4)*WIDTH-1,x
        sta COLRAM+(CTOP+12)*WIDTH-1,x
        cpx #WIDTH*2+1
        bcs +
        lda #$dc
        sta SCREEN+(CTOP-4)*WIDTH-1,x
        lda #BLUE
        sta COLRAM+(CTOP-4)*WIDTH-1,x
+       dex
        bne -

; ---------- repartir una carta ----------
deal    inc nu
        ldx z                   ; (z <= 46: es remena abans d'acabar la baralla)
        lda deck,x
        inx
        stx z
        ldx #0                  ; pal = carta/13, valor = resta+1
-       cmp #13
        bcc +
        sbc #13
        inx
        bne -
+       adc #1                  ; (C=0)
        sta rank
        txa                     ; cors i diamants (1, 3) en vermell
        and #1
        asl
        sta ccol
        lda suitch,x
        sta key
        inc tcol
        inc tcol
        inc tcol
        jsr clr_top
        ldx #CTOP               ; ---- dibuixar la carta
        ldy #0
        jsr drawbox
        lda ccol
        sta curcol
        ldy tcol                ; index de dalt
        iny
        ldx #CTOP+1
        jsr idxat
        ldy tcol                ; zona central 5x7, a la fila seguent
        iny
        jsr crlf
        lda #7
        sta cnt
        ldx rank
        dex
        dex
        cpx #9
        bcs face
        txa                     ; pips: 2 bits per fila
        asl
        tax
        lda pipdat,x
        sta pat
        lda pipdat+1,x
        sta pat+1
prow    lda #0
        asl pat
        rol pat+1
        rol
        asl pat
        rol pat+1
        rol
        tay
        lda rowmask,y
        ldy cnt
        cpy #7
        bne +
        ora #1                  ; pal sota l'index
+       sta mask
        ldx #5
-       lda #$20
        lsr mask
        bcc +
        lda #0
+       jsr cellout
        dex
        bne -
        jsr rowend
        bne prow
        beq cardok
face    lda rank                ; A J Q K -> 1 3 4 5
        and #7
        tax
        lda rowmask,x           ; (faceofs-1 = rowmask)
        sta tmp
frow    ldx #5
-       ldy tmp
        inc tmp
        lda faces,y
        jsr cellout
        dex
        bne -
        jsr rowend
        bne frow
cardok  lda rank                ; index de baix (ja som a la fila): tcol+5,
        eor #10                 ; o tcol+4 si es un 10
        cmp #1
        lda tcol
        adc #4
        sta cx
        jsr pidx
        ldx #D_CARD
        jsr delay
        lda rank                ; sumar: figures = 10
        cmp #10
        bcc +
        lda #9                  ; (+C)
+       adc tu
        sta tu
        ldx rank
        dex
        bne +
        inc t2
+       jsr pmsg                ; punts
        +hdr MROW, C_BLU
        !scr "punts ",0
        ldx pl
        bne +
        jsr pmsg_c
        !scr "teus: ",0
        bne ++                  ; (pmsg torna amb Z=0)
+       jsr pmsg_c
        !scr "banca: ",0
++      lda tu
        jsr pbyte
        lda tu                  ; l'as pot valer 11?
        sta best
        lda t2
        beq +
        lda tu
        cmp #12
        bcs +
        adc #10                 ; (C=0)
        sta best
        jsr pmsg_c
        !scr " o ",0
        lda best
        jsr pbyte
+
        ; ---- jugades especials
        lda best
        cmp #21
        bne +
        ldx nu
        cpx #2
        bne +
        lda #30
        sta best
        jsr pmsg
        +hdr MROW+1, C_RED
        !scr "vint-i-u natural!",$ff
+       lda tu
        cmp #22
        bcc +
        lda #0
        sta best
        ldx pl
        bne bbust
        jsr pmsg
        +hdr MROW+1, C_RED
        !scr "t'has passat!",$ff
bbust   jsr pmsg
        +hdr MROW+1, C_RED
        !scr "la banca s'ha passat!",$ff
+       ldx nu
        cpx #5
        bne +
        lda #25
        sta best
        jsr pmsg
        +hdr MROW+1, C_RED
        !scr "5 cartes!",$ff
+       lda tu
        cmp #21
        bne no21
        ldx pl
        bne b21
        jsr pmsg
        +hdr MROW+1, C_RED
        !scr "tens 21!",$ff
b21     jsr pmsg
        +hdr MROW+1, C_RED
        !scr "la banca fa 21!",$ff
no21    ldx pl
        bne bank
        ldx nu
        dex
        bne options
        jmp bet

        ; ---- la banca demana fins a 17
bank    lda best
        cmp #17
        bcs +
        ldx #D_BANK
        jsr delay
        jmp deal
+       jsr pmsg
        +hdr MROW+2, C_GRN
        !scr "la banca es planta",$ff

        ; ---- opcions del jugador
options jsr pmsg
        +hdr MROW+1, C_PUR
        !byte 0
        lsr candbl              ; (0 o 1) -> 0
        lda eb                  ; doblar: sense haver demanat i amb fitxes
        bne +
        lda mu
        cmp be
        lda mu+1
        sbc be+1
        bcc +
        inc candbl
        jsr pmsg_c
        !byte $84               ; lletra clau en invers
        !scr "oblar ",0
+       jsr pmsg_c
        !byte $83
        !scr "arta ",0
        lda best                ; plantar-se amb 16 o mes
        cmp #16
        bcc +
        jsr pmsg_c
        !byte $90
        !scr "lantar-se",0
+       jsr pmsg_c
        !scr " ?",0
-       jsr getkey
        cmp #'C'
        beq hit
        cmp #'D'
        bne +
        ldx candbl
        bne dbl
+       cmp #'P'
        bne -
        lda best
        cmp #16
        bcc -
        jsr pmsg
        +hdr MROW+2, C_GRN
        !scr "et plantes.",$ff
dbl     clc                     ; tb += be, mu -= be
        lda tb
        adc be
        sta tb
        lda tb+1
        adc be+1
        sta tb+1
        sec
        lda mu
        sbc be
        sta mu
        lda mu+1
        sbc be+1
        sta mu+1
        !byte $2c               ; (BIT abs: salta l'INC)
hit     inc eb
        jmp deal

; ---------- aposta ----------
bet     jsr showmu
bet_ag  jsr pmsg
        +hdr MROW+2, C_PUR
        !scr "aposta?      ",0
        lda #8
        sta cx
        lda #0
        sta be
        sta be+1
bet_lp  lda #$a0                ; cursor
        jsr putc_nc
        jsr getkey
        cmp #13
        bne bet_k
        lda be                  ; RETURN: 0 < aposta <= fitxes
        ora be+1
        beq bet_ag
        lda mu
        cmp be
        lda mu+1
        sbc be+1
        bcs dbl                 ; (el cursor l'esborra clr_top a deal)
        bcc bet_ag                 ; tb = be, mu -= be
bet_k   cmp #20                 ; DEL
        bne bet_d
        lda be
        ora be+1
        beq bet_lp
        lda #$20
        jsr putc_nc
        dec cx
        ldx #be
        jsr div10
        beq bet_lp              ; (Z=1)
bet_d   cmp #$21                ; xifres, o les mateixes amb SHIFT
        bcc bet_lp
        cmp #$3a
        bcs bet_lp
        and #$0f
        cmp #10
        bcs bet_lp
        sta tmp
        ora be                  ; sense zeros a l'esquerra
        ora be+1
        beq bet_lp
        lda be+1                ; < 6400: cap desbordament
        cmp #$19
        bcs bet_lp
        ldx #10                 ; be = xifra + 10*be
        lda tmp
        ldy #0
-       clc
        adc be
        pha
        tya
        adc be+1
        tay
        pla
        dex
        bne -
        sta be
        sty be+1
        lda tmp
        ora #$30
        jsr putc
        bne bet_lp              ; (Z=0)


; =============================================================
;  RUTINES
; =============================================================
addmu   clc                     ; mu += A/X, amb topall a 65535
        adc mu
        sta mu
        txa
        adc mu+1
        sta mu+1
        bcc +
        lda #$ff
        sta mu
        sta mu+1
+       rts

; ---- esborra la columna A de la pila
clrcol  tay
        ldx #STOP
        jsr setcur
        ldx #11
-       lda #$20
        jsr putc_nc
        jsr nextrow
        dex
        bne -
        rts

; ---- capsa de carta (11 files) amb plantilla
draw_back
        ldx #STOP
        ldy #tb_back-tmpl
drawbox sty tbase
        ldy tcol
        jsr setcur
        ldx tbase
--      lda tmpl,x              ; files d'aquest tipus (0 = fi)
        beq ++
        sta tmp
-       lda #GREEN
        sta curcol
        lda tmpl+1,x
        jsr putc
        lda tmpl+4,x
        sta curcol
        lda #5
        sta cnt
---     lda tmpl+2,x
        jsr putc
        dec cnt
        bne ---
        lda #GREEN
        sta curcol
        lda tmpl+3,x
        jsr putc
        ldy tcol
        jsr crlf
        dec tmp
        bne -
        txa
        clc
        adc #5
        tax
        bne --
++      rts

; ---- final de fila de la zona central
rowend  ldy tcol
        iny
        jsr crlf
        dec cnt
        rts

; ---- casella central: $00 = pal, $80 = pal invers
cellout asl
        beq +
        ror
        bne putc                ; (sempre)
+       lda key
        bcc putc
        ora #$80
        bne putc                ; (sempre)

; ---- index: valor de la carta ("10" en dues xifres)
idxat   jsr setcur
pidx    ldx rank
        cpx #10
        bne +
        lda #$31
        jsr putc
+       lda rankch-1,x
putc    jsr putc_nc
        inc cx
        rts
putc_nc ldy cx
        sta (sp),y
        lda curcol
        sta (cp),y
        rts

; ---- pantalla
setcur  lda #0                  ; X fila (>0), Y columna
        sta sp
        sta cp
        lda #>SCREEN
        sta sp+1
        lda #>COLRAM
        sta cp+1
        sty cx
-       jsr nextrow
        dex
        bne -
        rts

crlf    sty cx                  ; columna Y de la fila seguent
nextrow lda sp
        clc
        adc #WIDTH
        sta sp
        sta cp
        bcc +
        inc sp+1
        inc cp+1
+       rts

cls     ldx #0
        lda #$20
-       sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        inx
        bne -
        rts

clr_top ldx #WIDTH*4-1
        lda #$20
-       sta SCREEN+MROW*WIDTH,x
        dex
        bpl -
        rts

; ---- missatges inline. pmsg: capcalera + text + 0
;      pmsg_c: text + 0 al cursor. Si acaba amb $ff en lloc de 0, salta a result
pmsg    sec
        !byte $24               ; (BIT zp: salta el CLC)
pmsg_c  clc
        pla
        sta mptr
        pla
        sta mptr+1
        bcc pm_lp
        jsr nextb               ; capcalera (torna Y=0)
        lsr                     ; C = hi ha columna
        pha
        bcc +
        jsr nextb
        tay
+       pla
        pha
        and #3
        tax
        lda coltab,x
        sta curcol
        pla
        lsr
        lsr
        tax
        jsr setcur
pm_lp   jsr nextb
        beq +
        cmp #$ff
        beq result
        jsr tputc
        beq pm_lp               ; (Z=1)
+       jsr nextb               ; tornar despres del 0 (amb Z=0)
        jmp (mptr)


; ---------- final del torn ----------
result  ldx #D_MSG
        jsr delay
        ldx pl
        bne final
        lda best
        sta yy
        beq settle              ; el jugador s'ha passat
        inc pl
        jmp turn
final   lda best                ; banca >= jugador: guanya la banca
        cmp yy
        bcs settle
        lda yy                  ; gg = 1, o 2 amb natural / cinc cartes
        cmp #22
        lda #0
        adc #1
        sta gg

; ---------- cobrar ----------
settle  jsr clr_top
        lda gg
        bne won
        jsr pmsg
        +hdr MROW, C_RED
        !scr "guanya la banca",0
        bne shm                 ; (Z=0)
won     lda tb                  ; tornar l'aposta
        ldx tb+1
        jsr addmu
        lda tb                  ; premi = tb o 2*tb
        ldx tb+1
        lsr gg
        bcs +
        asl
        pha
        txa
        rol
        tax
        pla
+       sta num
        stx num+1
        jsr addmu
        jsr pmsg
        +hdr MROW, C_RED
        !scr "guanyes ",0
        jsr pnumv
shm     jsr showmu
        jsr pmsg
        +hdr MROW+2, C_PUR
        !scr "prem una tecla",0
        jsr getkey
        lda mu
        ora mu+1
        beq +
        jmp newhand
+       jsr cls
        jsr pmsg
        +hdr MROW+1, C_RED|HCOL
        !byte (WIDTH-15)/2
        !scr "t'has arruinat!",0
        ldx #D_RUIN
        jsr delay
        jmp restart

nextb   inc mptr
        bne +
        inc mptr+1
+       ldy #0
        lda (mptr),y
        rts

tputc   jsr putc                ; lletra a lletra, amb "tic"
        lda #$e0
        sta VOICE_H
        ldx #D_TYPE
        jsr delay
        stx VOICE_H             ; (X=0)
        rts

; ---- numeros
showmu  jsr pmsg
        +hdr MROW+1, C_GRN
        !scr "fitxes: ",0
        lda #RED
        sta curcol
        lda mu
        ldx mu+1
        !byte $2c               ; (BIT abs: salta el LDX #0)
pbyte   ldx #0
pnum    sta num                 ; A baix, X alt
        stx num+1
pnumv   lda #0
        pha
        ldx #num
-       jsr div10
        ora #$30
        pha
        lda num
        ora num+1
        bne -
-       pla
        beq ++
        jsr tputc
        beq -                   ; (Z=1)
div10   ldy #16                 ; (X) /= 10, A = residu. X = adreca zp
        lda #0
-       asl 0,x
        rol 1,x
        rol
        cmp #10
        bcc +
        sbc #10
        inc 0,x
+       dey
        bne -
++      rts

; ---- teclat, temps, atzar
getkey  lda #0
        sta NKEYS
-       jsr rnd
        jsr GETIN
        beq -
        and #$7f                ; ignorar SHIFT
        rts

delay                           ; X unitats de 2 jiffies (torna X=0, Z=1)
--      lda JIFFY
        clc
        adc #2
-       cmp JIFFY
        bne -
        dex
        bne --
        rts

rnd     lda rng+1               ; xorshift 16 bits
        lsr
        lda rng
        ror
        eor rng+1
        sta rng+1
        ror
        eor rng
        sta rng
        eor rng+1
        sta rng+1
        rts

; =============================================================
;  DADES
; =============================================================
; registres $9000-$900f (PAL). $9006-$9009 son de lectura i $900a-$900d
; nomes necessiten el bit 7 a 0: hi posem coltab i suitch
vicini  !byte $06,$16,WIDTH,HEIGHT*2,0,$f0
coltab  !byte RED,PURPLE,GREEN,BLUE
suitch  !byte $41,$53,$58,$5a           ; piques, cors, trebols, diamants
        !byte 5,$1d                     ; volum, fons blanc i vora verda
rankch  !scr "a234567890jqk"
; mascara de fila per tipus (0 centre, 1 buida, 2 parella); a partir
; de l'index 1 fa tambe d'inici de cada figura, indexat per valor AND 7
rowmask !byte $04,$00,$0a,35,70,105
pipdat  !byte $44,$45,$44,$44,$64,$65,$64,$64,$64,$66,$64,$62,$24,$62,$a4,$68,$88,$89
; capses: [files, esquerra, mig x5, dreta, color del mig], 0 = fi
tmpl    !byte 1,$cf,$f7,$d0,GREEN, 9,$f4,$20,$ea,GREEN, 1,$cc,$ef,$fa,GREEN, 0
tb_back !byte 1,$4f,$77,$50,GREEN, 9,$74,$66,$6a,BLUE, 1,$4c,$6f,$7a,GREEN
        ; (el $00 inicial de faces tanca tb_back)
faces   ; A, J, Q, K: 5x7, $00 = pal, $80 = pal invers
	!byte $00,$20,$00,$20,$20
	!byte $20,$6e,$66,$6e,$20
	!byte $20,$66,$20,$66,$20
	!byte $20,$66,$6e,$66,$20
	!byte $20,$66,$20,$66,$20
	!byte $20,$66,$20,$66,$20
	!byte $20,$20,$00,$20,$20
	!byte $00,$20,$6e,$20,$20
	!byte $6e,$66,$66,$66,$6e
	!byte $66,$51,$20,$51,$66
	!byte $66,$20,$20,$20,$66
	!byte $5d,$4a,$43,$61,$5d
	!byte $4a,$72,$43,$72,$61
	!byte $20,$a0,$80,$a0,$20
	!byte $00,$ff,$a0,$7f,$20
	!byte $ff,$ff,$20,$7f,$7f
	!byte $ff,$51,$20,$51,$7f
	!byte $ff,$20,$57,$20,$7f
	!byte $ff,$4a,$43,$61,$7f
	!byte $ff,$4d,$20,$4e,$7f
	!byte $20,$d3,$80,$df,$20
	!byte $00,$df,$df,$df,$df
	!byte $66,$66,$66,$66,$66
	!byte $66,$51,$49,$51,$66
	!byte $66,$20,$6d,$20,$66
	!byte $66,$4a,$43,$61,$66
	!byte $4a,$72,$43,$72,$61
	!byte $6c,$a0,$80,$a0,$7b

deck    = *
end_of_code = deck + 52
!if end_of_code > SCREEN { !error "No hi cap!" }
