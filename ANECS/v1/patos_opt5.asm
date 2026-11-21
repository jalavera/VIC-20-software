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
gw      = $50            ; amplada del forat de les parets
gp      = $51            ; primera columna del forat
ge      = $52            ; primera columna despres del forat
rw      = $53            ; fila que es dibuixa
att     = $56            ; intents fallits en triar la posicio de l'ant
seed    = $59            ; llavor del generador pseudoaleatori (2)

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
    lda #$e1
    sta seed
    lda #$ac
    sta seed+1

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
-   inc seed             ; (el temps de reaccio de l'usuari sembra l'atzar)
    ldx $c5              ; espera tecles 1-3-5-7-9
    inx
    cpx #6
    bcs -
    stx level
    jsr blk
    lda #$ff
    sta VIC_CHR          ; mode grafic
    lda #2
    sta tcol
    jsr home
    lda #NL
    jsr cputc            ; cursor a la fila 1 (la 0 es el marcador)
    lda #12
    sec
    sbc level
    sbc level
    sta gw               ; forat de 12-2*nivell caselles
    lda #1
    sta rw
.row
    ldy #1               ; fila lliure: nomes les columnes 0 i 21
    sty gp
    ldy #21
    sty ge
    lda rw
    and #3
    bne .go              ; parets a les files 4,8,12,16,20 ...
    lda level
    cmp #2
    bcc .go              ; ... excepte al nivell 1
-   jsr rdl              ; forat [g, g+gw) amb g aleatori dins la fila
    and #31
    beq -
    sta gp
    clc
    adc gw
    cmp #22
    bcs -
    sta ge
    lda rw
    and #4
    beq .r
    lda ge
    cmp #12              ; parets 4,12,20: forat a l'esquerra
    bcs -
    bcc .go
.r  lda gp
    cmp #10              ; parets 8,16: forat a la dreta
    bcc -
.go ldx #0
.cell
    lda #BRICK
    cpx gp
    bcc +
    cpx ge
    bcs +
    lda #RSP
+   jsr cputc
    inx
    cpx #22
    bne .cell
    inc rw
    lda rw
    cmp #23
    bne .row
    lda #15
    sta VIC_VOL
    lda #$1f
    sta peep
    sta peep+1           ; peephole = $1f1f
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
    lda #0
    sta att              ; intents fallits d'aquest ant
pick:
    jsr rdl              ; casella a l'atzar de 0..511 (es descarten les
    sta duckp            ; que no serveixen)
    jsr rdl
    and #1
    ora #$1e
    sta duckp+1
    lsr                  ; dins del rang del punt de mira: $1e17..$1fe2
    lda duckp
    bcs +
    cmp #$17
    bcc pick
    bcs ++
+   cmp #$e3
    bcs pick
++  ldy #0
    lda #BRICK
    cmp (duckp),y        ; el 2x2 ha d'estar lliure de maons
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
    lda duckp            ; |ant - punt de mira| en caselles
    sec
    sbc peep
    tax
    lda duckp+1
    sbc peep+1
    beq .c
    cmp #$ff
    bne .dok             ; mes de 256: prou lluny
    txa
    eor #$ff
    clc
    adc #1
    tax
.c  lda level            ; distancia minima = 24*nivell - intents fallits
    asl
    asl
    asl
    sta tmp
    asl
    clc
    adc tmp
    sec
    sbc att
    bcc .dok
    sta tmp
    cpx tmp
    bcs .dok
    inc att
    jmp pick
.dok
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
rd:                      ; A = suma dels dos timers (original; tremolor)
    lda $9114
    clc
    adc $9119
    rts

rdl:                     ; A = byte pseudoaleatori (xorshift de 16 bits; X,Y intactes)
    lda seed+1
    lsr
    lda seed
    ror
    eor seed+1
    sta seed+1
    ror
    eor seed
    sta seed
    eor seed+1
    sta seed+1
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
