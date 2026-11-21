; ============================================================
; PATOS - VIC-20 unexpanded - versio optimitzada a ma (ACME)
; Ensamblar:  acme -f cbm -o patos_opt.prg patos_opt.asm
; ============================================================
!cpu 6502

; --- constants ---
COLS    = 24             ; pantalla ampliada: 24 columnes x 28 files = 672 caselles
ROWS    = 28
XORG    = 10              ; origen horitzontal VIC (PAL: 12 per defecte, -2 per les 2 columnes de mes: simetric)
YORG    = 28             ; origen vertical VIC (PAL: 38 per defecte, -10 per les 5 files de mes: simetric)
SCR     = $1c00          ; pantalla (1 K: $1c00-$1fff); color a $9400
UDG     = $1f00          ; caracters 96..99 definits aqui (cua de la pantalla, no es veu)
CH0     = 96             ; primer codi d'UDG ($1c00 + 96*8 = $1f00)
P0      = SCR+14*COLS+1  ; posicio inicial del punt de mira (meitat d'alcada, vora l'esquerra)
BRICK   = $e6
RSP     = $a0            ; espai invers
NCELL   = COLS*ROWS
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
RMAP    = $9400          ; mapa temporal del flood: 1 byte/casella, dins la RAM de color (nomes mentre es genera)
MAPB    = $1f20          ; mapa d'accessibilitat definitiu: 1 bit/casella (128 bytes, a la cua de la pantalla)
att     = $56            ; intents fallits en triar la posicio de l'ant
lm      = $34            ; temps (unitats) de l'ultim moviment de l'ant lila
mus     = $29            ; musica activa (1) o en pausa (0)
rtk     = $2a            ; musica: tics que queden de la fila (4 o 5)
rw      = $2b            ; musica: fila dins del compas (0..19)
br      = $2c            ; musica: compas dins la canco
sch     = $35            ; puntuacio: byte alt (0..999)
ph      = $3a            ; centenes (char) de la puntuacio a mostrar
hisc2   = $6e            ; record: byte alt
seed    = $59            ; llavor del generador pseudoaleatori (2)
ar      = $62            ; musica: pas de l'arpegi (0..2)
vp      = $46            ; musica: (2) desplacament dins dels patrons: 0 = baix, 1 = solista
vd      = $48            ; (2) files que queden de la nota
vn      = $4a            ; (2) nota actual (0 = silenci)
va      = $4c            ; (2) edat de la nota en tics
broot   = $4e            ; transposicio del baix
lroot   = $4f            ; transposicio del solista
cb      = $3e            ; acord: index de l'arpegi (0,3,6)
fl      = $3f            ; bit0 = solista, bit1 = arpegi
dpo     = $42            ; patro de bateria (desplacament)
dix     = $43            ; punter a la sequencia de soroll del cop de bateria
et      = $65            ; posicio d'escriptura del buffer d'eco
EBUF    = $1fa0          ; buffer d'eco (16 bytes, cua de la pantalla)
wd      = $3b            ; amplada de fila de la pantalla actual (22 text, COLS joc)
it      = $63            ; musica: temporal de la rutina d'interrupcio

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
    jsr txt              ; geometria de text (22x23) a $1c00
    ldx #31
-   lda udg,x            ; carrega UDGs
    sta UDG,x
    dex
    bpl -
    lda #0
    sta hisc
    sta hisc2
    sta mus
    sei                  ; la musica va per interrupcions (50/60 Hz)
    lda #<irq
    sta $0314
    lda #>irq
    sta $0315
    cli

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
    jsr gam              ; pantalla de joc ampliada (24x28)
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
    adc #<($10000-(SCR+NCELL-1))   ; z+m>=NCELL-1  <=>  cur+m >= SCR+NCELL-1
    adc cur
    lda cur+1
    adc #>($10000-(SCR+NCELL-1))
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
    ldx #ROWS-1
-   jsr nl
    lda #BRICK
    ldy #0
    sta (cur),y
    ldy #COLS-1
    sta (cur),y
    dex
    bne -
    lda #RSP             ; el punt de mira inicial no pot tenir cap maó a sobre
    sta P0
    sta P0+1
    sta P0+COLS
    sta P0+COLS+1
    lda #15
    sta VIC_VOL
    lda #<P0
    sta peep
    sta yy
    lda #>P0
    sta peep+1           ; peephole = P0
    sta yy+1
    jsr flood            ; mida de la zona on arriba el punt de mira
    bcs +
    jmp gen              ; massa petita: es torna a generar (sense mostrar-ho)
