org 100h
%define CAR_WIDTH  26
%define CAR_HEIGHT 32
%define BONUS_SIZE 16

jmp start

; var
car_x dw 107          ; car X position (left lane)
car_y dw 160          ; car Y position
current_lane db 0     ; 0=left, 1=middle, 2=right
scroll_offset dw 0    ; for scrolling animation
spawn_counter dw 0    ; for obstacle spawning
bonus_counter dw 0    ; for bonus spawning

; text
game_title db "RACING GAME", 0
student_info db "By: Maliha (0660), Fatima (0588)", 0
semester_info db "Semester: Fall 2025", 0
press_any_key db "Press any key to start...", 0
exit_confirm_msg db "Do you want to exit? (Y/N)", 0
score_msg db "Your Score: ", 0
game_over_msg db "GAME OVER!", 0

; car
obstacle_active db 0      
obstacle_x dw 0          
obstacle_y dw 0          
obstacle_lane db 0  

; obh
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
   
    jmp no_key_pressed

no_key_pressed:
    ; Generate new objects if needed
    call generate_obstacle
    call generate_bonus
   
    ; Scroll the screen FIRST
    call move_screen
   
    ; Update positions
    call update_obstacle_position
    call update_bonus_position
   
    ; Draw objects at new positions
    call draw_obstacle
    call draw_bonus
   
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
    ; Small delay to show final frame
    call delay
    call delay
   
    ; Jump to exit screen
    jmp exit_game

; === EXIT ===
exit_game:
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
   
    ; Convert number to string
    mov bx, 10
    mov cx, 0
   
convert_num_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz convert_num_loop
   
print_num_loop:
    pop ax
    add al, '0'
    mov ah, 0Eh
    mov bh, 0
    int 10h
    loop print_num_loop
   
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === MOVE SCREEN (SCROLL DOWN) ===
move_screen:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
   
    ; Move all rows down by 1 pixel
    mov cx, 198         ; start at row 198
scroll_loop:
    push cx
   
    ; Calculate source position (current row)
    mov di, cx
    imul di, 320
   
    ; Calculate destination (next row down)
    mov si, di
    add si, 320
   
    ; Copy road section (100 to 220)
    mov bx, 100
copy_road:
        mov al, [es:di+bx]
        mov [es:si+bx], al
        inc bx
        cmp bx, 220
        jl copy_road
   
    ; Copy left landscape (0 to 100)
    mov bx, 0
copy_left:
        mov al, [es:di+bx]
        mov [es:si+bx], al
        inc bx
        cmp bx, 100
        jl copy_left
   
    ; Copy right landscape (220 to 320)
    mov bx, 220
copy_right:
        mov al, [es:di+bx]
        mov [es:si+bx], al
        inc bx
        cmp bx, 320
        jl copy_right
   
    pop cx
    dec cx
    cmp cx, 0
    jge scroll_loop
   
    ; Redraw top row
    call redraw_top_row
   
    ; Redraw car (it stays in same position)
    mov bx, [car_x]
    mov cx, [car_y]
    call draw_car_sprite
   
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
    mov cx, 0           ; y = 0 (top row)
   
    ; Draw left landscape
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
   
    ; Draw road
    mov dx, 100
redraw_road_top:
        mov di, dx
        mov al, 7           ; grey
        mov [es:di], al
        inc dx
        cmp dx, 220
        jl redraw_road_top
   
    ; Draw right landscape
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
   
    mov di, 219
    mov [es:di], al
    mov [es:di-1], al
   
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
   
    mov dx, 0           ; row counter
erase_row:
    mov di, cx
    add di, dx
    imul di, 320
    add di, bx
   
    push cx
    push bx
    mov cx, 0           ; column counter
erase_col:
        mov al, 7       ; default road color (grey)
       
        ; Check if we're on a lane divider
        mov bx, [car_x]
        add bx, cx
       
        cmp bx, 140
        je check_divider
        cmp bx, 180
        je check_divider
        jmp not_divider
       
check_divider:
        push ax
        push dx
        mov ax, [car_y]
        add ax, dx
        push cx
        mov cx, 20
        xor dx, dx
        div cx
        cmp dx, 10
        pop cx
        pop dx
        pop ax
        jge not_divider
       
        mov al, 15      ; white dash
       
not_divider:
        mov [es:di], al
        inc di
        inc cx
        cmp cx, CAR_WIDTH
        jl erase_col
    pop bx
    pop cx
   
    inc dx
    cmp dx, CAR_HEIGHT
    jl erase_row
   
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
    mov word [obstacle_y], 0
   
