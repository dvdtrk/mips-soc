// ONLY FOR SIMULATION

module sdram_behavioral_model (
	input  logic        DRAM_CLK,
	input  logic        DRAM_CKE,
	input  logic        DRAM_CS_N,
	input  logic        DRAM_RAS_N,
	input  logic        DRAM_CAS_N,
	input  logic        DRAM_WE_N,
	input  logic [12:0] DRAM_ADDR,
	input  logic [1:0]  DRAM_BA,
	inout  wire  [15:0] DRAM_DQ,
	input  logic        DRAM_LDQM,
	input  logic        DRAM_UDQM
);

	// AC ELECTRICAL CHARACTERISTICS, -7 grade (page 17), in ns
	localparam real tRC_ns      = 60.0;
	localparam real tRAS_MIN_ns = 37.0;
	localparam real tRAS_MAX_ns = 100_000.0;
	localparam real tRP_ns      = 15.0;
	localparam real tRCD_ns     = 15.0;
	localparam real tDPL_ns     = 14.0;
	localparam real tMRD_ns     = 14.0; // page 18 also says 2 cycles
	localparam real tCK2_MIN_ns = 7.5; // CAS latency = 2
	localparam real tCK3_MIN_ns = 7.0; // CAS latency = 3
	localparam real tPOWERUP_ns = 100_000.0; // Initialization, page 20
	localparam real tREF_ns     = 64_000_000.0;
	localparam real REFRESH_ROWS = 8192.0;

	logic [15:0] mem [0:33554431]; // {BA1,BA0, row(13), column(10)}

	logic [15:0] dq_out;
	logic        dq_out_en;
	assign DRAM_DQ = dq_out_en ? dq_out : 16'bz;

	integer violation_count = 0;
	task automatic violation(input string msg);
		begin
			violation_count = violation_count + 1;
			$display("[%0t] DATASHEET VIOLATION: %s", $time, msg);
		end
	endtask

	// per-bank state
	logic        bank_open [0:3];
	logic [12:0] bank_row  [0:3];
	real		 last_ACT  [0:3];
	real         last_PRE  [0:3];
	real         last_WRIT [0:3];
	real         last_REF, last_MRS, last_edge, clk_period, now;
	real         first_cmd_time;
	integer      init_phase; // 0 power-up, 1 after PALL, 2 mode register set
	integer      init_ref_count;
	integer      cas_latency; // decoded from the mode register (0 = not set)
	integer      i, b;
	logic        dqm_flagged;
	logic [24:0] addr25;
	logic [15:0] merged;

	// read data pipeline: data is driven so that it is valid CAS-latency clocks
	// after the READ is registered (page 26)
	logic        rd_v [0:2];
	logic [24:0] rd_a [0:2];

	initial begin
		for (i = 0; i < 4; i = i + 1) begin
			bank_open[i] = 1'b0; bank_row[i] = 13'd0;
			last_ACT[i] = -1.0e12; last_PRE[i] = -1.0e12; last_WRIT[i] = -1.0e12;
		end
		for (i = 0; i < 3; i = i + 1) begin rd_v[i] = 1'b0; rd_a[i] = 25'd0; end
		last_REF = -1.0e12; last_MRS = -1.0e12; last_edge = -1.0; clk_period = 0.0;
		first_cmd_time = -1.0; init_phase = 0; init_ref_count = 0;
		cas_latency = 0; dqm_flagged = 1'b0; dq_out_en = 1'b0; dq_out = 16'd0;
	end

	always @(posedge DRAM_CLK) begin
		now = $realtime;
		if (last_edge > 0.0) clk_period = now - last_edge;
		last_edge = now;

		//read data pipeline ---------------------------------------------------------------------------------
		rd_v[2] <= rd_v[1]; rd_a[2] <= rd_a[1];
		rd_v[1] <= rd_v[0]; rd_a[1] <= rd_a[0];
		rd_v[0] <= 1'b0;
		dq_out_en <= 1'b0;
		if (cas_latency >= 2 && rd_v[cas_latency - 2]) begin
			dq_out    <= mem[rd_a[cas_latency - 2]];
			dq_out_en <= 1'b1;
		end

		// always-on checks ------------------------------------------------------------------------------------
		if (now > 200.0) begin
			if (DRAM_CKE !== 1'b1)
				violation("CKE is not high (the controller is not supposed to use power-down or clock suspend)");
			if (init_phase == 0 && !dqm_flagged && (DRAM_LDQM !== 1'b1 || DRAM_UDQM !== 1'b1)) begin
				dqm_flagged = 1'b1;
				violation("DQM not high during power-up (Initialization, page 20)");
			end
			if (clk_period > 0.0 && cas_latency == 2 && clk_period < tCK2_MIN_ns)
				violation("clock period below tCK2 minimum");
			if (clk_period > 0.0 && cas_latency == 3 && clk_period < tCK3_MIN_ns)
				violation("clock period below tCK3 minimum");
		end

		// command decode: {CS, RAS, CAS, WE} -------------------------------------------------------------------------
		if (now <= 200.0) begin
			// outputs are not defined until reset has taken effect
		end else if ((^{DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N}) === 1'bx) begin
			violation("command pins are unknown (X/Z)");
		end else begin
			casez ({DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N})
				4'b1???, 4'b0111: ;  // DESL / NOP: nothing to check

				default: begin
					// rules that apply to every real command ----------------------------------------------------------
					if (first_cmd_time < 0.0) begin
						first_cmd_time = now;
						if (now < tPOWERUP_ns)
							violation("first command before the 100us power-up delay (page 20)");
					end
					if (last_MRS > 0.0 && (now - last_MRS) < tMRD_ns)
						violation("tMRD: command too soon after MODE REGISTER SET");
					if (last_MRS > 0.0 && clk_period > 0.0 && (now - last_MRS) < 2.0 * clk_period)
						violation("tMRD: fewer than 2 clocks after MODE REGISTER SET (page 18)");

					case ({DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N})

					// ACT: bank activate ------------------------------------------------------------------------------
					4'b0011: begin
						b = DRAM_BA;
						if (init_phase < 2) violation("ACT before the mode register was set");
						if (bank_open[b])   violation("ACT to a bank that already has an open row (ILLEGAL, page 10)");
						if ((now - last_PRE[b]) < tRP_ns)  violation("tRP: ACT too soon after PRE");
						if ((now - last_ACT[b]) < tRC_ns)  violation("tRC: ACT to ACT on the same bank");
						if ((now - last_REF)    < tRC_ns)  violation("tRC: ACT too soon after REF");
						bank_open[b] = 1'b1;
						bank_row[b]  = DRAM_ADDR;
						last_ACT[b]  = now;
					end

					// READ --------------------------------------------------------------------------------------------
					4'b0101: begin
						b = DRAM_BA;
						if (init_phase < 2)   violation("READ before the mode register was set");
						if (!bank_open[b])    violation("READ to a bank with no open row (ILLEGAL)");
						else if ((now - last_ACT[b]) < tRCD_ns) violation("tRCD: READ too soon after ACT");
						if (DRAM_ADDR[10])    violation("READ with auto precharge is not modeled");
						rd_v[0] <= 1'b1;
						rd_a[0] <= {DRAM_BA, bank_row[b], DRAM_ADDR[9:0]};
					end

					// WRITE --------------------------------------------------------------------------------------------
					4'b0100: begin
						b = DRAM_BA;
						if (init_phase < 2)   violation("WRIT before the mode register was set");
						if (!bank_open[b])    violation("WRIT to a bank with no open row (ILLEGAL)");
						else if ((now - last_ACT[b]) < tRCD_ns) violation("tRCD: WRIT too soon after ACT");
						if (DRAM_ADDR[10])    violation("WRIT with auto precharge is not modeled");
						if ((^DRAM_DQ) === 1'bx) violation("WRIT while DQ is undriven or unknown (write data must accompany the command)");
						addr25 = {DRAM_BA, bank_row[b], DRAM_ADDR[9:0]};
						merged = mem[addr25];
						if (!DRAM_LDQM) merged[7:0]  = DRAM_DQ[7:0];    // DQML low = low byte written
						if (!DRAM_UDQM) merged[15:8] = DRAM_DQ[15:8];   // DQMH low = high byte written
						mem[addr25] <= merged;
						last_WRIT[b] = now;
					end

					// PRE / PALL --------------------------------------------------------------------------------------
					4'b0010: begin
						if (init_phase == 0) begin
							if (!DRAM_ADDR[10]) violation("first command after power-up must be PRECHARGE ALL (A10 = H)");
							init_phase = 1;
						end
						for (i = 0; i < 4; i = i + 1) begin
							if (DRAM_ADDR[10] || i == DRAM_BA) begin
								if (bank_open[i]) begin
									if ((now - last_ACT[i])  < tRAS_MIN_ns) violation("tRAS: PRE too soon after ACT");
									if ((now - last_ACT[i])  > tRAS_MAX_ns) violation("tRAS: row left open longer than 100us");
									if ((now - last_WRIT[i]) < tDPL_ns)     violation("tDPL: PRE too soon after the last write data");
								end
								bank_open[i] = 1'b0;
								last_PRE[i]  = now;
							end
						end
					end

					// REF: CBR auto-refresh ---------------------------------------------------------------------------
					4'b0001: begin
						if (init_phase == 0) violation("REF before PRECHARGE ALL during power-up");
						for (i = 0; i < 4; i = i + 1) begin
							if (bank_open[i]) violation("REF while a bank has an open row (ILLEGAL)");
							if ((now - last_PRE[i]) < tRP_ns) violation("tRP: REF too soon after PRE");
						end
						if ((now - last_REF) < tRC_ns) violation("tRC: REF to REF");
						if (init_phase == 1) init_ref_count = init_ref_count + 1;
						if (init_phase == 2 && last_REF > 0.0 &&
						    (now - last_REF) > (tREF_ns / REFRESH_ROWS))
							violation("refresh rate below 8192 cycles every 64ms (7.8125us apart)");
						last_REF = now;
					end

					// MRS: mode register set ----------------------------------------------------------------------------
					4'b0000: begin
						if (init_phase != 1 || init_ref_count < 2)
							violation("MODE REGISTER SET before PRECHARGE ALL and at least 2 auto-refreshes (page 20)");
						for (i = 0; i < 4; i = i + 1)
							if (bank_open[i]) violation("MODE REGISTER SET while a bank is open");
						if ((now - last_REF) < tRC_ns) violation("tRC: MODE REGISTER SET too soon after REF");
						if ({DRAM_BA, DRAM_ADDR[12:10]} != 5'b0)
							violation("mode register: BA1, BA0, A12, A11, A10 must be 0 (page 24)");
						if (DRAM_ADDR[2:0] != 3'b000)
							violation("mode register: this controller is expected to program burst length 1");
						if (DRAM_ADDR[8:7] != 2'b00)
							violation("mode register: M8:M7 must be 00 (standard operation)");
						case (DRAM_ADDR[6:4])
							3'b010:  cas_latency = 2;
							3'b011:  cas_latency = 3;
							default: begin cas_latency = 0; violation("mode register: reserved CAS latency"); end
						endcase
						last_MRS   = now;
						init_phase = 2;
					end

					default: violation("BURST STOP / unrecognized command (not modeled)");
					endcase
				end
			endcase
		end
	end

endmodule