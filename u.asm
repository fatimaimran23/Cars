org 100h
%define CAR_WIDTH  26
%define CAR_HEIGHT 32
%define BONUS_SIZE 16

jmp start

; === VARIABLES ===
car_x dw 107          ; car X position (left lane)
car_y dw 160          ; car Y position
current_lane db 0     ; 0=left, 1=middle, 2=right
scroll_offset dw 0    ; for scrolling animation
spawn_counter dw 0    ; for obstacle spawning
bonus_counter dw 0    ; for bonus spawning
old_timer_isr dd 0        ; Store original timer ISR address
timer_tick_count dw 0     ; Count timer ticks for scroll timing
scroll_delay dw 3         ; Ticks before scroll (adjust for speed)
scroll_ready db 0         ; Flag: 1 when it's time to scroll

; === TEXT STRINGS FOR SCREENS ===
game_title db "RACING GAME", 0
student_info db "By: Maliha (0660), Fatima (0588)", 0
semester_info db "Semester: Fall 2025", 0
press_any_key db "Press any key to start...", 0
exit_confirm_msg db "Do you want to exit? (Y/N)", 0
score_msg db "Your Score: ", 0
game_over_msg db "GAME OVER!", 0
score_text_small db "Score:", 0

; === OBSTACLE CAR VARIABLES ===
obstacle_active db 0      
obstacle_x dw 0          
obstacle_y dw 0          
obstacle_lane db 0  

; === BONUS OBJECT VARIABLES ===
bonus_active db 0
bonus_x dw 0
bonus_y dw 0
bonus_lane db 0
     
collision_detected db 0   ; flag for collision
game_over db 0            ; flag for game over state
score dw 0                ; player score

; === START ===
start:

; SETUP VIDEO MODE
mov ax, 13h
int 10h             ; set 320x200 graphics mode

mov ax, 0A000h
mov es, ax          ; video memory segment

; COLOR PALETTE
call setup_palette

; === SHOW INTRODUCTION SCREEN ===
call show_intro_screen

; Wait for keypress to start
wait_start_key:
    mov ah, 00h
    int 16h         ; wait for any key

; Reset scroll flag before game starts
mov byte [scroll_ready], 0

; DRAW INITIAL SCREEN
call draw_landscape
call draw_road
call draw_road_borders
call draw_lane_dividers
call draw_decorations

; Draw car at initial position
mov bx, [car_x]
mov cx, [car_y]
call draw_car_sprite

; Install timer AFTER drawing initial screen
call install_timer_isr

; === GAME LOOP ===
game_loop:
    ; Check for key press FIRST (non-blocking)
    mov ah, 01h
    int 16h
    jz no_key_pressed           ; no key pressed
   
    ; Key pressed, get it and clear buffer
    mov ah, 00h
    int 16h
   
    ; Check if ESC pressed
    cmp ah, 01h         ; ESC scan code
    je near exit_game
   
    ; Check Right Arrow (scan code 4Dh)
    cmp ah, 4Dh
    je handle_right
   
    ; Check Left Arrow (scan code 4Bh)
    cmp ah, 4Bh
    je handle_left
   
    jmp no_key_pressed

handle_right:
    mov al, [current_lane]
    cmp al, 2           ; already in right lane?
    jge no_key_pressed
   
    ; Erase old car position
    mov bx, [car_x]
    mov cx, [car_y]
    call erase_car
   
    ; Move to next lane
    inc byte [current_lane]
    add word [car_x], 40
   
    ; Draw car at new position
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite
   
    jmp no_key_pressed

handle_left:
    mov al, [current_lane]
    cmp al, 0           ; already in left lane?
    jle no_key_pressed
   
    ; Erase old car position
    mov bx, [car_x]
    mov cx, [car_y]
    call erase_car
   
    ; Move to previous lane
    dec byte [current_lane]
    sub word [car_x], 40
   
    ; Draw car at new position
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite
   
no_key_pressed:
    ; CHECK IF IT'S TIME TO SCROLL
    cli                         ; disable interrupts while checking flag
    mov al, [scroll_ready]
    cmp al, 1
    jne skip_scroll_check
    
    ; Reset flag
    mov byte [scroll_ready], 0
    sti                         ; re-enable interrupts
    
    ; Scroll the screen
    call scroll_background_only
    jmp after_scroll
    
