;;;;;;;;;;;;;; Header / Startup Code ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "HEADER"    
	.byte   "NES", $1A      ; iNES header identifier
	.byte   2               ; 2x 16KB PRG code
	.byte   1               ; 1x  8KB CHR data
	.byte   $01, $00        ; mapper 0, vertical mirroring

.segment "STARTUP"

.segment "CODE"

reset:
.include "include/reset.s"

;;;;;;;;;;;;;; Macros ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.macro vram hi, lo
	pha
	lda hi
	sta $2006
	lda lo
	sta $2006
	pla
.endmacro

.macro strobe
	pha
	lda #$01
	sta $4016
	lda #$00
	sta $4016
	pla
.endmacro

.macro tile add_x, add_y
	lda ball_x
	adc add_x
	sta $00
	lda ball_y
	adc add_y
	sta $01
	jsr get_tile
.endmacro

.macro addr label
	pha
	lda #.LOBYTE(label)
	sta $00
	lda #.HIBYTE(label)
	sta $01
	pla
.endmacro

.macro load_attrs label
.scope
	vram #$23, #$c0
	ldx #$00
@loop:	lda label, x
	sta $2007
	inx
	cpx #$40
	bne @loop
.endscope
.endmacro


;;;;;;;;;;;;;; Global Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


; Pallet cycle timer and delay
palette_timer = $0300
palette_delay = $0b

; Paddle's palette state
paddle_state = $0301

; Master game states
game_state = $0302

.enum State
	TITLE
	NEW
	PLAYING
	LOSE_LIFE
	PAUSED
	GAMEOVER
.endenum

; Ball position
ball_x = $0203
ball_y = $0200

; Ball direction
ball_dx = $0303
ball_dy = $0304

; Whether or not the ball is moving
ball_moving = $0305

; Flag that determines if start was held last frame
start_down = $0306

; Whether or not the game is paused
game_paused = $0307

; Paddle position
paddle_x = $0207

; Number of hits required to destroy a block
; Can be: #$44, #$46, #$48, #$4A
; Used in conjunction with the 'block_hit' routine
;
; TODO Not working yet, fixme!
;
block_destroyed = $0208


;;;;;;;;;;;;;; Main Program ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main:
	; Load the default palette
	jsr load_palette

	; Set the game state to the title screen
	lda #State::TITLE
	sta $00
	jsr change_state

	lda #$44
	sta block_destroyed

	; Reset VRAM address
	vram #0, #0

forever:
	jmp forever


;;;;;;;;;;;;;; Game Loop (NMI) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
game_loop:
	lda game_state
	
@title:	bne @play
	jsr title_loop
	jmp cleanup

@play:	cmp #State::PLAYING
	bne @pause
	jsr play_loop
	jmp cleanup

@pause:	cmp #State::PAUSED
	bne @over
	jsr pause_loop
	jmp cleanup

@over:  ; TODO Implement me

cleanup:
	lda #$00 	; Draw sprites
	sta $2003
	lda #$02
	sta $4014
	vram #0, #0 	; Clear VRAM Address
	rti

;;;;;;;;;;;;;; Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
; Game loop code for the title screen
;
title_loop:
	; Strobe the controller
	strobe

	; Proceed to the start button
	lda $4016
	lda $4016
	lda $4016

	; Read the start button
	lda #$01
	and $4016
	beq @done

	; Indicate that the start button is being pressed
	lda #1
	sta start_down

	; Change to the new game state if they pressed start
	lda #State::NEW
	sta $00
	jsr change_state

@done:	rts
	
;
; Game loop code for the main game
;
play_loop:
	; Strobe the controller
	strobe


	; A - Gets the ball moving at the start of the game
button_a:
	lda #$01
	and $4016
	beq button_start

	lda ball_moving
	bne button_start

	lda #$01
	sta ball_moving


	; Start - Pauses the game
button_start:
	lda $4016 ; Skip B
	lda $4016 ; Skip Select
	
	lda start_down
	bne @ignore

	lda #$01
	and $4016
	beq button_left

	lda #1
	sta start_down

	lda #State::PAUSED
	sta $00
	jsr change_state
	rts

@ignore:
	lda #$01
	and $4016
	sta start_down

	
button_left:
	lda $4016 ; Skip Up
	lda $4016 ; Skip Down

	lda #$01
	and $4016
	beq button_right

	lda $0207
	cmp #$10
	beq check_palette_timer

	ldx #$02
	lda ball_moving
	beq @move_with_ball

@move:
	dec $0207
	dec $020b
	dec $020f
	dec $0213
	dex
	bne @move
	jmp @done_left

@move_with_ball:
	dec $0207
	dec $020b
	dec $020f
	dec $0213
	dec $0203
	dex
	bne @move_with_ball

@done_left:
	jmp check_palette_timer

button_right:
	lda #$01
	and $4016
	beq check_palette_timer

	lda $0213
	cmp #$e6
	beq check_palette_timer

	ldx #$02
	lda ball_moving
	beq @move_with_ball

@move:
	inc $0207
	inc $020b
	inc $020f
	inc $0213
	dex
	bne @move
	jmp @done_right

@move_with_ball:
	inc $0207
	inc $020b
	inc $020f
	inc $0213
	inc $0203
	dex
	bne @move_with_ball

@done_right:


check_palette_timer:
	inc palette_timer
	ldx palette_timer
	cpx #palette_delay
	beq @cycle_palette
	jmp @done
	
@cycle_palette:
	ldx #$00
	stx palette_timer

	inc paddle_state
	lda paddle_state
	and #$07
	sta paddle_state
	tax
	vram #$3f, #$12
	lda paddle_cycle, x
	sta $2007
@done:


check_hit:
	bit $2002
	bvs check_x
	jmp check_paddle

check_x:
	lda ball_dx
	bne check_right

check_left:
	; (x, y+4)
	tile #0, #4
	cmp #$ff
	beq check_y
	jsr block_hit
	lda #1
	sta ball_dx
	jmp check_y

check_right:
	; (x+7, y+3)
	tile #7, #3
	cmp #$ff
	beq check_y
	jsr block_hit
	lda #0
	sta ball_dx

check_y:
	lda ball_dy
	bne check_down

check_up:
	; (x+3, y)
	tile #3, #0
	cmp #$ff
	beq check_paddle
	jsr block_hit
	lda #1
	sta ball_dy
	jmp check_paddle

check_down:
	; (x+4, y+7)
	tile #4, #7
	cmp #$ff
	beq check_paddle
	jsr block_hit
	lda #0
	sta ball_dy

check_paddle:
	lda ball_y
	cmp #$c0
	bne check_lose

	; ball_x >= paddle_x
	lda ball_x
	cmp paddle_x
	bcc check_lose

	; paddle_x + 33 >= ball_x
	clc
	lda paddle_x
	adc #$21
	cmp ball_x
	bcc check_lose

	; The paddle is in the right spot!
	lda #0
	sta ball_dy

check_lose:
	lda ball_y
	cmp #$f0
	bcc move_ball

	lda #State::LOSE_LIFE
	sta $00
	jsr change_state
	rts

move_ball:
	lda ball_moving
	beq @done_y

	; Move the ball in the x-coordinate
	lda ball_dx
	bne @move_right
	dec $0203
	jmp @done_x
@move_right:
	inc $0203
@done_x:
	
	; Move the ball in the y-coordinate
	lda ball_dy
	bne @move_down
	dec $0200
	jmp @done_y
@move_down:
	inc $0200
@done_y:

	rts


;
; Game loop for the paused state
;
pause_loop:
	strobe
	lda $4016
	lda $4016
	lda $4016

	lda start_down
	bne @skip

	lda #$01
	and $4016
	beq @done

	sta start_down
	lda #State::PLAYING
	sta $00
	jsr change_state
	rts

@skip:	lda #$01
	and $4016
	sta start_down

@done:	rts


;
; Sets the game state
;
; Params:
;	$00 - The state to set
;
change_state:
	; Store the new game state
	lda $00
	sta game_state

@title: 
	cmp #State::TITLE
	bne @new_game

	; Disable NMI, sprites, and background
	lda #$00
	sta $2000
	sta $2001

	; Load the title screen
	jsr clear_sprites
	jsr draw_title

	; Wait for VBLANK
@wait:	bit $2002
	bpl @wait

	; Enable NMI
	lda #%10000000
	sta $2000

	; Enable background
	lda #%00001000
	sta $2001

	jmp @return

@new_game:
	cmp #State::NEW
	bne @lose_life

	; Disable NMI, sprites, and background
	lda #$00
	sta $2000
	sta $2001

	; Load sprites for main game play
	jsr clear_sprites
	jsr load_sprites
	
	; Reset the palette timer and paddle palette state
	lda #$00
	sta palette_timer
	sta paddle_state

	; Reset the ball dx, dy
	sta ball_dx
	sta ball_dy

	; Reset ball moving and game paused
	sta ball_moving
	sta game_paused

	; Set the game state to "playing"
	lda #State::PLAYING
	sta game_state
	
	; Draw the game board
	jsr draw_board

	; Wait for VBLANK
@wait2:	bit $2002
	bpl @wait2

	; Enable NMI, sprites and background
	lda #%10000000
	sta $2000
	lda #%00011110
	sta $2001

	jmp @return

