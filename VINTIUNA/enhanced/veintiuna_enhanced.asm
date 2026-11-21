; =============================================================
;  VEINTIUNA ENHANCED v4  -  VIC-20 sense expansio, PAL
;  Joc del Pontoon de "INPUT Juegos", en codi maquina i en catala
;  Versio optimitzada per mida.
;  Assemblar:  acme -f cbm -o veintiuna_enhanced.prg veintiuna_enhanced.asm
; =============================================================
!cpu 6502

; ---------- pantalla 28x31 a $1c00, color a $9400 ----------
SCREEN  = $1c00
COLOFS  = $78           ; >COLRAM - >SCREEN
WIDTH   = 28
HEIGHT  = 31
MROW    = 1             ; primera de les 4 files de missatges
CTOP    = 11            ; fila superior de les cartes
FAN0    = (WIDTH-19)/2  ; columna de la primera carta (ventall de 5)
PILEC   = (WIDTH-7)/2   ; columna de la pila al remenar
STOP    = 10            ; fila superior de la pila

; ---------- sistema ----------
JIFFY   = $a2           ; rellotge, 60 Hz
NKEYS   = $c6           ; tecles al buffer
SHFLAG  = $0291         ; bloqueig SHIFT+C=
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

; ---------- capcalera de missatge: 1 byte ----------
; bits 0-4 fila, bits 5-6 color (coltab), bit 7 = segueix un byte de columna
C_RED = 0<<5 : C_PUR = 1<<5 : C_GRN = 2<<5 : C_BLU = 3<<5 : HCOL = $80

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
tu      = $20           ; total amb l'as = 1   } es posen a 0
nu      = $21           ; cartes d'aquesta ma   } a cada torn
t2      = $22           ; hi ha as              }
bonus   = $23           ; 30 natural, 25 cinc cartes }
tb      = $24           ; aposta total (2)      } i aquests
eb      = $26           ; ja ha demanat carta   } a cada ma
gg      = $27           ;                       }
pl      = $28           ; 0 jugador, 1 banca    }
t3      = $29           ; 10 si l'as pot valer 11
best    = $2a           ; tu+t3
z       = $3c           ; cartes usades de la baralla
sc      = $2b           ; puntuacio del torn
yy      = $2c           ; puntuacio del jugador
tcol    = $2e           ; columna de la carta
suit    = $2f
rank    = $30
ccol    = $31           ; color de la carta
key     = $32           ; caracter del pal
tmp     = $33
cnt     = $34
fch     = $35
tbase   = $36
sidx    = $37
dir     = $38
candbl  = $39
canstd  = $3a
rflag   = $3b

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
        lda $9124               ; llavor
        eor JIFFY
        sta rng
        lda $9125
        ora #1
        sta rng+1
restart lda #100
        sta mu
        lda #0
        sta mu+1
        ldx #51                 ; baralla ordenada
-       txa
        sta deck,x
        dex
        bpl -

; ---------- remenat: les cartes llisquen cap a la pila ----------
shuffle jsr cls
        jsr pmsg
        !byte HCOL|C_RED|(MROW+2),(WIDTH-17)/2
        !scr "vint-i-u enhanced",0
        jsr pmsg
        !byte HCOL|C_PUR|(STOP+13),(WIDTH-11)/2
        !scr "barrejant...",0
        lda #PILEC
        sta tcol
        jsr draw_back
        lda #0
        sta sidx
shuf_lp jsr swap                ; dues barreges per carta
        jsr swap
        ldx #0                  ; des de l'esquerra...
        ldy #1
        lda sidx
        and #2
        beq +
        ldx #PILEC*2            ; ...o des de la dreta
        dey
        dey
+       stx tcol
        sty dir
slide   jsr draw_back
        lda tcol                ; "frrr" que canvia amb la posicio
        asl
        ora #$c0
        sta VOICE_N
        ldx #D_STEP
        jsr delay
        lda tcol
        cmp #PILEC
        beq landed
        ldy dir                 ; columna que queda al darrere
        bpl +
        adc #5                  ; (C=1 aqui) -> tcol+6
+       jsr clrcol
        lda tcol
        clc
        adc dir
        sta tcol
        bne slide               ; (sempre)
landed  lda #$f8                ; "clac"
        sta VOICE_N
        lda #12
        sta VOLUME
        ldx #D_CLAC
        jsr delay
        lda #5
        sta VOLUME
        lda #0
        sta VOICE_N
        lda sidx
        cmp #52
        bne shuf_lp
        lda #0
        sta z