skip_scroll_check:
    sti                         ; re-enable interrupts
    
after_scroll:
    ; Display score
    call display_score_ingame
    
    ; Generate new objects if needed
    call generate_obstacle
    call generate_bonus
   
    ; Update positions
    call update_obstacle_position
    call update_bonus_position
   
    ; Draw player car
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite
   
    ; Draw obstacle
    mov al, [obstacle_active]
    cmp al, 0
    je skip_draw_obs_loop
    mov bx, [obstacle_x]
    mov cx, [obstacle_y]
    call draw_obstacle_sprite
skip_draw_obs_loop:
   
    ; Draw bonus
    mov al, [bonus_active]
    cmp al, 0
    je skip_draw_bon_loop
    mov bx, [bonus_x]
    mov cx, [bonus_y]
    call draw_bonus_sprite
skip_draw_bon_loop:
   
    ; Check for collision
    call check_collision
    call check_bonus_collision
   
    ; Check if game over
    mov al, [game_over]
    cmp al, 1
    je handle_game_over
   
    ; Small delay for animation
    call delay

    jmp game_loop

; === HANDLE GAME OVER ===
handle_game_over:
    ; Restore timer before showing exit screen
    call restore_timer_isr
    
    ; Small delay to show final frame
    call delay
    call delay
   
    ; Jump to exit screen
    jmp exit_game

; === EXIT ===
exit_game:
    call restore_timer_isr
    
    ; Switch to text mode to show message
    mov ax, 3h
    int 10h              ; back to text mode
   
    ; Clear screen
    mov ah, 06h
    mov al, 0
    mov bh, 17h          ; white on blue
    mov cx, 0
    mov dx, 184Fh        ; full screen
    int 10h
   
    ; Show game over if collision
    mov al, [collision_detected]
    cmp al, 1
    jne skip_game_over_text
   
    mov dh, 8
    mov dl, 30
    mov si, game_over_msg
    call print_string_text
   
skip_game_over_text:
    ; Show score
    mov dh, 10
    mov dl, 28
    mov si, score_msg
    call print_string_text
   
    ; Display score number
    mov ax, [score]
    mov dh, 10
    mov dl, 42
    call print_number_text
   
    ; Show exit confirmation
    mov dh, 12
    mov dl, 22
    mov si, exit_confirm_msg
    call print_string_text
   
    ; Wait for Y or N
wait_exit_response:
    mov ah, 00h
    int 16h
   
    ; Check for 'Y' or 'y'
    cmp al, 'Y'
    je confirm_exit
    cmp al, 'y'
    je confirm_exit
   
    ; Check for 'N' or 'n'
    cmp al, 'N'
    je cancel_exit
    cmp al, 'n'
    je cancel_exit
   
    ; Invalid key, wait again
    jmp wait_exit_response

confirm_exit:
    mov ax, 3h
    int 10h              ; ensure text mode
    int 20h              ; exit program

cancel_exit:
    ; Reset game state
    mov byte [collision_detected], 0
    mov byte [game_over], 0
    mov byte [obstacle_active], 0
    mov byte [bonus_active], 0
    mov word [score], 0
    mov word [spawn_counter], 0
    mov word [bonus_counter], 0
    mov byte [scroll_ready], 0
    mov word [timer_tick_count], 0
    
    ; Reset player position
    mov word [car_x], 107
    mov word [car_y], 160
    mov byte [current_lane], 0
    
    ; Return to graphics mode and redraw
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
    
    ; Reinstall timer
    call install_timer_isr
    
    jmp game_loop

; === PRINT STRING IN TEXT MODE ===
print_string_text:
    push ax
    push bx
    push si
   
    mov ah, 02h
    mov bh, 0
    int 10h              ; set cursor
   
print_text_loop:
    lodsb                ; load byte from SI into AL
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

; === PRINT NUMBER IN TEXT MODE ===
print_number_text:
    push ax
    push bx
    push cx
    push dx
   
    ; Set cursor position
    mov ah, 02h
    mov bh, 0
    int 10h
    
    ; Handle zero case
    cmp ax, 0
    jne convert_num_loop
    
    mov ah, 0Eh
    mov al, '0'
    mov bh, 0
    int 10h
    jmp print_num_text_done
   
    ; Convert number to string