+   jsr pack             ; mapa d'abast en bits
    jsr recolor          ; ara si: es mostren els maons en vermell
    lda #10
    sta score
    lda #0
    sta sch
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
    jsr minit            ; comenca la musica (continua d'un ant al seguent)
    lda #1
    sta mus

nextduck:
    lda dnum             ; numero d'ant (1..10)
    cmp #10
    bcc +
    ldx #$b0
    stx SCR+$10
    lda #1
+   ora #$b0
    sta SCR+$0f
    lda #0
    sta att              ; intents fallits d'aquest ant
    sta lm
pick:
    jsr rdl              ; casella a l'atzar de 0..511 (es descarten les
    sta duckp            ; que no serveixen)
    jsr rdl
    and #3               ; 0..1023 (el mapa de bits cobreix 128 bytes)
    ora #>SCR
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
    inc dnum
    lda #$ff
    jsr addsc            ; -1 per ant
    jsr wscore
    lda #2               ; la bateria calla mentre sona el soroll d'efecte
    sta mus
    lda #$82
    sta VIC_NOI
    lda #42
    jsr wait
    lda #1
    sta mus
    lda #0
    sta VIC_NOI
    ldx #3
    jsr d4               ; esborra l'ant (A=0)
    lda dnum
    cmp #11
    bcs over
    jmp nextduck

over:
    jsr txt              ; torna a la geometria de text 22x23
    jsr blk
    lda #240
    sta VIC_CHR          ; torna al mode text
    lda #0               ; calla la musica
    sta mus
    sta VIC_NOI
    sta $900a
    sta $900b
    sta $900c
    lda #7
    ldx #gameover-strs
    jsr pr
    lda #2
    ldx #yscore-strs
    jsr pr
    jsr pn               ; puntuacio, 4 xifres
    lda #3
    ldx #hscore-strs
    jsr pr
    lda score
    cmp hisc
    lda sch
    sbc hisc2
    bcc +
    lda score
    sta hisc
    lda sch
    sta hisc2
+   lda hisc
    ldx hisc2
    jsr dgt
    jsr pn               ; record, 4 xifres
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
    adc #<($9400+10*22)
    sta cp
    lda #>($9400+10*22)
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
    ora #>SCR
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

; ---------- un fotograma del joc ----------
fr:
    jsr mv
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
    sta SCR+$15
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

mchk:                    ; A=lo, X=hi d'una posicio de pantalla -> Z=1 si no es accessible (mapa de bits)
    pha
    lsr
    lsr
    lsr
    sta fp               ; lo>>3
    txa
    sec
    sbc #>SCR
    asl
    asl
    asl
    asl
    asl                  ; (hi-SCR)<<5
    ora fp
    tax                  ; byte del mapa = index>>3
    pla
    and #7
    tay
    lda MAPB,x
    and bits,y
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
    sta $9400,y
+   lda SCR+$100,y
    cmp #BRICK
    bne +
    lda #2
    sta $9500,y
+   lda SCR+$200,y
    cmp #BRICK
    bne +
    lda #2
    sta $9600,y
+   iny
    bne -
    rts

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

; ---------- disparar ----------
fire:
    lda #0               ; el tret talla la musica
    sta mus
    sta $900a
    sta $900b
    sta $900c
    lda #15
    sta VIC_VOL          ; volum ple pel soroll del tret
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
    adc #$ff             ; guany x3 - 1 (carry=0)
    jsr addsc
.k1 jsr wscore
    lda #1
    jsr addsc
    lda #99
    sta tm
    bne .common
