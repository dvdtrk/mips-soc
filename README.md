# mips-soc

A pipelined MIPS CPU implemented in SystemVerilog, running on a Terasic DE10-Lite (Intel MAX 10) FPGA. This project is a from-scratch exploration of computer architecture and digital hardware design, built on top of a 5-stage pipelined MIPS core originally written in VHDL for a Computer Organization course, which I converted to SystemVerilog (translating std_logic/std_logic_vector to logic, VHDL processes to always_comb/always_ff blocks, etc.) and verified against the original before extending it. The end goal is a small but complete computer: real branch/jump support, a memory-mapped graphics accelerator driving VGA output to a monitor, PS/2 keyboard input, and a bootloader that loads compiled programs off an SD card into RAM at runtime, a genuine hardware/software boundary, rather than one fixed program baked into the FPGA bitstream, all tied together with a simple 2D game as the end-to-end demo. Built as a hands-on way to learn the fundamentals of digital hardware design such as pipelining, hazards, timing, memory-mapped I/O, with a longer-term goal of understanding graphics-hardware-adjacent concepts (fixed-function accelerators, memory bandwidth, CPU/coprocessor interaction) from the ground up.

## Hardware

- **Board:** Terasic DE10-Lite
- **FPGA:** Intel MAX 10 (10M50DAF484C7G)
- **Toolchain:** Quartus Prime Lite Edition

## Project structure

```
src/            SystemVerilog source files
mips_soc.qpf    Quartus project file
mips_soc.qsf    Quartus settings / pin assignments
```