convert_num_loop:
    mov bx, 10
    mov cx, 0
   
convert_num_loop2:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz convert_num_loop2
   
print_num_loop:
    pop ax
    add al, '0'
    mov ah, 0Eh
    mov bh, 0
    int 10h
    loop print_num_loop
   
print_num_text_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === SCROLL BACKGROUND ONLY ===
scroll_background_only:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    ; Move rows down by 1 pixel (from bottom to top)
    mov cx, 198
scroll_bg_loop:
    push cx
   
    ; Source row (cx)
    mov si, cx
    imul si, 320
    
    ; Destination row (cx + 1)
    mov di, cx
    inc di
    imul di, 320
   
    ; Copy LEFT landscape (0 to 99)
    mov bx, 0
copy_left_land:
        mov al, [es:si+bx]
        mov [es:di+bx], al
        inc bx
        cmp bx, 100
        jl copy_left_land
    
    ; Copy ROAD section (100 to 219)
    mov bx, 100
copy_road_section:
        mov al, [es:si+bx]
        mov [es:di+bx], al
        inc bx
        cmp bx, 220
        jl copy_road_section
    
    ; Copy RIGHT landscape (220 to 319)
    mov bx, 220
copy_right_land:
        mov al, [es:si+bx]
        mov [es:di+bx], al
        inc bx
        cmp bx, 320
        jl copy_right_land
   
    pop cx
    dec cx
    cmp cx, 0
    jge scroll_bg_loop
   
    ; Redraw top row
    call redraw_top_row
   
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === REDRAW TOP ROW ===
redraw_top_row:
    push ax
    push bx
    push cx
    push dx
    push di
   
    ; Increment scroll offset for pattern
    inc word [scroll_offset]
    cmp word [scroll_offset], 20
    jl continue_redraw
    mov word [scroll_offset], 0
   
continue_redraw:
    ; Draw left landscape at row 0
    mov dx, 0
redraw_left:
        mov di, dx
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
   
    ; Draw road at row 0
    mov dx, 100
redraw_road_top:
        mov di, dx
        mov al, 7           ; grey
        mov [es:di], al
        inc dx
        cmp dx, 220
        jl redraw_road_top
   
    ; Draw right landscape at row 0
    mov dx, 220
redraw_right:
        mov di, dx
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
   
    ; Redraw borders at top
    mov di, 100
    mov al, 14
    mov [es:di], al
    mov [es:di+1], al
   
    mov di, 218
    mov [es:di], al
    mov [es:di+1], al
   
    ; Redraw lane dividers at top if needed
    mov ax, [scroll_offset]
    cmp ax, 10
    jge skip_divider_top
   
    mov di, 140
    mov al, 15
    mov [es:di], al
   
    mov di, 180
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
    mov dx, 8000h
delay_loop:
    dec dx
    jnz delay_loop
    loop delay_loop
   
    pop dx
    pop cx
    ret

; === ERASE CAR ===
erase_car:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    
    ; Save parameters
    mov si, bx          ; save X
   
    mov dx, 0           ; row counter
erase_row:
    ; Calculate screen position
    mov ax, cx          ; Y position
    add ax, dx          ; add row offset
    cmp ax, 200         ; bounds check
    jge erase_car_done
    
    mov di, ax
    imul di, 320
    add di, si          ; add X position
   
    push cx
    mov cx, 0           ; column counter
erase_col:
        ; Calculate current X position
        mov ax, si
        add ax, cx
        
        ; Default road color
        mov al, 7
       
        ; Check if we're on a lane divider position
        mov bx, si
        add bx, cx
       
        cmp bx, 140
        je check_divider_erase
        cmp bx, 180
        je check_divider_erase
        jmp not_divider_erase
       
check_divider_erase:
        ; Check if this row should have a dash
        push ax
        push dx
        mov ax, [car_y]
        add ax, dx
        push cx
        push bx
        mov bx, 20
        xor dx, dx
        div bx
        cmp dx, 10
        pop bx
        pop cx
        pop dx
        pop ax
        jge not_divider_erase
       
        mov al, 15      ; white dash
       
