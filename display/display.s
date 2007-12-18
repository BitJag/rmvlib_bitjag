; The Removers'Library 
; Copyright (C) 2006 Seb/The Removers
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

	include	"jaguar.inc"

	.if	^^defined	DISPLAY_H
	.print	"sprites.s already included"
	end
	.endif
DISPLAY_H	equ	1
	.print	"including display.s"

	include	"display_def.s"
	
	.extern	_a_vdb
	.extern	_bcopy
	.extern	_vblCounter
	.extern	_stop_object
			
	include	"display_cfg.s"

GPU_STACK_SIZE		equ	32	; in long words
	
; 	.bss
; 	.phrase
; gpu_isp:	ds.l	GPU_STACK_SIZE
; 	.phrase
; gpu_usp:	ds.l	GPU_STACK_SIZE
; GPU_ISP	equ	gpu_isp
; GPU_USP	equ	gpu_usp
GPU_USP	equ	(G_ENDRAM-(4*GPU_STACK_SIZE))
GPU_ISP	equ	(GPU_USP-(4*GPU_STACK_SIZE))
			
	.text
	.68000

.macro	padding_nop
	.print	"adding ",\1/2," padding nop"
	.rept	(\1 / 2)
	nop
	.endr
.endm

.macro	push
	;; push \1 on stack
	subqt	#4,r31
	store	\1,(r31)
.endm

.macro	pop
	;; pop \1 from stack
	load	(r31),\1
	addqt	#4,r31
.endm

.macro	display_save_first_regs
	push	r1
	push	r2
	push	r14
	push	r15
.endm

.macro	display_restore_first_regs
	pop	r15
	pop	r14
	pop	r2
	pop	r1
.endm	
		
.macro	display_save_other_regs
	push	r0
*	push	r1
*	push	r2
	push	r3
	push	r4
	push	r5
	push	r6
	push	r7
	push	r8
	push	r9
	push	r10
	push	r11
	push	r12
	push	r13
*	push	r14
*	push	r15
	push	r16
	push	r17
	push	r18
	push	r19
	push	r20
	push	r21
	push	r22
	push	r23
	push	r24
	push	r25
	push	r26
	push	r27
.endm

.macro	display_restore_other_regs
	pop	r27
	pop	r26
	pop	r25
	pop	r24
	pop	r23
	pop	r22
	pop	r21
	pop	r20
	pop	r19
	pop	r18
	pop	r17
	pop	r16
*	pop	r15
*	pop	r14
	pop	r13
	pop	r12
	pop	r11
	pop	r10
	pop	r9
	pop	r8
	pop	r7
	pop	r6
	pop	r5
	pop	r4
	pop	r3
*	pop	r2
*	pop	r1
	pop	r0
.endm

;;; the GPU display driver
;;; for sake of simplicity, it clears the interrupt handlers
;;; so you shoud install your own interrupts after having initialised
;;; the display driver
;;; this code is not self-relocatable
	.phrase
gpu_display_driver:
	.gpu
	.org	G_RAM
.gpu_display_driver_begin:
	;; CPU interrupt
	.if	!DISPLAY_USE_OP_IT
	movei	#.gpu_display_from_cpu_it,r28
	movei	#G_FLAGS,r30
	jump	(r28)
	load	(r30),r29	; get flags
	.endif
	padding_nop	(G_RAM+$10-*)
	;; 
	.org	G_RAM+$10
	;; DSP interrupt
	padding_nop	$10
	;; 
	.org	G_RAM+$20
	;; Timing interrupt
	padding_nop	$10
	;; 
	.org	G_RAM+$30
	;; OP interrupt
	.if	DISPLAY_USE_OP_IT
	movei	#.gpu_display_from_op_it,r28
	movei	#G_FLAGS,r30
	jump	(r28)
	load	(r30),r29	; get flags
	.endif
	padding_nop	(G_RAM+$40-*)
	;; 
	.org	G_RAM+$40	
	;; Blitter interrupt
	padding_nop	$10
	.org	G_RAM+$50
