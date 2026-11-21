; ============================================================
; PATOS - VIC-20 unexpanded - versio optimitzada a ma (ACME)
; Ensamblar:  acme -f cbm -o patos_opt.prg patos_opt.asm
; ============================================================
!cpu 6502

; --- constants ---
SCR     = $1e00          ; pantalla
UDG     = $1c00          ; caracters definits (8 x 4)
BRICK   = $e6
RSP     = $a0            ; espai invers
NL      = $cd            ; "\n" en screen codes (com el KickC)

VIC_CHR = $9005
VIC_BORD= $900f
VIC_VOL = $900e
VIC_NOI = $900d
VIC_VPOS= $9001

; --- pagina zero ---
cur     = $fb            ; punter pantalla (2)
bp      = $fd            ; punter auxiliar d4 (2)
cp      = $22            ; punter color (2)
curx    = $21
tcol    = $28            ; color de text
yy      = $30            ; posicio joystick (2)
score   = $32
cnt     = $33
dum     = $34
pts     = $36            ; 2 digits (chars) de la puntuacio
m       = $38
tmp     = $2d
tmp2    = $2e
Z       = $3d            ; base: duckp = Z+3, peep = Z+7 (d4 indexa per X)
duckp   = $40            ; 2
peep    = $44            ; 2
level   = $64
tm      = $6d
hisc    = $6f
dnum    = $70
jm      = $71
fp      = $50            ; flood fill: punter a pantalla (2)
rp      = $52            ; flood fill: punter al mapa d'accessibilitat (2)
rc      = $54            ; flood fill: caselles accessibles (saturat a 255)
att     = $56            ; candidats que queden per mirar per a l'ant
bestd   = $57            ; millor distancia fins ara
bestp   = $58            ; millor candidat fins ara (2)
chg     = $55           ; flood fill: s'ha canviat alguna cosa en aquesta passada
RMAP    = $1800          ; mapa d'accessibilitat (512 bytes) = pantalla - $0600
MINREACH = 32            ; si hi ha menys caselles accessibles, es regeneren els maons

; --- capcalera BASIC: 10 SYS4109 ---
*= $1001
!word nextline
!word 10
!byte $9e
!text "4109"
!byte 0
nextline !word 0
; el codi comença a $100d = 4109

start:
    lda #8
    sta VIC_BORD         ; vora i paper negres
    jsr $ffd2            ; bloqueja canvi majuscules/minuscules (A=8)
    ldx #31
-   lda udg,x            ; carrega UDGs
    sta UDG,x
    dex
    bpl -
    lda #0
    sta yy
    sta yy+1
    sta hisc

game:
    jsr blk
    lda #7
    ldx #intro-strs
    jsr pr
    lda #1
    ldx #levels-strs
    jsr pr
    lda #2
    ldx #foot-strs
    jsr pr
-   ldx $c5              ; espera tecles 1-3-5-7-9
    inx
    cpx #6
    bcs -
    stx level
gen:
    jsr blk
    lda #$ff
    sta VIC_CHR          ; mode grafic
                         ; (el camp es dibuixa en negre sobre negre: invisible
                         ;  fins que se sap que es bo; vegeu recolor)
    lda level
    cmp #2
    bcc cols
bricks:
    lda level
    asl
    asl
    sta tmp
    lda #29
    sec
    sbc tmp
    tax                  ; n = 29-4*level
    lda #7
    sec
    sbc level            ; k = 7-level
    jsr random
    sta m
    clc
    adc #7               ; z+m>505  <=>  cur+m >= $1ff9
    adc cur
    lda cur+1
    adc #$e0
    bcs cols
    ldx m
-   lda #RSP
    jsr cputc
    dex
    bne -
    lda #BRICK
    jsr cputc
    jmp bricks
cols:
    jsr home             ; columnes esquerra i dreta
    lda #NL
    jsr cputc
    ldx #22
-   lda #BRICK
    jsr cputc
    lda #20
    jsr adv
    lda #BRICK
    jsr cputc
    dex
    bne -
    lda #15
    sta VIC_VOL
    lda #$1f
    sta peep
    sta peep+1           ; peephole = $1f1f
    jsr flood            ; zona on arriba el punt de mira
    bcs +
    jmp gen              ; massa petita: es tornen a generar els maons
+   jsr recolor          ; ara si: es mostren els maons en vermell
    lda #10
    sta score
    lda #1
    sta dnum
    jsr home
    lda #7
    ldx #pts_s-strs
    jsr pr
    jsr wscore
    lda #18
    jsr gx
    lda #7
    ldx #chrono-strs
    jsr pr
    lda #10
    jsr gx
    lda #5
    ldx #duck_s-strs
    jsr pr