not_divider_erase:
        mov [es:di], al
        inc di
        inc cx
        cmp cx, CAR_WIDTH
        jl erase_col
    pop cx
   
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

; === ERASE OBSTACLE ===
erase_obstacle:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    
    mov si, bx          ; save X
   
    mov dx, 0           ; row counter
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
    mov cx, 0           ; column counter
erase_obs_col:
        mov al, 7       ; road color (grey)
       
        mov bx, [obstacle_x]
        add bx, cx
       
        cmp bx, 140
        je check_obs_divider_erase
        cmp bx, 180
        je check_obs_divider_erase
        jmp not_obs_divider_erase
       
check_obs_divider_erase:
        push ax
        push dx
        mov ax, [obstacle_y]
        add ax, dx
        push cx
        push bx
        mov bx, 20
        xor dx, dx
        div bx
        cmp dx, 10
        pop bx
        pop cx
        pop dx
        pop ax
        jge not_obs_divider_erase
       
        mov al, 15      ; white dash
       
not_obs_divider_erase:
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
	
; === ERASE BONUS ===
erase_bonus:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    
    mov si, bx          ; save X
   
    mov dx, 0           ; row counter
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
    mov cx, 0           ; column counter
erase_bon_col:
        mov al, 7       ; road color (grey)
       
        mov bx, [bonus_x]
        add bx, cx
       
        cmp bx, 140
        je check_bon_divider_erase
        cmp bx, 180
        je check_bon_divider_erase
        jmp not_bon_divider_erase
       
check_bon_divider_erase:
        push ax
        push dx
        mov ax, [bonus_y]
        add ax, dx
        push cx
        push bx
        mov bx, 20
        xor dx, dx
        div bx
        cmp dx, 10
        pop bx
        pop cx
        pop dx
        pop ax
        jge not_bon_divider_erase
       
        mov al, 15      ; white dash
       
not_bon_divider_erase:
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

; === PALETTE SETUP ===
setup_palette:
    push ax
    push bx
    push cx
   
    ; color 2 = dark forest green
    mov al, 2
    mov bh, 0
    mov bl, 25
    mov ch, 0
    call set_palette_color

    ; color 3 = lighter grass green
    mov al, 3
    mov bh, 0
    mov bl, 45
    mov ch, 0
    call set_palette_color

    ; color 6 = brown
    mov al, 6
    mov bh, 30
    mov bl, 15
    mov ch, 0
    call set_palette_color

    ; color 7 = dark asphalt grey
    mov al, 7
    mov bh, 8
    mov bl, 8
    mov ch, 10
    call set_palette_color

    ; color 8 = black
    mov al, 8
    mov bh, 4
    mov bl, 4
    mov ch, 4
    call set_palette_color

    ; color 10 = mid green
    mov al, 10
    mov bh, 0
    mov bl, 35
    mov ch, 0
    call set_palette_color

    ; color 12 = dark red shadow
    mov al, 12
    mov bh, 25
    mov bl, 0
    mov ch, 0
    call set_palette_color

    ; color 14 = yellow
    mov al, 14
    mov bh, 55
    mov bl, 55
    mov ch, 0
    call set_palette_color

    ; color 15 = white
    mov al, 15
    mov bh, 63
    mov bl, 63
    mov ch, 63
    call set_palette_color

    ; color 1 = dark blue
    mov al, 1
    mov bh, 0
    mov bl, 0
    mov ch, 35
    call set_palette_color

    ; color 9 = bright blue  
    mov al, 9
    mov bh, 0
    mov bl, 30
    mov ch, 55
    call set_palette_color
    
    ; color 4 = red (for player car)
    mov al, 4
    mov bh, 50
    mov bl, 0
    mov ch, 0
    call set_palette_color
   
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

; === SHOW INTRODUCTION SCREEN ===
show_intro_screen:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    ; Clear screen with dark blue background
    mov cx, 0
    mov di, 0
