module framebuffer (
	input  logic        clock,       // CPU-side write clock
	// CPU write port
	input  logic        write_en,
	input  logic [14:0] write_addr,  // word address, 0..19199 (160*120-1)
	input  logic [31:0] write_data,  // only [7:0] is meaningful (color index)
	// VGA scanout read port, now synchronous (registered), since real
	// block RAM can only latch data out on a clock edge. The smaller
	// memories elsewhere in this project are combinational-read only
	// because they're small enough for Quartus to build out of MLAB
	// instead, this one is too big for that, so it needs a real clocked
	// read to map onto actual block RAM.
	input  logic        read_clock,  // VGA's pixel clock
	input  logic [14:0] read_addr,
	output logic [7:0]  read_data
);

	logic [7:0] mem [0:19199]; // 160*120 pixels, one byte each (in a 32-bit word slot)

	// No explicit initialization here. Both a full loop and a sparse
	// handful of explicit assignments broke Quartus's ability to infer
	// this as block RAM once it's this large - it turns out any initial
	// values at all for a memory this size need to go through $readmemh
	// with an external file to be reliably recognized, not inline initial
	// statements. Since addi is coming next anyway, and that's the
	// actually correct way to get real pixels on screen, it's not worth
	// chasing further workarounds just for a temporary test pattern.
	// On real hardware this means the screen shows whatever the block RAM
	// happens to power up as until the CPU writes over it for real.

	always_ff @(posedge clock) begin
		if (write_en)
			mem[write_addr] <= write_data[7:0];
	end

	always_ff @(posedge read_clock) begin
		read_data <= mem[read_addr];
	end

endmodule