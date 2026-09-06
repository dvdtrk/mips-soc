module microcomputer (
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
	output logic [3:0] VGA_B
);

	//---- Signal declarations ----
	logic        reset;
	logic        clock;
	logic [31:0] instruction;
	logic [31:0] pc;

	logic [31:0] address;
	logic [31:0] Writedata;
	logic        memory_read, memory_write;
	logic [31:0] Readdata;

    //---------------------------------------------------------------------
	// VGA / framebuffer: memory-mapped I/O address decode
	//---------------------------------------------------------------------
	// Addresses 0x10000 through 0x10000 + 19200*4 map to the framebuffer.

	localparam logic [31:0] FB_BASE  = 32'h00010000;
	localparam logic [31:0] FB_BYTES = 32'd76800 * 4;
	localparam logic [31:0] TXT_BASE  = 32'h00060000;
	localparam logic [31:0] TXT_BYTES = 32'd4800 * 4;

	logic        is_fb_region, is_txt_region;
	logic        memory_write_dm, memory_write_fb, memory_write_txt;
	logic [16:0] fb_write_addr;
	logic [12:0] txt_write_addr;
	assign is_fb_region     = (address >= FB_BASE)  && (address < FB_BASE  + FB_BYTES);
	assign is_txt_region    = (address >= TXT_BASE) && (address < TXT_BASE + TXT_BYTES);
	assign memory_write_dm  = memory_write && !is_fb_region && !is_txt_region;
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

	assign vga_reset = ~KEY[1]; // same physical reset as the CPU

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
	assign reset = ~KEY[1]; // KEY[1] is reset
	assign clock = ~KEY[0]; // KEY[0] used as the clock (50MHz is too fast)
							// may need debouncing circuit

	assign counter_set = flipflops[0] ^ flipflops[1];

	always_ff @(posedge CLOCK_50) begin
		flipflops[0] <= ~KEY[0];
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
		.Readdata_mips    (Readdata)
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
	always_ff @(posedge clk25) begin
		char_row_in_glyph_d <= row_in_glyph;
		col_in_glyph_d      <= col_in_glyph;
	end

	logic [7:0] font_row_bits;
	logic       text_pixel_on;
	assign text_pixel_on = font_row_bits[3'd7 - col_in_glyph_d];

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
		end else if (text_pixel_on) begin
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

		end else if (SW == 10'b0000000001) begin // PC
			plusone  = pc[3:0];
			plusone1 = pc[7:4];
			plusone2 = pc[11:8];
			plusone3 = pc[15:12];
			plusone4 = pc[19:16];
			plusone5 = pc[23:20];

		end else if (SW == 10'b0000000010) begin // instruction
			plusone  = instruction[3:0];
			plusone1 = instruction[7:4];
			plusone2 = instruction[11:8];
			plusone3 = instruction[15:12];
			plusone4 = instruction[19:16];
			plusone5 = pc[3:0];

		end else if (SW == 10'b0000000100) begin // Writedata (=rdata2)
			plusone  = Writedata[3:0];
			plusone1 = Writedata[7:4];
			plusone2 = Writedata[11:8];
			plusone3 = Writedata[15:12];
			plusone4 = Writedata[19:16];
			plusone5 = pc[3:0];

		end else if (SW == 10'b0000001000) begin // address (=ALUresult)
			plusone  = address[3:0];
			plusone1 = address[7:4];
			plusone2 = address[11:8];
			plusone3 = address[15:12];
			plusone4 = address[19:16];
			plusone5 = pc[3:0];

		end else if (SW == 10'b0000010000) begin // Readdata
			plusone  = Readdata[3:0];
			plusone1 = Readdata[7:4];
			plusone2 = Readdata[11:8];
			plusone3 = Readdata[15:12];
			plusone4 = Readdata[19:16];
			plusone5 = pc[3:0];

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

endmodule