intro_clear:
        mov byte [es:di], 1
        inc di
        inc cx
        cmp cx, 64000
        jl intro_clear
   
    ; Display title
    mov dh, 5
    mov dl, 13
    mov si, game_title
    mov bl, 15
    call print_string
   
    ; Display student info
    mov dh, 10
    mov dl, 5
    mov si, student_info
    mov bl, 14
    call print_string
   
    ; Display semester
    mov dh, 12
    mov dl, 10
    mov si, semester_info
    mov bl, 14
    call print_string
   
    ; Display "press any key"
    mov dh, 20
    mov dl, 8
    mov si, press_any_key
    mov bl, 10
    call print_string
   
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === PRINT STRING ===
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

; === DRAW LANDSCAPE ===
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

; === DRAW ROAD ===
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

; === DRAW ROAD BORDERS ===
draw_road_borders:
    push ax
    push bx
    push cx
    push dx
    push di

    mov bx, 100
    mov dx, 219
    mov cx, 0
border_loop:
        mov di, cx
        imul di, 320
        add di, bx
        mov al, 14
        mov [es:di], al
        mov [es:di+1], al

        mov di, cx
        imul di, 320
        add di, dx
        mov al, 14
        mov [es:di], al
        mov [es:di-1], al

        inc cx
        cmp cx, 200
        jl border_loop

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === DRAW LANE DIVIDERS ===
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
        mov dx, bx
        mov si, 0
dash_segment:
            mov di, cx
            imul di, 320
            add di, dx
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

; === DRAW DECORATIONS ===
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

; === DRAW CAR SPRITE ===
draw_car_sprite:
    push ax
    push dx
    push di
    push si

    mov si, car_sprite_data
    mov dx, 0

car_row:
    mov di, cx
    add di, dx
    imul di, 320
    add di, bx

    mov ah, 0
car_col:
        mov al, [si]
        cmp al, 0
        je skip_pixel
        mov [es:di], al
skip_pixel:
        inc si
        inc di
        inc ah
        cmp ah, CAR_WIDTH
        jl car_col

    inc dx
    cmp dx, CAR_HEIGHT
    jl car_row

    pop si
    pop di
    pop dx
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

; === DRAW TREE SPRITE ===
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

; === DRAW BUSH SPRITE ===
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

; === GENERATE OBSTACLE CAR ===
generate_obstacle:
    push ax
    push bx
    push cx
    push dx
   
    ; Check if obstacle already active
    mov al, [obstacle_active]
    cmp al, 1
    je skip_generate
   
    ; Counter-based spawning
    inc word [spawn_counter]
    mov ax, [spawn_counter]
    cmp ax, 80
    jl skip_generate
   
    ; Reset counter and spawn
    mov word [spawn_counter], 0
    mov byte [obstacle_active], 1
   
    ; Get random lane using system time
    mov ah, 0
    int 1Ah
    mov ax, dx
    xor dx, dx
    mov cx, 3
    div cx
    mov [obstacle_lane], dl
   
    ; Set X position based on lane (SAME as player: 107, 147, 187)
    cmp dl, 0
    je set_obs_lane_0
    cmp dl, 1
    je set_obs_lane_1
    ; Lane 2 (right)
    mov word [obstacle_x], 187
    jmp obs_lane_set
   
set_obs_lane_0:
    mov word [obstacle_x], 107
    jmp obs_lane_set
   
set_obs_lane_1:
    mov word [obstacle_x], 147
   
obs_lane_set:
    mov word [obstacle_y], -32     ; Start above screen
   
skip_generate:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === UPDATE OBSTACLE POSITION ===
update_obstacle_position:
    push ax
    push bx
    push cx
   
    mov al, [obstacle_active]
    cmp al, 0
    je skip_update_obs_pos
    
    ; ERASE OLD POSITION FIRST
    mov bx, [obstacle_x]
    mov cx, [obstacle_y]
    call erase_obstacle
   
    ; Move down by 2 pixels (faster)
    add word [obstacle_y], 2
   
    ; Check if off screen
    mov ax, [obstacle_y]
    cmp ax, 200
    jl skip_update_obs_pos
   
    ; Passed player - increment score
    add word [score], 10
   
    ; Deactivate
    mov byte [obstacle_active], 0
   
skip_update_obs_pos:
    pop cx
    pop bx
    pop ax
    ret

