// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

/*spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(in_paddr[4:0]),
  .wb_dat_i(in_pwdata),
  .wb_dat_o(in_prdata),
  .wb_sel_i(in_pstrb),
  .wb_we_i (in_pwrite),
  .wb_stb_i(in_psel),
  .wb_cyc_i(in_penable),
  .wb_ack_o(in_pready),
  .wb_err_o(in_pslverr),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);*/

// 判断是否为flash地址空间的访问
wire is_flash_access = (in_paddr >= flash_addr_start) && (in_paddr <= flash_addr_end);

// XIP模式状态机状态定义
localparam XIP_IDLE     = 3'd0;  // 空闲状态
localparam XIP_SETUP_DIV = 3'd1; // 设置分频器
localparam XIP_SETUP_SS = 3'd2;  // 设置片选
localparam XIP_SETUP_TX = 3'd3;  // 设置发送数据
localparam XIP_SETUP_CTRL = 3'd4; // 设置控制寄存器
localparam XIP_WAIT     = 3'd5;  // 等待传输完成
localparam XIP_READ     = 3'd6;  // 读取数据
localparam XIP_DONE     = 3'd7;  // 完成状态

// 状态机寄存器
reg [2:0]  xip_state;
reg [2:0]  xip_next_state;
reg [31:0] xip_addr;
reg [31:0] xip_data;
reg        xip_error;
// 用于APB输出信号的寄存器
reg        xip_pready;
reg [31:0] xip_prdata;
reg        xip_pslverr;

// SPI控制器接口信号
reg [4:0]  spi_addr;
reg [31:0] spi_wdata;
reg        spi_we;
reg        spi_stb;
reg        spi_cyc;
wire       spi_ack;
wire [31:0] spi_rdata;
wire       spi_err;
wire       spi_int;