skip_generate:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; === UPDATE OBSTACLE POSITION ===
update_obstacle_position:
    push ax
   
    mov al, [obstacle_active]
    cmp al, 0
    je skip_update_pos
   
    ; Move down by 1 (in addition to scroll)
    inc word [obstacle_y]
   
    ; Check if off screen
    mov ax, [obstacle_y]
    cmp ax, 200
    jl skip_update_pos
   
    ; Passed player - increment score
    add word [score], 10
   
    ; Deactivate
    mov byte [obstacle_active], 0
   
skip_update_pos:
    pop ax
    ret

; === DRAW OBSTACLE ===
draw_obstacle:
    push ax
    push bx
    push cx
   
    mov al, [obstacle_active]
    cmp al, 0
    je skip_draw_obstacle
   
    mov bx, [obstacle_x]
    mov cx, [obstacle_y]
    call draw_obstacle_sprite
   
skip_draw_obstacle:
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

    ; Check if obstacle is within screen bounds
    mov ax, [obstacle_y]
    cmp ax, 0
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
    jge skip_obstacle_row

    mov di, cx
    add di, dx
    imul di, 320
    add di, bx

    mov ah, 0
obstacle_car_col:
        mov al, [si]
        inc si
        
        cmp al, 0
        je skip_obstacle_pixel
        
        ; Check if pixel is within road boundaries (X: 102 to 217)
        push ax
        push bx
        mov al, ah      ; get column counter
        xor ah, ah      ; extend to 16-bit
        add ax, bx      ; ax now has current X position
        
        cmp ax, 102     ; left road boundary
        jl skip_obstacle_pixel_bound
        
        cmp ax, 217     ; right road boundary
        jg skip_obstacle_pixel_bound
        
        pop bx
        pop ax
        
        ; Convert red colors to blue
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
        
skip_obstacle_pixel_bound:
        pop bx
        pop ax
        
skip_obstacle_pixel:
continue_obstacle_pixel:
        inc di
        inc ah
        cmp ah, CAR_WIDTH
        jl obstacle_car_col

skip_obstacle_row:
    inc dx
    cmp dx, CAR_HEIGHT
    jl obstacle_car_row

skip_draw_obs_sprite:
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
   
    ; collision boom!!!
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
    mov word [bonus_y], 0
   
skip_gen_bonus:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; checking bonus position
update_bonus_position:
    push ax
   
    mov al, [bonus_active]
    cmp al, 0
    je skip_update_bonus
   
    inc word [bonus_y]
   
    mov ax, [bonus_y]
    cmp ax, 200
    jl skip_update_bonus
   
    mov byte [bonus_active], 0
   
skip_update_bonus:
    pop ax
    ret

; bonus!!
draw_bonus:
    push ax
    push bx
    push cx
   
    mov al, [bonus_active]
    cmp al, 0
    je skip_draw_bonus
   
    mov bx, [bonus_x]
    mov cx, [bonus_y]
    call draw_bonus_sprite
   
skip_draw_bonus:
    pop cx
    pop bx
    pop ax
    ret

; drawing bonus :)
draw_bonus_sprite:
    push ax
    push dx
    push di
    push si

    ; Check if bonus is within screen bounds
    mov ax, [bonus_y]
    cmp ax, 0
    jl skip_draw_bon_sprite
    cmp ax, 200
    jge skip_draw_bon_sprite

    mov si, bonus_sprite_data
    mov dx, 0

bonus_sprite_row:
    mov di, cx
    add di, dx
    imul di, 320
    add di, bx

    mov ah, 0
bonus_sprite_col:
        mov al, [si]
        cmp al, 0
        je skip_bonus_pixel
        
        ; Check if pixel is within road boundaries (X: 102 to 217)
        push ax
        push bx
        mov al, ah      ; get column counter
        mov ah, 0       ; extend to 16-bit
        add bx, ax      ; bx now has current X position
        cmp bx, 102
        pop bx
        jl skip_bonus_pixel_bound
        
        push bx
        mov al, ah
        mov ah, 0
        add bx, ax
        cmp bx, 217
        pop bx
        jg skip_bonus_pixel_bound
        
        pop ax
        mov [es:di], al
        jmp skip_bonus_pixel
        
skip_bonus_pixel_bound:
        pop ax
        
skip_bonus_pixel:
        inc si
        inc di
        inc ah
        cmp ah, BONUS_SIZE
        jl bonus_sprite_col

    inc dx
    cmp dx, BONUS_SIZE
    jl bonus_sprite_row

skip_draw_bon_sprite:
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

; bonus
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
    mov ax, [car_x
    mov bx, [car_y]
    mov cx, ax
    add cx, CAR_WIDTH
    mov dx, bx
    add dx, CAR_HEIGHT
   
    ; Get bonus bounds
    mov si, [bonus_x]
    mov di, [bonus_y]
   
    ; Check overlap
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

; === END OF PROGRAM ===8,8,8,8,8,8,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,8,8,8,8,8,8,8,