; === DRAW OBSTACLE CAR SPRITE (WITH BOUNDARY CHECKING) ===
draw_obstacle_sprite:
    push ax
    push dx
    push di
    push si
    push bx
    push cx

    ; Check if obstacle is within screen bounds
    mov ax, cx              ; cx = obstacle_y
    cmp ax, -32
    jl skip_draw_obs_sprite
    cmp ax, 200
    jge skip_draw_obs_sprite

    mov si, obstacle_car_data
    mov dx, 0

obstacle_car_row:
    ; Check if current row is within screen
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jl skip_obstacle_row
    cmp ax, 200
    jge skip_draw_obs_sprite

    mov di, ax
    imul di, 320
    add di, bx

    push cx
    mov cx, 0           ; column counter
obstacle_car_col:
        mov al, [si]
        inc si
        
        cmp al, 0
        je skip_obstacle_pixel
        
        ; Check if pixel is within road boundaries (X: 102 to 217)
        push bx
        add bx, cx
        cmp bx, 102
        jl skip_obs_pixel_pop
        cmp bx, 217
        jg skip_obs_pixel_pop
        pop bx
        
        ; Convert red colors to blue for obstacle
        cmp al, 12
        je use_dark_blue
        cmp al, 4
        je use_blue
        jmp draw_obstacle_pixel
       
use_dark_blue:
        mov al, 1
        jmp draw_obstacle_pixel
use_blue:
        mov al, 9
       
draw_obstacle_pixel:
        mov [es:di], al
        jmp continue_obstacle_pixel
        
skip_obs_pixel_pop:
        pop bx
        
skip_obstacle_pixel:
continue_obstacle_pixel:
        inc di
        inc cx
        cmp cx, CAR_WIDTH
        jl obstacle_car_col
    pop cx

skip_obstacle_row:
    ; Advance SI past remaining columns if we skipped the row
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jge no_skip_si
    add si, CAR_WIDTH
    sub si, cx              ; Adjust if we partially processed
    jmp after_si_adjust
no_skip_si:
after_si_adjust:
    inc dx
    cmp dx, CAR_HEIGHT
    jl obstacle_car_row

skip_draw_obs_sprite:
    pop cx
    pop bx
    pop si
    pop di
    pop dx
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

; === CHECK COLLISION ===
check_collision:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    mov al, [obstacle_active]
    cmp al, 0
    je no_collision
   
    mov al, [collision_detected]
    cmp al, 1
    je no_collision
   
    ; Get player car bounds
    mov ax, [car_x]           ; player left
    mov bx, [car_y]           ; player top
    mov cx, ax
    add cx, CAR_WIDTH         ; player right
    mov dx, bx
    add dx, CAR_HEIGHT        ; player bottom
   
    ; Get obstacle bounds
    mov si, [obstacle_x]      ; obstacle left
    mov di, [obstacle_y]      ; obstacle top
   
    ; Check for NO overlap (if any of these is true, no collision)
    ; 1. Player right <= Obstacle left
    cmp cx, si
    jle no_collision
   
    ; 2. Player left >= Obstacle right
    push si
    add si, CAR_WIDTH
    cmp ax, si
    pop si
    jge no_collision
   
    ; 3. Player bottom <= Obstacle top
    cmp dx, di
    jle no_collision
   
    ; 4. Player top >= Obstacle bottom
    push di
    add di, CAR_HEIGHT
    cmp bx, di
    pop di
    jge no_collision
   
    ; If we reach here, there IS a collision!
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

; === GENERATE BONUS ===
generate_bonus:
    push ax
    push bx
    push cx
    push dx
   
    mov al, [bonus_active]
    cmp al, 1
    je skip_gen_bonus
   
    inc word [bonus_counter]
    mov ax, [bonus_counter]
    cmp ax, 150
    jl skip_gen_bonus
   
    mov word [bonus_counter], 0
    mov byte [bonus_active], 1
   
    ; Get random lane
    mov ah, 0
    int 1Ah
    mov ax, dx
    add ax, 7
    xor dx, dx
    mov cx, 3
    div cx
    mov [bonus_lane], dl
   
    ; Set bonus position - centered in lane (bonus is 16px, car is 26px)
    ; So we add (26-16)/2 = 5 pixels to center it
    cmp dl, 0
    je set_bonus_lane_0
    cmp dl, 1
    je set_bonus_lane_1
    ; Lane 2 (right): 187 + 5 = 192
    mov word [bonus_x], 192
    jmp bonus_lane_set
   