.fail
    lda level            ; fallada: nivell-6 (x3 amb l'ant lila)
    sec
    sbc #6
    jsr x3
    jsr addsc
    jsr wscore
.common
    lda #0
    sta cnt
.sh lda #1               ; tremolor de pantalla (mateixos cicles que l'original)
    ldx #40
    jsr random
    lda m
    clc
    adc #YORG-20
    sta tmp
    sta VIC_VPOS
    lda #5
    jsr wait
    inc cnt
    lda cnt
    cmp #50
    bcc .sh
    lda #YORG
    sta VIC_VPOS
    lda #126
    jsr wait
    lda #0
    sta VIC_NOI
    lda #1               ; la musica continua
    sta mus
    rts

x3:                      ; A -> 3*A (tots els ants son lilas)
    sta tmp
    asl
    clc
    adc tmp
    rts

; ---------- accessibilitat del punt de mira ----------
; Marca a RMAP (pantalla-$0600) totes les posicions del peephole (2x2 sense
; maons, dins del rang que permet el joc) a les quals es pot arribar des de
; la posicio inicial amb moviments esquerra/dreta/amunt/avall (sense diagonals).
; Sortida: carry=1 si hi ha prou caselles accessibles (>= MINREACH).
flood:
    lda #0               ; el mapa (RAM de color) ja es a zero: blk l'ha netejat
    sta rc
    lda #1
    sta RMAP+P0-SCR      ; llavor: P0 en el mapa
.pass
    lda #0
    sta chg
    lda #<(SCR+COLS+1)
    sta fp
    lda #>(SCR+COLS+1)
    sta fp+1             ; primera posicio valida
.cell
    lda fp               ; rp = fp - $0600 - 22  (apunta a R[p-22])
    sec
    sbc #COLS
    sta rp
    lda fp+1
    sbc #>(SCR-RMAP)
    sta rp+1
    ldy #COLS
    lda (rp),y
    and #$0f             ; (la RAM de color nomes te 4 bits)
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
    and #$0f
    bne .found
    dex
    bpl -
    bmi .next
.found
    ldy #COLS
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
    cmp #<(SCR+NCELL-COLS-1) ; fi
    bne .cell
    lda fp+1
    cmp #>(SCR+NCELL-COLS-1)
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

noff:   !byte 0,COLS-1,COLS+1,2*COLS ; -COLS, -1, +1, +COLS respecte a p-COLS

; ---------- puntuacio ----------
wscore:
    lda score
    ldx sch
    jsr dgt
    lda ph
    ora #$80
    sta SCR+4
    lda pts
    ora #$80
    sta SCR+5
    lda pts+1
    ora #$80
    sta SCR+6
    rts

d10:                     ; A -> X=char desena, A=unitats
    ldx #$30
-   cmp #10
    bcc +
    sbc #10
    inx
    bne -
+   rts

dgt:                     ; A=lo, X=hi (<1000) -> ph, pts, pts+1 (chars)
    ldy #$30
.h  cpx #0
    bne .s
    cmp #100
    bcc .d
.s  sec
    sbc #100
    bcs +
    dex
+   iny
    bne .h
.d  sty ph
    jsr d10
    stx pts
    ora #$30
    sta pts+1
    rts

pn:                      ; escriu ph, pts, pts+1 i un 0 (puntuacio x10)
    lda ph
    jsr cputc
    lda pts
    jsr cputc
    lda pts+1
    jsr cputc
    lda #$30
    jmp cputc

addsc:                   ; score += A (amb signe), minim 0
    ldx #0
    cmp #$80
    bcc +
    dex
+   clc
    adc score
    sta score
    txa
    adc sch
    sta sch
    bpl +
    lda #0
    sta score
    sta sch
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
    sta SCR,x
    sta SCR+$100,x
    sta SCR+$200,x
    lda #0
    sta $9400,x
    sta $9500,x
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
    lda #>SCR
    sta cur+1
    sta ls+1
    rts

txt:                     ; geometria de text: 22x23, origen per defecte del PAL
    ldx #0
    lda #22
    bne setg
gam:                     ; geometria de joc: COLS x ROWS centrada
    ldx #4
    lda #COLS
setg:
    sta wd
    ldy #3
-   lda vregs,x
    sta $9000,y
    inx
    dey
    bpl -
    rts

pack:                    ; mapa de color (1 byte/casella) -> mapa de bits MAPB; deixa el color net
    ldx #0
    stx cp
    lda #>RMAP
    sta cp+1
.pb ldy #7
-   lda (cp),y
    and #1
    lsr
    rol tmp
    lda #0
    sta (cp),y
    dey
    bpl -
    lda tmp
    sta MAPB,x
    lda cp
    clc
    adc #8
    sta cp
    bcc +
    inc cp+1
+   inx
    bpl .pb
    rts

nl:                      ; cursor a l'inici de la fila seguent
    lda ls
    clc
    adc wd
    sta ls
    sta cur
    lda ls+1
    adc #0
    sta ls+1
    sta cur+1
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

irq:                     ; musica: una passada per tick (50 Hz)
    lda mus
    beq .ix
    jsr tick
.ix jmp $eabf            ; continua amb la rutina d'interrupcio del KERNAL

minit:                   ; prepara la canco perque el primer tic comenci el compas 0
    lda #$ff
    sta br
    lda #19
    sta rw
    lda #1
    sta rtk
    lda #0
    sta ar
    sta dix
    sta et
    ldx #15              ; buffer d'eco net
-   sta EBUF,x
    dex
    bpl -
    rts

tick:
    dec rtk
    bne .tk              ; mateixa fila: nomes cal tocar
    ldx rw               ; ---- fila nova ----
    inx
    cpx #20
    bcc .sr
    jsr newbar           ; ---- compas nou ----
    ldx #0
.sr stx rw
    txa
    and #1
    clc
    adc #4               ; files alternes de 4 i 5 tics (4,5 tics de mitjana)
    sta rtk
    ldx #1               ; veus melodiques: 1 = solista, 0 = baix
.ev dec vd,x
    bne .nx
    ldy vp,x             ; esdeveniment nou: nota, durada (files)
    lda pat,y
    sta vn,x
    lda pat+1,y
    sta vd,x
    iny
    iny
    sty vp,x
    lda #0
    sta va,x
.nx dex
    bpl .ev
    lda dpo              ; bateria: mascara de la fila
    clc
    adc rw
    tax
    lda dru,x
    beq .tk
    tax
    lda dst,x
    sta dix              ; el cop comenca a sonar
.tk ldy #0               ; ---- baix: staccato, 2 octaves per sota del solista
    lda vn
    beq .b1
    ldx va
    cpx #14
    bcs .b1
    clc
    adc broot
    tax
    ldy nt,x
.b1 sty $900a
    ldy #0               ; ---- solista: escombrada d'entrada + vibrato retardat
    lda vn+1
    beq .l1
    clc
    adc lroot
    tax
    lda nt,x
    sta it
    ldx va+1
    cpx #2
    bcs +
    lda bnd,x
    bne .lo
+   lda #0
    cpx #8
    bcc .lo
    txa
    lsr
    and #3
    tax
    lda vtab,x
.lo clc
    adc it
    tay
.l1 sty $900c
    tya                  ; guarda el solista al buffer d'eco
    ldx et
    sta EBUF,x
    inx
    txa
    and #15
    sta et
    ldy #0               ; ---- veu alto: eco del solista (una octava avall, 9 tics tard) o arpegi
    lda fl
    and #4
    beq .ar
    lda et
    clc
    adc #6
    and #15
    tax
    ldy EBUF,x
    jmp .a1
.ar lda fl               ; arpegi d'acord, un to per tic
    and #2
    beq .a1
    lda cb
    clc
    adc ar
    tax
    lda chd,x
    tax
    ldy nt,x
.a1 sty $900b
    ldx ar
    inx
    cpx #3
    bcc +
    ldx #0
+   stx ar
    inc va
    inc va+1
    lda mus              ; ---- bateria (noise), muda mentre sona un efecte
    cmp #2
    beq .dn
    ldx dix
    lda dtab,x
    sta VIC_NOI
    beq .dn
    inc dix
.dn rts

newbar:                  ; ---- cursors, arrels i bateria del compas seguent
    ldx br
    inx
    cpx #NBAR
    bcc +
    ldx #LOOPB
+   stx br
    txa
    lsr
    lsr
    tay                  ; fase = compas/4
    lda phb,y
    sta broot
    lda phl,y
    sta lroot
    lda phc,y
    sta cb
    lda phf,y
    sta fl
    lda phd,y
    sta dpo
    lda phv,y
    sta VIC_VOL          ; dinamica: la introduccio comença suau
    lda br
    and #3
    cmp #3
    bne +
    lda #40              ; l'ultim compas de cada fase porta un redoble
    sta dpo
+   lda br               ; riff del baix: A o B alternant
    and #1
    asl
    asl
    asl
    sta vp
    lda fl               ; solista: motiu T1..T4 o silenci
    and #1
    beq .rl
    lda br
    and #3
    sta it
    asl
    adc it
    asl
    adc #16
    bne .sl
.rl lda #40
.sl sta vp+1
    lda #1
    sta vd
    sta vd+1
    rts

; ---------- dades ----------
offs:   !byte 0,1,COLS,COLS+1,0,1,COLS,COLS+1
; Musica: tema de Mission: Impossible en 5/4 (20 files per compas, files de 4,5 tics).
; Riff del baix (G G Bb C | G G F F#) i motiu del solista (Bb G D | Bb G Db | Bb G C | Bb C):
; el motiu es la melodia publicada en notacio ABC; la resta (acords, passos a Do m i Re m, bateria) es arranjament propi.
nt:     !byte $82,$89,$90,$96,$9c,$a1,$a7,$ac,$b0,$b5,$b9,$bd,$c1,$c4,$c7,$ca,$cd,$d0,$d3,$d5,$d8,$da,$dc,$de,$e0,$e2,$e3,$e5,$e6   ; registre del soprano per semitons des de Do#3 (138,6 Hz)
pat:    !byte $12,$06,$12,$06,$15,$04,$17,$04,$12,$06,$12,$06,$10,$04,$11,$04,$15,$02,$12,$02,$0d,$10,$15,$02,$12,$02,$0c,$10,$15,$02,$12,$02,$0b,$10,$09,$02,$0b,$02,$00,$10,$00,$14
chd:    !byte 13,18,21, 11,14,18, 13,16,20   ; arpegis: Sol m (Re Sol Sib), Do m (Do Mib Sol), Re m (Re Fa La)
bnd:    !byte $fe,$ff            ; escombrada: -2, -1 passos de registre
vtab:   !byte 0,1,0,$ff          ; vibrato simetric (+-1 pas)
dtab:   !byte 0                  ; (0 = silenci)
        !byte $b4,$a0,$92,$88,0  ; bombo: soroll greu que baixa
        !byte $f0,$ea,$e2,$d8,0  ; caixa: soroll agut que s'apaga
        !byte $fa,0              ; hi-hat
dst:    !byte 0,1,6,6,11,1,6,6   ; mascara de la fila (1 bombo, 2 caixa, 4 hi-hat) -> inici a dtab
dru:    !byte 1,0,4,0,4,0,1,0,4,0,4,0,1,0,4,0,1,0,4,0   ; fase d'introduccio: bombo + hi-hat
        !byte 1,0,4,0,4,0,1,0,2,0,4,0,1,0,4,0,2,0,4,0   ; complet
        !byte 1,0,4,0,4,0,1,0,2,0,4,0,2,0,2,0,2,2,2,2   ; redoble
NBAR    = 28                     ; 7 fases de 4 compassos
LOOPB   = 8                      ; en acabar torna a la fase 2 (sense la introduccio)
; fases:      intro  intro2 tema  tema  Do m  Re m  tema
phb:    !byte 0,     0,     0,    0,    $f9,  $fb,  0       ; transposicio del baix (0, -7, -5)
phl:    !byte 0,     0,     0,    0,    5,    $fb,  0       ; transposicio del solista (0, +5, -5)
phc:    !byte 0,     0,     0,    0,    3,    6,    0       ; acord
phf:    !byte 0,     2,     3,    5,    3,    5,    3       ; bit0 solista, bit1 arpegi, bit2 eco
phv:    !byte 10,    12,    15,   15,   15,   15,   15      ; volum
phd:    !byte 0,     20,    20,   20,   20,   20,   20      ; patro de bateria
jk:     !byte $10,$80,$04,$08    ; mascares: esquerra, dreta, amunt, avall
jl:     !byte <-1,1,<-COLS,<COLS,<(-COLS-1),<(1-COLS),<(COLS-1),<(COLS+1)   ; increments (baix)
jh:     !byte >-1,0,>-COLS,>COLS,>(-COLS-1),>(1-COLS),>(COLS-1),>(COLS+1)   ; increments (alt)
chars:  !byte CH0,CH0+1,CH0+2,CH0+3,$fd,$ed,$ee,$f0
vregs:  !byte 46,22,38,12             ; text (de $9003 a $9000)
        !byte ROWS*2,COLS,YORG,XORG ; joc
bits:   !byte 1,2,4,8,16,32,64,128
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
!if * > SCR {
    !error "el codi xoca amb la pantalla"
}
