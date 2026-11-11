module scancode_to_ascii (
	input  logic [7:0] scancode,
	input  logic       shift,
	output logic [7:0] ascii
);

	logic [7:0] base; //unshifted character

	always_comb begin
		case (scancode)
			8'h15: base = 8'h71; // 'q'
			8'h16: base = 8'h31; // '1'
			8'h1a: base = 8'h7a; // 'z'
			8'h1b: base = 8'h73; // 's'
			8'h1c: base = 8'h61; // 'a'
			8'h1d: base = 8'h77; // 'w'
			8'h1e: base = 8'h32; // '2'
			8'h21: base = 8'h63; // 'c'
			8'h22: base = 8'h78; // 'x'
			8'h23: base = 8'h64; // 'd'
			8'h24: base = 8'h65; // 'e'
			8'h25: base = 8'h34; // '4'
			8'h26: base = 8'h33; // '3'
			8'h29: base = 8'h20; // 'space'
			8'h2a: base = 8'h76; // 'v'
			8'h2b: base = 8'h66; // 'f'
			8'h2c: base = 8'h74; // 't'
			8'h2d: base = 8'h72; // 'r'
			8'h2e: base = 8'h35; // '5'
			8'h31: base = 8'h6e; // 'n'
			8'h32: base = 8'h62; // 'b'
			8'h33: base = 8'h68; // 'h'
			8'h34: base = 8'h67; // 'g'
			8'h35: base = 8'h79; // 'y'
			8'h36: base = 8'h36; // '6'
			8'h3a: base = 8'h6d; // 'm'
			8'h3b: base = 8'h6a; // 'j'
			8'h3c: base = 8'h75; // 'u'
			8'h3d: base = 8'h37; // '7'
			8'h3e: base = 8'h38; // '8'
			8'h42: base = 8'h6b; // 'k'
			8'h43: base = 8'h69; // 'i'
			8'h44: base = 8'h6f; // 'o'
			8'h45: base = 8'h30; // '0'
			8'h46: base = 8'h39; // '9'
			8'h4b: base = 8'h6c; // 'l'
			8'h4d: base = 8'h70; // 'p'
			8'h41: base = 8'h2c; // 'comma'
			8'h49: base = 8'h2e; // 'period'
			8'h4a: base = 8'h2f; // 'slash'
			8'h4c: base = 8'h3b; // 'semicolon'
			8'h52: base = 8'h27; // 'apostrophe'
			8'h4e: base = 8'h2d; // 'minus'
			8'h55: base = 8'h3d; // 'equals'
			8'h66: base = 8'h08; // 'backspace'
			default: base = 8'h00;
		endcase
	end

	logic is_lowercase_letter;
	assign is_lowercase_letter = (base >= 8'h61) && (base <= 8'h7a);
	assign ascii = (shift && is_lowercase_letter) ? (base - 8'h20) : base; // convert to uppercase if shift is held

endmodule
