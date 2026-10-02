// ISSI IS42S16320F-7TL
// https://www.issi.com/WW/pdf/42-45R-S_86400F-16320F.pdf

module sdram_controller (
	input  logic clock,	// 50MHz
	input  logic reset,

	input  logic [23:0] word_addr,
	input  logic [31:0] write_data,
	input  logic read_req,
	input  logic write_req,
	output logic [31:0] read_data,
	output logic busy,
	output logic done,

	output logic [12:0] DRAM_ADDR,
	output logic [1:0] DRAM_BA,
	output logic DRAM_CAS_N,
	output logic DRAM_CKE,
	output logic DRAM_CLK,
	output logic DRAM_CS_N,
	inout  wire [15:0] DRAM_DQ,
	output logic DRAM_LDQM,
	output logic DRAM_RAS_N,
	output logic DRAM_UDQM,
	output logic DRAM_WE_N
);

	assign DRAM_CLK = clock;
	assign DRAM_CKE = 1'b1; // stays high

	// command truth table (page 8)
	localparam logic [3:0] CMD_NOP  = 4'b0111;
	localparam logic [3:0] CMD_READ = 4'b0101; // A10 = L: no auto precharge
	localparam logic [3:0] CMD_WRIT = 4'b0100; // A10 = L: no auto precharge
	localparam logic [3:0] CMD_ACT  = 4'b0011; // bank activate
	localparam logic [3:0] CMD_PALL = 4'b0010; // precharge all banks (A10 = H)
	localparam logic [3:0] CMD_REF  = 4'b0001; // CBR auto-refresh
	localparam logic [3:0] CMD_MRS  = 4'b0000; // mode register set

	// mode register definition (page 24). BA1, BA0, A12, A11, A10 = 0.
	localparam logic [2:0] M_BURST_LENGTH     = 3'b000; // M2:M0 burst length 1
	localparam logic       M_BURST_TYPE       = 1'b0; // M3 sequential
	localparam logic [2:0] M_LATENCY_MODE     = 3'b010; // M6:M4 CAS latency 2
	localparam logic [1:0] M_OPERATING_MODE   = 2'b00; // M8:M7 standard operation
	localparam logic       M_WRITE_BURST_MODE = 1'b0; // M9 programmed burst length
	localparam logic [12:0] MODE_REGISTER =
		{3'b000, M_WRITE_BURST_MODE, M_OPERATING_MODE, M_LATENCY_MODE, M_BURST_TYPE, M_BURST_LENGTH};

	// Timing. Datasheet minimums (ns, -7 grade, page 17) are converted to clock cycles 
	//the way page 27 describes (divide by the clock period and round up), then 
	// margin extra cycle(s) are added
	localparam int tCK_ns      = 20; // 50MHz. Datasheet min tCK2 = 7.5ns (CL = 2, -7).
	localparam int MARGIN      = 1;

	localparam int tRC_ns      = 60; // ACT to ACT / REF to REF
	localparam int tRAS_ns     = 37; // ACT to PRE (min)
	localparam int tRP_ns      = 15; // PRE to ACT
	localparam int tRCD_ns     = 15; // ACT to READ / WRIT
	localparam int tDPL_ns     = 14; // last write data to PRE
	localparam int tPOWERUP_ns = 100_000; // "A 100us delay is required" (page 20)

	localparam int tRC  = (tRC_ns  + tCK_ns - 1) / tCK_ns + MARGIN;
	localparam int tRAS = (tRAS_ns + tCK_ns - 1) / tCK_ns + MARGIN;
	localparam int tRP  = (tRP_ns  + tCK_ns - 1) / tCK_ns + MARGIN;
	localparam int tRCD = (tRCD_ns + tCK_ns - 1) / tCK_ns + MARGIN;
	localparam int tDPL = (tDPL_ns + tCK_ns - 1) / tCK_ns + MARGIN;
	localparam int tMRD = 2; // page 18: 2 cycles
	localparam int tCAC = 2; // CAS latency in cycles, matches M_LATENCY_MODE
	localparam int tPOWERUP = (tPOWERUP_ns + tCK_ns - 1) / tCK_ns;

	localparam int INIT_REFRESH_COUNT = 8;   // page 20: "at least two"

	// tREF: 8192 refresh cycles every 64ms (page 17)
	localparam int tREF_ms       = 64;
	localparam int REFRESH_ROWS  = 8192;
	localparam int REFRESH_SLACK = 20;
	localparam int tREFI = (tREF_ms * 1_000_000 / REFRESH_ROWS) / tCK_ns - REFRESH_SLACK;

	// States
	typedef enum logic [3:0] {
		S_POWER_ON, // 100us of NOP, DQM high, CKE high
		S_INIT_PRECHARGING, // after PALL, wait tRP
		S_INIT_REFRESHING, // after REF, wait tRC
		S_INIT_MODE_REGISTER_ACCESSING, // after MRS, wait tMRD
		S_IDLE,
		S_REFRESHING, // after REF, wait tRC
		S_ROW_ACTIVATING, // after ACT, wait tRCD
		S_READING_LOW, // READ of the low half issued, wait tCAC
		S_READING_HIGH, // READ of the high half issued, wait tCAC
		S_WRITING_LOW, // WRIT of the low half issued
		S_WRITE_RECOVERING, // WRIT of the high half issued, wait tDPL
		S_PRECHARGING // after PALL, wait tRP
	} state_t;

	state_t state;
	logic [15:0] wait_counter;
	logic [3:0] refresh_count;
	logic [15:0] refresh_timer;
	logic initializing;

	// latched request (from the pulse) and the request being executed
	logic req_pending, req_is_write;
	logic [23:0] req_addr;
	logic [31:0] req_data;
	logic op_is_write;
	logic [23:0] op_addr;
	logic [31:0] op_data;

	logic [15:0] dq_out;
	logic dq_out_en;
	assign DRAM_DQ = dq_out_en ? dq_out : 16'bz;

	logic [3:0] command;
	assign {DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N} = command;

	always_ff @(posedge clock or posedge reset) begin
		if (reset) begin
			state <= S_POWER_ON;
			wait_counter <= 16'd0;
			refresh_count <= 4'd0;
			refresh_timer <= 16'd0;
			initializing <= 1'b1;
			command <= CMD_NOP;
			DRAM_ADDR <= 13'd0;
			DRAM_BA <= 2'd0;
			DRAM_LDQM <= 1'b1; // power-up: "DQM High and CKE High" (page 20)
			DRAM_UDQM <= 1'b1;
			dq_out <= 16'd0;
			dq_out_en <= 1'b0;
			busy <= 1'b1;
			done <= 1'b0;
			read_data <= 32'd0;
			req_pending <= 1'b0;
			req_is_write <= 1'b0;
			req_addr <= 24'd0;
			req_data <= 32'd0;
			op_is_write <= 1'b0;
			op_addr <= 24'd0;
			op_data <= 32'd0;
		end else begin
			command <= CMD_NOP;
			dq_out_en <= 1'b0;
			done <= 1'b0;

			// Latch a request pulse whenever there is room, in any state.
			if ((read_req || write_req) && !req_pending) begin
				req_pending <= 1'b1;
				req_is_write <= write_req;
				req_addr <= word_addr;
				req_data <= write_data;
			end

			if (!initializing && refresh_timer < tREFI - 1)
				refresh_timer <= refresh_timer + 16'd1;

			case (state)
				// power-up sequence (page 20) ----------------------------------------
				S_POWER_ON: begin
					if (wait_counter >= tPOWERUP - 1) begin
						command <= CMD_PALL;
						DRAM_ADDR[10] <= 1'b1; // A10 = H: all banks
						wait_counter <= 16'd0;
						state <= S_INIT_PRECHARGING;
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				S_INIT_PRECHARGING: begin
					if (wait_counter >= tRP - 1) begin
						command <= CMD_REF;
						refresh_count <= 4'd0;
						wait_counter <= 16'd0;
						state <= S_INIT_REFRESHING;
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				S_INIT_REFRESHING: begin
					if (wait_counter >= tRC - 1) begin
						wait_counter <= 16'd0;
						if (refresh_count == INIT_REFRESH_COUNT - 1) begin
							command <= CMD_MRS;
							DRAM_BA <= 2'b00;
							DRAM_ADDR <= MODE_REGISTER;
							state <= S_INIT_MODE_REGISTER_ACCESSING;
						end else begin
							command <= CMD_REF;
							refresh_count <= refresh_count + 4'd1;
						end
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				S_INIT_MODE_REGISTER_ACCESSING: begin
					if (wait_counter >= tMRD - 1) begin
						DRAM_LDQM <= 1'b0; // enable the I/O buffers for normal operation
						DRAM_UDQM <= 1'b0;
						initializing <= 1'b0;
						busy <= 1'b0;
						state <= S_IDLE;
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				// idle ---------------------------------------------------------
				S_IDLE: begin
					busy <= 1'b0;
					if (refresh_timer >= tREFI - 1) begin
						busy <= 1'b1;
						refresh_timer <= 16'd0;
						command <= CMD_REF;
						wait_counter <= 16'd0;
						state <= S_REFRESHING;
					end else if (req_pending) begin
						busy <= 1'b1;
						req_pending <= 1'b0;
						op_is_write <= req_is_write;
						op_addr <= req_addr;
						op_data <= req_data;
						DRAM_BA <= req_addr[23:22];
						DRAM_ADDR <= req_addr[21:9]; // row
						command <= CMD_ACT;
						wait_counter <= 16'd0;
						state <= S_ROW_ACTIVATING;
					end
				end

				S_REFRESHING: begin
					if (wait_counter >= tRC - 1) begin
						busy <= 1'b0;
						state <= S_IDLE;
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				// read / write access ----------------------------------------
				S_ROW_ACTIVATING: begin
					if (wait_counter >= tRCD - 1) begin
						DRAM_ADDR <= {3'b000, op_addr[8:0], 1'b0};   // column 2w, A10 = L
						wait_counter <= 16'd0;
						if (op_is_write) begin
							command <= CMD_WRIT;
							dq_out <= op_data[15:0];   // write data goes with the command
							dq_out_en <= 1'b1;
							state <= S_WRITING_LOW;
						end else begin
							command <= CMD_READ;
							state <= S_READING_LOW;
						end
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				// data is valid tCAC cycles after the READ is registered
				S_READING_LOW: begin
					if (wait_counter >= tCAC) begin
						read_data[15:0] <= DRAM_DQ;
						DRAM_ADDR <= {3'b000, op_addr[8:0], 1'b1}; // column 2w + 1
						command <= CMD_READ;
						wait_counter <= 16'd0;
						state <= S_READING_HIGH;
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				S_READING_HIGH: begin
					if (wait_counter >= tCAC) begin
						read_data[31:16] <= DRAM_DQ;
						command <= CMD_PALL;
						DRAM_ADDR[10] <= 1'b1;
						wait_counter <= 16'd0;
						state <= S_PRECHARGING;
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				// tCCD = 1: a second WRIT may follow on the very next clock
				S_WRITING_LOW: begin
					DRAM_ADDR <= {3'b000, op_addr[8:0], 1'b1};   // column 2w + 1
					command <= CMD_WRIT;
					dq_out <= op_data[31:16];
					dq_out_en <= 1'b1;
					wait_counter <= 16'd0;
					state <= S_WRITE_RECOVERING;
				end

				// PRE must come tDPL after the last write data is registered
				S_WRITE_RECOVERING: begin
					if (wait_counter >= tDPL - 1) begin
						command <= CMD_PALL;
						DRAM_ADDR[10] <= 1'b1;
						wait_counter <= 16'd0;
						state <= S_PRECHARGING;
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				S_PRECHARGING: begin
					if (wait_counter >= tRP - 1) begin
						busy <= 1'b0;
						done <= 1'b1;
						state <= S_IDLE;
					end else
						wait_counter <= wait_counter + 16'd1;
				end

				default: state <= S_IDLE;
			endcase
		end
	end

endmodule