.macro	gpu_display_swap_lists
	;; r15 is display list address
	load	(r15+DISPLAY_LOG/4),r1 ; logical list
	load	(r15+DISPLAY_PHYS/4),r14 ; physical list
	store	r1,(r15+DISPLAY_PHYS/4)	; logical becomes physical
	store	r14,(r15+DISPLAY_LOG/4)	; physical becomes logical
	.if	DISPLAY_SWAP_METHOD
	shrq	#3,r1		; physical list address in phrases
	load	(r15+(DISPLAY_LIST_OB4+4)/4),r2	; read BRANCH object
	move	r1,r28		; copy address
	shlq	#15,r2
	shrq	#8,r1		; high bits of BRANCH object
	shrq	#15,r2
	shlq	#24,r28
	or	r28,r2		; low bits
	store	r1,(r15+DISPLAY_LIST_OB4/4)
	store	r2,(r15+((DISPLAY_LIST_OB4+4)/4))
	.else
	movei	#OLP,r2
	rorq	#16,r1		; word swapped
	store	r1,(r2)
	.endif
.endm
	.if	!DISPLAY_USE_OP_IT
.gpu_display_from_cpu_it:
	.if	DISPLAY_IT_SAVE_REGS
	display_save_first_regs
	.endif
	movei	#active_display_list,r1
	load	(r1),r15
	gpu_display_swap_lists
	.if	DISPLAY_BG_IT
	movei	#DISPLAY_BG_CPU|DISPLAY_BG_SWAP,r1
	.endif
*	movei	#.gpu_display_main,r28
	bset	#9,r29		; clear latch 0
*	jump	(r28)
*	nop
	.else
.gpu_display_from_op_it:
	.if	DISPLAY_IT_SAVE_REGS
	display_save_first_regs
	.endif
	.if	DISPLAY_OP_IT_COMP_PT
	movei	#active_display_list,r1
	load	(r1),r15
	.else
	movei	#OB2,r1
	load	(r1),r15
	rorq	#16,r15
	.endif
	gpu_display_swap_lists
	.if	DISPLAY_BG_IT
	movei	#DISPLAY_BG_OP|DISPLAY_BG_SWAP,r1	; BLUE
	.endif
	movei	#OBF,r28
	storew	r28,(r28)	; relaunch OP
*	movei	#.gpu_display_main,r28
	bset	#12,r29		; clear latch 3
*	jump	(r28)
*	nop
	.endif
.gpu_display_main:
	.if	DISPLAY_IT_SAVE_REGS
	display_save_other_regs
	.endif
	.if	DISPLAY_BG_IT
	movei	#BG,r2
	or	r2,r2
	storew	r1,(r2)
	.endif
	;; must not modify neither r29 nor r30 nor r31 !!
	;; r15 is display_list address
	;; r14 is logical list address
*	movei	#active_display_list,r1
*	load	(r1),r1
*	moveq	#DISPLAY_LOG,r14
	movei	#DISPLAY_HASHTBL,r0
	add	r15,r0		; to hash table
*	add	r1,r14
*	addq	#4,r0		; skip previous field
*	load	(r14),r14	; logical list
	.if	!DISPLAY_SWAP_METHOD
	movei	#DISPLAY_LIST,r2
	add	r2,r14
	.endif
	addq	#DISPLAY_Y,r15
	movei	#_a_vdb,r19
	load	(r15),r27	; DISPLAY_Y|DISPLAY_X
	loadw	(r19),r19	; a_vdb
	moveq	#1<<DISPLAY_NB_LAYER,r3 ; layer counter	
	addq	#1,r19
	movei	#.compute_one_layer,r20
	shrq	#1,r19		; (a_vdb+1)/2
	movei	#.do_layer,r21
	movei	#.do_layer_tst,r22
	movei	#.next_in_layer,r23
	movei	#.anim_off,r24
	movei	#.non_scaled_sprite,r25
	movei	#.y_height_ok,r26
.compute_one_layer:
	;; r0 go through hash table
	;; r3 is the layer counter
	;; r14 is logical list pointer
	;; r19 is (a_vdb+1)
	;; r27 is DISPLAY_Y|DISPLAY_X
	load	(r0),r4		; read attribute
	addq	#4,r0
	sharq	#1,r4		; test hidden flag
	jr	cs,.layer_visible ; if set then the layer is visible
	moveq	#0,r15		; simulate empty layer
	jump	(r22)		; test if layer is empty
	addq	#12,r0		; next layer
