; The Removers'Library 
; Copyright (C) 2006-2012 Seb/The Removers
; http://removers.atari.org/
	
; This library is free software; you can redistribute it and/or 
; modify it under the terms of the GNU Lesser General Public 
; License as published by the Free Software Foundation; either 
; version 2.1 of the License, or (at your option) any later version. 

; This library is distributed in the hope that it will be useful, 
; but WITHOUT ANY WARRANTY; without even the implied warranty of 
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU 
; Lesser General Public License for more details. 

; You should have received a copy of the GNU Lesser General Public 
; License along with this library; if not, write to the Free Software 
; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA 

	include	"../jaguar.inc"

	include	"../risc.s"
	
DSP_BG	equ	0

DSP_STACK_SIZE	equ	32	; long words

; 	.bss
; 	.phrase
; dsp_isp:	ds.l	DSP_STACK_SIZE
; 	.phrase
; dsp_usp:	ds.l	DSP_STACK_SIZE
; DSP_USP	equ	dsp_usp		
; DSP_ISP	equ	dsp_isp
DSP_USP	equ	(D_ENDRAM-(4*DSP_STACK_SIZE))
DSP_ISP	equ	(DSP_USP-(4*DSP_STACK_SIZE))

; VOICEs
; ======
; START (read by DSP)
; -----
; base address of sound
;
; LENGTH (read by DSP)
; ------
; length of sound in **bytes**
;
; CONTROL (read by DSP)
; -------
; 800Bbbbb 0Vvvvvvv IIIIiiii iiiiiiii
;
; 8: 0 = 8 bits sound, 1 = 16 bits sound
; Bbbbb: right balance from 0 to 16 [saturated] (left balance is 16 minus right balance)
; Vvvvvvv: volume from 0 to 64 [saturated]
; IIII.iiiiiiiiiiii: 4.12 resampling increment
;
; private fields
; ==============
; CURRENT (read/written by DSP) 
; -------
; current address in the sound
;
; END (read/written by DSP)
; ---
; end address of the sound
;
; FRAC (read/written by DSP)
; ----
; fractionnal increment (12 higher bits)

	.offset	0
VOICE_START:	ds.l	1
VOICE_LENGTH:	ds.l	1
VOICE_CONTROL:	ds.l	1
VOICE_CURRENT:	ds.l	1
VOICE_END:	ds.l	1
VOICE_FRAC:	ds.l	1
VOICE_SIZEOF:	ds.l	0

; CONTROL (read by DSP and cleared for acknowledgement)
; -------
; S0000000 00000000 00000000 OOOOOOOO
;
; S: 0 = clear bits, 1 = set bits
; O: activate/deactivate voice
;
; private fields
; ==============
; STATE (read/written by DSP)
; -----
; 00000000 00000000 00000000 OOOOOOOO
; O: voice on/off
	
	.offset	0
DMA_CONTROL:	ds.l	1
DMA_STATE:	ds.l	1
DMA_SIZEOF:	ds.l	0

	.text

LOG2_NB_VOICES	equ	3
NB_VOICES	equ	(1<<LOG2_NB_VOICES)

	.extern	_bcopy
	
;;; the DSP sound driver
;;; for sake of simplicity, it clears the interrupt handlers
;;; so you shoud install your own interrupts after having initialised
;;; the sound driver
;;; this code is not self-relocatable
	.phrase
dsp_sound_driver:
	.dsp
	.org	D_RAM
.dsp_sound_driver_begin:
	;; CPU interrupt
	padding_nop	$10
	;; I2S interrupt
	movei	#.dsp_sound_i2s_it,r28
	movei	#D_FLAGS,r30
	jump	(r28)
	load	(r30),r29	; read flags
	padding_nop	(D_RAM+$20-*)
	;; Timer 0 interrupt
	padding_nop	$10
	;; Timer 1 interrupt
	padding_nop	$10
	;; External 0 interrupt
	padding_nop	$10
	;; External 1 interrupt
	padding_nop	$10
