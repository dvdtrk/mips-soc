// SD test: just talk to the card once.
//   1. wait 2 ms after reset
//   2. 80 clocks with CS high (the card needs >= 74 to wake up in SPI mode)
//   3. send CMD0 (GO_IDLE_STATE): 0x40 0x00 0x00 0x00 0x00 0x95
//   4. read bytes until the card answers (the answer, "R1", has its top bit = 0)
// A healthy card answers R1 = 0x01 ("idle"). Nothing answering reads as 0xFF.
// Runs once after reset. Slow SCK (200 kHz), as the SD spec requires at start-up.
module sd_cmd0_test #(
	parameter int POWERUP_CYCLES   = 100_000, // 2 ms at 50 MHz
	parameter int SLOW_HALF_PERIOD = 125 // 50 MHz / 250 = 200 kHz
) (
	input  logic       clock,
	input  logic       reset,

	output logic       finished,
	output logic       got_response, // the card answered within 10 bytes
	output logic [7:0] r1, // the answer (0xFF = none)

	output logic       sd_cs_n,
	output logic       sd_sck,
	output logic       sd_mosi,
	input  logic       sd_miso
);

	logic       spi_start, spi_busy, spi_done;
	logic [7:0] spi_tx, spi_rx;

	sd_spi_master SPI (
		.clock       (clock),
		.reset       (reset),
		.half_period (SLOW_HALF_PERIOD[7:0]),
		.start       (spi_start),
		.tx_byte     (spi_tx),
		.busy        (spi_busy),
		.done        (spi_done),
		.rx_byte     (spi_rx),
		.sck         (sd_sck),
		.mosi        (sd_mosi),
		.miso        (sd_miso)
	);

	typedef enum logic [2:0] { S_WAIT, S_DUMMY, S_CMD, S_R1, S_END, S_DONE } state_t;
	state_t state;

	logic [31:0] wait_cnt;
	logic [3:0]  cnt;
	logic        issued;

	// CMD0 on the wire: start bits 01 + command 0, 32-bit argument 0, CRC 0x95
	logic [7:0] cmd0_byte;
	always_comb begin
		case (cnt[2:0])
			3'd0:    cmd0_byte = 8'h40;
			3'd5:    cmd0_byte = 8'h95;
			default: cmd0_byte = 8'h00;
		endcase
	end

	always_ff @(posedge clock or posedge reset) begin
		if (reset) begin
			state        <= S_WAIT;
			wait_cnt     <= 32'd0;
			cnt          <= 4'd0;
			issued       <= 1'b0;
			spi_start    <= 1'b0;
			spi_tx       <= 8'hFF;
			sd_cs_n      <= 1'b1;
			finished     <= 1'b0;
			got_response <= 1'b0;
			r1           <= 8'hFF;
		end else begin
			spi_start <= 1'b0;
			case (state)
				S_WAIT: begin
					if (wait_cnt == POWERUP_CYCLES - 1) state <= S_DUMMY;
					else wait_cnt <= wait_cnt + 32'd1;
				end

				S_DUMMY: begin // 10 bytes of 0xFF with CS high = 80 clocks
					if (!issued) begin
						spi_tx <= 8'hFF; 
						spi_start <= 1'b1; 
						issued <= 1'b1;
					end else if (spi_done) begin
						issued <= 1'b0;
						if (cnt == 4'd9) begin 
							cnt <= 4'd0; 
							sd_cs_n <= 1'b0; 
							state <= S_CMD; 
						end else 
							cnt <= cnt + 4'd1;
					end
				end

				S_CMD: begin // the 6 command bytes, CS low
					if (!issued) begin
						spi_tx <= cmd0_byte; 
						spi_start <= 1'b1; 
						issued <= 1'b1;
					end else if (spi_done) begin
						issued <= 1'b0;
						if (cnt == 4'd5) begin 
							cnt <= 4'd0; 
							state <= S_R1; 
						end else 
							cnt <= cnt + 4'd1;
					end
				end

				S_R1: begin // clock out 0xFF until the card answers
					if (!issued) begin
						spi_tx <= 8'hFF; 
						spi_start <= 1'b1; 
						issued <= 1'b1;
					end else if (spi_done) begin
						issued <= 1'b0;
						if (!spi_rx[7]) begin
							r1 <= spi_rx;
							got_response <= 1'b1; 
							state <= S_END;
						end else if (cnt == 4'd9) begin
							r1 <= 8'hFF; 
							got_response <= 1'b0; 
							state <= S_END;
						end else 
							cnt <= cnt + 4'd1;
					end
				end

				S_END: begin // CS high and 8 more clocks, then stop
					sd_cs_n <= 1'b1;
					if (!issued) begin
						spi_tx <= 8'hFF; 
						spi_start <= 1'b1; 
						issued <= 1'b1;
					end else if (spi_done) begin
						issued <= 1'b0; 
						finished <= 1'b1; 
						state <= S_DONE;
					end
				end

				S_DONE: begin end
				default: state <= S_DONE;
			endcase
		end
	end

endmodule
