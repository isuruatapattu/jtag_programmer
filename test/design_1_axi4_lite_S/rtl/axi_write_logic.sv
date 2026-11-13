module axi_write_logic(
	input 		axi_clk,
	input 		rstn,

	input	[1:0]	write_addr,
	input		write_addr_valid,
	output	reg	write_addr_ready,

	input	[31:0]	write_data,
	input		write_data_valid,
	output	reg	write_data_ready,

	input		write_resp_ready,
	output	reg	write_resp_valid,
	output	[1:0]	write_resp,

	output	[31:0]	data_out,
	output	[1:0]	addr_out,
	output		data_valid
);

//registers to store data
reg [31:0]	data_r;
reg [1:0]	addr_r;
//registers to track handshake completion
reg	addr_done_r;
reg	data_done_r;

assign data_out = data_r;
assign addr_out	= addr_r;

assign data_valid = data_done_r&addr_done_r;

assign write_resp = 2'd0; //always indicate OKAY status for writes


//write address handshake
always_ff@(posedge axi_clk)
begin
	if(~rstn|(write_addr_valid&write_addr_ready))
		write_addr_ready <= 0;
	else if (~write_addr_ready&write_addr_valid)
		write_addr_ready <= 1;
end

//write data handshake
always_ff@(posedge axi_clk)
begin
	if(~rstn|(write_data_valid&write_data_ready))
		write_data_ready <= 0;
	else if (~write_data_ready&write_data_valid)
		write_data_ready <= 1;
end

//track handshake completion
always_ff@(posedge axi_clk)
begin
	if (~rstn||(addr_done_r&data_done_r))
	begin
		addr_done_r <= 0;
		data_done_r <= 0;
	end
	else
	begin
		if(write_data_valid&write_data_ready)
			data_done_r <= 1;
		if(write_addr_valid&write_addr_ready)
			addr_done_r <= 1;
	end
end

//store received data and address
always_ff@(posedge axi_clk)
begin
	if (~rstn)
	begin
		data_r <= 32'd0;
		addr_r <= 2'd0;
	end
	else
	begin
		if(write_data_valid&write_data_ready)
			data_r <= write_data;
		if(write_addr_valid&write_addr_ready)
			addr_r <= write_addr;
	end
end

//write response logic
always_ff@(posedge axi_clk)
begin
	if (~rstn|(write_resp_valid&write_resp_ready))
		write_resp_valid <= 0;
	else if (~write_resp_valid&(data_done_r&addr_done_r))
		write_resp_valid <= 1;
end

endmodule