.dsp_sound_i2s_it:
	;; r0 = start of first half (currently played)
	;; r1 = end of first half
	;; r2 = start of other half (currently generated)
	;; r3 = end of other half
	;; r14 = current pointer in played buffer
	;; r15 = L_I2S
	load	(r14),r4		; left sample
	load	(r14+1),r5		; right sample
	addq	#8,r14
	store	r4,(r15+1)	; write left channel (Zerosquare fix)
	store	r5,(r15)	; write right channel (Zerosquare fix)
	cmp	r14,r1
	jr	ne,.no_swap	; have we reached the end of buffer?
	moveq	#1,r4
	;; r0 <-> r2
	;; r1 <-> r3
	;; r14 := previous r2 = current r0
	move	r2,r14		; other half becomes active buffer
	move	r3,r5		; update end pointer of active buffer
	move	r0,r2		; first half becomes other half
	move	r1,r3
	move	r14,r0		; other half becomes first half
	move	r5,r1
	moveta	r4,r0		; indicate switch of sound buffer to main loop
.no_swap:
	;; return from interrupt
	load	(r31),r28	; return address
	bset	#10,r29		; clear latch 1
	bclr	#3,r29		; clear IMASK
	addq	#4,r31		; pop from stack
	addqt	#2,r28		; next instruction
	jump	t,(r28)		; return
	store	r29,(r30)	; restore flags
	.long
.sound_dma:
SOUND_DMA	equ	.sound_dma
	.rept	DMA_SIZEOF/4
	dc.l	0
	.endr
	.long
.sound_voices:
;;; voices are alternating: left, right, left, right, ...
SOUND_VOICES	equ	.sound_voices
	.rept	NB_VOICES
	.rept	VOICE_SIZEOF/4
	dc.l	0
	.endr
	.endr	
.dsp_sound_driver_main:
	;; r0 is used by it handler to indicate that audio buffers have been switched
	cmpq	#0,r0
	jr	eq,.dsp_sound_driver_main
	nop
	moveq	#0,r0		; reset flag
	movei	#BG,r1
	movefa	r0,r2
	jr	.dsp_sound_driver_main
	storew	r2,(r1)
	.long
.dsp_sound_driver_init:
	;; 
SOUND_DRIVER_FRQ	equ	0
SOUND_DRIVER_BUFSIZE	equ	4
SOUND_DRIVER_LOCK	equ	8
	;; assume run from bank 1
	movei	#DSP_ISP+(DSP_STACK_SIZE*4),r31	; init isp
	moveta	r31,r31		; ISP (bank 0)
	movei	#DSP_USP+(DSP_STACK_SIZE*4),r31	; init usp
	;; set I2S
	movei	#SCLK,r10
	movei	#SMODE,r11
	movei	#.dsp_sound_driver_param,r14
	movei	#%001101,r13	; SMODE (Zerosquare fix)
	load	(r14+SOUND_DRIVER_FRQ/4),r12	; SCLK
	store	r12,(r10)
	store	r13,(r11)
	;;
	load	(r14+SOUND_DRIVER_BUFSIZE/4),r13 ; number of samples (might be odd)
	movei	#.dsp_sound_buffer,r10		; first half of audio buffer
	move	r13,r12
	shrq	#1,r13				; half of samples
	move	r10,r11
	shlq	#3,r13				; a sample is 8 bytes
	shlq	#3,r12
	add	r13,r11				; second half of audio buffer
	add	r10,r12				; end of audio buffer
	;;
	moveta	r10,r0				; start of first half (buffer played)
	moveta	r11,r1				; end of first half (buffer played)
	moveta	r11,r2				; start of other half (buffer generated)
	moveta	r12,r3				; end of other half (buffer generated)
	moveta	r10,r14				; current point in buffer played
	movei	#L_I2S,r13
	moveta	r13,r15
	;; enable interrupts
	movei	#D_FLAGS,r28
	movei	#D_I2SENA|REGPAGE,r29
	;; go to driver
	moveq	#0,r1
	movei	#.dsp_sound_driver_main,r0
	store	r1,(r14+SOUND_DRIVER_LOCK/4)	; clear LOCK
	jump	(r0)				; jump to main loop
	store	r29,(r28)
	.long
.dsp_sound_driver_param:
	dc.l	0		; frequency
	dc.l	0		; buffer size (number of samples)
	dc.l	0		; lock
	.long
.dsp_sound_buffer:
	.rept	882
	dc.l	0
	dc.l	0
	.endr
