# mips-soc

A pipelined MIPS CPU written in SystemVerilog, running on a Terasic DE10-Lite FPGA (Intel MAX 10). The goal is a small and relatively simple yet complete computer that boots off an SD card and shows a terminal on a VGA monitor, with a PS/2 keyboard for input.

The CPU started as a 5-stage MIPS core I wrote in VHDL for my Computer Organization class. I converted it to SystemVerilog, checked it against the original, and have been building on it ever since. Everything around the core is new. That means the VGA output, the keyboard, the SDRAM and the SD card.

I built this to learn digital hardware design by doing it, including pipelining, hazards, timing and memory-mapped I/O. The longer-term goal is to understand graphics-hardware-adjacent ideas like fixed-function accelerators, memory bandwidth and how a CPU talks to a coprocessor.

## Hardware

- Board is a Terasic DE10-Lite
- FPGA is an Intel MAX 10 (10M50DAF484C7G)
- Toolchain is Quartus Prime Lite Edition
- The keyboard is a PS/2 keyboard on the Arduino header. Clock is on IO3 and data is on IO2. PS/2 runs at 5 V and the FPGA pins are 3.3 V, so both lines go through a small logic level shifter module.
- The SD card is a microSD breakout on the Arduino header. CS is on IO10, MOSI on IO11, MISO on IO12 and SCK on IO13. It runs on 3.3 V.
- A breadboard power supply module provides the 3.3 V and 5 V rails for the keyboard, the level shifter and the SD breakout.

## Memory map

| Address | What it is |
|---|---|
| 0x00010000 | Framebuffer, one word per pixel (320x240, 3-3-2 color) |
| 0x00060000 | Text buffer, one word per character (80x60) |
| 0x00070000 to 0x00070008 | Raw keyboard scancode, status and acknowledge |
| 0x00070010 to 0x00070018 | Typed characters (data, status and acknowledge) |
| 0x00070020 | Cursor position |
| 0x00070030 | LED register |
| 0x04000000 to 0x07FFFFFF | SDRAM (64 MB) |

## Board controls

KEY[0] is reset. KEY[1] steps the CPU one clock when SW[0] is up, and pauses or resumes it when SW[0] is down.

| Switch | What it does |
|---|---|
| SW[0] | Up for single-step, down for free-run |
| SW[1] to SW[5] | Pick what the six HEX displays show (see below) |
| SW[6] | Keyboard debug on the HEX displays. It shows the last raw scancode and overrides SW[1] to SW[5]. |
| SW[7] | Down shows the SDRAM and CPU LEDs, up shows the SD card status LEDs |
| SW[8], SW[9] | Not used |

SW[5:1] is read as one 5-bit code, with SW[5] as the top bit.

| SW[5:1] | HEX displays show |
|---|---|
| 00001 | Program counter |
| 00010 | Current instruction |
| 00100 | Write data |
| 01000 | Memory address |
| 10000 | Read data |
| 11000 | SDRAM test, the value it expected after a failure |
| 11001 | SDRAM test, the value it actually read after a failure |
| 11010 | SD test, the byte read, the byte expected and the block number after a mismatch |
| 11011 | SD test, the error code, the position of the bad byte and whether the card is SDHC |

In the SDRAM and SD modes the left digit is a status digit. C means the test passed, 8 means it failed and 0 means it is still running.

With SW[7] down, the LEDs show the following.

| LED | Meaning |
|---|---|
| LEDR[0] | SDRAM power-on test passed |
| LEDR[1] | SDRAM power-on test failed |
| LEDR[2] | SDRAM test is in its waiting period |
| LEDR[9:3] | LED register the CPU writes to. Its SDRAM test writes 1 while running, 3 when it passes and 5 when it fails. |

With SW[7] up, the LEDs show the SD card status.

| LED | Meaning |
|---|---|
| LEDR[0] | Card is set up |
| LEDR[1] | SD test passed |
| LEDR[2] | SD test failed |
| LEDR[3] | Card is SDHC or SDXC |
| LEDR[4] | Controller hit an error |
| LEDR[9:5] | Error code (low 5 bits) |

The SD error codes are 01 for no reply to CMD0, 02 for a wrong reply to CMD0, 03 and 04 for CMD8, 05 for CMD55, 06 for ACMD41 (the card never got ready), 07 for CMD58, 08 for CMD16, 10 to 13 for block read problems, 20 for a data mismatch and 21 for the wrong number of bytes.

## Project structure

```
src/            SystemVerilog source files
mips_soc.qpf    Quartus project file
mips_soc.qsf    Quartus settings and pin assignments
```