.layer_visible:	
	load	(r0),r28	; LAYER_Y|LAYER_X
	addq	#8,r0		; go to "next" field
	move	r27,r1
	move	r28,r2
	shlq	#16,r1
	shlq	#16,r2
	sharq	#16,r28		; LAYER_Y
	add	r2,r1		; DISPLAY_X+LAYER_X|0
	move	r27,r2
	sharq	#16,r1		; DISPLAY_X+LAYER_X
	sharq	#16,r2		; DISPLAY_Y
	add	r28,r2		; DISPLAY_Y+LAYER_Y
	;; r1 is DISPLAY_X+LAYER_X
	;; r2 is DISPLAY_Y+LAYER_Y
	load	(r0),r15	; get sprite address
	jump	(r22)		; go test if layer is empty
	addq	#4,r0		; next layer in hash table
.do_layer:
	load	(r15+SPRITE_SND_PHRASE/4),r4
	btst	#SPRITE_INVISIBLE,r4
	jump	ne,(r23)				; if sprite invisible then next_in_layer
	btst	#SPRITE_ANIM_ON_OFF,r4			; is it animated?
	jump	eq,(r24)				; no then anim_off
	load	(r15+(SPRITE_SND_PHRASE+4)/4),r5	; ** load low bits of snd phrase **
	.if	DISPLAY_USE_LEGACY_ANIMATION
.anim_on:
	load	(r15+SPRITE_ANIM_DATA/4),r7	; anim settings
	load	(r15+SPRITE_ANIM_ARRAY/4),r6	; anim array address
	move	r7,r8
	move	r7,r9
	shrq	#24,r8		; 0|0|0|COUNTER
	shlq	#16,r9		; INDEX.w|0|0
	subq	#1,r8		; COUNTER--
	jr	ne,.anim_no_next ; if not null then do nothing special
	shrq	#14,r9		; 0|0|INDEX.w << 2
.anim_next:
	move	r7,r8
	addq	#1<<2,r9	; INDEX++
	shrq	#16,r8		; ?|SPEED
.anim_no_next:
	;; here the lower byte of r8 is the new COUNTER
	;; and the lower word of r9 contains the INDEX (plus the loop flag) shifted by two bits
	bclr	#15+2,r9	; ignore loop flag
	move	r6,r10		; copy array address
	shlq	#8,r7		; SPEED|?|?|?
	add	r9,r6		; array[index]
	shrq	#24,r7		; 0|0|0|SPEED
	load	(r6),r6		; DATA address
	shlq	#16,r7		; 0|SPEED|0|0
	cmpq	#0,r6		; is DATA address null ?
	jr	ne,.no_anim_index_fix	; no
	shlq	#24,r8		; COUNTER|0|0|0
.anim_index_fix:
	moveq	#1,r9		; loop flag
	load	(r10),r6	; DATA address
	shlq	#17,r9		; loop flag set and INDEX = 0 
.no_anim_index_fix:
	or	r8,r7		; COUNTER|SPEED|0|0
	shrq	#2,r9		; 0|0|INDEX.w
	or	r9,r7
	jr	.data_ok
	store	r7,(r15+SPRITE_ANIM_DATA/4)
	.else
.anim_on:
	load	(r15+SPRITE_ANIM_DATA/4),r7	; anim settings
	load	(r15+SPRITE_ANIM_ARRAY/4),r10	; anim array address
	move	r7,r8
	shlq	#17,r7		; clear loop flag
	shrq	#16,r8		; COUNTER
	shrq	#14,r7		; INDEX<<3
	move	r10,r11		; copy array address
	add	r7,r10
	subq	#1,r8
	jr	ne,.anim_no_next
	shrq	#3,r7		; INDEX
.anim_next:
	addq	#1<<3,r10
	addq	#1,r7		; INDEX++
	load	(r10),r6	; DATA address
	addq	#4,r10
	cmpq	#0,r6		; is DATA null ?
	jr	ne,.anim_write_data
	loadw	(r10),r8	; SPEED
	jr	.anim_index_fix
	move	r8,r7		; loop INDEX
.anim_no_next:
	jr	.anim_write_data
	load	(r10),r6	; DATA address
.anim_index_fix:
	shlq	#3,r8
	bset	#15,r7		; loop flag
	add	r8,r11
	load	(r11),r6	; DATA address
	addq	#4,r11
	loadw	(r11),r8	; SPEED
.anim_write_data:
	;; r7 = INDEX + loop flag
	;; r8 = COUNTER
	shlq	#16,r8
	or	r8,r7
	jr	.data_ok
	store	r7,(r15+SPRITE_ANIM_DATA/4)
	.endif
.anim_off:
	load	(r15+SPRITE_DATA/4),r6