.dsp_sound_driver_end:
		
SOUND_DRIVER_INIT	equ	.dsp_sound_driver_init
SOUND_DRIVER_PARAM	equ	.dsp_sound_driver_param
SOUND_DRIVER_SIZE	equ	.dsp_sound_driver_end-.dsp_sound_driver_begin

	.if	(SOUND_DRIVER_SIZE+(2*4*DSP_STACK_SIZE)) > (D_ENDRAM-D_RAM)
	.print	"Sound driver too big: ", (SOUND_DRIVER_SIZE+(2*4*DSP_STACK_SIZE)), " bytes (max allowed = ", (D_ENDRAM-D_RAM), " bytes)"
	.fail	
	.endif
	
	.print	"Sound driver code size (DSP): ", SOUND_DRIVER_SIZE
				
	.68000

	.globl	_init_sound_driver
;; int init_sound_driver(int frequency)
_init_sound_driver:
	move.l	#0,D_CTRL
	;; copy DSP code
	pea	SOUND_DRIVER_SIZE	
	pea	D_RAM
	pea	dsp_sound_driver
	jsr	_bcopy
	lea	12(sp),sp
	;; set timers
	move.l	4(sp),d0
	; n = (830968,75/(2*freq))-1 = 25 for 16000hz
        ; f = 830968,75/(2*(n+1))
; 	move.l	d0,replay_frequency
	move.l	#83096875,d1
	divu.w	d0,d1
	and.l	#$ffff,d1
	divu.w	#200,d1
	and.l	#$ffff,d1
	subq.l	#1,d1
	move.l	d1,SOUND_DRIVER_PARAM+SOUND_DRIVER_FRQ
 	addq.l	#1,d1
	mulu.w	#200,d1
 	move.l	#83096875,d0
 	divu.w	d1,d0
	and.l	#$ffff,d0
 	move.l	d0,replay_frequency
	;; compute size of audio buffer
	move.w	CONFIG,d0
	move.w	#50,d1
	and.w	#VIDTYPE,d0
	beq.s	.ok_frq
	move.w	#60,d1
.ok_frq:
	move.l	replay_frequency,d0
	divu.w	d1,d0		
	and.l	#$ffff,d0	; number of samples per vbl
	move.l	d0,SOUND_DRIVER_PARAM+SOUND_DRIVER_BUFSIZE
	;; set DSP for interrupts
	move.l	#REGPAGE,D_FLAGS
	;; launch the driver
	move.l	#SOUND_DRIVER_PARAM+SOUND_DRIVER_LOCK,a0
	move.l	#$ffffffff,(a0)
	move.l	#SOUND_DRIVER_INIT,D_PC
	move.l	#DSPGO,D_CTRL
	bsr	compute_amiga_frequencies ; does not modify a0
.wait_init:
	tst.l	(a0)
	bne.s	.wait_init
	move.l	replay_frequency,d0
	rts

MAX_PERIOD	equ	1024

compute_amiga_frequencies:
	move.l	d2,-(sp)
	move.l	replay_frequency,d2	
	move.l	#_amiga_frequencies + (2*MAX_PERIOD),a1
	move.l	#MAX_PERIOD-1,d0
.compute_one_period:
	move.l	#7159092,d1	; (10^7 / 2.79365) << 1
	tst.l	d0
	beq.s	.skip_div
	divu.w	d0,d1
.skip_div:	
	swap	d1
	clr.w	d1
	lsr.l	#5,d1		; <<11
	divu.w	d2,d1
	move.w	d1,-(a1)
	dbf	d0,.compute_one_period
	move.l	(sp)+,d2
	rts

.macro	wait_dma
.wait\~:
	tst.l	\1
	bne.s	.wait\~
.endm
	
	.globl  _set_voice
