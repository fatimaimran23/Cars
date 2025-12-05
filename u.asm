//EDITED AFTER TA ASKED TO INCREASE THE SPEED 
org 100h
%define CAR_WIDTH  26
%define CAR_HEIGHT 32
%define BONUS_SIZE 16

jmp start

; variables
car_x dw 107          ; car x position (left lane)
car_y dw 160          ; car y position
current_lane db 0     ; 0=left, 1=middle, 2=right
scroll_offset dw 0    ; for scrolling animation
spawn_counter dw 0    ; for obstacle spawning
bonus_counter dw 0    ; for bonus spawning
old_timer_isr dd 0    ; store original timer isr adress
old_keyboard_isr dd 0 ; store original keyboard isr address
timer_tick_count dw 0 ; count timer ticks for scroll timing
scroll_delay dw 1     ; ticks before scroll (adjust for speed)
scroll_ready db 0     ; flag: 1 when its time to scroll
key_pressed db 0      ; key scan code from interrupt
game_paused db 0      ; flag: 1 when game is paused
esc_pressed db 0      ; flag: 1 when esc is pressed

; text strings for screens
game_title db "RACING GAME", 0
student_info db "By: Maliha (0660), Fatima (0588)", 0
semester_info db "Semester: Fall 2025", 0
press_any_key db "Press any key to start...", 0
exit_confirm_msg db "Do you want to exit? (Y/N)", 0
score_msg db "Your Score: ",0
game_over_msg db "GAME OVER!", 0
score_text_small db "Score:", 0
pause_title db "GAME PAUSED", 0
pause_resume db "Press R to Resume", 0
pause_quit db "Press Q to Quit", 0
score_text_inline db "Score: ", 0

; obstacle car variables
obstacle_active db 0      
obstacle_x dw 0          
obstacle_y dw 0          
obstacle_lane db 0  

; bonus object stuff
bonus_active db 0
bonus_x dw 0
bonus_y dw 0
bonus_lane db 0
     
collision_detected db 0   ; flag for collision
game_over db 0            ; flag for game over state
score dw 0                ; player score

; start
start:

; setup video mode
mov ax, 13h
int 10h             ; set 320x200 graphics mode

mov ax, 0A000h
mov es, ax          ; video memory segment

; color palette
call setup_palette

; show intro screen
call show_intro_screen

; wait for keypress to start
wait_start_key:
    mov ah, 00h
    int 16h         ; wait for any key

; reset flags before game starts
mov byte [scroll_ready], 0
mov byte [game_paused], 0
mov byte [esc_pressed], 0
mov byte [key_pressed], 0

; draw initial screen
call draw_landscape
call draw_road
call draw_road_borders
call draw_lane_dividers
call draw_decorations

; draw car at initial pos
mov bx, [car_x]
mov cx, [car_y]
call draw_car_sprite

; install interrupts after drawing initial screen
call install_timer_isr
call install_keyboard_isr

; game loop
game_loop:
    ; check if game over first
    cmp byte [game_over], 1
    jne game_not_over
    jmp handle_game_over
game_not_over:

    ; check if esc was pressed (pause)
    cmp byte [esc_pressed], 1
    jne not_paused
    call show_pause_screen
    jmp game_loop
not_paused:

    ; check if game is paused
    cmp byte [game_paused], 1
    je game_loop            ; skip game logic if paused

    ; process keyboard input from interupt
    cli
    mov al, [key_pressed]
    mov byte [key_pressed], 0   ; clear the key
    sti
    
    cmp al, 0
    je no_key_action
    
    ; check right arrow (scan code 4Dh)
    cmp al, 4Dh
    je do_handle_right
    
    ; check left arrow (scan code 4Bh)
    cmp al, 4Bh
    je do_handle_left
    
    jmp no_key_action

do_handle_right:
    cmp byte [current_lane], 2
    jge no_key_action
    
    mov bx, [car_x]
    mov cx, [car_y]
    call erase_car
    
    inc byte [current_lane]
    add word [car_x], 40
    
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite
    jmp no_key_action

do_handle_left:
    cmp byte [current_lane], 0
    jle no_key_action
    
    mov bx, [car_x]
    mov cx, [car_y]
    call erase_car
    
    dec byte [current_lane]
    sub word [car_x], 40
    
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite

no_key_action:
    ; check if its time to scroll
    cli
    mov al, [scroll_ready]
    mov byte [scroll_ready], 0
    sti
    
    cmp al, 1
    jne skip_scroll_this_frame
    
    call scroll_background_only
    
    
skip_scroll_this_frame:
    ; display score
    call display_score_ingame
    
    ; generate new objects if needed
    call generate_obstacle
    call generate_bonus
   
    ; update positions
    call update_obstacle_position
    call update_bonus_position
   
    ; check for collisions before drawing
    call check_bonus_collision
    call check_collision
   
    ; draw player car
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite
   
    ; draw obstacle if active
    cmp byte [obstacle_active], 0
    je skip_draw_obs_loop
    mov bx, [obstacle_x]
    mov cx, [obstacle_y]
    call draw_obstacle_sprite
skip_draw_obs_loop:
   
    ; draw bonus if active
    cmp byte [bonus_active], 0
    je skip_draw_bon_loop
    mov bx, [bonus_x]
    mov cx, [bonus_y]
    call draw_bonus_sprite
skip_draw_bon_loop:
   
    ; small delay
    call delay

    jmp game_loop

; show pause screen
show_pause_screen:
    push ax
    push bx
    push cx
    push dx
    push si
    
    mov byte [game_paused], 1
    mov byte [esc_pressed], 0
    
    ; draw pause overlay (dark box in center)
    mov cx, 70
pause_bg_y:
    push cx
    mov dx, 80
