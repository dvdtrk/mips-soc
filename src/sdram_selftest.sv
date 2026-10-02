// Standalone SDRAM bring-up test, independent of the CPU.

module sdram_selftest #(
	parameter int RETENTION_CYCLES = 50_000_000
) (
	input  logic clock,
	input  logic reset,

	// request side of sdram_controller
	output logic [23:0] word_addr,
	output logic [31:0] write_data,
	output logic read_req,
	output logic write_req,
	input  logic [31:0] read_data,
	input  logic busy,
	input  logic done,

	// results
	output logic passed,
	output logic finished,
	output logic retention_wait, // high while waiting between the phases
	output logic [23:0] fail_addr,
	output logic [31:0] fail_expected,
	output logic [31:0] fail_actual
);

	localparam int NUM_TESTS = 8;

	logic [2:0] test_index;
	logic [23:0] test_addr;
	logic [31:0] test_value;

	always_comb begin
		case (test_index)
			3'd0: begin test_addr = 24'h000100; test_value = 32'hDEADBEEF; end // bank 0
			3'd1: begin test_addr = 24'h400100; test_value = 32'h12345678; end // bank 1
			3'd2: begin test_addr = 24'h001000; test_value = 32'hCAFEF00D; end // another row
			3'd3: begin test_addr = 24'h000200; test_value = 32'h11111111; end // neighboring words:
			3'd4: begin test_addr = 24'h000201; test_value = 32'h22222222; end // must not overlap
			3'd5: begin test_addr = 24'h800200; test_value = 32'hA5A5A5A5; end // bank 2
			3'd6: begin test_addr = 24'hC00200; test_value = 32'h5A5A5A5A; end // bank 3
			3'd7: begin test_addr = 24'hFFFFFF; test_value = 32'h0F0F0F0F; end // last word of the chip
			default: begin test_addr = 24'h000000; test_value = 32'h00000000; end
		endcase
	end

	typedef enum logic [2:0] {
		T_START, T_WRITE, T_WRITE_WAIT, T_RETENTION, T_READ, T_READ_WAIT, T_DONE
	} test_state_t;

	test_state_t test_state;
	logic reading_phase;
	logic [31:0] retention_counter;

	assign retention_wait = (test_state == T_RETENTION);

	always_ff @(posedge clock or posedge reset) begin
		if (reset) begin
			test_state <= T_START;
			test_index <= 3'd0;
			reading_phase <= 1'b0;
			retention_counter <= 32'd0;
			word_addr <= 24'd0;
			write_data <= 32'd0;
			read_req <= 1'b0;
			write_req <= 1'b0;
			passed <= 1'b0;
			finished <= 1'b0;
			fail_addr <= 24'd0;
			fail_expected <= 32'd0;
			fail_actual <= 32'd0;
		end else begin
			read_req <= 1'b0;
			write_req <= 1'b0;

			case (test_state)
				T_START: begin
					if (!busy) begin
						word_addr <= test_addr;
						write_data <= test_value;
						test_state <= reading_phase ? T_READ : T_WRITE;
					end
				end

				T_WRITE: begin
					write_req <= 1'b1;
					test_state <= T_WRITE_WAIT;
				end

				T_WRITE_WAIT: begin
					if (done) begin
						if (test_index == NUM_TESTS - 1) begin
							test_index <= 3'd0;
							retention_counter <= 32'd0;
							test_state <= T_RETENTION;
						end else begin
							test_index <= test_index + 3'd1;
							test_state <= T_START;
						end
					end
				end

				T_RETENTION: begin
					if (retention_counter >= RETENTION_CYCLES - 1) begin
						reading_phase <= 1'b1;
						test_state <= T_START;
					end else
						retention_counter <= retention_counter + 32'd1;
				end

				T_READ: begin
					read_req <= 1'b1;
					test_state <= T_READ_WAIT;
				end

				T_READ_WAIT: begin
					if (done) begin
						if (read_data !== test_value) begin
							fail_addr <= test_addr;
							fail_expected <= test_value;
							fail_actual <= read_data;
							passed <= 1'b0;
							finished <= 1'b1;
							test_state <= T_DONE;
						end else if (test_index == NUM_TESTS - 1) begin
							passed <= 1'b1;
							finished <= 1'b1;
							test_state <= T_DONE;
						end else begin
							test_index <= test_index + 3'd1;
							test_state <= T_START;
						end
					end
				end

				T_DONE: begin
					// result stays latched in passed / finished / fail_*
				end

				default: test_state <= T_START;
			endcase
		end
	end

endmodule
