# Cars

A retro racing game built in x86 Assembly (DOS). Dodge oncoming cars, collect bonus items, and survive as long as possible on a 3-lane road rendered in VGA Mode 13h (320×200, 256 colors).

Built for the Fall 2025 semester by Maliha (0660) and Fatima (0588).

---

## Gameplay

- Avoid the red obstacle cars coming toward you
- Collect yellow bonus items for extra points (+50)
- Every obstacle car you survive past scores +10 points
- The game ends when you collide with an obstacle car
- Press **ESC** at any time to pause

---

## Controls

| Key | Action |
|---|---|
| ← Left Arrow | Move car to left lane |
| → Right Arrow | Move car to right lane |
| ESC | Pause game |
| R | Resume (from pause) |
| Q | Quit (from pause) |
| Y / N | Confirm or cancel exit |

---

## How to Run

You need DOSBox or a real DOS environment to run this.

### With DOSBox

1. Install [DOSBox](https://www.dosbox.com/)
2. Assemble the source file using NASM:
```bash
nasm -f bin game.asm -o game.com
```
3. Open DOSBox and mount your project folder:
```
mount c C:\path\to\cars
c:
game.com
```

### Assembling

Make sure you have [NASM](https://www.nasm.us/) installed, then:
```bash
nasm -f bin game.asm -o game.com
```

---

## Features

- **VGA Mode 13h** — 320×200 resolution, 256 color graphics
- **Scrolling road** — Background scrolls downward using a timer interrupt for smooth animation
- **3 lanes** — Left, middle, and right lanes to dodge between
- **Sprite rendering** — Pixel-art car, obstacle car, bonus item, trees, and bushes drawn using sprite data
- **Custom interrupts** — Timer (INT 08h) and keyboard (INT 09h) handlers installed for real-time input and scrolling
- **Pause screen** — Overlay with resume and quit options
- **Score system** — Live score displayed in a HUD bar at the top of the screen
- **Intro screen** — Title screen shown on launch before the game starts
- **Game over screen** — Shows final score with option to play again or exit
- **Collision detection** — AABB (bounding box) collision for both obstacle cars and bonus items

---

## Project Structure

```
cars/
└── game.asm    ← Full game source (single file)
```

---

## Technical Details

| Detail | Value |
|---|---|
| Architecture | x86 16-bit (DOS COM file) |
| Assembler | NASM |
| Video mode | VGA Mode 13h (320×200) |
| Origin | `org 100h` (COM format) |
| Car sprite size | 26×32 pixels |
| Bonus sprite size | 16×16 pixels |
| Scrolling | Timer interrupt (INT 08h) driven |
| Input | Keyboard interrupt (INT 09h) |
| Scoring | +10 per obstacle survived, +50 per bonus collected |