pause_bg_x:
        mov di, cx
        imul di, 320
        add di, dx
        mov byte [es:di], 1     ; dark blue backround
        inc dx
        cmp dx, 240
        jl pause_bg_x
    pop cx
    inc cx
    cmp cx, 130
    jl pause_bg_y
    
    ; draw border
    mov cx, 70
pause_border_top:
    mov di, 70
    imul di, 320
    add di, cx
    mov byte [es:di], 15
    add di, 80
    mov byte [es:di+79], 15
    inc cx
    cmp cx, 240
    jl pause_border_top
    
    ; display pause text
    mov dh, 10
    mov dl, 15
    mov si, pause_title
    mov bl, 14
    call print_string
    
    mov dh, 13
    mov dl, 12
    mov si, pause_resume
    mov bl, 15
    call print_string
    
    mov dh, 15
    mov dl, 13
    mov si, pause_quit
    mov bl, 15
    call print_string
    
pause_wait_key:
    ; wait for r or q
    mov ah, 00h
    int 16h
    
    cmp al, 'R'
    je resume_game
    cmp al, 'r'
    je resume_game
    cmp al, 'Q'
    je quit_from_pause
    cmp al, 'q'
    je quit_from_pause
    
    jmp pause_wait_key
    
resume_game:
    mov byte [game_paused], 0
    mov byte [esc_pressed], 0
    
    ; redraw the game screen
    call draw_landscape
    call draw_road
    call draw_road_borders
    call draw_lane_dividers
    call draw_decorations
    
    ; redraw player car
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite
    
    ; redraw obstacle if active
    cmp byte [obstacle_active], 0
    je skip_redraw_obs
    mov bx, [obstacle_x]
    mov cx, [obstacle_y]
    call draw_obstacle_sprite
skip_redraw_obs:
    
    ; redraw bonus if active
    cmp byte [bonus_active], 0
    je skip_redraw_bon
    mov bx, [bonus_x]
    mov cx, [bonus_y]
    call draw_bonus_sprite
skip_redraw_bon:
    
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
    
quit_from_pause:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    jmp exit_game

; handle game over
handle_game_over:
    call restore_keyboard_isr
    call restore_timer_isr
    
    call delay
    call delay
   
    jmp show_exit_screen

; exit
exit_game:
    call restore_keyboard_isr
    call restore_timer_isr

show_exit_screen:
    ; switch to text mode
    mov ax, 3h
    int 10h
   
    ; clear screen
    mov ah, 06h
    mov al, 0
    mov bh, 17h
    mov cx, 0
    mov dx, 184Fh
    int 10h
   
    ; show game over if colision
    cmp byte [collision_detected], 1
    jne skip_game_over_text
   
    mov dh, 8
    mov dl, 30
    mov si, game_over_msg
    call print_string_text
   
skip_game_over_text:
    ; show score
    mov dh, 10
    mov dl, 28
    mov si, score_msg
    call print_string_text
   
    ; display score number
    mov ax, [score]
    mov dh, 10
    mov dl, 42
    call print_number_text
   
    ; show exit confirmation
    mov dh, 12
    mov dl, 22
    mov si, exit_confirm_msg
    call print_string_text
   
wait_exit_response:
    mov ah, 00h
    int 16h
   
    cmp al, 'Y'
    je confirm_exit
    cmp al, 'y'
    je confirm_exit
   
    cmp al, 'N'
    je cancel_exit
    cmp al, 'n'
    je cancel_exit
   
    jmp wait_exit_response

confirm_exit:
    ; final safe termination
    mov ax, 3h
    int 10h
    
    ; show clean exit msg
    mov ah, 09h
    mov dx, exit_message
    int 21h
    
    int 20h

exit_message db "Game exited safely. Thank you for playing!$"

cancel_exit:
    ; reset game state
    mov byte [collision_detected], 0
    mov byte [game_over], 0
    mov byte [obstacle_active], 0
    mov byte [bonus_active], 0
    mov word [score], 0
    mov word [spawn_counter], 0
    mov word [bonus_counter], 0
    mov byte [scroll_ready], 0
    mov word [timer_tick_count], 0
    mov byte [game_paused], 0
    mov byte [esc_pressed], 0
    mov byte [key_pressed], 0
    
    ; reset player position
    mov word [car_x], 107
    mov word [car_y], 160
    mov byte [current_lane], 0
    
    ; return to graphics mode
    mov ax, 13h
    int 10h
   
    mov ax, 0A000h
    mov es, ax
   
    call setup_palette
    call draw_landscape
    call draw_road
    call draw_road_borders
    call draw_lane_dividers
    call draw_decorations
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite
    
    ; reinstall interrupts
    call install_timer_isr
    call install_keyboard_isr
    
    jmp game_loop

; install keyboard isr (int 9)
install_keyboard_isr:
    push ax
    push bx
    push dx
    push es
    
    cli
    
    ; save old keyboard isr
    mov ax, 3509h
    int 21h
    mov word [old_keyboard_isr], bx
    mov word [old_keyboard_isr+2], es
    
    ; install new keyboard isr
    push ds
    push cs
    pop ds
    mov dx, keyboard_isr
    mov ax, 2509h
    int 21h
    pop ds
    
    sti
    
    pop es
    pop dx
    pop bx
    pop ax
    ret

; keyboard isr (int 9)
keyboard_isr:
    push ax
    push ds
    
    push cs
    pop ds
    
    ; read scan code from keyboard port
    in al, 60h
    
    ; check if its a key press (not release)
    test al, 80h
    jnz kbd_done
    
    ; check for esc (scan code 01h)
    cmp al, 01h
    jne not_esc_key
    mov byte [esc_pressed], 1
    jmp kbd_done
    
not_esc_key:
    ; check for left arrow (4Bh)
    cmp al, 4Bh
    je store_key
    
    ; check for right arrow (4Dh)
    cmp al, 4Dh
    je store_key
    
    jmp kbd_done
    
store_key:
    mov [key_pressed], al
    