;; void set_voice(int voice_num, int control, char *start, int len, char *loop_start, int loop_len);
_set_voice:
        move.l  #SOUND_VOICES,a0
	move.l  0+4(sp),d0
        and.l   #NB_VOICES-1,d0
	moveq	#1,d1
	lsl.l	d0,d1		; select voice
        mulu.w  #VOICE_SIZEOF,d0
        lea     (a0,d0.l),a0
	;; 
	move.l	#SOUND_DMA,a1
	wait_dma	DMA_CONTROL(a1)
	move.l	d1,DMA_CONTROL(a1) ; disable voice
	;; 
	move.l	0+8(sp),VOICE_CONTROL(a0)
	move.l	0+12(sp),VOICE_START(a0)
	move.l	0+12+4(sp),VOICE_LENGTH(a0)
	;; 
	or.l	#$80000000,d1
	wait_dma	DMA_CONTROL(a1)
	move.l	d1,DMA_CONTROL(a1) ; enable voice
	wait_dma	DMA_CONTROL(a1)
	;; 
	move.l	0+20(sp),VOICE_START(a0)
	move.l	0+20+4(sp),VOICE_LENGTH(a0)
        rts

	.globl	_clear_voice
;; void clear_voice(int voice_num);
_clear_voice:
        move.l  #SOUND_VOICES,a0
	move.l  0+4(sp),d0
        and.l   #NB_VOICES-1,d0
	moveq	#1,d1
	lsl.l	d0,d1		; select voice
        mulu.w  #VOICE_SIZEOF,d0
        lea     (a0,d0.l),a0
	;; 
	move.l	#SOUND_DMA,a1
	wait_dma	DMA_CONTROL(a1)
	move.l	d1,DMA_CONTROL(a1) ; disable voice
	rts
	
	.globl	_set_panning
;; void set_panning(int voice_num, int panning);
_set_panning:	
        move.l  #SOUND_VOICES,a0
	move.l  0+4(sp),d0
        and.l   #NB_VOICES-1,d0
	moveq	#1,d1
	lsl.l	d0,d1		; select voice
        mulu.w  #VOICE_SIZEOF,d0
        lea     (a0,d0.l),a0
	;;
	move.w	0+8+2(sp),d0
	and.w	#%11111,d0
	move.l	VOICE_CONTROL(a0),d1
	rol.l	#8,d1
	and.b	#%11100000,d1
	or.b	d0,d1
	ror.l	#8,d1
	move.l	d1,VOICE_CONTROL(a0)
	rts

	.globl	_set_volume
;; void set_volume(int voice_num, int volume);
_set_volume:	
        move.l  #SOUND_VOICES,a0
	move.l  0+4(sp),d0
        and.l   #NB_VOICES-1,d0
	moveq	#1,d1
	lsl.l	d0,d1		; select voice
        mulu.w  #VOICE_SIZEOF,d0
        lea     (a0,d0.l),a0
	;;
	move.w	0+8+2(sp),d0
	and.w	#%1111111,d0
	move.l	VOICE_CONTROL(a0),d1
	swap	d1
	move.b	d0,d1
	swap	d1
	move.l	d1,VOICE_CONTROL(a0)
	rts

	.data
	.even
	dc.b	"Sound Driver by Seb/The Removers"
	.even

	.bss
	.long
replay_frequency:
	ds.l	1
	
	.long
	.globl	_amiga_frequencies
_amiga_frequencies:
	ds.w	MAX_PERIOD
	.long

	.text
SOUND_VOICE0	equ	SOUND_VOICES
SOUND_VOICE1	equ	SOUND_VOICE0+VOICE_SIZEOF
SOUND_VOICE2	equ	SOUND_VOICE1+VOICE_SIZEOF
SOUND_VOICE3	equ	SOUND_VOICE2+VOICE_SIZEOF
SOUND_VOICE4	equ	SOUND_VOICE3+VOICE_SIZEOF
SOUND_VOICE5	equ	SOUND_VOICE4+VOICE_SIZEOF
SOUND_VOICE6	equ	SOUND_VOICE5+VOICE_SIZEOF
SOUND_VOICE7	equ	SOUND_VOICE6+VOICE_SIZEOF		
	
	include	"pt-play.s"

	.text
	.globl	_init_module
;; init_module(char *module, int tempo_enabled);
_init_module	equ	mt_init

	.globl	_play_module
;; play_module();
_play_module	equ	mt_music_vbl

	.globl	_clear_module
;; clear_module();
_clear_module	equ	mt_clear

	.globl	_pause_module
;; pause_module();
_pause_module	equ	mt_pause

	.globl	_enable_module_voices
;; enable_module_voices(int mask);
_enable_module_voices	equ	mt_enable_voices
	