nextduck:
    lda dnum             ; numero d'ant (1..10)
    cmp #10
    bcc +
    ldx #$b0
    stx $1e10
    lda #1
+   ora #$b0
    sta $1e0f
    lda level
    asl
    sbc #0               ; (carry net) 2*nivell-1 candidats
    sta att
    lda #0
    sta bestd
pick:
    jsr rd
    sta tmp
    jsr rd
    clc
    adc tmp
    ldy #$1e
    bcc +
    iny
+   clc
    adc #$15
    sta duckp
    bcc +
    iny
+   sty duckp+1
    cpy #$20
    bcs pick
    cpy #$1f
    bne +
    lda duckp
    cmp #$e4
    bcs pick
+   ldy #0
    lda #BRICK
    cmp (duckp),y
    beq pick
    iny
    cmp (duckp),y
    beq pick
    ldy #22
    cmp (duckp),y
    beq pick
    iny
    cmp (duckp),y
    beq pick
    lda duckp            ; l'ant ha d'estar en una casella accessible
    sta bp
    lda duckp+1
    sec
    sbc #6
    sta bp+1
    ldy #0
    lda (bp),y
    beq pick
    ; Dificultat: es miren 2*nivell-1 candidats valids i es tria el mes lluny
    ; (distancia manhattan) del punt de mira. Nivell 1 = un sol candidat (atzar).
    lda duckp
    ldx duckp+1
    jsr rowcol
    sta tmp              ; columna de l'ant
    stx tmp2             ; fila de l'ant
    lda peep
    ldx peep+1
    jsr rowcol           ; A=columna, X=fila del punt de mira
    sec
    sbc tmp
    bcs +
    eor #$ff
    adc #1
+   sta tmp              ; |dc|
    txa
    sec
    sbc tmp2
    bcs +
    eor #$ff
    adc #1
+   clc
    adc tmp              ; A = |dc| + |df|
    cmp bestd
    bcc +                ; no millora el millor candidat
    sta bestd
    lda duckp
    sta bestp
    lda duckp+1
    sta bestp+1
+   dec att
    beq .dok
    jmp pick             ; encara falten candidats
.dok
    lda bestp
    sta duckp
    lda bestp+1
    sta duckp+1
    lda #0
    sta tm
    tax
    tay
    jsr $ffdb            ; reinicia el cronometre
-   jsr fr
    lda tm
    cmp #10
    bcc -
    inc dnum
    dec score
    jsr wscore
    lda #$82
    sta VIC_NOI
    lda #42
    jsr wait
    lda #0
    sta VIC_NOI
    ldx #3
    jsr d4               ; esborra l'ant (A=0)
    lda dnum
    cmp #11
    bcs over
    jmp nextduck

over:
    jsr blk
    lda #240
    sta VIC_CHR          ; torna al mode text
    lda #7
    ldx #gameover-strs
    jsr pr
    lda #2
    ldx #yscore-strs
    jsr pr
    lda pts
    jsr cputc
    lda pts+1
    jsr cputc
    lda #$30
    jsr cputc
    lda #3
    ldx #hscore-strs
    jsr pr
    lda score
    cmp hisc
    bcc +
    sta hisc
+   lda hisc
    jsr d10
    pha
    cpx #$30
    beq +
    txa
    jsr cputc
+   pla
    ora #$30
    jsr cputc
    lda #$30
    jsr cputc
    lda #1
    ldx #again-strs
    jsr pr
-   ldx $c5              ; espera Y o N
    cpx #11
    bne +
    jmp game
+   cpx #28
    bne -
    jmp $fd22            ; reset del VIC

; ---------- un fotograma del joc ----------
fr:
    jsr $ffde            ; llegeix cronometre: A=lsb X=mid (jiffies)
    ldy #$ff
-   iny                  ; Y = jiffies / 60 (segons)
    sec
    sbc #60
    bcs -
    dex
    bpl -
    sty tm
    cpy #10
    bcs +
    lda #$b9
    sec
    sbc tm
    sta $1e15
+   lda $911f            ; joystick
    sta jm
    lda #$7f
    sta $9122
    ldx $9120
    lda #$ff
    sta $9122
    lda #16              ; esquerra
    and jm
    bne +
    lda yy
    bne ++
    dec yy+1
++  dec yy
+   txa                  ; dreta
    bmi +
    inc yy
    bne +
    inc yy+1
+   lda #4               ; amunt
    and jm
    bne +
    lda yy
    sec
    sbc #22
    sta yy
    lda yy+1
    sbc #0
    sta yy+1
+   lda #8               ; avall
    and jm
    bne +
    lda yy
    clc
    adc #22
    sta yy
    bcc +
    inc yy+1
+   lda #$20             ; foc
    and jm
    bne +
    jsr fire