kbd_done:
    pop ds
    pop ax
    
    ; jump to original keyboard isr
    jmp far [cs:old_keyboard_isr]

; restore keyboard isr
restore_keyboard_isr:
    push ax
    push bx
    push dx
    push ds
    
    cli
    
    ; check if valid
    mov ax, [old_keyboard_isr]
    or ax, [old_keyboard_isr+2]
    jz skip_restore_kbd
    
    ; restore original keyboard isr
    mov dx, [old_keyboard_isr]
    mov bx, [old_keyboard_isr+2]
    mov ds, bx
    mov ax, 2509h
    int 21h
    
    push cs
    pop ds
    mov word [old_keyboard_isr], 0
    mov word [old_keyboard_isr+2], 0
    
skip_restore_kbd:
    sti
    
    pop ds
    pop dx
    pop bx
    pop ax
    ret

; print string in text mode
print_string_text:
    push ax
    push bx
    push si
   
    mov ah, 02h
    mov bh, 0
    int 10h
   
print_text_loop:
    lodsb
    cmp al, 0
    je print_text_done
   
    mov ah, 0Eh
    mov bh, 0
    mov bl, 15
    int 10h
    jmp print_text_loop
   
print_text_done:
    pop si
    pop bx
    pop ax
    ret

; print number in text mode
print_number_text:
    push ax
    push bx
    push cx
    push dx
    push si             ; save si register
    
    mov si, ax          ; save the number in si before modifying ax
    
    ; set cursor position (this destroys ah)
    mov ah, 02h
    mov bh, 0
    int 10h
    
    mov ax, si          ; restore the number from si
    
    ; check if number is zero
    test ax, ax
    jnz do_convert_num
    
    ; print "0" for zero case
    mov ah, 0Eh
    mov al, '0'
    mov bh, 0
    int 10h
    jmp print_num_text_done
   
do_convert_num:
    mov bx, 10
    mov cx, 0
   
convert_num_loop:
    xor dx, dx
    div bx
    push dx             ; save remainder (digit)
    inc cx              ; count digits
    test ax, ax
    jnz convert_num_loop
   
print_num_loop:
    pop ax              ; get digit
    add al, '0'         ; convert to ascii
    mov ah, 0Eh
    mov bh, 0
    int 10h
    loop print_num_loop
   
print_num_text_done:
    pop si              ; restore si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; scroll background only
scroll_background_only:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    mov cx, 198
scroll_bg_loop:
    push cx
   
    mov si, cx
    imul si, 320
    
    mov di, cx
    inc di
    imul di, 320
   
    mov bx, 0
copy_left_land:
        mov al, [es:si+bx]
        mov [es:di+bx], al
        inc bx
        cmp bx, 100
        jl copy_left_land
    
    mov bx, 100
copy_road_section:
        mov al, [es:si+bx]
        mov [es:di+bx], al
        inc bx
        cmp bx, 220
        jl copy_road_section
    
    mov bx, 220
copy_right_land:
        mov al, [es:si+bx]
        mov [es:di+bx], al
        inc bx
        cmp bx, 320
        jl copy_right_land
   
    pop cx
    dec cx
    cmp cx, 10              ; stop at row 10 to protect hud area (rows 0-9)
    jge scroll_bg_loop
   
    call redraw_top_row
   
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; redraw top row
; redraws row 10 (first game row after hud area)
redraw_top_row:
    push ax
    push bx
    push cx
    push dx
    push di
   
    inc word [scroll_offset]
    cmp word [scroll_offset], 20
    jl continue_redraw
    mov word [scroll_offset], 0
   
continue_redraw:
    ; row 10 = 10 * 320 = 3200
    mov dx, 0
redraw_left:
        mov di, 3200            ; row 10 instead of row 0
        add di, dx
        mov al, 2
        mov bl, dl
        add bl, byte [scroll_offset]
        test bl, 2
        jz skip_tint_top
        inc al
skip_tint_top:
        mov [es:di], al
        inc dx
        cmp dx, 100
        jl redraw_left
   
    mov dx, 100
redraw_road_top:
        mov di, 3200            ; row 10
        add di, dx
        mov al, 7
        mov [es:di], al
        inc dx
        cmp dx, 220
        jl redraw_road_top
   
    mov dx, 220
redraw_right:
        mov di, 3200            ; row 10
        add di, dx
        mov al, 2
        mov bl, dl
        add bl, byte [scroll_offset]
        test bl, 2
        jz skip_tint_top2
        inc al
skip_tint_top2:
        mov [es:di], al
        inc dx
        cmp dx, 320
        jl redraw_right
   
    ; draw border at row 10
    mov di, 3200 + 100
    mov al, 14
    mov [es:di], al
    mov [es:di+1], al
   
    mov di, 3200 + 218
    mov [es:di], al
    mov [es:di+1], al
   
    ; lane dividers at row 10
    mov ax, [scroll_offset]
    cmp ax, 10
    jge skip_divider_top
   
    mov di, 3200 + 140
    mov al, 15
    mov [es:di], al
   
    mov di, 3200 + 180
    mov [es:di], al
   
skip_divider_top:
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

delay:
    push cx
    push dx
   
    mov cx, 1
    mov dx, 6000h
delay_loop:
    dec dx
    jnz delay_loop
    loop delay_loop
   
    pop dx
    pop cx
    ret

; erase car
erase_car:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    
    mov si, bx
   
    mov dx, 0
erase_row:
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jl skip_erase_row
    cmp ax, 200
    jge erase_car_done
    
    mov di, ax
    imul di, 320
    add di, si
   
    push cx
    mov cx, 0
erase_col:
        mov al, 7
       
        mov bx, si
        add bx, cx
       
        cmp bx, 140
        je check_divider_erase
        cmp bx, 180
        je check_divider_erase
        jmp not_divider_erase
       
