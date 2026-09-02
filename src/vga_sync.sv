module vga_sync (
	input  logic       clk50,      // board's 50MHz clock
	input  logic       reset,
	output logic       clk25 = 1'b0,      // pixel clock, divided down from clk50
	output logic       hsync,      // active low
	output logic       vsync,      // active low
	output logic       video_on,   // high during the visible 640x480 region
	output logic [9:0] h_count = 10'd0, // current pixel column, 0-799 (only 0-639 visible)
	output logic [9:0] v_count = 10'd0  // current pixel row,    0-524 (only 0-479 visible)
);

	// Standard 640x480@60Hz VESA timing. The real spec calls for a
	// 25.175MHz pixel clock; dividing the board's 50MHz clock by 2 gives
	// 25MHz instead, which is close enough that essentially all monitors
	// display it correctly, this is the standard, well known approach for
	// FPGA VGA projects that don't have a dedicated pixel clock PLL.
	localparam int H_VISIBLE     = 640;
	localparam int H_FRONT_PORCH = 16;
	localparam int H_SYNC_PULSE  = 96;
	localparam int H_BACK_PORCH  = 48;
	localparam int H_TOTAL       = H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

	localparam int V_VISIBLE     = 480;
	localparam int V_FRONT_PORCH = 10;
	localparam int V_SYNC_PULSE  = 2;
	localparam int V_BACK_PORCH  = 33;
	localparam int V_TOTAL       = V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

	// pixel clock: divide 50MHz by 2
	always_ff @(posedge clk50 or posedge reset) begin
		if (reset)
			clk25 <= 1'b0;
		else
			clk25 <= ~clk25;
	end

	// horizontal and vertical counters, advancing on the pixel clock
	always_ff @(posedge clk25 or posedge reset) begin
		if (reset) begin
			h_count <= 10'd0;
			v_count <= 10'd0;
		end else begin
			if (h_count == H_TOTAL - 1) begin
				h_count <= 10'd0;
				if (v_count == V_TOTAL - 1)
					v_count <= 10'd0;
				else
					v_count <= v_count + 10'd1;
			end else begin
				h_count <= h_count + 10'd1;
			end
		end
	end

	// sync pulses are active low, asserted during their pulse window
	assign hsync = ~((h_count >= H_VISIBLE + H_FRONT_PORCH) &&
	                  (h_count <  H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE));
	assign vsync = ~((v_count >= V_VISIBLE + V_FRONT_PORCH) &&
	                  (v_count <  V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE));

	assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

endmodule
