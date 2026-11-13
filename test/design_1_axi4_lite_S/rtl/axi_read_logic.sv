module axi_read_logic(
	input		axi_clk,
	input		rstn,

	input	[1:0]	read_addr,
	input		read_addr_valid,
	output	reg	read_addr_ready,

	output	[31:0]	read_data,
	output	reg	read_data_valid,
	input		read_data_ready,

	output	[1:0]	read_resp,

	output	[1:0]	addr_out,	// register index to read
	input	[31:0]	data_in		// register file contents at addr_out
);

//registers to store data
reg [31:0]	data_r;
reg [1:0]	addr_r;
reg		addr_done_r;	// address accepted, data not fetched yet

// a read is outstanding until the R handshake completes
wire busy = addr_done_r | read_data_valid;

assign addr_out  = addr_r;
assign read_data = data_r;
assign read_resp = 2'd0; //always indicate OKAY status for reads

//read address handshake (only accept a new address when idle)
always_ff@(posedge axi_clk)
begin
	if(~rstn|(read_addr_valid&read_addr_ready))
		read_addr_ready <= 0;
	else if (~read_addr_ready&read_addr_valid&~busy)
		read_addr_ready <= 1;
end

// latch address, fetch data, drive R channel
always_ff@(posedge axi_clk)
begin
	if(~rstn)
	begin
		addr_r          <= 2'd0;
		data_r          <= 32'd0;
		addr_done_r     <= 0;
		read_data_valid <= 0;
	end
	else
	begin
		addr_done_r <= 0;

		if(read_addr_valid&read_addr_ready)
		begin
			addr_r      <= read_addr;
			addr_done_r <= 1;
		end

		if(addr_done_r)
		begin
			data_r          <= data_in;	// addr_r is valid by now
			read_data_valid <= 1;
		end
		else if(read_data_valid&read_data_ready)
			read_data_valid <= 0;
	end
end

endmodule
