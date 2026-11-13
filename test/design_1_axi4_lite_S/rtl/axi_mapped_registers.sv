module axi_mapped_registers(
	input		ACLK,
	input		ARESETN,
	
	input	[31:0]	WDATA,
	input		WVALID,
	output		WREADY,

	input	[1:0]	AWADDR,
	input		AWVALID,
	output		AWREADY,

	output	[1:0]	BRESP,
	input		BREADY,
	output		BVALID,

	input	[1:0]	ARADDR,
	input		ARVALID,
	output		ARREADY,

	output	[31:0]	RDATA,
	output		RVALID,
	input		RREADY,
	output	[1:0]	RRESP
);

reg	[31:0]	rfile[3:0];
wire 	[1:0]	wraddr;
wire 	[31:0]	rdata_in;
wire 		write_en;
wire 	[1:0]	rdaddr;
wire 	[31:0]	rfile_rdata;

assign rfile_rdata = rfile[rdaddr];

axi_write_logic wrinst(
	.axi_clk		(ACLK),
	.rstn			(ARESETN),
	.write_addr		(AWADDR),
	.write_addr_valid	(AWVALID),
	.write_addr_ready	(AWREADY),
	.write_data		(WDATA),
	.write_data_valid	(WVALID),
	.write_data_ready	(WREADY),
	.write_resp_ready	(BREADY),
	.write_resp_valid	(BVALID),
	.write_resp		(BRESP),
	.data_out		(rdata_in),
	.addr_out		(wraddr),
	.data_valid		(write_en)
);

axi_read_logic rdinst(
	.axi_clk		(ACLK),
	.rstn			(ARESETN),
	.read_addr		(ARADDR),
	.read_addr_valid	(ARVALID),
	.read_addr_ready	(ARREADY),
	.read_data		(RDATA),
	.read_data_valid	(RVALID),
	.read_data_ready	(RREADY),
	.read_resp		(RRESP),
	.addr_out		(rdaddr),
	.data_in		(rfile_rdata)
);

integer i;
//write logic for register file
always_ff @(posedge ACLK)
begin
	if(ARESETN==0)
	begin
		for(i=0;i<4;i=i+1)
			rfile[i]<=0;
	end
	else if(write_en)
		rfile[wraddr] <= rdata_in;
end

endmodule
