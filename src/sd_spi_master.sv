// SPI master, mode 0 (CPOL=0, CPHA=0), one byte per transfer, MSB first.
//   - SCK idles low.
//   - MOSI changes on the falling edge of SCK (and is set up half a period
//     before the first rising edge).
//   - MISO is sampled on the rising edge of SCK.
// An SD card in SPI mode uses exactly this mode.

// half_period = number of CLOCK_50 cycles per half SCK period, so SCK frequency = 50 MHz / (2 * half_period).
// Keep half_period >= 4: MISO goes through a 2-flop synchronizer, and the card needs time after the falling edge 
// to put the next bit on the wire.
module sd_spi_master (
	input  logic       clock,
	input  logic       reset,
	input  logic [7:0] half_period,
	input  logic       start, // one-clock pulse; ignored while busy
	input  logic [7:0] tx_byte,
	output logic       busy,
	output logic       done, // one-clock pulse; rx_byte is valid
	output logic [7:0] rx_byte,
	output logic       sck,
	output logic       mosi,
	input  logic       miso
);

	logic miso_s1, miso_s2;
	always_ff @(posedge clock) begin
		miso_s1 <= miso;
		miso_s2 <= miso_s1;
	end

	logic [7:0] tx_shift, rx_shift, div;
	logic [2:0] bit_idx;

	always_ff @(posedge clock or posedge reset) begin
		if (reset) begin
			sck      <= 1'b0;
			mosi     <= 1'b1;
			busy     <= 1'b0;
			done     <= 1'b0;
			rx_byte  <= 8'hFF;
			tx_shift <= 8'hFF;
			rx_shift <= 8'hFF;
			div      <= 8'd0;
			bit_idx  <= 3'd0;
		end else begin
			done <= 1'b0;
			if (!busy) begin
				if (start) begin
					busy     <= 1'b1;
					tx_shift <= tx_byte;
					mosi     <= tx_byte[7];
					bit_idx  <= 3'd0;
					div      <= 8'd0;
					sck      <= 1'b0;
				end
			end else if (div == half_period - 8'd1) begin
				div <= 8'd0;
				sck <= ~sck;
				if (!sck) begin
					// rising edge: sample the card's bit
					rx_shift <= {rx_shift[6:0], miso_s2};
				end else begin
					// falling edge: next bit out, or finish after the 8th
					if (bit_idx == 3'd7) begin
						busy    <= 1'b0;
						done    <= 1'b1;
						rx_byte <= rx_shift;
					end else begin
						bit_idx  <= bit_idx + 3'd1;
						tx_shift <= {tx_shift[6:0], 1'b0};
						mosi     <= tx_shift[6];
					end
				end
			end else begin
				div <= div + 8'd1;
			end
		end
	end

endmodule