check_divider_erase:
        push ax
        push bx
        push dx
        mov ax, [car_y]
        add ax, dx
        mov bx, 20
        xor dx, dx
        div bx
        cmp dx, 10
        pop dx
        pop bx
        pop ax
        jge not_divider_erase
       
        mov al, 15
       
not_divider_erase:
        mov [es:di], al
        inc di
        inc cx
        cmp cx, CAR_WIDTH
        jl erase_col
    pop cx
   
skip_erase_row:
    inc dx
    cmp dx, CAR_HEIGHT
    jl erase_row
   
erase_car_done:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; erase obstacle
erase_obstacle:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    
    mov si, bx
   
    mov dx, 0
erase_obs_row:
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jl skip_erase_obs_row
    cmp ax, 200
    jge erase_obs_done
    
    mov di, ax
    imul di, 320
    add di, si
   
    push cx
    mov cx, 0
erase_obs_col:
        mov al, 7
       
        mov bx, si
        add bx, cx
       
        cmp bx, 140
        je check_obs_div_erase
        cmp bx, 180
        je check_obs_div_erase
        jmp not_obs_div_erase
       
check_obs_div_erase:
        push ax
        push bx
        push dx
        mov ax, [obstacle_y]
        add ax, dx
        mov bx, 20
        xor dx, dx
        div bx
        cmp dx, 10
        pop dx
        pop bx
        pop ax
        jge not_obs_div_erase
       
        mov al, 15
       
not_obs_div_erase:
        mov [es:di], al
        inc di
        inc cx
        cmp cx, CAR_WIDTH
        jl erase_obs_col
    pop cx
   
skip_erase_obs_row:
    inc dx
    cmp dx, CAR_HEIGHT
    jl erase_obs_row
   
erase_obs_done:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret
	
; erase bonus
erase_bonus:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    
    mov si, bx
   
    mov dx, 0
erase_bon_row:
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jl skip_erase_bon_row
    cmp ax, 200
    jge erase_bon_done
    
    mov di, ax
    imul di, 320
    add di, si
   
    push cx
    mov cx, 0
erase_bon_col:
        mov al, 7
       
        mov bx, si
        add bx, cx
       
        cmp bx, 140
        je check_bon_div_erase
        cmp bx, 180
        je check_bon_div_erase
        jmp not_bon_div_erase
       
check_bon_div_erase:
        push ax
        push bx
        push dx
        mov ax, [bonus_y]
        add ax, dx
        mov bx, 20
        xor dx, dx
        div bx
        cmp dx, 10
        pop dx
        pop bx
        pop ax
        jge not_bon_div_erase
       
        mov al, 15
       
not_bon_div_erase:
        mov [es:di], al
        inc di
        inc cx
        cmp cx, BONUS_SIZE
        jl erase_bon_col
    pop cx
   
skip_erase_bon_row:
    inc dx
    cmp dx, BONUS_SIZE
    jl erase_bon_row
   
erase_bon_done:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; palette setup
setup_palette:
    push ax
    push bx
    push cx
    push dx
   
    mov al, 2
    mov bh, 0
    mov bl, 25
    mov ch, 0
    call set_palette_color

    mov al, 3
    mov bh, 0
    mov bl, 45
    mov ch, 0
    call set_palette_color

    mov al, 4
    mov bh, 50
    mov bl, 0
    mov ch, 0
    call set_palette_color

    mov al, 6
    mov bh, 30
    mov bl, 15
    mov ch, 0
    call set_palette_color

    mov al, 7
    mov bh, 8
    mov bl, 8
    mov ch, 10
    call set_palette_color

    mov al, 8
    mov bh, 4
    mov bl, 4
    mov ch, 4
    call set_palette_color

    mov al, 10
    mov bh, 0
    mov bl, 35
    mov ch, 0
    call set_palette_color

    mov al, 12
    mov bh, 25
    mov bl, 0
    mov ch, 0
    call set_palette_color

    mov al, 14
    mov bh, 55
    mov bl, 55
    mov ch, 0
    call set_palette_color

    mov al, 15
    mov bh, 63
    mov bl, 63
    mov ch, 63
    call set_palette_color

    mov al, 1
    mov bh, 0
    mov bl, 0
    mov ch, 35
    call set_palette_color

    mov al, 9
    mov bh, 0
    mov bl, 30
    mov ch, 55
    call set_palette_color
   
    pop dx
    pop cx
    pop bx
    pop ax
    ret

set_palette_color:
    push ax
    push dx
    mov dx, 0x3C8
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    mov al, bl
    out dx, al
    mov al, ch
    out dx, al
    pop dx
    pop ax
    ret

; show intro screen (minimalist)
show_intro_screen:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    ; clear screen w black background
    xor di, di
    mov cx, 64000
intro_clear:
    mov byte [es:di], 0
    inc di
    loop intro_clear
    
    ; single underline below title
    mov di, 320 * 55 + 115
    mov cx, 90
title_line:
    mov byte [es:di], 15
    inc di
    loop title_line
    
    ; title
    mov dh, 5
    mov dl, 14
    mov si, game_title
    mov bl, 15
    call print_string
    
    ; student info
    mov dh, 10
    mov dl, 4
    mov si, student_info
    mov bl, 15
    call print_string
    
    ; semester
    mov dh, 12
    mov dl, 10
    mov si, semester_info
    mov bl, 15
    call print_string
    
    ; press any key
    mov dh, 20
    mov dl, 9
    mov si, press_any_key
    mov bl, 7
    call print_string
   
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; print string
print_string:
    push ax
    push bx
    push cx
    push dx
    push si
   
print_loop:
    mov al, [si]
    cmp al, 0
    je print_done
   
    mov ah, 02h
    mov bh, 0
    int 10h
   
    mov ah, 09h
    mov bh, 0
    mov cx, 1
    int 10h
   
    inc dl
    inc si
    jmp print_loop
   