@lose_life:
	cmp #State::LOSE_LIFE
	bne @playing

	; Disable NMI
	lda #$00
	sta $2000

	; TODO Add lives code here

	; Reset ball and paddle position
	lda #$00
	sta ball_dx
	sta ball_dy
	sta ball_moving
	jsr load_sprites

	; Jump into the "playing state"
	lda #State::PLAYING
	sta game_state

	; Enable NMI
	lda #%10000000
	sta $2000

	jmp @return

@playing:
	cmp #State::PLAYING
	bne @paused

	; Swtich to color mode
	lda #%00011110
	sta $2001

	jmp @return

@paused:
	cmp #State::PAUSED
	bne @game_over

	; Switch to monochrome mode
	lda #%00011111
	sta $2001

	jmp @return

@game_over:
	; TODO Implement me


@return:
	rts


;;;;;;;;;;;;;; Drawing Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;
; Clears sprite memory
;
clear_sprites:
	lda #$ff
	ldx #$00
@clear:	sta $0200, x
	inx
	bne @clear
	rts


;
; Clears nametable memory
;
clear_nametable:
	ldx #$00
	ldy #$04
	lda #$FF
	vram #$20, #$00
@loop:	sta $2007
	inx
	bne @loop
	dey
	bne @loop
	rts

;
; Loads sprites into sprite memory
;
load_sprites:
	; Load the paddle and ball
	ldx #$00
@loop:	lda sprites, x
	sta $0200, x
	inx
	cpx #$14
	bne @loop
	rts


;
; loads the game's master palette
; 
load_palette:
	ldx #$00
	vram #$3f, #$00
@loop:	lda palette, x
	sta $2007
	inx
	cpx #$20
	bne @loop
	rts


;
; Draws the game's main title screen to VRAM
;
draw_title:
	jsr clear_nametable

	; Load the attribute table
	load_attrs title_attr
	
.scope	; Draw the logo into the nametable
	col = 8
	row = 10
	address = $2000 + col + (row * $20)
	
	lo = $20
	hi = $21
	
	lda #.HIBYTE(address)
	sta hi
	lda #.LOBYTE(address)
	sta lo

	ldy #$00
@row:	vram hi, lo
	ldx #$10
@col:	sty $2007
	iny
	dex
	bne @col
	
	clc
	lda lo
	adc #$20
	sta lo
	lda #$00
	adc hi
	sta hi

	cpy #$40
	bne @row
.endscope

	
.scope	; print "Press Start"
	col = 10
	row = 17
	address = $2000 + col + (row * $20)
	vram #.HIBYTE(address), #.LOBYTE(address)
	addr press_start
	jsr prints
.endscope

	rts

;
; Draws the main game board to the nametable
;
draw_board:
	jsr clear_nametable

	; Load the attribute table
	load_attrs board_attr

	; Top left corner (1, 1)
	vram #$20, #$21
	lda #$4b
	sta $2007

	; Top right corner (30, 1)
	vram #$20, #$3e
	lda #$4d
	sta $2007

	; Bottom left corner (1, 26)
	vram #$23, #$21
	lda #$51
	sta $2007

	; Bottom right corner (30, 26)
	vram #$23, #$3e
	lda #$53
	sta $2007

	; Top Border
	vram #$20, #$22
	ldx #$1c
	lda #$4c
@loop:	sta $2007
	dex
	bne @loop

	; Set write increments to 32
	lda #%00000100
	sta $2000
	
	; Left Border
	vram #$20, #$41
	lda #$4e
	ldx #$17
@loop2:	sta $2007
	dex
	bne @loop2

	; Right Border
	vram #$20, #$5e
	lda #$50
	ldx #$17
@loop3:	sta $2007
	dex
	bne @loop3

	; Set write increments back to 1
	lda #%00000000
	sta $2000

	; Setup the blocks
	vram #$20, #$82
	jsr block_row
	vram #$20, #$a2
	jsr block_row
	vram #$20, #$c2
	jsr block_row
	vram #$20, #$e2
	jsr block_row
	vram #$21, #$02
	jsr block_row
	vram #$21, #$22
	jsr block_row

	rts

;
; Draws a row of game blocks.
; Note: Call this after setting the vram address with $2006
;
block_row:
	ldx #$0e
@loop:	lda #$42
	sta $2007
	lda #$43
	sta $2007
	dex
	bne @loop
	rts


;
; Prints a null terminated string into VRAM. Strings are
; limited to 256 characters in length. 
;
; Note: Caller is responsible for setting the appropriate 
;       VRAM address.
;
; Params:
;	$00 - Low byte of the memory address of the string.
;	$01 - High byte of the memory address of the string.
;
prints:
	ldy #$00
@loop:	lda ($00), y
	beq @break
	clc
	adc #$34
	sta $2007
	iny
	bne @loop
