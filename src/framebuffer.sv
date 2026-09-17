module framebuffer (
	// write_en/write_addr/write_data are generated in the CPU's own slow
	// clock domain, but actually latched into memory on read_clock below
	input  logic        reset,
	input  logic        write_en,
	input  logic [16:0] write_addr,  // word address, 0..76799 (320*240-1)
	input  logic [31:0] write_data,  // only [7:0] is meaningful (color index)
	// VGA scanout read port, synchronous (registered)
	input  logic        read_clock,  // VGA's pixel clock, also drives the write port and the reset sweep
	input  logic [16:0] read_addr,
	output logic [7:0]  read_data
);

	logic [7:0] mem [0:76799]; // 320*240 pixels, one byte each (in a 32-bit word slot)

	logic write_en_sync1, write_en_sync2, write_en_prev;
	always_ff @(posedge read_clock or posedge reset) begin //synchronization
		if (reset) begin
			write_en_sync1 <= 1'b0;
			write_en_sync2 <= 1'b0;
			write_en_prev  <= 1'b0;
		end else begin
			write_en_sync1 <= write_en;
			write_en_sync2 <= write_en_sync1;
			write_en_prev  <= write_en_sync2;
		end
	end
	logic write_pulse;
	assign write_pulse = ~write_en_prev & write_en_sync2; // rising edge
	
	// On reset, sweep through every address and write zero
	// runs independently of the CPU's own manual step clock
	logic        clearing;
	logic [16:0] clear_addr;

	always_ff @(posedge read_clock or posedge reset) begin
		if (reset) begin
			clearing   <= 1'b1;
			clear_addr <= 17'd0;
		end else if (clearing) begin
			if (clear_addr == 17'd76799)
				clearing <= 1'b0;
			else
				clear_addr <= clear_addr + 17'd1;
		end
	end

	always_ff @(posedge read_clock) begin
		if (clearing)
			mem[clear_addr] <= 8'h00;
		else if (write_pulse)
			mem[write_addr] <= write_data[7:0];
	end

	always_ff @(posedge read_clock) begin
		read_data <= mem[read_addr];
	end

endmodule