print_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw landscape
draw_landscape:
    push ax
    push bx
    push cx
    push dx
    push di
   
    mov cx, 0
landscape_y:
    mov dx, 0
left_land:
        mov di, cx
        imul di, 320
        add di, dx
        mov al, 2
        mov bl, dl
        add bl, cl
        test bl, 2
        jz skip_tint
        inc al
skip_tint:
        mov [es:di], al
        inc dx
        cmp dx, 100
        jl left_land

    mov dx, 220
right_land:
        mov di, cx
        imul di, 320
        add di, dx
        mov al, 2
        mov bl, dl
        add bl, cl
        test bl, 2
        jz skip_tint2
        inc al
skip_tint2:
        mov [es:di], al
        inc dx
        cmp dx, 320
        jl right_land

    inc cx
    cmp cx, 200
    jl landscape_y
   
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw road
draw_road:
    push ax
    push cx
    push dx
    push di
   
    mov cx, 0
road_y:
    mov dx, 100
road_x:
        mov di, cx
        imul di, 320
        add di, dx
        mov al, 7
        mov [es:di], al
        inc dx
        cmp dx, 220
        jl road_x
    inc cx
    cmp cx, 200
    jl road_y
   
    pop di
    pop dx
    pop cx
    pop ax
    ret

; draw road borders
draw_road_borders:
    push ax
    push bx
    push cx
    push dx
    push di

    mov cx, 0
border_loop:
        mov di, cx
        imul di, 320
        
        mov al, 14
        mov [es:di+100], al
        mov [es:di+101], al

        mov [es:di+218], al
        mov [es:di+219], al

        inc cx
        cmp cx, 200
        jl border_loop

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw lane dividers
draw_lane_dividers:
    push bx
   
    mov bx, 140
    call draw_dashed_line

    mov bx, 180
    call draw_dashed_line
   
    pop bx
    ret

draw_dashed_line:
    push ax
    push cx
    push dx
    push si
    push di
   
    mov cx, 0
next_dash_y:
        mov si, 0
dash_segment:
            mov di, cx
            imul di, 320
            add di, bx
            mov al, 15
            mov [es:di], al
            inc si
            inc cx
            cmp si, 10
            jl dash_segment

        add cx, 10
        cmp cx, 200
        jl next_dash_y
       
    pop di
    pop si
    pop dx
    pop cx
    pop ax
    ret

; draw decorations
draw_decorations:
    push bx
    push cx
   
    mov bx, 40
    mov cx, 50
    call draw_tree_sprite

    mov bx, 60
    mov cx, 120
    call draw_bush_sprite

    mov bx, 250
    mov cx, 40
    call draw_tree_sprite

    mov bx, 240
    mov cx, 130
    call draw_bush_sprite
   
    pop cx
    pop bx
    ret

; draw car sprite
draw_car_sprite:
    push ax
    push bx
    push cx
    push dx
    push di
    push si

    mov si, car_sprite_data
    mov dx, 0

car_row:
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jl skip_car_row
    cmp ax, 200
    jge car_sprite_done
    
    mov di, ax
    imul di, 320
    add di, bx

    push cx
    mov cx, 0
car_col:
        mov al, [si]
        cmp al, 0
        je skip_car_pixel
        mov [es:di], al
skip_car_pixel:
        inc si
        inc di
        inc cx
        cmp cx, CAR_WIDTH
        jl car_col
    pop cx
    jmp next_car_row

skip_car_row:
    add si, CAR_WIDTH
    
next_car_row:
    inc dx
    cmp dx, CAR_HEIGHT
    jl car_row

car_sprite_done:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

car_sprite_data:
    db 0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0,0
    db 0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0
    db 0,0,8,4,4,4,12,12,12,15,15,15,15,15,15,12,12,12,4,4,4,8,0,0,0,0
    db 0,8,4,4,12,12,12,12,12,15,15,15,15,15,15,12,12,12,12,12,4,4,8,0,0,0
    db 0,8,4,12,12,12,12,12,12,12,12,15,15,12,12,12,12,12,12,12,12,4,8,0,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,4,8,0,0
    db 0,8,4,4,4,4,12,12,12,12,12,12,12,12,12,12,12,12,4,4,4,4,8,0,0,0
    db 0,8,4,4,4,4,12,12,12,14,14,14,14,14,14,12,12,12,4,4,4,4,8,0,0,0
    db 0,8,4,4,4,4,12,12,14,14,14,14,14,14,14,14,12,12,4,4,4,4,8,0,0,0
    db 0,8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0,0
    db 0,8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0,0
    db 0,8,4,4,4,12,12,12,12,12,12,12,12,12,12,12,12,12,4,4,4,8,0,0,0,0
    db 0,8,4,4,4,4,4,12,12,12,12,12,12,12,12,4,4,4,4,4,8,0,0,0,0,0
    db 8,8,8,8,8,8,8,0,0,0,0,0,0,0,0,0,8,8,8,8,8,8,8,8,0,0
    db 8,8,8,8,8,8,8,0,0,0,0,0,0,0,0,0,8,8,8,8,8,8,8,8,0,0
    db 0,0,8,8,8,8,8,0,0,0,0,0,0,0,0,0,8,8,8,8,8,8,8,0,0,0
    db 0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0
    db 0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0
    db 0,0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0,0
    db 0,0,0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0,0,0

; draw tree sprite
draw_tree_sprite:
    push ax
    push dx
    push di
    push si

    mov si, tree_sprite_data
    mov dx, 0

tree_row:
    mov di, cx
    add di, dx
    imul di, 320
    add di, bx

    mov ah, 0
tree_col:
        mov al, [si]
        cmp al, 0
        je skip_tree_pixel
        mov [es:di], al
skip_tree_pixel:
        inc si
        inc di
        inc ah
        cmp ah, 16
        jl tree_col

    inc dx
    cmp dx, 16
    jl tree_row

    pop si
    pop di
    pop dx
    pop ax
    ret

