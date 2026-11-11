// Turns the raw byte stream from ps2_receiver into key events and tracks whether a Shift key is held.
module ps2_key_decoder (
	input  logic       clock,
	input  logic       reset,
	input  logic [7:0] scancode, // from ps2_receiver
	input  logic       data_ready, // one-clock pulse: a new byte arrived

	output logic       key_valid, // one-clock pulse: a plain key was pressed
	output logic [7:0] key_code, // that key's scan code
	output logic       shift_down // a Shift key is currently held
);

	localparam logic [7:0] EXTENDED_PREFIX = 8'hE0;
	localparam logic [7:0] RELEASE_PREFIX  = 8'hF0;
	localparam logic [7:0] LEFT_SHIFT = 8'h12;
	localparam logic [7:0] RIGHT_SHIFT = 8'h59;

	logic saw_extended, saw_release;
	logic shift_left, shift_right;

	assign shift_down = shift_left | shift_right;

	always_ff @(posedge clock or posedge reset) begin
		if (reset) begin
			saw_extended <= 1'b0;
			saw_release <= 1'b0;
			shift_left <= 1'b0;
			shift_right <= 1'b0;
			key_valid <= 1'b0;
			key_code <= 8'h00;
		end else begin
			key_valid <= 1'b0; // pulses for one clock only

			if (data_ready) begin
				if (scancode == EXTENDED_PREFIX) begin
					saw_extended <= 1'b1;
				end else if (scancode == RELEASE_PREFIX) begin
					saw_release <= 1'b1;
				end else begin
					// a real key code: the prefixes just seen say what happened
					if (!saw_extended) begin
						if (scancode == LEFT_SHIFT)
							shift_left <= !saw_release;
						else if (scancode == RIGHT_SHIFT)
							shift_right <= !saw_release;
						else if (!saw_release) begin
							key_valid <= 1'b1; // normal key press
							key_code  <= scancode;
						end
					end
					saw_extended <= 1'b0;
					saw_release  <= 1'b0;
				end
			end
		end
	end

endmodule