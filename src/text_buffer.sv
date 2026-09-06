module text_buffer (
	// write_en/write_addr/write_data are generated in the CPU's own slow
	// clock domain, but actually latched into memory on read_clock below
	input  logic        reset,
	input  logic        write_en,
	input  logic [12:0] write_addr,  // 0..4799 (80*60-1)
	input  logic [31:0] write_data,  // only [7:0] is meaningful (ASCII code)
	input  logic        read_clock,  // VGA's pixel clock, also drives the write port and the reset sweep
	input  logic [12:0] read_addr,
	output logic [7:0]  read_data
);

	logic [7:0] mem [0:4799]; // 80 columns x 60 rows, native 640x480 resolution

	// On reset, sweep through every address and write a space character (32)
	logic        clearing;
	logic [12:0] clear_addr;

	always_ff @(posedge read_clock or posedge reset) begin
		if (reset) begin
			clearing   <= 1'b1;
			clear_addr <= 13'd0;
		end else if (clearing) begin
			if (clear_addr == 13'd4799)
				clearing <= 1'b0;
			else
				clear_addr <= clear_addr + 13'd1;
		end
	end

	always_ff @(posedge read_clock) begin
		if (clearing)
			mem[clear_addr] <= 8'd32; // space
		else if (write_en)
			mem[write_addr] <= write_data[7:0];
	end

	always_ff @(posedge read_clock) begin
		read_data <= mem[read_addr];
	end

endmodule