+   lda yy               ; y dins de [$1e17,$1fe2] ?
    sec
    sbc #$17
    lda yy+1
    sbc #$1e
    bcc .nomv
    lda yy
    cmp #$e3
    lda yy+1
    sbc #$1f
    bcs .nomv
    ldy #0               ; cap maó sota el peephole?
    lda #BRICK
    cmp (yy),y
    beq .nomv
    iny
    cmp (yy),y
    beq .nomv
    ldy #22
    cmp (yy),y
    beq .nomv
    iny
    cmp (yy),y
    beq .nomv
    lda #0               ; esborra peephole vell i mou
    ldx #7
    jsr d4
    lda yy
    sta peep
    lda yy+1
    sta peep+1
.nomv
    lda peep             ; y = peephole
    sta yy
    lda peep+1
    sta yy+1
    lda #1
    ldx #7
    jsr d4               ; dibuixa peephole
    lda #15
    jsr wait
    lda #7
    ldx #3
    jsr d4               ; dibuixa l'ant
    lda #15
    jmp wait

; ---------- disparar ----------
fire:
    lda #$82
    sta VIC_NOI
    lda peep
    cmp duckp
    bne .fail
    lda peep+1
    cmp duckp+1
    bne .fail
    lda score            ; encert
    clc
    adc level
    adc #6
    sec
    sbc tm
    cmp score
    beq .k1
    bcc .k1
    sbc #1
    sta score
.k1 jsr wscore
    inc score
    lda #99
    sta tm
    bne .common
.fail
    lda score            ; fallada
    clc
    adc level
    sec
    sbc #6
    sta score
    jsr wscore
.common
    lda #0
    sta cnt
.sh lda #1               ; tremolor de pantalla
    ldx #40
    jsr random
    clc
    adc #18
    sta VIC_VPOS
    lda #5
    jsr wait
    inc cnt
    lda cnt
    cmp #50
    bcc .sh
    lda #38
    sta VIC_VPOS
    lda #126
    jsr wait
    lda #0
    sta VIC_NOI
    rts

; ---------- dibuixa 4 caselles: A=color, X=3 (ant) o 7 (peephole) ----------
d4:
    sta tmp
    lda Z,x
    sta bp
    sta cp
    lda Z+1,x
    sta bp+1
    clc
    adc #$78
    sta cp+1
-   ldy offs,x
    lda chars,x
    sta (bp),y
    lda tmp
    sta (cp),y
    dex
    bmi +
    cpx #3
    bne -
+   rts

; ---------- fila i columna d'una adreça de pantalla ----------
rowcol:                  ; A=lo, X=hi  ->  X=fila, A=columna
    sta bp
    txa
    sec
    sbc #$1e
    sta bp+1
    ldx #$ff
-   inx
    lda bp
    sec
    sbc #22
    sta bp
    lda bp+1
    sbc #0
    sta bp+1
    bcs -
    lda bp
    clc
    adc #22
    rts

; ---------- pinta de vermell els maons (el camp es dibuixa invisible) ----------
recolor:
    ldy #0
-   lda SCR,y
    cmp #BRICK
    bne +
    lda #2
    sta $9600,y
+   lda SCR+$100,y
    cmp #BRICK
    bne +
    lda #2
    sta $9700,y
+   iny
    bne -
    rts

; ---------- accessibilitat del punt de mira ----------
; Marca a RMAP (pantalla-$0600) totes les posicions del peephole (2x2 sense
; maons, dins del rang que permet el joc) a les quals es pot arribar des de
; la posicio inicial amb moviments esquerra/dreta/amunt/avall (sense diagonals).
; Sortida: carry=1 si hi ha prou caselles accessibles (>= MINREACH).
flood:
    lda #0
    tay
-   sta RMAP,y
    sta RMAP+$100,y
    iny
    bne -
    sta rc
    lda #1
    sta RMAP+$11f        ; llavor: $1f1f - $0600
.pass
    lda #0
    sta chg
    lda #$17
    sta fp
    lda #$1e
    sta fp+1             ; fp = $1e17 (primera posicio valida)
.cell
    lda fp               ; rp = fp - $0600 - 22  (apunta a R[p-22])
    sec
    sbc #22
    sta rp
    lda fp+1
    sbc #6
    sta rp+1
    ldy #22
    lda (rp),y
    bne .next            ; ja accessible
    ldy #0
    lda #BRICK
    cmp (fp),y           ; el 2x2 ha d'estar lliure de maons
    beq .next
    iny
    cmp (fp),y
    beq .next
    ldy #22
    cmp (fp),y
    beq .next
    iny
    cmp (fp),y
    beq .next
    ldx #3               ; algun veí (esq, dre, amunt, avall) accessible?
-   ldy noff,x
    lda (rp),y
    bne .found
    dex
    bpl -
    bmi .next