tree_sprite_data:
    db 0,0,0,0,0,2,2,2,2,0,0,0,0,0,0,0
    db 0,0,0,0,2,10,10,10,10,2,0,0,0,0,0,0
    db 0,0,0,2,10,10,2,2,10,10,2,0,0,0,0,0
    db 0,0,2,10,2,2,2,2,2,2,10,2,0,0,0,0
    db 0,2,10,2,2,2,10,10,2,2,2,10,2,0,0,0
    db 2,10,10,10,10,10,10,10,10,10,10,10,10,2,0,0
    db 0,2,10,10,10,10,10,10,10,10,10,10,2,0,0,0
    db 0,0,2,10,10,10,10,10,10,10,10,2,0,0,0,0
    db 0,0,0,2,10,10,10,10,10,10,2,0,0,0,0,0
    db 0,0,0,0,2,10,10,10,10,2,0,0,0,0,0,0
    db 0,0,0,0,0,6,6,6,6,0,0,0,0,0,0,0
    db 0,0,0,0,0,6,6,6,6,0,0,0,0,0,0,0
    db 0,0,0,0,0,6,6,6,6,0,0,0,0,0,0,0
    db 0,0,0,0,0,6,6,6,6,0,0,0,0,0,0,0
    db 0,0,0,0,0,6,6,6,6,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; draw bush sprite
draw_bush_sprite:
    push ax
    push dx
    push di
    push si

    mov si, bush_sprite_data
    mov dx, 0

bush_row:
    mov di, cx
    add di, dx
    imul di, 320
    add di, bx

    mov ah, 0
bush_col:
        mov al, [si]
        cmp al, 0
        je skip_bush_pixel
        mov [es:di], al
skip_bush_pixel:
        inc si
        inc di
        inc ah
        cmp ah, 16
        jl bush_col

    inc dx
    cmp dx, 16
    jl bush_row

    pop si
    pop di
    pop dx
    pop ax
    ret

bush_sprite_data:
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,2,10,10,10,10,2,0,0,0,0,0,0
    db 0,0,0,2,10,10,10,10,10,10,2,0,0,0,0,0
    db 0,0,2,10,10,2,2,2,2,10,10,2,0,0,0,0
    db 0,2,10,2,2,10,10,10,10,2,2,10,2,0,0,0
    db 2,10,10,10,10,10,10,10,10,10,10,10,10,2,0,0
    db 0,2,10,10,10,10,10,10,10,10,10,10,2,0,0,0
    db 0,0,2,10,10,10,10,10,10,10,10,2,0,0,0,0
    db 0,0,0,2,10,10,10,10,10,10,2,0,0,0,0,0
    db 0,0,0,0,2,10,10,10,10,2,0,0,0,0,0,0
    db 0,0,0,0,0,2,2,2,2,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; generate obstacle car
generate_obstacle:
    push ax
    push bx
    push cx
    push dx
   
    cmp byte [obstacle_active], 1
    je skip_generate
   
    inc word [spawn_counter]
    cmp word [spawn_counter], 10
    jl skip_generate
   
    mov word [spawn_counter], 0
    mov byte [obstacle_active], 1
   
    mov ah, 0
    int 1Ah
    mov ax, dx
    xor dx, dx
    mov cx, 3
    div cx
    mov [obstacle_lane], dl
   
    cmp dl, 0
    je set_obs_lane_0
    cmp dl, 1
    je set_obs_lane_1
    mov word [obstacle_x], 187
    jmp obs_lane_set
   
set_obs_lane_0:
    mov word [obstacle_x], 107
    jmp obs_lane_set
   
set_obs_lane_1:
    mov word [obstacle_x], 147
   
obs_lane_set:
    mov word [obstacle_y], -32
   
skip_generate:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; update obstacle position
update_obstacle_position:
    push ax
    push bx
    push cx
   
    cmp byte [obstacle_active], 0
    je skip_update_obs_pos
    
    mov bx, [obstacle_x]
    mov cx, [obstacle_y]
    call erase_obstacle
   
    add word [obstacle_y], 6
   
    cmp word [obstacle_y], 200
    jl skip_update_obs_pos
   
    add word [score], 10
    mov byte [obstacle_active], 0
   
skip_update_obs_pos:
    pop cx
    pop bx
    pop ax
    ret

; draw obstacle car sprite
draw_obstacle_sprite:
    push ax
    push bx
    push cx
    push dx
    push di
    push si

    mov si, obstacle_car_data
    mov dx, 0

obstacle_car_row:
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jl skip_obstacle_row
    cmp ax, 200
    jge obstacle_sprite_done

    mov di, ax
    imul di, 320
    add di, bx

    push cx
    push bx
    mov cx, 0
obstacle_car_col:
        mov al, [si]
        inc si
        
        cmp al, 0
        je skip_obstacle_pixel
        
        mov ax, bx
        add ax, cx
        cmp ax, 102
        jl skip_obstacle_pixel
        cmp ax, 217
        jg skip_obstacle_pixel
        
        mov al, [si-1]
        
        cmp al, 12
        je use_dark_blue
        cmp al, 4
        je use_blue
        jmp draw_obs_pixel
       
use_dark_blue:
        mov al, 1
        jmp draw_obs_pixel
use_blue:
        mov al, 9
       
draw_obs_pixel:
        mov [es:di], al
        
skip_obstacle_pixel:
        inc di
        inc cx
        cmp cx, CAR_WIDTH
        jl obstacle_car_col
    pop bx
    pop cx
    jmp next_obstacle_row

skip_obstacle_row:
    add si, CAR_WIDTH
    
next_obstacle_row:
    inc dx
    cmp dx, CAR_HEIGHT
    jl obstacle_car_row

obstacle_sprite_done:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