; ---------- nova ma ----------
round   ldx #pl-tu            ; nova ma: tot a 0
        !byte $2c               ; (BIT abs: salta el LDX seguent)
turn    ldx #bonus-tu         ; nou torn: tu, nu, t2, bonus
        lda #0
-       sta tu,x
        dex
        bpl -
        lda #FAN0-3
        sta tcol
        jsr draw_table

; ---------- repartir una carta ----------
deal    inc nu
        ldx z
        cpx #52
        bcc +
        ldx #0
+       lda deck,x
        inx
        stx z
        ldx #0                  ; pal = carta/13, valor = resta+1
-       cmp #13
        bcc +
        sbc #13
        inx
        bne -
+       stx suit
        adc #1                  ; (C=0)
        sta rank
        txa                     ; cors i diamants (1, 3) en vermell
        lsr
        lda #BLACK
        bcc +
        lda #RED
+       sta ccol
        lda tcol
        clc
        adc #3
        sta tcol
        jsr clr_top
        jsr draw_card
        ldx #D_CARD
        jsr delay
        lda rank                ; sumar: figures = 10
        cmp #11
        bcc +
        lda #10
+       clc
        adc tu
        sta tu
        lda rank
        cmp #1
        bne +
        sta t2
+       jsr pmsg                ; punts
        !byte C_BLU|MROW
        !scr "punts ",0
        ldx pl
        bne +
        jsr pmsg_c
        !scr "teus: ",0
        beq ++                  ; (pmsg_c torna amb Z=1)
+       jsr pmsg_c
        !scr "banca: ",0
++      lda tu
        jsr pbyte
        ldx #0                  ; l'as pot valer 11?
        lda t2
        beq +
        lda tu
        cmp #12
        bcs +
        ldx #10
+       stx t3
        txa
        clc
        adc tu
        sta best
        txa
        beq +
        jsr pmsg_c
        !scr " o ",0
        lda best
        jsr pbyte
+
        ; ---- jugades especials
        lda best
        cmp #21
        bne +
        lda nu
        cmp #2
        bne +
        lda #30
        sta bonus
        jsr pmsgr
        !byte C_RED|(MROW+1)
        !scr "vint-i-u natural!",0
+       lda tu
        cmp #22
        bcc +
        ldx pl
        bne bbust
        jsr pmsgr
        !byte C_RED|(MROW+1)
        !scr "t'has passat!",0
bbust   jsr pmsgr
        !byte C_RED|(MROW+1)
        !scr "la banca s'ha passat!",0
+       lda nu
        cmp #5
        bne +
        lda #25
        sta bonus
        jsr pmsgr
        !byte C_RED|(MROW+1)
        !scr "5 cartes!",0
+       lda tu
        cmp #21
        bne no21
        ldx pl
        bne b21
        jsr pmsgr
        !byte C_RED|(MROW+1)
        !scr "tens 21!",0
b21     jsr pmsgr
        !byte C_RED|(MROW+1)
        !scr "la banca fa 21!",0
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
+       jsr pmsgr
        !byte C_GRN|(MROW+2)
        !scr "la banca es planta",0

        ; ---- opcions del jugador
options jsr pmsg
        !byte C_PUR|(MROW+1),0
        lda #0
        sta candbl
        sta canstd
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
        inc canstd
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
        ldx canstd
        beq -
        jsr pmsgr
        !byte C_GRN|(MROW+2)
        !scr "et plantes.",0
hit     inc eb
        jmp deal
dbl     jsr takebet
        jmp deal

; ---------- aposta ----------
bet     jsr showmu
bet_ag  jsr pmsg
        !byte C_PUR|(MROW+2)
        !scr "aposta?      ",0
        lda #8
        sta cx
        lda #0
        sta num
        sta num+1
bet_lp  lda #$a0                ; cursor
        jsr putc_nc
        jsr getkey
        cmp #13
        bne bet_k
        lda num                 ; RETURN: 0 < aposta <= fitxes
        ora num+1
        beq bet_ag
        lda mu
        cmp num
        lda mu+1
        sbc num+1
        bcc bet_ag
        lda #$20
        jsr putc_nc
        lda num
        sta be
        lda num+1
        sta be+1
        jsr takebet
        jmp deal
