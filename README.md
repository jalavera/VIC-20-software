# VIC-20-software

Jocs per al Commodore VIC-20, escrits en assemblador 6502 (ACME), (C) JIMSOFT.
Cada joc té la seva carpeta amb els `.prg` (per carregar a l'emulador o al
VIC-20) i el codi font.

## Jocs

| Joc | Memòria | Què és | Descàrrega | Carpeta |
|---|---|---|---|---|
| Vint-i-una (versió original) | sense ampliar | El programa BASIC de la Veintiuna (Pontoon) d'INPUT Juegos, per al VIC-20, amb les instruccions en PDF | [veintiuna.prg](VINTIUNA/original/veintiuna.prg) · [veintiuna_3k.prg](VINTIUNA/original/veintiuna_3k.prg) · [instruccions](VINTIUNA/original/La_Veintiuna_VIC20_instruccions.pdf) | [VINTIUNA/original](VINTIUNA/original/) |
| Vint-i-una Enhanced | sense ampliar | La Vint-i-una passada a codi màquina, amb esperes per llegir els textos | [veintiuna_enhanced_v2.prg](VINTIUNA/enhanced/veintiuna_enhanced_v2.prg) | [VINTIUNA/enhanced](VINTIUNA/enhanced/) |
| Vint-i-una Pro (Pontoon Pro) | sense ampliar | Cartes amb caràcters propis multicolor i figures grans; català i anglès | [vintiuna_pro.prg](VINTIUNA/pro/vintiuna_pro.prg) · [codi font](VINTIUNA/pro/vintiuna_pro_src.zip) | [VINTIUNA/pro](VINTIUNA/pro/) |
| Solitari | +3 KB | Solitari Klondike amb palanca de joc, menú d'opcions, pantalla completa i so | [solitari.prg](SOLITARI/solitari.prg) · [codi font](SOLITARI/solitari_pro_src.zip) | [SOLITARI](SOLITARI/) |
| Ànecs v1 - Bàsic | sense ampliar | El joc dels ànecs, optimitzat a mà (patos_opt0 a 11) | [patos_opt11.prg](ANECS/v1/patos_opt11.prg) | [ANECS/v1](ANECS/v1/) |
| Ànecs v2 - Ànec lila hipermotivat | sense ampliar | L'ànec lila, més ràpid i difícil | [patos_opt_pas2_lila_opt2.prg](ANECS/v2/patos_opt_pas2_lila_opt2.prg) | [ANECS/v2](ANECS/v2/) |
| Ànecs v3 - Duck Enhanced | sense ampliar | Tots els ànecs hipermotivats, música i pantalla gegant | [duck_enhanced_v9.prg](ANECS/v3/duck_enhanced_v9.prg) | [ANECS/v3](ANECS/v3/) |

A les carpetes dels Ànecs hi ha també les versions intermèdies, cadascuna
amb el seu `.asm` i el seu `.prg`.

## Assemblar

    acme -f cbm -o joc.prg joc.asm