.data_ok:	
	;; r4 contains the higher bits of snd phrase
	;; r5 contains the lower bits of snd phrase
	;; r6 contains DATA field (in bytes)
	shrq	#3,r6		; DATA in phrases
	load	(r15+SPRITE_Y/4),r7	; Y|X
	move	r5,r9
	move	r7,r8
	shlq	#16,r7
	sharq	#16,r8		; Y
	sharq	#16,r7		; X
	shlq	#22,r9		; keep HEIGHT<<22
	add	r1,r7		; X+DISPLAY_X
	cmpq	#0,r9		; HEIGHT = 0 ?
	jump	eq,(r23)	; yes -> .next_in_layer
	shrq	#22,r9		; HEIGHT
	add	r2,r8		; Y+DISPLAY_Y
	btst	#SPRITE_TYPE,r4
	jump	eq,(r25)	; if non scaled sprite then .non_scaled_sprite
	shrq	#12,r5		; clear for HEIGHT field
.scaled_sprite:
	subq	#1,r9		; HEIGHT-- (fix for scaled sprites)
	jump	eq,(r23)	; if HEIGHT = 0 then .next_in_layer
	move	r5,r11		; to get DWIDTH
	load	(r15+SPRITE_SCALE/4),r12 ; load scale values
	shrq	#6,r11
	btst	#SPRITE_USE_HOTSPOT,r4 ; check if HOTSPOT is used
	jr	eq,.jump_scaled_no_hotspot ; no then nothing to fix
	nop
	load	(r15+SPRITE_HY/4),r16 ; load hotspot shifts
	move	r12,r18		; get scales
	move	r16,r17
	shlq	#16,r18		; to get VSCALE
	sharq	#16,r16		; HY
	shrq	#24,r18		; VSCALE
	shlq	#16,r17		; to get HX
	imult	r18,r16		; HY*VSCALE
	jr	.scaled_continue_hotspot
	move	r12,r18		; get scales
.jump_scaled_no_hotspot:
	jr	.scaled_no_hotspot ; trick to have short jumps 
.scaled_continue_hotspot:
	sharq	#16,r17		; HX
	shlq	#24,r18		; to get HSCALE
	sharq	#5,r16		; get integer part of HY*VSCALE
	shrq	#24,r18		; HSCALE
	sub	r16,r8		; Y -= HY*VSCALE
	imult	r18,r17		; HX*HSCALE
	btst	#SPRITE_REFLECT,r4 ; REFLECT?
	jr	eq,.scaled_hotspot_no_reflect
	sharq	#5,r17		; get integer part of HX*HSCALE
	neg	r17		; negate HX
.scaled_hotspot_no_reflect:
	sub	r17,r7		; X -= HX*HSCALE
.scaled_no_hotspot:	
	cmpq	#0,r8
	jr	pl,.jump_scaled_y_positive	; .scaled_y_positive
	shlq	#22,r11		; DWIDTH << 22
	move	r12,r10
	shlq	#16,r12		; clear REMAINDER
	shrq	#16,r10		; keep REMAINDER
	move	r12,r13
	shlq	#24,r10		; REMAINDER in higher byte
	shrq	#24,r13		; keep VSCALE
	shrq	#16,r12		; VSCALE|HSCALE
	moveq	#1,r16
	shlq	#24,r13		; VSCALE in higher byte
	shlq	#5+24,r16	; 1<<5 in higher byte
	jr	.scaled_sprite_fix_y
	shrq	#22,r11		; DWIDTH
.jump_scaled_y_positive:
	jr	.scaled_y_positive ; trick to have short jumps
.scaled_sprite_fix_y:
	sub	r16,r10		; REMAINDER--
	jr	cc,.scaled_sprite_fix_y_no_add_vscale ; no carry
	nop
.scaled_sprite_fix_y_add_vscale:
	add	r11,r6		; fix DATA
	subq	#1,r9		; HEIGHT--
	jump	eq,(r23)	; if HEIGHT = 0 then .next_in_layer
	add	r13,r10		; add VSCALE to REMAINDER
	jr	cc,.scaled_sprite_fix_y_add_vscale
	nop
.scaled_sprite_fix_y_no_add_vscale:
	addq	#1,r8				; Y++
	jr	ne,.scaled_sprite_fix_y		; not null? 
	nop
	shrq	#8,r10
	or	r10,r12
.scaled_y_positive:
	store	r12,(r14+5)	; write scale values
	jump	(r26)		; goto .y_height_ok
	moveq	#SCBITOBJ,r10	; set TYPE to SCBITOBJ