obstacle_car_data:
    db 0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0,0
    db 0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0
    db 0,0,8,4,4,4,12,12,12,15,15,15,15,15,15,12,12,12,4,4,4,8,0,0,0,0
    db 0,8,4,4,12,12,12,12,12,15,15,15,15,15,15,12,12,12,12,12,4,4,8,0,0,0
    db 0,8,4,12,12,12,12,12,12,12,12,15,15,12,12,12,12,12,12,12,12,4,8,0,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0
    db 8,4,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,4,8,0,0
    db 0,8,4,4,4,4,12,12,12,12,12,12,12,12,12,12,12,12,4,4,4,4,8,0,0,0
    db 0,8,4,4,4,4,12,12,12,14,14,14,14,14,14,12,12,12,4,4,4,4,8,0,0,0
    db 0,8,4,4,4,4,12,12,14,14,14,14,14,14,14,14,12,12,4,4,4,4,8,0,0,0
    db 0,8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0,0
    db 0,8,4,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,4,8,0,0,0
    db 0,8,4,4,4,12,12,12,12,12,12,12,12,12,12,12,12,12,4,4,4,8,0,0,0,0
    db 0,8,4,4,4,4,4,12,12,12,12,12,12,12,12,4,4,4,4,4,8,0,0,0,0,0
    db 8,8,8,8,8,8,8,0,0,0,0,0,0,0,0,0,8,8,8,8,8,8,8,8,0,0
    db 8,8,8,8,8,8,8,0,0,0,0,0,0,0,0,0,8,8,8,8,8,8,8,8,0,0
    db 0,0,8,8,8,8,8,0,0,0,0,0,0,0,0,0,8,8,8,8,8,8,8,0,0,0
    db 0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0
    db 0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0
    db 0,0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0,0
    db 0,0,0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0,0,0,0,0

; check collision
check_collision:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    cmp byte [obstacle_active], 0
    je no_collision
   
    cmp byte [collision_detected], 1
    je no_collision
   
    mov ax, [car_x]
    mov bx, [car_y]
    mov cx, ax
    add cx, CAR_WIDTH
    mov dx, bx
    add dx, CAR_HEIGHT
   
    mov si, [obstacle_x]
    mov di, [obstacle_y]
   
    cmp cx, si
    jle no_collision
   
    push si
    add si, CAR_WIDTH
    cmp ax, si
    pop si
    jge no_collision
   
    cmp dx, di
    jle no_collision
   
    push di
    add di, CAR_HEIGHT
    cmp bx, di
    pop di
    jge no_collision
   
    mov byte [collision_detected], 1
    mov byte [game_over], 1
   
no_collision:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; generate bonus
generate_bonus:
    push ax
    push bx
    push cx
    push dx
   
    cmp byte [bonus_active], 1
    je skip_gen_bonus
   
    inc word [bonus_counter]
    cmp word [bonus_counter], 30
    jl skip_gen_bonus
   
    mov word [bonus_counter], 0
    mov byte [bonus_active], 1
   
    mov ah, 0
    int 1Ah
    mov ax, dx
    add ax, 7
    xor dx, dx
    mov cx, 3
    div cx
    mov [bonus_lane], dl
   
    cmp dl, 0
    je set_bonus_lane_0
    cmp dl, 1
    je set_bonus_lane_1
    mov word [bonus_x], 192
    jmp bonus_lane_set
   
set_bonus_lane_0:
    mov word [bonus_x], 112
    jmp bonus_lane_set
   
set_bonus_lane_1:
    mov word [bonus_x], 152
   
bonus_lane_set:
    mov word [bonus_y], -16
   
skip_gen_bonus:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; update bonus position
update_bonus_position:
    push ax
    push bx
    push cx
   
    cmp byte [bonus_active], 0
    je skip_update_bon_pos
    
    mov bx, [bonus_x]
    mov cx, [bonus_y]
    call erase_bonus
   
    add word [bonus_y], 6
   
    cmp word [bonus_y], 200
    jl skip_update_bon_pos
   
    mov byte [bonus_active], 0
   
skip_update_bon_pos:
    pop cx
    pop bx
    pop ax
    ret

; draw bonus sprite
draw_bonus_sprite:
    push ax
    push bx
    push cx
    push dx
    push di
    push si

    mov si, bonus_sprite_data
    mov dx, 0

bonus_sprite_row:
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jl skip_bonus_row
    cmp ax, 200
    jge bonus_sprite_done
    
    mov di, ax
    imul di, 320
    add di, bx

    push cx
    push bx
    mov cx, 0
bonus_sprite_col:
        mov al, [si]
        inc si
        cmp al, 0
        je skip_bonus_pixel
        
        mov ax, bx
        add ax, cx
        cmp ax, 102
        jl skip_bonus_pixel
        cmp ax, 217
        jg skip_bonus_pixel
        
        mov al, [si-1]
        mov [es:di], al
        
skip_bonus_pixel:
        inc di
        inc cx
        cmp cx, BONUS_SIZE
        jl bonus_sprite_col
    pop bx
    pop cx
    jmp next_bonus_row

skip_bonus_row:
    add si, BONUS_SIZE
    
next_bonus_row:
    inc dx
    cmp dx, BONUS_SIZE
    jl bonus_sprite_row

bonus_sprite_done:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