set_bonus_lane_0:
    ; Lane 0 (left): 107 + 5 = 112
    mov word [bonus_x], 112
    jmp bonus_lane_set
   
set_bonus_lane_1:
    ; Lane 1 (middle): 147 + 5 = 152
    mov word [bonus_x], 152
   
bonus_lane_set:
    mov word [bonus_y], -16     ; Start above screen
   
skip_gen_bonus:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === UPDATE BONUS POSITION ===
update_bonus_position:
    push ax
    push bx
    push cx
   
    mov al, [bonus_active]
    cmp al, 0
    je skip_update_bon_pos
    
    ; ERASE OLD POSITION FIRST
    mov bx, [bonus_x]
    mov cx, [bonus_y]
    call erase_bonus
   
    ; Move down by 2 pixels
    add word [bonus_y], 2
   
    ; Check if off screen
    mov ax, [bonus_y]
    cmp ax, 200
    jl skip_update_bon_pos
   
    ; Deactivate
    mov byte [bonus_active], 0
   
skip_update_bon_pos:
    pop cx
    pop bx
    pop ax
    ret

; === DRAW BONUS SPRITE (Gold Star) ===
draw_bonus_sprite:
    push ax
    push dx
    push di
    push si
    push bx
    push cx

    ; Check if bonus is within screen bounds
    mov ax, cx
    cmp ax, -16
    jl skip_draw_bon_sprite
    cmp ax, 200
    jge skip_draw_bon_sprite

    mov si, bonus_sprite_data
    mov dx, 0

bonus_sprite_row:
    mov ax, cx
    add ax, dx
    cmp ax, 0
    jl skip_bonus_row
    cmp ax, 200
    jge skip_draw_bon_sprite
    
    mov di, ax
    imul di, 320
    add di, bx

    push cx
    mov cx, 0
bonus_sprite_col:
        mov al, [si]
        inc si
        cmp al, 0
        je skip_bonus_pixel
        
        ; Check road boundaries
        push bx
        add bx, cx
        cmp bx, 102
        jl skip_bon_pixel_pop
        cmp bx, 217
        jg skip_bon_pixel_pop
        pop bx
        
        mov [es:di], al
        jmp continue_bonus_pixel
        
skip_bon_pixel_pop:
        pop bx
        
skip_bonus_pixel:
continue_bonus_pixel:
        inc di
        inc cx
        cmp cx, BONUS_SIZE
        jl bonus_sprite_col
    pop cx
    jmp after_bonus_row

skip_bonus_row:
    add si, BONUS_SIZE
    
after_bonus_row:
    inc dx
    cmp dx, BONUS_SIZE
    jl bonus_sprite_row

skip_draw_bon_sprite:
    pop cx
    pop bx
    pop si
    pop di
    pop dx
    pop ax
    ret

bonus_sprite_data:
    ; 16x16 golden star
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

; === CHECK BONUS COLLISION ===
check_bonus_collision:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    mov al, [bonus_active]
    cmp al, 0
    je no_bonus_collision
   
    ; Get player bounds
    mov ax, [car_x]
    mov bx, [car_y]
    mov cx, ax
    add cx, CAR_WIDTH
    mov dx, bx
    add dx, CAR_HEIGHT
   
    ; Get bonus bounds
    mov si, [bonus_x]
    mov di, [bonus_y]
   
    ; Check overlap
    ; 1. Player right <= Bonus left
    cmp cx, si
    jle no_bonus_collision
   
    ; 2. Player left >= Bonus right
    push si
    add si, BONUS_SIZE
    cmp ax, si
    pop si
    jge no_bonus_collision
   
    ; 3. Player bottom <= Bonus top
    cmp dx, di
    jle no_bonus_collision
   
    ; 4. Player top >= Bonus bottom
    push di
    add di, BONUS_SIZE
    cmp bx, di
    pop di
    jge no_bonus_collision
   
    ; BONUS COLLECTED!
    ; Erase the bonus first
    push bx
    push cx
    mov bx, [bonus_x]
    mov cx, [bonus_y]
    call erase_bonus
    pop cx
    pop bx
    
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

