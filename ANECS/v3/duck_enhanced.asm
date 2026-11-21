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
ls      = $26            ; inici de la fila actual (2)
tcol    = $28            ; color de text
yy      = $30            ; posicio joystick (2)
score   = $32
cnt     = $33
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
chg     = $55            ; flood fill: s'ha canviat alguna cosa en aquesta passada
wm      = $5b            ; wait: comptador intern
wk      = $5c            ; wait: comptador extern
wn      = $5d            ; wait: n
dvr     = $5e            ; jiffies per unitat de temps (=6*(11-nivell))
RMAP    = $1800          ; mapa d'accessibilitat (512 bytes) = pantalla - $0600
att     = $56            ; intents fallits en triar la posicio de l'ant
lm      = $34            ; temps (unitats) de l'ultim moviment de l'ant lila
mi      = $2c            ; posicio de la tonada
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
    sta seed+1           ; llavor: byte alt no nul (el baix es remena al menu)
    jsr $ffd2            ; bloqueja canvi majuscules/minuscules (A=8)
    ldx #31
-   lda udg,x            ; carrega UDGs
    sta UDG,x
    dex
    bpl -
    lda #0
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
-   inc seed             ; (el temps de reaccio de l'usuari sembra l'atzar)
    ldx $c5              ; espera tecles 1-3-5-7-9 (o 0 = sortir)
    cpx #60
    bne +
    jmp bye
+   inx
    cpx #6
    bcs -
    stx level
    lda #11              ; el temps per ant va de 10 s (nivell 1) a 6 s (nivell 5):
    sec                  ; la finestra segueix sent de 10 unitats (la puntuacio
    sbc level            ; no canvia), pero cada unitat dura (11-nivell)/10 s
    sta tmp
    asl
    adc tmp
    asl
    sta dvr              ; 6*(11-nivell) jiffies per unitat
gen:
    jsr blk              ; pantalla negra (tcol=0): el camp es dibuixa invisible
    lda #$ff
    sta VIC_CHR          ; mode grafic
    lda level
    cmp #2
    bcc cols             ; nivell 1: cap maó
bricks:                  ; maons separats per forats aleatoris (algorisme original)
    lda level
    asl
    asl
    sta tmp
    lda #29
    sec
    sbc tmp
    tax                  ; n = 29-4*nivell
    lda #7
    sec
    sbc level            ; k = 7-nivell
    jsr rr
    sta m
    clc
    adc #7               ; z+m>505  <=>  cur+m >= $1ff9
    adc cur
    lda cur+1
    adc #$e0
    bcs cols
    lda m                ; salta m caselles (ja son buides) i posa un maó
    clc
    adc cur
    sta cur
    bcc +
    inc cur+1
+   lda #BRICK
    jsr cputc
    jmp bricks
cols:
    jsr home             ; columnes esquerra i dreta
    ldx #22
-   jsr nl
    lda #BRICK
    ldy #0
    sta (cur),y
    ldy #21
    sta (cur),y
    dex
    bne -
    lda #RSP             ; el punt de mira inicial no pot tenir cap maó a sobre
    sta $1f1f
    sta $1f20
    sta $1f35
    sta $1f36
    lda #15
    sta VIC_VOL
    lda #$1f
    sta peep
    sta peep+1           ; peephole = $1f1f
    sta yy
    sta yy+1
    jsr flood            ; mida de la zona on arriba el punt de mira
    bcs +
    jmp gen              ; massa petita: es torna a generar (sense mostrar-ho)
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
    lda #0
    sta att              ; intents fallits d'aquest ant
    sta mi               ; la tonada comenca des del principi
    sta lm
pick:
    jsr rdl              ; casella a l'atzar de 0..511 (es descarten les
    sta duckp            ; que no serveixen)
    jsr rdl
    and #1
    ora #$1e
    sta duckp+1
    lda duckp            ; l'ant ha de ser a la zona accessible (lliure de maons)
    ldx duckp+1
    jsr mchk
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
.c  lda level            ; distancia minima = 16*nivell - intents fallits
    asl
    asl
    asl
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
    lda #0
    sta $900c            ; calla la tonada
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

; ---------- sortir: credits que s'esbaeixen i reset ----------
bye:
    jsr blk              ; pantalla negra
    lda #1
    ldx #cred-strs
    jsr pr               ; text blanc centrat
    ldx #64
.rd lda #40            ; el text es queda fix uns 7 s
    jsr wait
    dex
    bne .rd
    lda #0
    sta cnt
.bf ldx #2
.bs jsr rdl              ; esborra (color negre) una casella a l'atzar del text
    and #63
    clc
    adc #$dc
    sta cp
    lda #$96
    adc #0
    sta cp+1
    lda #0
    tay
    sta (cp),y
    dex
    bne .bs
    jsr rdl              ; guspira: una estrella de color en una casella qualsevol
    sta bp
    jsr rdl
    and #1
    ora #$1e
    sta bp+1
    lda #$2a
    sta (bp),y
    lda bp+1
    clc
    adc #$78
    sta bp+1
    jsr rdl
    and #7
    sta (bp),y
    lda #5
    jsr wait             ; ~1/60 s per fotograma
    inc cnt
    lda cnt
    cmp #230
    bcc .bf
    jmp $fd22            ; reset del VIC

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

; ---------- random ----------
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
rr:                      ; A=k, X=n -> A uniforme en [k..n] (xorshift)
    sta tmp
    stx tmp2
-   jsr rdl
    and #31
    cmp tmp
    bcc -
    cmp tmp2
    beq +
    bcs -
+   rts

; ---------- pantalla / cursor ----------
blk:                     ; pantalla negra amb espais inversos; text en color 0
    ldx #0
-   lda #RSP
    sta $1e00,x
    sta $1f00,x
    lda #0
    sta $9600,x
    sta $9700,x
    dex
    bne -
    sta tcol
home:
    lda #0
gx:                      ; cursor a (A,0)
    sta cur
    sta ls
    lda #$1e
    sta cur+1
    sta ls+1
    rts

nl:                      ; cursor a l'inici de la fila seguent
    lda ls
    clc
    adc #22
    sta ls
    sta cur
    lda ls+1
    adc #0
    sta ls+1
    sta cur+1
    rts

; ---------- espera: A=n (n * 255 iteracions de 13 cicles) ----------
wait:                    ; A=n. Mateixos cicles que el KickC original (la vibracio en depen)
    sta wn
    lda #0
    sta wk
-   lda #0
    sta wm
--  inc wm
    lda wm
    cmp #$ff
    bcc --
    inc wk
    lda wk
    cmp wn
    bcc -
    rts
!if (wait & $ff) != $ed {
    !error "wait ha de comencar a $xxED"
}

; ---------- un fotograma del joc ----------
fr:
    jsr mv
    ldx mi               ; sona la tonada (una nota per fotograma)
    lda tune,x
    sta $900c
    inx
    txa
    and #31
    sta mi
    jsr $ffde            ; llegeix cronometre: A=lsb X=mid (jiffies)
    ldy #$ff
-   iny                  ; Y = jiffies / dvr (unitats de temps)
    sec
    sbc dvr
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
    sta jm+2
    sta jm+3
    lda #$7f
    sta $9122
    lda $9120
    sta jm+1
    lda #$ff
    sta $9122
    ldx #3               ; esquerra, dreta, amunt, avall
.j  lda jm,x
    and jk,x
    bne +
    lda yy
    clc
    adc jl,x
    sta yy
    lda yy+1
    adc jh,x
    sta yy+1
+   dex
    bpl .j
    lda #$20             ; foc
    and jm
    bne +
    jsr fire
+
    lda yy               ; nomes es mou a una posicio del mapa d'accessibilitat
    ldx yy+1
    jsr mchk
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
    lda #4               ; ant lila
    ldx #3
    jsr d4               ; dibuixa l'ant
    lda #15
    jmp wait

mv:                      ; l'ant es mou 1 casella (8 direccions), entre 1 i 2 unitats de temps
    lda tm
    sec
    sbc lm
    cmp #1
    bcc .mr              ; menys d'1: es queda
    cmp #2
    bcs .mg              ; 2 o mes: es mou si o si
    jsr rdl
    and #3
    bne .mr              ; entre 1 i 2: 1 de cada 4 fotogrames
.mg jsr rdl
    and #7
    tax                  ; direccio: 4 ortogonals i 4 diagonals
    lda duckp
    clc
    adc jl,x
    sta rp
    lda duckp+1
    adc jh,x
    sta rp+1
    lda rp
    ldx rp+1
    jsr mchk             ; mapa d'accessibilitat: lliure de maons i dins del camp?
    beq .mr
    lda #0
    ldx #3
    jsr d4               ; esborra l'ant
    lda rp
    sta duckp
    lda rp+1
    sta duckp+1
    lda tm
    sta lm
.mr rts

mchk:                    ; A=lo, X=hi d'una posicio de pantalla -> A=mapa (0 = no valida)
    sta fp
    txa
    sec
    sbc #6
    sta fp+1
    ldy #0
    lda (fp),y
    rts

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
    lda level            ; encert: guany = nivell+6-temps (x3 amb l'ant lila)
    clc
    adc #6
    sec
    sbc tm
    beq .k1
    bmi .k1
    jsr x3
    clc
    adc score
    sbc #0
    sta score
.k1 jsr wscore
    inc score
    lda #99
    sta tm
    bne .common
.fail
    lda level            ; fallada: nivell-6 (x3 amb l'ant lila)
    sec
    sbc #6
    jsr x3
    clc
    adc score
    sta score
    jsr wscore
.common
    lda #0
    sta cnt
.sh lda #1               ; tremolor de pantalla (mateixos cicles que l'original)
    ldx #40
    jsr random
    lda m
    clc
    adc #18
    sta tmp
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

x3:                      ; A -> 3*A (tots els ants son lilas)
    sta tmp
    asl
    clc
    adc tmp
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
    lda #BRICK
    ldx #3
-   ldy offs,x           ; el 2x2 ha d'estar lliure de maons
    cmp (fp),y
    beq .next
    dex
    bpl -
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
    lda level            ; llindar = 16*nivell
    asl
    asl
    asl
    asl
    sta tmp
    lda rc
    cmp tmp              ; carry=1 si hi ha prou caselles accessibles
    rts

noff:   !byte 0,21,23,44 ; -22, -1, +1, +22 respecte a p-22

random:                  ; A=k, X=n -> m en [k..n]; clon del KickC original (timers)
    sta tmp
    stx tmp2
-   lda $9114
    clc
    adc $9119
    sta m
    cmp tmp
    bcc -
    lda tmp2
    cmp m
    bcc -
    rts

cputc:                   ; A=caracter amb color tcol; cursor++
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
    inc cur
    bne .rt
    inc cur+1
.rt rts

pr:                      ; A=color, X=index a strs ($c0+n = n salts de linia)
    sta tcol
-   lda strs,x
    beq .rt
    cmp #$c0
    bcc .pc
    and #$1f
    sta tmp
.pn jsr nl
    dec tmp
    bne .pn
    beq .pi
.pc jsr cputc
.pi inx
    bne -
    rts

; ---------- dades ----------
offs:   !byte 0,1,22,23,0,1,22,23
tune:   !byte $d3,$d3,$d3,$d3,$d3,0,$d3,$d3,$d3,$d3,$d3,0,$da,$da,$de,$de
        !byte $d3,$d3,$d3,$d3,$d3,0,$d3,$d3,$d3,$d3,$d3,0,$cd,$cd,$d0,$d0
jk:     !byte $10,$80,$04,$08    ; mascares: esquerra, dreta, amunt, avall
jl:     !byte $ff,1,$ea,22,$e9,$eb,21,23       ; increments (baix)
jh:     !byte $ff,0,$ff,0,$ff,$ff,0,0        ; increments (alt)
chars:  !byte 0,1,2,3,$fd,$ed,$ee,$f0
udg:    !byte $0e,$1b,$3f,$1f,$0f,$07,$0f,$1f
        !byte $00,$00,$00,$00,$00,$c0,$70,$bc
        !byte $1f,$1d,$1e,$0f,$03,$01,$01,$03
        !byte $ce,$1e,$7c,$f8,$e0,$40,$40,$e0
strs:
duck_s: !byte $84,$95,$83,$8b,$ba,$a0,$a0,0           ; "DUCK:  "
pts_s:  !byte $90,$94,$93,$ba,$b0,$b0,$b0,$b0,0       ; "PTS:0000"
chrono: !byte $94,$8d,$ba,$b9,0                       ; "TM:9"
intro:  !byte $c0+3
        !scr "difficulty"
        !byte $c0+1
        !scr "----------"
        !byte 0
levels: !byte $c0+3
        !scr "1.easiest"
        !byte $c0+2
        !scr "3.easy"
        !byte $c0+2
        !scr "5.medium"
        !byte $c0+2
        !scr "7.hard"
        !byte $c0+2
        !scr "9.expert"
        !byte $c0+2
        !scr "0.exit"
        !byte 0
foot:   !byte $c0+4
        !scr "press: 1,3,5,7 or 9"
        !byte 0
cred:   !byte $c0+10
        !scr "  (c)jimsoft - 2026"
        !byte $c0+2
        !scr "    thanks claude!"
        !byte 0
gameover: !byte $c0+4
        !scr "game over"
        !byte 0
again:  !byte $c0+6
        !scr "play again (y/n)?"
        !byte 0
yscore: !byte $c0+4
        !scr "your score:"
        !byte 0
hscore: !byte $c0+2
        !scr "high score:"
        !byte 0