@break:	rts


;;;;;;;;;;;;;; Lookup & Math Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


; Performs a 16-bit arithmetic shift left.
; 
; Params:
; 	$00 - Low byte of the 16-bit value operand
; 	$01 - High byte of the 16-bit value operand
; 	$02 - Shift operand
;
; Return:
; 	$00 - The low byte of the result
;	$01 - The high byte of the result
asl16:
	ldx $02
@loop:	asl $01
	asl $00
	bcc @cont
	inc $01
@cont:	dex
	bne @loop
	rts


; Performs an add with two 16-bit operands storing
; the result in the first operand.
;
; Params:
; 	$00 - Low byte of the first operand
; 	$01 - High byte of the first operand
; 	$02 - Low byte of the second operand
; 	$03 - High byte of the second operand
;
; Return:
; 	$00 - The low byte of the result
;	$01 - The high byte of the result
add16:
	clc
	lda $02
	adc $00
	sta $00
	lda $03
	adc $01
	sta $01
	rts

; Find the tile in the nametable at the point (x, y).
;
; Params:
; 	$00 - x-coordinate
;	$01 - y-coordinate
;
; Return:
; 	A   - The value of the tile at that address
;	$00 - The low byte of the address
; 	$01 - The high byte of the address
get_tile:
	; Nab the x value and hold onto it
	ldy $00 

	; Calculate the offset into VRAM
	; Tile(x, y) = ($00, $01) = (y / 8) * 32 + (x / 8)

	; (y / 8) * 32 = (y & #$f8) << 2
	lda $01
	and #$f8
	sta $00
	lda #0
	sta $01
	lda #2
	sta $02
	jsr asl16

	; (x / 8)
	tya
	lsr
	lsr
	lsr

	; [(y/8) * 32] + (x/8)
	sta $02
	lda #0
	sta $03
	jsr add16


	; Find that tile in VRAM
	lda $01
	adc #$20
	sta $2006
	sta $01

	lda $00
	sta $2006

	lda $2007
	lda $2007

	rts

;
; Determines if the given vram address represents a block
; and causes a game "collision" to occur if it is.
;
; Params:
;	$00 - Low byte of the vram address
;	$01 - High byte of the vram addres
;
block_hit:
	; Check the tile to see if it's a block
	vram $01, $00
	lda $2007
	lda $2007

	; t >= $42
	clc
	cmp #$42
	bcc @return

	; t < $4A
	clc
	cmp #$4A
	bcs @return

	; Check to see if the tile is the left or right side
	; of the block
	tax
	and #$01
	bne @right

@left:
	txa
	clc
	adc #$02
	cmp #$46;block_destroyed
	beq @clear_left

	vram $01, $00
	sta $2007
	tax
	inx
	stx $2007
	jmp @return

@clear_left:
	lda #$ff
	vram $01, $00
	sta $2007
	sta $2007
	jmp @return

@right:
	txa
	clc
	adc #$01
	cmp #$46;block_destroyed
	beq @clear_right

	dec $00
	vram $01, $00
	sta $2007
	tax
	inx
	stx $2007
	jmp @return


@clear_right:
	lda #$ff
	dec $00
	vram $01, $00
	sta $2007
	sta $2007

@return:
	rts



;;;;;;;;;;;;;; Palettes, Nametables, etc. ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

palette:
	; Background
	.byte $0f, $03, $19, $00
	.byte $0f, $00, $10, $20
	.byte $0f, $09, $19, $29
	.byte $0f, $00, $00, $00

	; Sprites
	.byte $0f, $00, $08, $10
	.byte $0f, $06, $16, $27
	.byte $0f, $00, $00, $00
	.byte $0f, $00, $00, $00


sprites:
	; Ball (sprite 0)
	.byte $c0, $4a, %00000001, $7c

	; Paddle
	.byte $c8, $40, %00000000, $70
	.byte $c8, $41, %00000000, $78
	.byte $c8, $41, %01000000, $80
	.byte $c8, $40, %01000000, $88


paddle_cycle:
	.byte $08, $18, $28, $38
	.byte $28, $18, $08, $0f


title_attr:
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00


board_attr:
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21

press_start:
	.byte "PRESS START", $00

score:
	.byte "SCORE:", $00


;;;;;;;;;;;;;; Pattern Table (CHR-ROM) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.segment "CHARS"
.include "include/logo.s"	; $00 - $3f
.include "include/paddle.s"	; $40 - $41
.include "include/blocks.s"	; $42 - $49
.include "include/ball.s"	; $4a
.include "include/wall.s"	; $4b - $53
.include "include/font.s"	; $54 - $b9

;;;;;;;;;;;;;; Vectors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.segment "VECTORS"
.word 0, 0, 0, game_loop, reset, 0