// 状态转换和SPI控制信号生成（组合逻辑）
always @(*) begin
  // 默认值
  xip_next_state = xip_state;
  spi_addr = 5'h0;
  spi_wdata = 32'h0;
  spi_we = 1'b0;
  spi_stb = 1'b0;
  spi_cyc = 1'b0;

  if (is_flash_access) begin
    // Flash访问 - XIP模式
    case (xip_state)
      XIP_IDLE: begin
        // 空闲状态
        if (in_psel && !in_penable) begin
          if (in_pwrite) begin
            // 不支持写入flash
            xip_next_state = XIP_DONE;
          end else begin
            // 读取flash，进入设置分频器状态
            xip_next_state = XIP_SETUP_DIV;
          end
        end
      end
      
      XIP_SETUP_DIV: begin
        // 设置分频器寄存器
        spi_addr = 5'h14; // SPI_DIVIDER寄存器地址
        spi_wdata = 32'h5; // 设置分频值为5
        spi_we = 1'b1;
        spi_stb = 1'b1;
        spi_cyc = 1'b1;
        
        if (spi_ack) begin
          // 收到ack，进入设置SS状态
          xip_next_state = XIP_SETUP_SS;
        end
      end
      
      XIP_SETUP_SS: begin
        // 设置SS寄存器，选择flash设备
        spi_addr = 5'h18; // SPI_SS寄存器地址
        spi_wdata = 32'h1; // 选择SS[0]
        spi_we = 1'b1;
        spi_stb = 1'b1;
        spi_cyc = 1'b1;
        
        if (spi_ack) begin
          // 收到ack，进入设置TX状态
          xip_next_state = XIP_SETUP_TX;
        end
      end
      
      XIP_SETUP_TX: begin
        // 设置TX寄存器，发送读命令和地址
        spi_addr = 5'h04; // SPI_TX_1寄存器地址
        spi_wdata = {8'h03, xip_addr[23:0]}; // 标准读取命令(0x03)和地址
        spi_we = 1'b1;
        spi_stb = 1'b1;
        spi_cyc = 1'b1;

        if (spi_ack) begin
          // 收到ack，进入设置CTRL状态
          xip_next_state = XIP_SETUP_CTRL;
        end
      end
      
      XIP_SETUP_CTRL: begin
        // 设置CTRL寄存器，启动传输
        spi_addr = 5'h10; // SPI_CTRL寄存器地址
        spi_wdata = 32'h2140; // 32位字符长度，启用自动SS，设置GO位
        spi_we = 1'b1;
        spi_stb = 1'b1;
        spi_cyc = 1'b1;
        
        if (spi_ack) begin
          // 收到ack，进入等待状态
          xip_next_state = XIP_WAIT;
        end
      end
      
      XIP_WAIT: begin
        // 轮询CTRL寄存器的GO_BUSY位
        spi_addr = 5'h10; // SPI_CTRL寄存器地址
        spi_we = 1'b0;
        spi_stb = 1'b1;
        spi_cyc = 1'b1;
        
        if (spi_ack && ((spi_rdata & 32'h100) == 32'h0)) begin
          // GO_BUSY位为0，表示传输完成，进入读取状态
          xip_next_state = XIP_READ;
        end
      end
      
      XIP_READ: begin
        // 读取RX寄存器中的数据
        spi_addr = 5'h00; // SPI_RX_0寄存器地址
        spi_we = 1'b0;
        spi_stb = 1'b1;
        spi_cyc = 1'b1;
        
        if (spi_ack) begin
          // 收到ack，进入完成状态
          xip_next_state = XIP_DONE;
        end
      end
      
      XIP_DONE: begin
        // 完成状态
        if (in_penable) begin
          // 收到penable，返回空闲状态
          xip_next_state = XIP_IDLE;
        end

      end
      
      default: begin
        // 默认情况，返回空闲状态
        xip_next_state = XIP_IDLE;
      end
    endcase
  end else begin
    // 正常SPI控制器访问 - 直接传递APB信号
    spi_addr = in_paddr[4:0];
    spi_wdata = in_pwdata;
    spi_we = in_pwrite;
    spi_stb = in_psel;
    spi_cyc = in_penable;
  end
end

// 状态更新（时序逻辑）
always @(posedge clock or posedge reset) begin
  if (reset) begin
    xip_state <= XIP_IDLE;
    xip_addr <= 32'h0;
    xip_data <= 32'h0;
    xip_error <= 1'b0;
  end else begin
    // 更新状态
    xip_state <= xip_next_state;
    
    // 根据当前状态和输入更新其他寄存器
    case (xip_state)
      XIP_IDLE: begin
        if (in_psel && !in_penable && is_flash_access) begin
          if (in_pwrite) begin
            // 不支持写入flash
            xip_error <= 1'b1;
          end else begin
            // 读取flash，保存地址
            xip_addr <= in_paddr;
            xip_error <= 1'b0;
          end
        end
      end
      
      XIP_READ: begin
        if (spi_ack) begin
          // 收到ack，保存读取的数据
          xip_data <= spi_rdata;
        end
      end

      default: begin
        // 在其他状态下不需要更新任何寄存器
        // 这个分支是为了解决CASEINCOMPLETE警告
      end
    endcase
  end
end


// APB接口信号生成（组合逻辑）
always @(*) begin
  if (is_flash_access) begin
    // Flash访问 - XIP模式
    if (xip_state == XIP_DONE) begin
      // 只有在XIP_DONE状态（整个XIP序列完成）时才向处理器返回ready
      xip_pready = 1'b1;
      xip_prdata = xip_error ? 32'h0 : xip_data;
      xip_pslverr = xip_error;
    end else begin
      xip_pready = 1'b0;
      xip_prdata = 32'h0;
      xip_pslverr = 1'b0;
    end
  end else begin
    // 正常SPI控制器访问 - 直接使用spi_ack
    xip_pready = spi_ack;
    xip_prdata = spi_rdata;
    xip_pslverr = spi_err;
  end
end

assign in_pready = xip_pready;
assign in_prdata = xip_prdata;
assign in_pslverr = xip_pslverr;


// 实例化SPI控制器
spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(spi_addr),
  .wb_dat_i(spi_wdata),
  .wb_dat_o(spi_rdata),
  .wb_sel_i(is_flash_access ? 4'hF : in_pstrb),  // XIP模式下选择所有字节，否则传递pstrb
  .wb_we_i(spi_we),
  .wb_stb_i(spi_stb),
  .wb_cyc_i(spi_cyc),
  .wb_ack_o(spi_ack),
  .wb_err_o(spi_err),
  .wb_int_o(spi_int),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

// 连接中断信号
assign spi_irq_out = spi_int;
`endif // FAST_FLASH

endmodule
