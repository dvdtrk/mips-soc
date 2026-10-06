module microcomputer #(
	parameter int FREERUN_BIT = 14, // ~1.5kHz free-run clock
	parameter int SELFTEST_RETENTION_CYCLES = 50_000_000
) (
	input  logic       CLOCK_50,   // 50MHz clock on the DE10-Lite board
	input  logic [1:0] KEY,        // keys/buttons (KEY[0]-KEY[1])
	input  logic [9:0] SW,         // switches (SW[9]..SW[0])
	output logic [9:0] LEDR,       // LEDs (unused, see note below)
	output logic [6:0] HEX0,       // 7-segment display, digit 0
	output logic [6:0] HEX1,       // 7-segment display, digit 1
	output logic [6:0] HEX2,       // 7-segment display, digit 2
	output logic [6:0] HEX3,       // 7-segment display, digit 3
	output logic [6:0] HEX4,       // 7-segment display, digit 4
	output logic [6:0] HEX5,       // 7-segment display, digit 5
    output logic       VGA_HS,
	output logic       VGA_VS,
	output logic [3:0] VGA_R,
	output logic [3:0] VGA_G,
	output logic [3:0] VGA_B,
	input  logic       PS2_KBD_CLK,   // ARDUINO_IO[3] / D3
	input  logic       PS2_KBD_DATA,   // ARDUINO_IO[2] / D2

	output logic [12:0] DRAM_ADDR,
	output logic [1:0]  DRAM_BA,
	output logic        DRAM_CAS_N,
	output logic        DRAM_CKE,
	output logic        DRAM_CLK,
	output logic        DRAM_CS_N,
	inout  wire  [15:0] DRAM_DQ,
	output logic        DRAM_LDQM,
	output logic        DRAM_RAS_N,
	output logic        DRAM_UDQM,
	output logic        DRAM_WE_N
);

	//---- Signal declarations ----
	logic        reset;
	logic        clock;
	logic [31:0] instruction;
	logic [31:0] pc;

	logic [31:0] address;
	logic [31:0] Writedata;
	logic        memory_read, memory_write;
	logic 		 sdram_stall;
	logic [31:0] sdram_read_data;
	logic [31:0] Readdata;

    //---------------------------------------------------------------------
	// VGA / framebuffer: memory-mapped I/O address decode
	//---------------------------------------------------------------------
	// Addresses 0x10000 through 0x10000 + 19200*4 map to the framebuffer.

	localparam logic [31:0] FB_BASE  = 32'h00010000;
	localparam logic [31:0] FB_BYTES = 32'd76800 * 4;
	localparam logic [31:0] TXT_BASE  = 32'h00060000;
	localparam logic [31:0] TXT_BYTES = 32'd4800 * 4;

	localparam logic [31:0] KBD_DATA_ADDR 	= 32'h00070000;
	localparam logic [31:0] KBD_STATUS_ADDR = 32'h00070004;
	localparam logic [31:0] KBD_ACK_ADDR 	= 32'h00070008;

	localparam logic [31:0] KEY_EVENT_DATA_ADDR   	= 32'h00070010;
	localparam logic [31:0] KEY_EVENT_STATUS_ADDR 	= 32'h00070014;
	localparam logic [31:0] KEY_EVENT_ACK_ADDR		= 32'h00070018;
	localparam logic [31:0] CURSOR_POS_ADDR 		= 32'h00070020;
	localparam logic [31:0] LED_ADDR                = 32'h00070030; // SDRAM: 64MB at 0x04000000 - 0x07FFFFFF (address[31:26] == 1)

	logic is_kbd_data_region, is_kbd_status_region, is_kbd_ack_region;
	assign is_kbd_data_region 	= (address == KBD_DATA_ADDR);
	assign is_kbd_status_region = (address == KBD_STATUS_ADDR);
	assign is_kbd_ack_region	= (address == KBD_ACK_ADDR);

	logic is_key_event_data_region, is_key_event_status_region, is_key_event_ack_region;
	assign is_key_event_data_region   = (address == KEY_EVENT_DATA_ADDR);
	assign is_key_event_status_region = (address == KEY_EVENT_STATUS_ADDR);
	assign is_key_event_ack_region    = (address == KEY_EVENT_ACK_ADDR);
	logic is_cursor_pos_region;
	assign is_cursor_pos_region = (address == CURSOR_POS_ADDR);
	logic is_led_region, is_sdram_region;
	assign is_led_region   = (address == LED_ADDR);
	assign is_sdram_region = (address[31:26] == 6'd1); // 0x04000000 - 0x07FFFFFF

	logic        is_fb_region, is_txt_region;
	logic        memory_write_dm, memory_write_fb, memory_write_txt, memory_read_dm;
	logic [16:0] fb_write_addr;
	logic [12:0] txt_write_addr;
	assign is_fb_region     = (address >= FB_BASE)  && (address < FB_BASE  + FB_BYTES);
	assign is_txt_region    = (address >= TXT_BASE) && (address < TXT_BASE + TXT_BYTES);
	assign memory_write_dm  = memory_write && !is_fb_region && !is_txt_region && !is_kbd_ack_region && !is_key_event_ack_region  
								&& !is_cursor_pos_region && !is_led_region && !is_sdram_region;
	assign memory_read_dm   = memory_read  && !is_fb_region && !is_txt_region && !is_kbd_data_region && !is_kbd_status_region 
								&& !is_key_event_data_region && !is_key_event_status_region && !is_sdram_region;
	assign memory_write_fb  = memory_write &&  is_fb_region;
	assign memory_write_txt = memory_write &&  is_txt_region;
	assign fb_write_addr    = (address - FB_BASE)  >> 2;
	assign txt_write_addr   = (address - TXT_BASE) >> 2;


	// The framebuffer gets written on the CPU's slow manual clock but read
	// continuously on the free running 25MHz pixel clock, so these are two
	// different clock domains touching the same memory.

	logic       vga_reset;
	logic       clk25;
	logic       hsync, vsync, video_on;
	logic [9:0] h_count, v_count;
	logic [7:0] fb_pixel;
	logic [16:0] fb_read_addr;
	logic [7:0] char_code;
	logic [12:0] txt_read_addr;

	assign vga_reset = ~KEY[0]; // same physical reset as the CPU

	logic [3:0]  plusone, plusone1, plusone2, plusone3, plusone4, plusone5, plusone6, plusone7; // 7-seg digit values

	logic [31:0] counter_out;
	logic [1:0]  flipflops;
	logic        counter_set;
	localparam int COUNTER_SIZE = 16;

	initial begin
		counter_out = 32'h00000000;
		flipflops   = 2'b00;
	end

	//--------------------------------------------------------------------
	// reset / clock
	//--------------------------------------------------------------------
	assign reset = ~KEY[0]; // KEY[0] is reset
	assign clock = step_mode ? ~KEY[1] : clock_gated;
	// SW[0] selects between single-step mode (advance one instruction per KEY[1] press, 
	// and free-run mode (the CPU clocks itself automatically off a divided-down version 
	// of CLOCK_50 which is fast enough for keyboard interacton

	logic step_mode;
	assign step_mode = SW[0]; // 1 = single step, 0 = free run

	// dedicated free-run clock divider
	logic [31:0] freerun_counter;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset)
			freerun_counter <= 32'd0;
		else
			freerun_counter <= freerun_counter + 32'd1;
	end
	// bit 14 of a counter clocked at 50MHz toggles at roughly 1.5kHz
	logic freerun_clock;
	assign freerun_clock = freerun_counter[FREERUN_BIT];

	// synchronizes KEY[1] and keeps track of its previous value
	logic key1_sync1, key1_sync2, key1_prev;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset) begin
			key1_sync1 <= 1'b1;
			key1_sync2 <= 1'b1;
			key1_prev  <= 1'b1;
		end else begin
			key1_sync1 <= KEY[1];
			key1_sync2 <= key1_sync1;
			key1_prev  <= key1_sync2;
		end
	end

	logic pause_toggle;
	assign pause_toggle = ~step_mode & key1_prev & ~key1_sync2; // one-cycle pulse on the press edge

	// Pausing just freezes the CPU's clock mid-execution, in free-run mode only
	logic paused;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset)
			paused <= 1'b0;
		else if (pause_toggle)
			paused <= ~paused;
	end

	// Only lets freerun_clock's transitions through while not paused
	// While paused, this register simply holds its last value 
	logic clock_gated;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset)
			clock_gated <= 1'b0;
		else if (!paused && !sdram_stall)
			clock_gated <= freerun_clock;
	end

	assign counter_set = flipflops[0] ^ flipflops[1];

	always_ff @(posedge CLOCK_50) begin
		flipflops[0] <= ~KEY[1];
		flipflops[1] <= flipflops[0];
		if (counter_set)
			counter_out <= 32'h00000000;
		else if (!counter_out[COUNTER_SIZE])
			counter_out <= counter_out + 1;
		// else: clock <= flipflops[1]; (unused / commented out in original too)
	end

	//---- Component instantiations ----
	mips CPU_1 (
		.clock_mips       (clock),
		.reset_mips       (reset),
		.pc_mips          (pc),
		.instruction_mips (instruction),
		.address_mips     (address),
		.Writedata_mips   (Writedata),
		.overflow_mips    (),           // not wired up in original design either
		.invalid_mips     (),           // not wired up in original design either
		.memory_read_mips (memory_read),
		.memory_write_mips(memory_write),
		.Readdata_mips    (Readdata_cpu)
	);

	inst_memory_128B MEMORY_1 (
		.clock_im      (clock),
		.reset_im      (reset),
		.pc_im         (pc),
		.instruction_im(instruction)
	);

	data_memory_64B MEMORY_2 (
		.clock_dm        (clock),
		.reset_dm        (reset),
		.address_dm      (address),
		.Writedata_dm    (Writedata),
		.memory_read_dm  (memory_read),
		.memory_write_dm (memory_write_dm),
		.Readdata_dm     (Readdata)
	);

    // VGA / framebuffer instantiations -----------------------------------
	framebuffer FB (
		.reset      (reset),
		.write_en   (memory_write_fb),
		.write_addr (fb_write_addr),
		.write_data (Writedata),
		.read_clock (clk25),
		.read_addr  (fb_read_addr),
		.read_data  (fb_pixel)
	);

	text_buffer TXT (
		.reset      (reset),
		.write_en   (memory_write_txt),
		.write_addr (txt_write_addr),
		.write_data (Writedata),
		.read_clock (clk25),
		.read_addr  (txt_read_addr),
		.read_data  (char_code)
	);

	font_rom FONT (
		.char_code(char_code),
		.row      (char_row_in_glyph_d),
		.font_row (font_row_bits)
	);

	vga_sync VGA (
		.clk50   (CLOCK_50), // real-time, independent of the CPU's manual clock
		.reset   (vga_reset),
		.clk25   (clk25),
		.hsync   (hsync),
		.vsync   (vsync),
		.video_on(video_on),
		.h_count (h_count),
		.v_count (v_count)
	);

		//---- PS/2 keyboard ----
	// Runs on CLOCK_50, not the CPU's slow manual clock - the keyboard
	// sends data at its own fixed rate regardless of how often KEY[1] gets
	// pressed, so this needs to always be listening.
	logic [7:0] kbd_scancode;
	logic       kbd_data_ready;

	ps2_receiver KBD (
		.clock     (CLOCK_50),
		.reset     (reset),
		.ps2_clk   (PS2_KBD_CLK),
		.ps2_data  (PS2_KBD_DATA),
		.scancode  (kbd_scancode),
		.data_ready(kbd_data_ready)
	);

	// "new scancode available" status bit: set the moment a byte arrives.
	// Deliberately NOT cleared automatically by reading the status
	logic kbd_new_data;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset)
			kbd_new_data <= 1'b0;
		else if (kbd_data_ready)
			kbd_new_data <= 1'b1;
		else if (memory_write && is_kbd_ack_region)
			kbd_new_data <= 1'b0;
	end

	logic [7:0] kbd_scancode_held;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
    	if (reset)
        	kbd_scancode_held <= 8'h00;
    	else if (kbd_data_ready)
        	kbd_scancode_held <= kbd_scancode;
	end

	//This tracks whether the byte that just arrived should be swallowed because the previous byte was one of those two prefixes.
	logic prev_was_prefix;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset)
			prev_was_prefix <= 1'b0;
		else if (kbd_data_ready) begin
			if (prev_was_prefix)
				prev_was_prefix <= 1'b0;
			else if (kbd_scancode == 8'hF0 || kbd_scancode == 8'hE0)
				prev_was_prefix <= 1'b1;
		end
	end

	logic is_genuine_press;
	assign is_genuine_press = kbd_data_ready && !prev_was_prefix && (kbd_scancode != 8'hF0) && (kbd_scancode != 8'hE0);

	logic [7:0] key_ascii;
	scancode_to_ascii ASCII (
		.scancode(kbd_scancode),
		.ascii   (key_ascii)
	);

	logic key_event_ready;
	logic [7:0] key_event_char;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset) begin
			key_event_ready <= 1'b0;
			key_event_char  <= 8'h00;
		end else if (is_genuine_press && (key_ascii != 8'h00) && !key_event_ready) begin
			key_event_ready <= 1'b1;
			key_event_char  <= key_ascii;
		end else if (memory_write && is_key_event_ack_region) begin
			key_event_ready <= 1'b0;
		end
	end

	logic [31:0] Readdata_cpu;
	assign Readdata_cpu = is_sdram_region ? sdram_read_data :
							is_kbd_status_region ? {31'b0, kbd_new_data} :
	                    	is_kbd_data_region   ? {24'b0, kbd_scancode_held} :
							is_key_event_status_region ? {31'b0, key_event_ready} :
	                    	is_key_event_data_region   ? {24'b0, key_event_char} :
	                    	Readdata;


	// VGA scanout: map screen position to a framebuffer pixel ------------
	// each logical pixel is a 2x2 block on the real 640x480 screen:
	// 640/2=320, 480/2=240
	logic [16:0] fb_x, fb_y;
	assign fb_x = h_count[9:1]; // 0..319
	assign fb_y = v_count[9:1]; // 0..239
	assign fb_read_addr = (fb_y * 17'd320) + fb_x;

	//---- VGA scanout: map screen position to a text character cell ----
	// text uses the full native 640x480 resolution, split into 8x8 character
	// cells: 640/8=80 columns, 480/8=60 rows
	logic [6:0] char_col;
	logic [5:0] char_row;
	logic [2:0] col_in_glyph, row_in_glyph;
	assign char_col     = h_count[9:3];  // 0..79
	assign char_row     = v_count[8:3];  // 0..59
	assign col_in_glyph = h_count[2:0];  // 0..7
	assign row_in_glyph = v_count[2:0];  // 0..7
	assign txt_read_addr = (char_row * 7'd80) + char_col;

	// text_buffer and framebuffer both add one clk25 cycle of latency
	// (registered reads), so row_in_glyph and col_in_glyph need the same
	// one cycle delay to stay lined up with char_code once it comes back,
	// same idea as the hsync/vsync/video_on alignment below.
	logic [2:0] char_row_in_glyph_d, col_in_glyph_d;
	logic [6:0] char_col_d;
	logic [5:0] char_row_d;
	always_ff @(posedge clk25) begin
		char_row_in_glyph_d <= row_in_glyph;
		col_in_glyph_d      <= col_in_glyph;
		char_col_d          <= char_col;
		char_row_d 			<= char_row;
	end

	logic [7:0] font_row_bits;
	logic       text_pixel_on;
	assign text_pixel_on = font_row_bits[3'd7 - col_in_glyph_d];

	// Cursor
	logic [31:0] cursor_pos_addr;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset)
			cursor_pos_addr <= TXT_BASE;
		else if (memory_write && is_cursor_pos_region)
			cursor_pos_addr <= Writedata;
	end
	logic [12:0] cursor_char_index;
	assign cursor_char_index = (cursor_pos_addr - TXT_BASE) >> 2;

	logic cursor_on;
	assign cursor_on = (({6'b0, char_row_d} * 7'd80 + char_col_d) == cursor_char_index) && (char_row_in_glyph_d == 3'd7);

	// VGA color output ---------------------------------------------------

    logic hsync_d, vsync_d, video_on_d;
	always_ff @(posedge clk25) begin
		hsync_d    <= hsync;
		vsync_d    <= vsync;
		video_on_d <= video_on;
	end
    
	// simple 3-3-2 RGB decode: no palette table, just split the byte
	always_comb begin
		if (!video_on_d) begin
			VGA_R = 4'h0;
			VGA_G = 4'h0;
			VGA_B = 4'h0;
		end else if (text_pixel_on || cursor_on) begin
			VGA_R = 4'hF;
			VGA_G = 4'hF;
			VGA_B = 4'hF;	
		end else begin
			VGA_R = {fb_pixel[7:5], 1'b0}; // 3 bits -> upper 3 of the 4-bit DAC
			VGA_G = {fb_pixel[4:2], 1'b0};
			VGA_B = {fb_pixel[1:0], 2'b00}; // only 2 bits of blue available
		end
	end

	assign VGA_HS = hsync_d;
	assign VGA_VS = vsync_d;

	// PC, instruction, Writedata (=rdata2), address (=ALUresult), Readdata
	always_comb begin
		if (reset) begin
			plusone  = 4'b0000;
			plusone1 = 4'b0000;
			plusone2 = 4'b0000;
			plusone3 = 4'b0000;
			plusone4 = 4'b0000;
			plusone5 = 4'b0000;
			plusone6 = 4'b0000;
			plusone7 = 4'b0000;
					
		end else if (SW[6]) begin // keyboard debug: raw scancode + status, read directly from the ps2_receiver,
		                          // completely bypassing the CPU
			plusone  = kbd_scancode_held[3:0];
			plusone1 = kbd_scancode_held[7:4];
			plusone2 = {3'b000, kbd_new_data}; // 0 or 1: is a new key waiting?
			plusone3 = 4'b0000;
			plusone4 = 4'b0000;
			plusone5 = 4'b0000;

		end else if (SW[5:1] ==  5'b00001) begin // PC
			plusone  = pc[3:0];
			plusone1 = pc[7:4];
			plusone2 = pc[11:8];
			plusone3 = pc[15:12];
			plusone4 = pc[19:16];
			plusone5 = pc[23:20];

		end else if (SW[5:1] == 5'b00010) begin // instruction
			plusone  = instruction[3:0];
			plusone1 = instruction[7:4];
			plusone2 = instruction[11:8];
			plusone3 = instruction[15:12];
			plusone4 = instruction[19:16];
			plusone5 = pc[3:0];

		end else if (SW[5:1] == 5'b00100) begin // Writedata (=rdata2)
			plusone  = Writedata[3:0];
			plusone1 = Writedata[7:4];
			plusone2 = Writedata[11:8];
			plusone3 = Writedata[15:12];
			plusone4 = Writedata[19:16];
			plusone5 = pc[3:0];

		end else if (SW[5:1] == 5'b01000) begin // address (=ALUresult)
			plusone  = address[3:0];
			plusone1 = address[7:4];
			plusone2 = address[11:8];
			plusone3 = address[15:12];
			plusone4 = address[19:16];
			plusone5 = pc[3:0];

		end else if (SW[5:1] == 5'b10000) begin // Readdata
			plusone  = Readdata[3:0];
			plusone1 = Readdata[7:4];
			plusone2 = Readdata[11:8];
			plusone3 = Readdata[15:12];
			plusone4 = Readdata[19:16];
			plusone5 = pc[3:0];



		end else if (SW[5:1] == 5'b11000) begin // SDRAM test: expected value on failure
			plusone = fail_expected[3:0];
			plusone1 = fail_expected[7:4];
			plusone2 = fail_expected[11:8];
			plusone3 = fail_expected[15:12];
			plusone4 = fail_expected[19:16];
			plusone5 = {test_finished, test_passed, 2'b00}; // 1_1=passed, 1_0=failed, 0_x=still running

		end else if (SW[5:1] == 5'b11001) begin // SDRAM test: actual value read back on failure
			plusone = fail_actual[3:0];
			plusone1 = fail_actual[7:4];
			plusone2 = fail_actual[11:8];
			plusone3 = fail_actual[15:12];
			plusone4 = fail_actual[19:16];
			plusone5 = {test_finished, test_passed, 2'b00};



		end else begin
			plusone  = 4'b0000;
			plusone1 = 4'b0000;
			plusone2 = 4'b0000;
			plusone3 = 4'b0000;
			plusone4 = 4'b0000;
			plusone5 = pc[3:0];
		end
	end

	hex h0 (.i(plusone),  .o(HEX0));
	hex h1 (.i(plusone1), .o(HEX1));
	hex h2 (.i(plusone2), .o(HEX2));
	hex h3 (.i(plusone3), .o(HEX3));
	hex h4 (.i(plusone4), .o(HEX4));
	hex h5 (.i(plusone5), .o(HEX5));

	// NOTE: LEDR is declared as an output in the entity but is not driven
	// in the architecture, same pre-existing gap as overflow_mips/
	// invalid_mips, carried over faithfully rather than silently patched.
	// Worth wiring up when real debug/status LEDs are added.



	// SDRAM --------------------------------------------------------------------

	// Two parts share the controller. After reset, sdram_selftest runs the poweron check. O
	// Once that finishes, the CPU owns the controller.
	// A load or store whose address falls in the SDRAM region becomes a request,
	// and the CPU clock is held until the controller reports done

	logic [23:0] st_word_addr;
	logic [31:0] st_write_data;
	logic        st_read_req, st_write_req;
	logic [23:0] sdram_word_addr;
	logic [31:0] sdram_write_data;
	logic        sdram_read_req, sdram_write_req;
	logic        sdram_busy, sdram_done;

	logic        test_passed, test_finished, test_retention_wait;
	logic [31:0] fail_expected, fail_actual;

	logic cpu_read_req, cpu_write_req;
	assign sdram_word_addr  = test_finished ? address[25:2] : st_word_addr;
	assign sdram_write_data = test_finished ? Writedata     : st_write_data;
	assign sdram_read_req   = test_finished ? cpu_read_req  : st_read_req;
	assign sdram_write_req  = test_finished ? cpu_write_req : st_write_req;

	sdram_controller SDRAM (
		.clock      (CLOCK_50),
		.reset      (reset),
		.word_addr  (sdram_word_addr),
		.write_data (sdram_write_data),
		.read_req   (sdram_read_req),
		.write_req  (sdram_write_req),
		.read_data  (sdram_read_data),
		.busy       (sdram_busy),
		.done       (sdram_done),
		.DRAM_ADDR  (DRAM_ADDR),
		.DRAM_BA    (DRAM_BA),
		.DRAM_CAS_N (DRAM_CAS_N),
		.DRAM_CKE   (DRAM_CKE),
		.DRAM_CLK   (DRAM_CLK),
		.DRAM_CS_N  (DRAM_CS_N),
		.DRAM_DQ    (DRAM_DQ),
		.DRAM_LDQM  (DRAM_LDQM),
		.DRAM_RAS_N (DRAM_RAS_N),
		.DRAM_UDQM  (DRAM_UDQM),
		.DRAM_WE_N  (DRAM_WE_N)
	);

	sdram_selftest #(.RETENTION_CYCLES(SELFTEST_RETENTION_CYCLES)) SDRAM_SELFTEST (
		.clock          (CLOCK_50),
		.reset          (reset),
		.word_addr      (st_word_addr),
		.write_data     (st_write_data),
		.read_req       (st_read_req),
		.write_req      (st_write_req),
		.read_data      (sdram_read_data),
		.busy           (sdram_busy),
		.done           (sdram_done),
		.passed         (test_passed),
		.finished       (test_finished),
		.retention_wait (test_retention_wait),
		.fail_addr      (),
		.fail_expected  (fail_expected),
		.fail_actual    (fail_actual)
	);

	// The CPU clock as seen from the 50MHz domain, so a new CPU cycle can be
	// recognised (a new instruction has just entered the MEM stage).
	logic cpu_clk_s1, cpu_clk_s2, cpu_clk_prev;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset) begin
			cpu_clk_s1   <= 1'b0;
			cpu_clk_s2   <= 1'b0;
			cpu_clk_prev <= 1'b0;
		end else begin
			cpu_clk_s1   <= clock;
			cpu_clk_s2   <= cpu_clk_s1;
			cpu_clk_prev <= cpu_clk_s2;
		end
	end
	logic cpu_clock_edge;
	assign cpu_clock_edge = cpu_clk_s2 & ~cpu_clk_prev;

	// The instruction in the MEM stage is a load or store to SDRAM and has not been served yet. 
	// That is exactly when the CPU clock must be held.
	// "served" is cleared when a new instruction enters MEM and set when the  controller finishes, 
	// so each access happens exactly once even though the same address stays on the bus for the whole CPU cycle.
	logic sdram_access, sdram_served, cpu_req_pending;
	assign sdram_access = is_sdram_region && (memory_read || memory_write);
	assign sdram_stall  = sdram_access && !sdram_served;

	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset) begin
			sdram_served    <= 1'b0;
			cpu_req_pending <= 1'b0;
			cpu_read_req    <= 1'b0;
			cpu_write_req   <= 1'b0;
		end else begin
			cpu_read_req  <= 1'b0;
			cpu_write_req <= 1'b0;
			if (cpu_clock_edge) begin
				sdram_served <= 1'b0;
			end else if (cpu_req_pending) begin
				if (sdram_done) begin
					cpu_req_pending <= 1'b0;
					sdram_served    <= 1'b1;
				end
			end else if (sdram_access && !sdram_served && test_finished) begin
				cpu_req_pending <= 1'b1;
				cpu_read_req    <= memory_read;
				cpu_write_req   <= memory_write;
			end
		end
	end

	// A small LED register for programs: LEDR[9:3] show its low 7 bits.
	logic [6:0] led_reg;
	always_ff @(posedge CLOCK_50 or posedge reset) begin
		if (reset)
			led_reg <= 7'd0;
		else if (memory_write && is_led_region)
			led_reg <= Writedata[6:0];
	end
	
	// LEDR[0] = test finished and passed
	// LEDR[1] = test finished and failed
	// LEDR[2] = in the retention wait between writing and reading back
	// LEDR[9:3] = LED register (the CPU's SDRAM test writes 1 / 3 / 5)
	assign LEDR[0] = test_finished && test_passed;
	assign LEDR[1] = test_finished && !test_passed;
	assign LEDR[2] = test_retention_wait;
	assign LEDR[9:3] = led_reg;



endmodule