bet_k   cmp #20                 ; DEL
        bne bet_d
        lda num
        ora num+1
        beq bet_lp
        lda #$20
        jsr putc_nc
        dec cx
        jsr div10
        jmp bet_lp
bet_d   cmp #$21                ; xifres, o les mateixes amb SHIFT
        bcc bet_lp
        cmp #$3a
        bcs bet_lp
        and #$0f
        cmp #10
        bcs bet_lp
        sta tmp
        ora num                 ; sense zeros a l'esquerra
        ora num+1
        beq bet_lp
        lda num+1               ; < 6400: cap desbordament
        cmp #$19
        bcs bet_lp
        lda num                 ; num = num*10 + xifra
        ldx num+1
        asl num
        rol num+1
        asl num
        rol num+1
        adc num
        sta num
        txa
        adc num+1
        sta num+1
        asl num
        rol num+1
        lda num
        adc tmp
        sta num
        bcc +
        inc num+1
+       lda tmp
        ora #$30
        jsr putc
        jmp bet_lp

; ---------- final del torn ----------
result  ldx #D_MSG
        jsr delay
        lda best
        ldx tu
        cpx #22
        bcc +
        lda #0
+       ldx bonus
        beq +
        txa
+       sta sc
        ldx pl
        bne final
        sta yy
        tay
        beq settle              ; el jugador s'ha passat
        inc pl
        jmp turn
final   lda yy
        cmp sc
        beq settle
        bcc settle
        lda #2
        sta gg
        lda yy
        cmp #22
        bcc settle
        inc gg

; ---------- cobrar ----------
settle  ldx gg                  ; mu += gg*tb (amb topall)
        beq +
-       clc
        lda mu
        adc tb
        sta mu
        lda mu+1
        adc tb+1
        sta mu+1
        bcc ++
        lda #$ff
        sta mu
        sta mu+1
++      dex
        bne -
+       jsr clr_top
        lda gg
        bne won
        jsr pmsg
        !byte C_RED|MROW
        !scr "guanya la banca",0
        beq shm                 ; (pmsg torna amb Z=1)
won     jsr pmsg
        !byte C_RED|MROW
        !scr "guanyes ",0
        lda tb
        ldx tb+1
        ldy gg
        cpy #3
        bne +
        asl
        pha
        txa
        rol
        tax
        pla
+       jsr pnum
shm     jsr showmu
        jsr pmsg
        !byte C_PUR|(MROW+2)
        !scr "prem una tecla",0
        jsr getkey
        lda mu
        ora mu+1
        bne +
        jsr cls
        jsr pmsg
        !byte HCOL|C_RED|(MROW+1),(WIDTH-15)/2
        !scr "t'has arruinat!",0
        ldx #D_RUIN
        jsr delay
        jmp restart
+       lda z
        cmp #37
        bcs +
        jmp round
+       jmp shuffle

; =============================================================
;  RUTINES
; =============================================================
showmu  jsr pmsg
        !byte C_GRN|(MROW+1)
        !scr "fitxes: ",0
        lda #RED
        sta curcol
        lda mu
        ldx mu+1
        jmp pnum

takebet clc                     ; tb += be, mu -= be
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
        rts

swap    jsr rand52              ; deck(sidx) <-> deck(atzar)
        tay
        ldx sidx
        lda deck,x
        pha
        lda deck,y
        sta deck,x
        pla
        sta deck,y
        inc sidx
        rts

clrcol  tay                     ; esborra la columna A de la pila
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
        bne drawbox
drawbox sty tbase
        ldy tcol
        jsr setcur
        ldx #0
--      ldy tbase               ; plantilla: 1a fila, mig, ultima
        txa
        beq +
        iny
        iny
        iny
        iny
        cpx #10
        bne +
        iny
        iny
        iny
        iny
+       sty tmp
        lda #GREEN
        sta curcol
        lda tmpl,y
        jsr putc
        ldy tmp
        lda tmpl+3,y
        sta curcol
        lda #5
        sta cnt
-       ldy tmp
        lda tmpl+1,y
        jsr putc
        dec cnt
        bne -
        lda #GREEN
        sta curcol
        ldy tmp
        lda tmpl+2,y
        jsr putc
        lda tcol
        sta cx
        jsr nextrow
        inx
        cpx #11
        bne --
        rts