.non_scaled_sprite:
	btst	#SPRITE_USE_HOTSPOT,r4 ; check if HOTSPOT is used
	jr	eq,.nonscaled_no_hotspot ; no then nothing to fix
	nop
	load	(r15+SPRITE_HY/4),r16	; load hotspot shifts
	move	r16,r17
	sharq	#16,r16		; HY
	shlq	#16,r17		; to get HX
	sub	r16,r8		; Y -= HY
	btst	#SPRITE_REFLECT,r4 ; REFLECT?
	jr	eq,.non_scaled_hotspot_no_reflect
	sharq	#16,r17		; HX
	neg	r17		; negate HX
.non_scaled_hotspot_no_reflect:	
	sub	r17,r7		; X -= HX
.nonscaled_no_hotspot:	
	cmpq	#0,r8
	jr	pl,.non_scaled_y_positive ; if Y >= 0 then nothing to do
	moveq	#BITOBJ,r10	; set TYPE to BITOBJ
	move	r5,r11		; to get DWIDTH
	add	r8,r9		; adjust HEIGHT
	jump	mi,(r23)	; if HEIGHT <= 0 then .next_in_layer
	shrq	#6,r11
	neg	r8		; get |Y|
	shlq	#22,r11		; DWIDTH << 22
	shrq	#22,r11		; DWIDTH
	mult	r8,r11		; |Y|*DWIDTH
	moveq	#0,r8		; Y = 0
	add	r11,r6		; fix DATA
.non_scaled_y_positive:	
.y_height_ok:
	;; r4 contains the higher bits of snd phrase
	;; r5 has been shifted right by 12 bits
	;; r6 contains DATA (in phrases)
	;; r7 contains X
	;; r8 contains Y
	;; r9 contains HEIGHT
	;; r10 contains TYPE
	add	r19,r8		; Y+(a_vdb+1)/2
	shlq	#12,r5		; lower bits of snd phrase ready to receive XPOS
	shlq	#1+21,r8	; Y*2 << 21
	shlq	#20,r7		; keep only the 12 lower bits of X
	shrq	#18,r8		; YPOS
	shlq	#22,r9
	or	r8,r10		; YPOS|TYPE
	move	r14,r11		; LINK
	store	r4,(r14+2)	; write higher bit of snd phrase
	shrq	#8,r9		; HEIGHT ready
	shrq	#3,r11		; in phrases
	or	r9,r10		; HEIGHT|YPOS|TYPE
	addq	#4,r11		; next LINK (4 phrases after)
	shrq	#20,r7		; XPOS
	move	r11,r12		; copy next LINK
	or	r7,r5		; lower bits of snd phrase ready
	move	r12,r13		; copy next LINK
	store	r5,(r14+3)	; write lower bits of snd phrase
	shlq	#24,r11
	shrq	#8,r12
	or	r11,r10		; lower bits of first phrase ready
	shlq	#11,r6
	store	r10,(r14+1)	; write lower bits of first phrase
	or	r12,r6		; higher bits of first phrase ready
	shlq	#3,r13		; prepare next LINK
	store	r6,(r14)
	move	r13,r14		; next object address
.next_in_layer:
	load	(r15+SPRITE_NEXT/4),r15
.do_layer_tst:	
	cmpq	#0,r15		; is sprite address null ?
	jump	ne,(r21)	; if not then continue in layer
	nop
.end_layer:
	subq	#1,r3		; one layer less
	jump	ne,(r20)	; is it finished?
	nop
	;; write a final stop object
	moveq	#STOPOBJ,r0
	or	r0,r0
	store	r0,(r14+1)
.gpu_display_end_it:
	movei	#_vblCounter,r28
	loadw	(r28),r26
	movei	#displayCounter,r28
	storew	r26,(r28)
	.if	DISPLAY_IT_SAVE_REGS
	display_restore_other_regs
	display_restore_first_regs
	.endif
	load	(r31),r28	; return address
	bclr	#3,r29		; clear IMASK
	addq	#2,r28		; next instruction
	addq	#4,r31		; pop from stack
	jump	t,(r28)		; return
	store	r29,(r30)	; restore flags
.gpu_display_driver_loop:
	movei	#.gpu_display_driver_param,r0
	movei	#.gpu_display_driver_loop,r1
	load	(r0),r2		; read SUBROUT_ADDR
	moveq	#0,r3
	cmpq	#0,r2		; SUBROUT_ADDR != null
	jr	eq,.gpu_display_driver_loop ; if null then loop
	nop
	subq	#4,r31		; push on stack
	store	r3,(r0)		; clear SUBROUT_ADDR
	jump	(r2)		; jump to SUBROUT_ADDR
	store	r1,(r31)	; return address
	.long