.found
    ldy #22
    lda #1
    sta (rp),y
    sta chg
    inc rc
    bne .next
    dec rc               ; saturat a 255
.next
    inc fp
    bne +
    inc fp+1
+   lda fp
    cmp #$e3             ; fi: fp = $1fe3
    bne .cell
    lda fp+1
    cmp #$1f
    bne .cell
    lda chg
    bne .pass
    lda rc
    cmp #MINREACH        ; carry=1 si rc >= MINREACH
    rts

noff:   !byte 0,21,23,44 ; -22, -1, +1, +22 respecte a p-22

; ---------- puntuacio ----------
wscore:
    lda score
    cmp #100
    bcc +
    lda #0
    sta score
+   jsr d10
    ora #$30
    sta pts+1
    ora #$80
    sta $1e06
    stx pts
    txa
    ora #$80
    sta $1e05
    rts

d10:                     ; A -> X=char desena, A=unitats
    ldx #$30
-   cmp #10
    bcc +
    sbc #10
    inx
    bne -
+   rts

; ---------- espera: A=n (n * 255 iteracions de 13 cicles) ----------
wait:
    tay
-   ldx #255
--  inc dum
    bit dum
    dex
    bne --
    dey
    bne -
    rts

; ---------- random ----------
rd:
    lda $9114
    clc
    adc $9119
    rts
random:                  ; A=k, X=n -> A en [k..n]
    sta tmp
    stx tmp2
-   jsr rd
    cmp tmp
    bcc -
    cmp tmp2
    beq +
    bcs -
+   rts

; ---------- pantalla / cursor ----------
blk:
    lda #0
    sta tcol
    jsr home
    ldx #253
-   lda #RSP
    jsr cputc
    lda #RSP
    jsr cputc
    dex
    bne -
    rts

gx:                      ; cursor a (A,0)
    tax
    jsr home
    stx cur
    stx curx
    rts

adv:                     ; cur += A, curx += A
    tay
    clc
    adc curx
    sta curx
    tya
    clc
    adc cur
    sta cur
    bcc +
    inc cur+1
+   rts

cputc:
    cmp #NL
    beq .nl
    ldy #0
    sta (cur),y
    lda cur
    sta cp
    lda cur+1
    clc
    adc #$78
    sta cp+1
    lda tcol
    sta (cp),y
    lda #1
    jsr adv
    lda curx
    cmp #22
    bne .rt
    beq .fin
.nl lda #22
    sec
    sbc curx
    jsr adv
.fin
    lda #0
    sta curx
    lda cur
    cmp #$fa
    bne .rt
    lda cur+1
    cmp #$1f
    bne .rt
home:                    ; cursor a (0,0)
    lda #0
    sta curx
    sta cur
    lda #$1e
    sta cur+1
.rt rts

pr:                      ; A=color, X=index a strs
    sta tcol
-   lda strs,x
    beq +
    jsr cputc
    inx
    bne -
+   rts

; ---------- dades ----------
offs:   !byte 0,1,22,23,0,1,22,23
chars:  !byte 0,1,2,3,$fd,$ed,$ee,$f0
udg:    !byte $0e,$1b,$3f,$1f,$0f,$07,$0f,$1f
        !byte $00,$00,$00,$00,$00,$c0,$70,$bc
        !byte $1f,$1d,$1e,$0f,$03,$01,$01,$03
        !byte $ce,$1e,$7c,$f8,$e0,$40,$40,$e0
strs:
duck_s: !byte $84,$95,$83,$8b,$ba,$a0,$a0,0           ; "DUCK:  "
pts_s:  !byte $90,$94,$93,$ba,$b0,$b0,$b0,$b0,0       ; "PTS:0000"
chrono: !byte $94,$8d,$ba,$b9,0                       ; "TM:9"
intro:  !byte NL,NL,NL
        !scr "difficulty"
        !byte NL
        !scr "----------"
        !byte 0
levels: !byte NL,NL,NL
        !scr "1.easiest"
        !byte NL,NL
        !scr "3.easy"
        !byte NL,NL
        !scr "5.medium"
        !byte NL,NL
        !scr "7.hard"
        !byte NL,NL
        !scr "9.expert"
        !byte 0
foot:   !byte NL,NL,NL,NL,NL,NL
        !scr "press: 1,3,5,7 or 9"
        !byte 0
gameover: !byte NL,NL,NL,NL
        !scr "game over"
        !byte 0
again:  !byte NL,NL,NL,NL,NL,NL
        !scr "play again (y/n)?"
        !byte 0
yscore: !byte NL,NL,NL,NL
        !scr "your score:"
        !byte 0
hscore: !byte NL,NL
        !scr "high score:"
        !byte 0