; ---- carta de cara
draw_card
        ldx #CTOP
        ldy #0
        jsr drawbox
        lda ccol
        sta curcol
        ldx #CTOP+1             ; index de dalt
        ldy tcol
        iny
        jsr setcur
        ldx rank
        cpx #10
        beq +
        lda rankch-1,x
        jsr putc
        jmp ++
+       jsr p10
++      ldx #CTOP+9             ; index de baix
        lda tcol
        clc
        adc #4
        tay
        jsr setcur
        ldx rank
        cpx #10
        beq +
        inc cx
        lda rankch-1,x
        jsr putc
        jmp ++
+       jsr p10
++      ldy suit
        lda suitch,y
        sta key
        ldx #CTOP+2
        ldy #0
        jsr setcur
        ldx rank
        cpx #1
        beq face
        cpx #11
        bcs face
        stx cnt                 ; pips 2..10
        lda pipstart-2,x
        tax
-       lda pipoff,x
        sec
        adc tcol
        tay
        lda key
        sta (sp),y
        lda ccol
        sta (cp),y
        inx
        dec cnt
        bne -
        beq suitidx
face    ldx #0                  ; A J Q K
        lda rank
        cmp #1
        beq +
        sbc #10
        tax
+       lda faceofs,x
        sta tmp
        ldx #CTOP+2
        ldy tcol
        iny
        jsr setcur
        lda #7
        sta cnt
--      ldx #5
-       ldy tmp
        inc tmp
        lda faces,y
        tay
        and #$7f
        bne +
        tya                     ; $00 = pal, $80 = pal invers
        ora key
        tay
+       tya
        jsr putc
        dex
        bne -
        ldy tcol
        iny
        sty cx
        jsr nextrow
        dec cnt
        bne --
suitidx ldx #CTOP+2             ; pal sota l'index
        ldy tcol
        iny
        jsr setcur
        lda key
        jmp putc

p10     lda #$31
        jsr putc
        lda #$30
        jmp putc

; ---- tapet
draw_table
        jsr cls
        lda #BLUE
        sta curcol
        lda #$dc
        ldx #CTOP-4
        ldy #WIDTH*2
        jsr fill
        lda #BLACK
        sta curcol
        ldx #CTOP+4
        jsr fill8
        ldx #CTOP+12
fill8   lda #$ef
        ldy #WIDTH*8
fill    sta fch                 ; X fila, Y quantitat, A caracter
        sty cnt
        ldy #0
        jsr setcur
-       lda fch
        jsr putc
        dec cnt
        bne -
        rts

; ---- pantalla
setcur  lda #0                  ; X fila, Y columna
        sta sp
        sta cp
        lda #>SCREEN
        sta sp+1
        lda #(>SCREEN)+COLOFS
        sta cp+1
        sty cx
        txa
        beq +
-       jsr nextrow
        dex
        bne -
+       rts

nextrow lda sp
        clc
        adc #WIDTH
        sta sp
        sta cp
        bcc +
        inc sp+1
        inc cp+1
+       rts

putc    jsr putc_nc
        inc cx
        rts
putc_nc ldy cx
        sta (sp),y
        lda curcol
        sta (cp),y
        rts

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
;      pmsg_c: text + 0 al cursor. pmsgr: com pmsg i despres salta a result
pmsgr   inc rflag
pmsg    sec
        !byte $24               ; (BIT zp: salta el CLC)
pmsg_c  clc
        pla
        sta mptr
        pla
        sta mptr+1
        bcc pm_lp
        jsr nextb               ; capcalera
        pha
        and #$1f
        tax
        ldy #0
        pla
        pha
        bpl +
        jsr nextb
        tay
+       jsr setcur
        pla
        lsr
        lsr
        lsr
        lsr
        lsr
        and #3
        tax
        lda coltab,x
        sta curcol
pm_lp   jsr nextb
        beq +
        jsr tputc
        jmp pm_lp
+       lda rflag
        beq +
        dec rflag
        jmp result
+       lda mptr+1
        pha
        lda mptr
        pha
        lda #0                  ; Z=1 en tornar
        rts

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

pbyte   ldx #0
pnum    sta num                 ; A baix, X alt
        stx num+1
        lda #0
        pha
-       jsr div10
        ora #$30
        pha
        lda num
        ora num+1
        bne -
-       pla
        beq +
        jsr tputc
        jmp -
+       rts

div10   ldx #16                 ; num /= 10, A = residu
        lda #0
-       asl num
        rol num+1
        rol
        cmp #10
        bcc +
        sbc #10
        inc num
