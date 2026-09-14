module ps2_receiver (
	input  logic       clock,      // FPGA's own clock
	input  logic       reset,
	input  logic       ps2_clk,    // raw PS/2 clock line
	input  logic       ps2_data,   // raw PS/2 data line
	output logic [7:0] scancode,   // last fully received byte
	output logic       data_ready  // pulses high for one cycle when a new byte arrives
);

	// Synchronize both asynchronous PS/2 signals
	logic clk_sync1, clk_sync2;
	logic data_sync1, data_sync2;

	always_ff @(posedge clock or posedge reset) begin
		if (reset) begin
			clk_sync1  <= 1'b1;
			clk_sync2  <= 1'b1;
			data_sync1 <= 1'b1;
			data_sync2 <= 1'b1;
		end else begin
			clk_sync1  <= ps2_clk;
			clk_sync2  <= clk_sync1;
			data_sync1 <= ps2_data;
			data_sync2 <= data_sync1;
		end
	end

	// falling edge of ps2_clk, so detect that edge here
	logic clk_prev;
	logic falling_edge;

	always_ff @(posedge clock or posedge reset) begin
		if (reset)
			clk_prev <= 1'b1;
		else
			clk_prev <= clk_clean;
	end

	assign falling_edge = clk_prev & ~clk_clean;

	localparam int DEBOUNCE_THRESHOLD = 750; // ~15us at 50MHz

	logic       clk_clean;
	logic [9:0] debounce_count; // needs more width the higher the threshold is

	always_ff @(posedge clock or posedge reset) begin
		if (reset) begin
			clk_clean      <= 1'b1;
			debounce_count <= 10'd0;
		end else if (clk_sync2 == clk_clean) begin
			debounce_count <= 10'd0; // already stable, nothing to filter
		end else if (debounce_count >= DEBOUNCE_THRESHOLD - 1) begin
			clk_clean      <= clk_sync2; // held long enough, accept as a real transition
			debounce_count <= 10'd0;
		end else begin
			debounce_count <= debounce_count + 10'd1;
		end
	end

	// collect an 11-bit frame: 
    // start (0)
    // 8 data bits LSB first 
    // parity, stop (1).
	logic [3:0] bit_index; // 0..10
	logic [7:0] data_reg;

	always_ff @(posedge clock or posedge reset) begin
		if (reset) begin
			bit_index  <= 4'd0;
			data_ready <= 1'b0;
			scancode   <= 8'h00;
			data_reg   <= 8'h00;
		end else begin
			data_ready <= 1'b0; // by default only pulses on the cycle a frame completes

			if (falling_edge) begin
				case (bit_index)
					4'd0: begin // start bit, not validated yet
						bit_index <= bit_index + 4'd1;
					end
					4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8: begin // 8 data bits, LSB first
						data_reg[bit_index - 4'd1] <= data_sync2;
						bit_index <= bit_index + 4'd1;
					end
					4'd9: begin // parity bit, not validated yet
						bit_index <= bit_index + 4'd1;
					end
					4'd10: begin // stop bit
						scancode   <= data_reg;
						data_ready <= 1'b1;
						bit_index  <= 4'd0;
					end
					default: bit_index <= 4'd0;
				endcase
			end
		end
	end

endmodule