; === INSTALL TIMER ISR ===
install_timer_isr:
    push ax
    push bx
    push dx
    push es
    
    cli                     ; Disable interrupts
    
    ; Save old timer ISR (INT 08h)
    mov ax, 3508h           ; Get interrupt vector
    int 21h                 ; ES:BX now contains old ISR address
    mov word [old_timer_isr], bx
    mov word [old_timer_isr+2], es
    
    ; Install new timer ISR
    push ds
    push cs
    pop ds
    mov dx, timer_isr       ; Offset of our ISR
    mov ax, 2508h           ; Set interrupt vector
    int 21h
    pop ds
    
    sti                     ; Enable interrupts
    
    pop es
    pop dx
    pop bx
    pop ax
    ret

; === TIMER ISR ===
timer_isr:
    push ax
    push ds
    
    push cs
    pop ds
    
    ; Increment tick counter
    inc word [timer_tick_count]
    
    ; Check if it's time to scroll
    mov ax, [timer_tick_count]
    cmp ax, [scroll_delay]
    jl timer_done
    
    ; Reset counter and SET FLAG
    mov word [timer_tick_count], 0
    mov byte [scroll_ready], 1
    
timer_done:
    pop ds
    pop ax
    
    ; Jump to original timer ISR
    jmp far [cs:old_timer_isr]

; === RESTORE TIMER ISR ===
restore_timer_isr:
    push ax
    push dx
    push ds
    
    cli                     ; Disable interrupts
    
    ; Check if we have a valid saved ISR
    mov ax, [old_timer_isr]
    or ax, [old_timer_isr+2]
    jz skip_restore         ; Don't restore if not set
    
    ; Restore original timer ISR
    mov dx, [old_timer_isr]
    mov ax, [old_timer_isr+2]
    mov ds, ax
    mov ax, 2508h
    int 21h
    
    ; Clear the saved ISR
    push cs
    pop ds
    mov word [old_timer_isr], 0
    mov word [old_timer_isr+2], 0
    
skip_restore:
    sti                     ; Enable interrupts
    
    pop ds
    pop dx
    pop ax
    ret

; === DISPLAY SCORE DURING GAMEPLAY ===
display_score_ingame:
    push ax
    push bx
    push cx
    push dx
    push di
    
    ; Draw score background (top-right corner)
    mov cx, 2
score_bg_y:
    mov dx, 270
    push cx
score_bg_x:
        mov di, cx
        imul di, 320
        add di, dx
        mov al, 8  ; black background
        mov [es:di], al
        inc dx
        cmp dx, 318
        jl score_bg_x
    pop cx
    inc cx
    cmp cx, 12
    jl score_bg_y
    
    ; Display "Score:" text using BIOS
    mov dh, 0           ; row 0
    mov dl, 34          ; column
    mov si, score_text_small
    mov bl, 14          ; yellow color
    call print_string
    
    ; Display score number
    mov ax, [score]
    mov dh, 1           ; row 1
    mov dl, 35          ; column
    call print_number_small
    
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === PRINT NUMBER IN GRAPHICS MODE (SMALL) ===
print_number_small:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    ; Save starting position
    push dx
    
    ; Handle zero case
    test ax, ax
    jnz convert_start_small
    
    ; Display "0"
    pop dx
    mov ah, 02h
    mov bh, 0
    int 10h
    
    mov ah, 09h
    mov al, '0'
    mov bh, 0
    mov bl, 15
    mov cx, 1
    int 10h
    jmp print_num_small_done
    
convert_start_small:
    ; Convert number to string
    mov bx, 10
    mov cx, 0
    
convert_num_small_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz convert_num_small_loop
    
    ; Get starting position back
    pop dx              ; This is now the last digit, need position
    push dx             ; Put it back
    
    ; We need to reconstruct the original dx value
    ; For now, use fixed position
    mov dh, 1
    mov dl, 35
    
print_num_small_loop:
    ; Set cursor
    mov ah, 02h
    mov bh, 0
    int 10h
    
    pop ax              ; Get digit
    add al, '0'
    
    push cx
    push dx
    
    mov ah, 09h
    mov bh, 0
    mov bl, 15
    mov cx, 1
    int 10h
    
    pop dx
    pop cx
    
    inc dl              ; Next column
    
    loop print_num_small_loop
    
print_num_small_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret