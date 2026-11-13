`timescale 1ns/1ps

// Simple self-checking testbench for axi_mapped_registers (AXI4-Lite write and read channels).
module axi_mapped_registers_tb;

	localparam CLK_PERIOD = 10;

	reg		ACLK = 0;
	reg		ARESETN = 0;

	reg	[31:0]	WDATA = 0;
	reg		WVALID = 0;
	wire		WREADY;

	reg	[1:0]	AWADDR = 0;
	reg		AWVALID = 0;
	wire		AWREADY;

	wire	[1:0]	BRESP;
	reg		BREADY = 0;
	wire		BVALID;

	reg	[1:0]	ARADDR = 0;
	reg		ARVALID = 0;
	wire		ARREADY;

	wire	[31:0]	RDATA;
	wire		RVALID;
	reg		RREADY = 0;
	wire	[1:0]	RRESP;

	integer errors = 0;
	reg [31:0] expected [0:3];
	integer i;

	axi_mapped_registers dut (
		.ACLK		(ACLK),
		.ARESETN	(ARESETN),
		.WDATA		(WDATA),
		.WVALID		(WVALID),
		.WREADY		(WREADY),
		.AWADDR		(AWADDR),
		.AWVALID	(AWVALID),
		.AWREADY	(AWREADY),
		.BRESP		(BRESP),
		.BREADY		(BREADY),
		.BVALID		(BVALID),
		.ARADDR		(ARADDR),
		.ARVALID	(ARVALID),
		.ARREADY	(ARREADY),
		.RDATA		(RDATA),
		.RVALID		(RVALID),
		.RREADY		(RREADY),
		.RRESP		(RRESP)
	);

	// clock
	always #(CLK_PERIOD/2) ACLK = ~ACLK;

	// watchdog
	initial begin
		#(CLK_PERIOD*5000);
		$display("[%0t] ERROR: simulation timeout", $time);
		$finish;
	end

	// Inputs are driven on negedge and sampled on posedge to avoid races.
	task automatic send_aw(input [1:0] addr);
		begin
			@(negedge ACLK);
			AWADDR  = addr;
			AWVALID = 1;
			// handshake completes on the posedge where READY is seen high
			do @(posedge ACLK); while (!AWREADY);
			@(negedge ACLK);
			AWVALID = 0;
		end
	endtask

	task automatic send_w(input [31:0] data);
		begin
			@(negedge ACLK);
			WDATA  = data;
			WVALID = 1;
			do @(posedge ACLK); while (!WREADY);
			@(negedge ACLK);
			WVALID = 0;
		end
	endtask

	task automatic wait_bresp;
		begin
			BREADY = 1;
			do @(posedge ACLK); while (!BVALID);
			if (BRESP !== 2'b00) begin
				$display("[%0t] ERROR: BRESP = %b, expected OKAY (00)", $time, BRESP);
				errors = errors + 1;
			end
			@(negedge ACLK);
			BREADY = 0;
		end
	endtask

	// Full AXI write: address and data channels issued concurrently, then response.
	task automatic axi_write(input [1:0] addr, input [31:0] data);
		begin
			fork
				send_aw(addr);
				send_w(data);
			join
			wait_bresp();
			expected[addr] = data;
			repeat (2) @(posedge ACLK);
		end
	endtask

	// Write with the two channels started at different times.
	// aw_delay / w_delay are clock cycles to wait before raising each VALID.
	task automatic axi_write_skew(input [1:0] addr, input [31:0] data,
	                              input integer aw_delay, input integer w_delay);
		begin
			fork
				begin repeat (aw_delay) @(negedge ACLK); send_aw(addr); end
				begin repeat (w_delay)  @(negedge ACLK); send_w(data);  end
			join
			wait_bresp();
			expected[addr] = data;
			repeat (2) @(posedge ACLK);
		end
	endtask

	// Check the internal handshake-done flags and that no write has happened yet.
	task automatic check_partial(input exp_addr_done, input exp_data_done,
	                             input [1:0] addr);
		begin
			if (dut.wrinst.addr_done_r !== exp_addr_done ||
			    dut.wrinst.data_done_r !== exp_data_done) begin
				$display("[%0t] ERROR: addr_done_r=%b data_done_r=%b, expected %b %b",
					$time, dut.wrinst.addr_done_r, dut.wrinst.data_done_r,
					exp_addr_done, exp_data_done);
				errors = errors + 1;
			end
			if (BVALID !== 1'b0) begin
				$display("[%0t] ERROR: BVALID asserted before both channels completed", $time);
				errors = errors + 1;
			end
			if (dut.rfile[addr] !== expected[addr]) begin
				$display("[%0t] ERROR: rfile[%0d] changed before both channels completed", $time, addr);
				errors = errors + 1;
			end
		end
	endtask

	// Address channel completes first, data arrives later.
	task automatic axi_write_addr_first(input [1:0] addr, input [31:0] data);
		begin
			send_aw(addr);
			repeat (4) @(posedge ACLK);
			check_partial(1'b1, 1'b0, addr);
			send_w(data);
			wait_bresp();
			expected[addr] = data;
			repeat (2) @(posedge ACLK);
		end
	endtask

	// Data channel completes first, address arrives later.
	task automatic axi_write_data_first(input [1:0] addr, input [31:0] data);
		begin
			send_w(data);
			repeat (4) @(posedge ACLK);
			check_partial(1'b0, 1'b1, addr);
			send_aw(addr);
			wait_bresp();
			expected[addr] = data;
			repeat (2) @(posedge ACLK);
		end
	endtask

	// ---------------------------------------------------------------------
	// Read channel tasks
	// ---------------------------------------------------------------------

	// AR handshake. Returns on the falling edge after the handshake edge.
	task automatic send_ar(input [1:0] addr);
		begin
			@(negedge ACLK);
			ARADDR  = addr;
			ARVALID = 1;
			do @(posedge ACLK); while (!ARREADY);
			@(negedge ACLK);
			ARVALID = 0;
		end
	endtask

	// R handshake, then compare RDATA with expected[addr].
	//   rready_delay >= 0 : RREADY is raised that many cycles after RVALID is seen
	//                       (RDATA/RVALID must stay stable while waiting)
	//   rready_delay <  0 : RREADY is already high before RVALID rises
	task automatic wait_read_data(input [1:0] addr, input integer rready_delay);
		reg [31:0] held;
		integer n;
		begin
			if (rready_delay < 0) begin
				RREADY = 1;
				do @(posedge ACLK); while (!RVALID);
			end else begin
				RREADY = 0;
				do @(posedge ACLK); while (!RVALID);
				held = RDATA;
				for (n = 0; n < rready_delay; n = n + 1) begin
					@(posedge ACLK);
					if (RVALID !== 1'b1 || RDATA !== held) begin
						$display("[%0t] ERROR: RVALID/RDATA not held while RREADY low (RVALID=%b RDATA=0x%08h, was 0x%08h)",
							$time, RVALID, RDATA, held);
						errors = errors + 1;
					end
				end
				@(negedge ACLK);
				RREADY = 1;
				@(posedge ACLK);	// handshake edge
			end

			// sampled at the handshake edge
			if (RRESP !== 2'b00) begin
				$display("[%0t] ERROR: RRESP = %b, expected OKAY (00)", $time, RRESP);
				errors = errors + 1;
			end
			if (RDATA !== expected[addr]) begin
				$display("[%0t] ERROR: read[%0d] = 0x%08h, expected 0x%08h",
					$time, addr, RDATA, expected[addr]);
				errors = errors + 1;
			end else
				$display("[%0t] PASS : read[%0d] = 0x%08h", $time, addr, RDATA);

			@(negedge ACLK);
			RREADY = 0;
			if (RVALID !== 1'b0) begin
				$display("[%0t] ERROR: RVALID still high after R handshake", $time);
				errors = errors + 1;
			end
		end
	endtask

	// Full AXI read of one register, checked against expected[].
	task automatic axi_read(input [1:0] addr, input integer rready_delay);
		begin
			send_ar(addr);
			wait_read_data(addr, rready_delay);
			repeat (2) @(posedge ACLK);
		end
	endtask

	task automatic read_all(input integer rready_delay);
		integer k;
		begin
			for (k = 0; k < 4; k = k + 1)
				axi_read(k[1:0], rready_delay);
		end
	endtask

	// A second AR must not be accepted while the first read is outstanding.
	task automatic axi_read_blocked_while_busy(input [1:0] a0, input [1:0] a1);
		integer n;
		begin
			send_ar(a0);

			// second request waits; RREADY stays low so read a0 stays outstanding
			@(negedge ACLK);
			ARADDR  = a1;
			ARVALID = 1;
			for (n = 0; n < 6; n = n + 1) begin
				@(posedge ACLK);
				if (ARREADY !== 1'b0) begin
					$display("[%0t] ERROR: ARREADY asserted while previous read is outstanding", $time);
					errors = errors + 1;
				end
			end

			// finish first read, second address is then accepted
			wait_read_data(a0, 0);
			do @(posedge ACLK); while (!ARREADY);
			@(negedge ACLK);
			ARVALID = 0;
			wait_read_data(a1, 0);
			repeat (2) @(posedge ACLK);
		end
	endtask

	task automatic check_reg(input [1:0] addr);
		begin
			if (dut.rfile[addr] !== expected[addr]) begin
				$display("[%0t] ERROR: rfile[%0d] = 0x%08h, expected 0x%08h",
					$time, addr, dut.rfile[addr], expected[addr]);
				errors = errors + 1;
			end else
				$display("[%0t] PASS : rfile[%0d] = 0x%08h", $time, addr, dut.rfile[addr]);
		end
	endtask

	task automatic check_all;
		integer k;
		begin
			for (k = 0; k < 4; k = k + 1)
				check_reg(k[1:0]);
		end
	endtask

	initial begin
		for (i = 0; i < 4; i = i + 1)
			expected[i] = 32'h0;

		// reset
		ARESETN = 0;
		repeat (5) @(posedge ACLK);
		@(negedge ACLK);
		ARESETN = 1;
		repeat (3) @(posedge ACLK);

		$display("--- Test 1: registers are zero after reset");
		check_all();

		$display("--- Test 2: write each register");
		axi_write(2'd0, 32'hDEADBEEF);
		axi_write(2'd1, 32'hCAFEBABE);
		axi_write(2'd2, 32'h12345678);
		axi_write(2'd3, 32'hA5A5A5A5);
		check_all();

		$display("--- Test 3: overwrite a register, others unchanged");
		axi_write(2'd2, 32'h0BADF00D);
		check_all();

		$display("--- Test 4: back-to-back writes");
		axi_write(2'd0, 32'h00000001);
		axi_write(2'd0, 32'h00000002);
		axi_write(2'd3, 32'hFFFFFFFF);
		check_all();

		$display("--- Test 5: address first, data 4 cycles later");
		axi_write_addr_first(2'd1, 32'h11111111);
		check_all();

		$display("--- Test 6: data first, address 4 cycles later");
		axi_write_data_first(2'd2, 32'h22222222);
		check_all();

		$display("--- Test 7: staggered channels with overlapping delays");
		axi_write_skew(2'd0, 32'h33333333, 0, 3);
		axi_write_skew(2'd3, 32'h44444444, 3, 0);
		axi_write_skew(2'd1, 32'h55555555, 1, 2);
		axi_write_skew(2'd2, 32'h66666666, 5, 5);
		check_all();

		$display("--- Test 8: read back every register over AXI");
		read_all(0);

		$display("--- Test 9: read with RREADY delayed 5 cycles (RDATA must stay stable)");
		axi_read(2'd0, 5);
		axi_read(2'd3, 5);

		$display("--- Test 10: RREADY already high before RVALID");
		read_all(-1);

		$display("--- Test 11: second AR is held off while a read is outstanding");
		axi_read_blocked_while_busy(2'd1, 2'd2);

		$display("--- Test 12: write then read back the same register");
		for (i = 0; i < 4; i = i + 1) begin
			axi_write(i[1:0], 32'hA0000000 + i);
			axi_read(i[1:0], 0);
		end

		$display("--- Test 13: reset clears registers");
		@(negedge ACLK);
		ARESETN = 0;
		repeat (2) @(posedge ACLK);
		@(negedge ACLK);
		ARESETN = 1;
		for (i = 0; i < 4; i = i + 1)
			expected[i] = 32'h0;
		repeat (2) @(posedge ACLK);
		check_all();

		$display("--- Test 14: registers read as zero over AXI after reset");
		read_all(0);

		if (errors == 0)
			$display("*** TEST PASSED ***");
		else
			$display("*** TEST FAILED: %0d error(s) ***", errors);
		$finish;
	end

endmodule