.gpu_display_driver_param:
GPU_SUBROUT_ADDR	equ	.gpu_display_driver_param
	dc.l	0
	.long
.gpu_display_driver_init:
	;; assume run from bank 1
	movei	#GPU_ISP+(GPU_STACK_SIZE*4),r31	; init isp
	moveq	#0,r1
	moveta	r31,r31		; ISP (bank 0)
	movei	#.gpu_display_driver_param,r0
	movei	#.gpu_display_driver_loop,r2
	movei	#GPU_USP+(GPU_STACK_SIZE*4),r31	; init usp
	;; enable interrupts
	movei	#G_FLAGS,r28
	.if	DISPLAY_USE_OP_IT
	movei	#G_OPENA|REGPAGE,r29
	.else
	movei	#G_CPUENA|REGPAGE,r29
	.endif
	store	r29,(r28)
	;; jump to driver
	jump	(r2)
	store	r1,(r0)		; clear SUBROUT_ADDR (mutex)
	.long
.gpu_display_driver_end:
		
DISPLAY_DRIVER_INIT	equ	.gpu_display_driver_init
DISPLAY_DRIVER_SIZE	equ	.gpu_display_driver_end-.gpu_display_driver_begin

GPU_FREE_RAM		set	.gpu_display_driver_init

	.print	"Display manager code size (GPU): ", DISPLAY_DRIVER_SIZE
	.print	"Available GPU Ram after G_RAM+",GPU_FREE_RAM-G_RAM
				
	.68000

	.globl	GPU_SUBROUT_ADDR
	.globl	__GPU_FREE_RAM
__GPU_FREE_RAM	equ	GPU_FREE_RAM

	.globl	_init_display_driver	
_init_display_driver:
	move.l	#0,G_CTRL
	move.l	#_stop_object,d0
	swap	d0
	move.l	d0,OLP
	.if	!(DISPLAY_USE_OP_IT&!DISPLAY_OP_IT_COMP_PT)
	clr.l	active_display_list
	.endif
	clr.w	displayCounter
	;; copy GPU code
	pea	DISPLAY_DRIVER_SIZE	
	pea	G_RAM
	pea	gpu_display_driver
	jsr	_bcopy
	lea	12(sp),sp
	;; set GPU for interrupts
	move.l	#REGPAGE,G_FLAGS
	;; launch the driver
	move.l	#GPU_SUBROUT_ADDR,a0
	move.l	#$ffffffff,(a0)
	move.l	#DISPLAY_DRIVER_INIT,G_PC
	move.l	#GPUGO,G_CTRL
.wait_init:
	tst.l	(a0)
	bne.s	.wait_init
	move.w	#0,OBF
	rts

	.globl	_show_display
_show_display:
	move.l	4(sp),d0
	.if	!(DISPLAY_USE_OP_IT&!DISPLAY_OP_IT_COMP_PT)
	move.l	d0,active_display_list
	.endif
	.if	DISPLAY_SWAP_METHOD
	add.l	#DISPLAY_LIST,d0
	swap	d0
	move.l	d0,OLP
	.else
	move.l	d0,a0
	move.l	DISPLAY_PHYS(a0),d0
	swap	d0
	move.l	d0,OLP
	.endif
	rts

	.globl	_hide_display
_hide_display:
	move.l	#_stop_object,d0
	swap	d0
	move.l	d0,OLP
	rts
	
	.globl	_jump_gpu_subroutine
_jump_gpu_subroutine:
	move.l	4(sp),GPU_SUBROUT_ADDR
	rts

	.globl	_wait_display_refresh
_wait_display_refresh:
	move.l	#_vblCounter,a0
	move.l	#displayCounter,a1
.wait:
	move.w	(a0),d0		; inside the loop because interrupts can occur at any time
	cmp.w	(a1),d0
	bne.s	.wait
	rts

	.bss
	
	.if	!(DISPLAY_USE_OP_IT&!DISPLAY_OP_IT_COMP_PT)	
	.long
active_display_list:	ds.l	1
	.endif

	.bss
displayCounter:	
	ds.w	1
			
	.data
	.even
	dc.b	"Display Driver by Seb/The Removers"
	.even