+       dex
        bne -
        rts

; ---- teclat, temps, atzar
getkey  lda #0
        sta NKEYS
-       jsr rnd
        jsr GETIN
        beq -
        and #$7f                ; ignorar SHIFT
        rts

delay                           ; X unitats de 2 jiffies
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

rand52  jsr rnd
        and #$3f
        cmp #52
        bcs rand52
        rts

; =============================================================
;  DADES
; =============================================================
vicini  !byte $06,$16,WIDTH,HEIGHT*2,0,$f0,0,0  ; $9000-$9007 (PAL)
        !byte 0,0,0,0,0,0,5,$1d                 ; $9008-$900f: so, vora verda
coltab  !byte RED,PURPLE,GREEN,BLUE
tmpl    !byte $cf,$f7,$d0,GREEN                 ; cara: dalt
        !byte $f4,$20,$ea,GREEN                 ;       mig
        !byte $cc,$ef,$fa,GREEN                 ;       baix
tb_back !byte $4f,$77,$50,GREEN                 ; dors
        !byte $74,$66,$6a,BLUE
        !byte $4c,$6f,$7a,GREEN
suitch  !byte $41,$53,$58,$5a                   ; piques, cors, trebols, diamants
rankch  !scr "a234567890jqk"
pipstart !byte 0,2,5,9,14,20,27,35,44
pipoff  !byte 1*WIDTH+2,5*WIDTH+2,1*WIDTH+2,3*WIDTH+2,5*WIDTH+2,1*WIDTH+1,1*WIDTH+3,5*WIDTH+1,5*WIDTH+3,1*WIDTH+1,1*WIDTH+3,3*WIDTH+2,5*WIDTH+1,5*WIDTH+3,1*WIDTH+1,1*WIDTH+3,3*WIDTH+1,3*WIDTH+3,5*WIDTH+1,5*WIDTH+3,1*WIDTH+1,1*WIDTH+3,2*WIDTH+2,3*WIDTH+1,3*WIDTH+3,5*WIDTH+1,5*WIDTH+3,1*WIDTH+1,1*WIDTH+3,2*WIDTH+2,3*WIDTH+1,3*WIDTH+3,4*WIDTH+2,5*WIDTH+1,5*WIDTH+3,1*WIDTH+1,1*WIDTH+3,2*WIDTH+1,2*WIDTH+3,3*WIDTH+2,4*WIDTH+1,4*WIDTH+3,5*WIDTH+1,5*WIDTH+3,0*WIDTH+1,0*WIDTH+3,1*WIDTH+2,2*WIDTH+1,2*WIDTH+3,4*WIDTH+1,4*WIDTH+3,5*WIDTH+2,6*WIDTH+1,6*WIDTH+3
faceofs !byte 0,35,70,105
faces   ; A, J, Q, K: 5x7, $00 = pal, $80 = pal invers
	!byte $20,$20,$00,$20,$20
	!byte $20,$6e,$66,$6e,$20
	!byte $20,$66,$20,$66,$20
	!byte $20,$66,$6e,$66,$20
	!byte $20,$66,$20,$66,$20
	!byte $20,$66,$20,$66,$20
	!byte $20,$20,$00,$20,$20
	!byte $20,$20,$6e,$20,$20
	!byte $6e,$66,$66,$66,$6e
	!byte $66,$51,$20,$51,$66
	!byte $66,$20,$20,$20,$66
	!byte $5d,$4a,$43,$61,$5d
	!byte $4a,$72,$43,$72,$61
	!byte $20,$a0,$80,$a0,$20
	!byte $20,$ff,$a0,$7f,$20
	!byte $ff,$ff,$20,$7f,$7f
	!byte $ff,$51,$20,$51,$7f
	!byte $ff,$20,$57,$20,$7f
	!byte $ff,$4a,$43,$61,$7f
	!byte $ff,$4d,$20,$4e,$7f
	!byte $20,$d3,$80,$df,$20
	!byte $df,$df,$df,$df,$df
	!byte $66,$66,$66,$66,$66
	!byte $66,$51,$49,$51,$66
	!byte $66,$20,$6d,$20,$66
	!byte $66,$4a,$43,$61,$66
	!byte $4a,$72,$43,$72,$61
	!byte $6c,$a0,$80,$a0,$7b

deck    = *
end_of_code = deck + 52
!if end_of_code > SCREEN { !error "No hi cap!" }