bonus_sprite_data:
    db 0,0,0,0,0,0,0,14,14,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,14,14,14,14,0,0,0,0,0,0
    db 0,0,0,0,0,0,14,14,14,14,0,0,0,0,0,0
    db 0,0,0,0,0,14,14,14,14,14,14,0,0,0,0,0
    db 0,14,14,14,14,14,14,14,14,14,14,14,14,14,14,0
    db 0,0,14,14,14,14,14,14,14,14,14,14,14,14,0,0
    db 0,0,0,14,14,14,14,14,14,14,14,14,14,0,0,0
    db 0,0,0,0,14,14,14,14,14,14,14,14,0,0,0,0
    db 0,0,0,0,14,14,14,14,14,14,14,14,0,0,0,0
    db 0,0,0,14,14,14,14,14,14,14,14,14,14,0,0,0
    db 0,0,14,14,14,14,0,14,14,0,14,14,14,14,0,0
    db 0,14,14,14,14,0,0,14,14,0,0,14,14,14,14,0
    db 0,14,14,14,0,0,0,14,14,0,0,0,14,14,14,0
    db 0,14,14,0,0,0,0,14,14,0,0,0,0,14,14,0
    db 0,0,0,0,0,0,0,14,14,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; check bonus collision
check_bonus_collision:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    cmp byte [bonus_active], 0
    je no_bonus_collision
   
    mov ax, [car_x]
    mov bx, [car_y]
    mov cx, ax
    add cx, CAR_WIDTH
    mov dx, bx
    add dx, CAR_HEIGHT
   
    mov si, [bonus_x]
    mov di, [bonus_y]
   
    cmp cx, si
    jle no_bonus_collision
   
    push si
    add si, BONUS_SIZE
    cmp ax, si
    pop si
    jge no_bonus_collision
   
    cmp dx, di
    jle no_bonus_collision
   
    push di
    add di, BONUS_SIZE
    cmp bx, di
    pop di
    jge no_bonus_collision
   
    add word [score], 50
    mov byte [bonus_active], 0
   
no_bonus_collision:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; install timer isr
install_timer_isr:
    push ax
    push bx
    push dx
    push es
    
    cli
    
    mov ax, 3508h
    int 21h
    mov word [old_timer_isr], bx
    mov word [old_timer_isr+2], es
    
    push ds
    push cs
    pop ds
    mov dx, timer_isr
    mov ax, 2508h
    int 21h
    pop ds
    
    sti
    
    pop es
    pop dx
    pop bx
    pop ax
    ret

; timer isr
timer_isr:
    push ax
    push ds
    
    push cs
    pop ds
    
    ; dont scroll if paused
    cmp byte [game_paused], 1
    je timer_skip_scroll
    
    inc word [timer_tick_count]
    
    mov ax, [timer_tick_count]
    cmp ax, [scroll_delay]
    jl timer_done
    
    mov word [timer_tick_count], 0
    mov byte [scroll_ready], 1
    jmp timer_done
    
timer_skip_scroll:
timer_done:
    pop ds
    pop ax
    
    jmp far [cs:old_timer_isr]

; restore timer isr
restore_timer_isr:
    push ax
    push bx
    push dx
    push ds
    
    cli
    
    mov ax, [old_timer_isr]
    or ax, [old_timer_isr+2]
    jz skip_restore
    
    mov dx, [old_timer_isr]
    mov bx, [old_timer_isr+2]
    mov ds, bx
    mov ax, 2508h
    int 21h
    
    push cs
    pop ds
    mov word [old_timer_isr], 0
    mov word [old_timer_isr+2], 0
    
skip_restore:
    sti
    
    pop ds
    pop dx
    pop bx
    pop ax
    ret

; display score during gameplay
display_score_ingame:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    
    ; draw hud bar across entire top (rows 0-9, all 320 columns)
    mov cx, 0
score_bg_y:
    push cx
    mov di, cx
    imul di, 320
    
    mov dx, 0
score_bg_x:
    mov byte [es:di], 0         ; black background
    inc di
    inc dx
    cmp dx, 320                 ; full screen width
    jl score_bg_x
    
    pop cx
    inc cx
    cmp cx, 10                  ; height of hud bar
    jl score_bg_y
    
    ; set cursor to row 0, column 0
    mov ah, 02h
    mov bh, 0
    mov dh, 0
    mov dl, 0
    int 10h
    
    ; print "Score: "
    mov si, score_text_inline
print_score_label:
    lodsb
    cmp al, 0
    je print_score_number
    mov ah, 0Eh
    mov bh, 0
    mov bl, 14                  ; yellow
    int 10h
    jmp print_score_label
    
print_score_number:
    mov ax, [score]
    call print_number_inline
    
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; print number inline (same line, no newline)
print_number_inline:
    push ax
    push bx
    push cx
    push dx
    
    ; handle zero
    test ax, ax
    jnz not_zero_inline
    
    mov ah, 0Eh
    mov al, '0'
    mov bh, 0
    mov bl, 15
    int 10h
    jmp print_inline_done
    
not_zero_inline:
    ; convert to digits
    mov bx, 10
    xor cx, cx
    
conv_inline:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz conv_inline
    
print_inline_digits:
    pop ax
    add al, '0'
    mov ah, 0Eh
    mov bh, 0
    mov bl, 15              ; white
    int 10h
    loop print_inline_digits
    
print_inline_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; print number in graphics mode
print_number_small:
    push ax
    push bx
    push cx
    push dx
    push si
    
    ; save the number to print
    mov si, ax
    
    ; set cursor position first
    mov ah, 02h
    mov bh, 0
    int 10h
    
    ; now check if number is zero
    test si, si
    jnz do_convert_small
    
    ; print "0" for zero case
    mov ah, 0Eh
    mov al, '0'
    mov bh, 0
    int 10h
    jmp print_num_small_done
    
do_convert_small:
    ; convert number to string (push digits)
    mov ax, si          ; restore number
    mov bx, 10
    xor cx, cx          ; digit counter
    
convert_small_loop:
    xor dx, dx
    div bx
    push dx             ; save digit
    inc cx
    test ax, ax
    jnz convert_small_loop
    
    ; now print digits
print_digits_loop:
    pop ax              ; get digit
    add al, '0'
    
    push cx
    mov ah, 0Eh         ; teletype output
    mov bh, 0
    int 10h
    pop cx
    
    loop print_digits_loop
    
print_num_small_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
