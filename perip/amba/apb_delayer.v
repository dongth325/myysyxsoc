module apb_delayer(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,//随输入变化
  input         in_psel,//随paddr开始，随当前pc结束
  input         in_penable,//随paddr下一个周期开始，随当前pc结束
  input  [2:0]  in_pprot,//一直是1
  input         in_pwrite,//随paddr变为写地址变化，paddr写地址结束就为0
  input  [31:0] in_pwdata,//一直存在除非下一次wdata传入
  input  [3:0]  in_pstrb,//随paddr变为写地址变化，paddr写地址结束就为0
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,//和pc地址交界前一个周期为1,pc更新为0,持续一个周期，和sel enable一起结束
  input  [31:0] out_prdata,//和pready相同
  input         out_pslverr//一直是0
);



assign out_paddr   = in_paddr;
assign out_psel    = in_psel;
assign out_penable = in_penable;
assign out_pprot   = in_pprot;
assign out_pwrite  = in_pwrite;
assign out_pwdata  = in_pwdata;
assign out_pstrb   = in_pstrb;

// 核心控制逻辑
reg        busy;       // 延迟进行标志
reg [2:0]  delay_cnt;  // 延迟计数器（支持最大延迟8周期）
reg [31:0] data_buf;   // 数据缓存
reg        error_buf;  // 错误缓存

// 设备响应检测
wire dev_ready = out_pready && in_psel && in_penable;

always @(posedge clock or posedge reset) begin
  if (reset) begin
    busy      <= 0;
    delay_cnt <= 0;
    data_buf  <= 0;
    error_buf <= 0;
  end else begin
    // 事务中止处理
    if (!in_psel) begin
      busy <= 0;
    end
    // 正常操作
    else if (busy) begin
      if (delay_cnt == 0) busy <= 0;
      else delay_cnt <= delay_cnt - 1;
      
    end
    else if (dev_ready) begin
      busy      <= 1;
      delay_cnt <= 3'd4;  // 固定5周期延迟 (4+1)
      data_buf  <= out_prdata;
      error_buf <= out_pslverr;
    end
  end
end

// 协议兼容的输出逻辑
assign in_pready  = (busy && delay_cnt == 0) && in_psel;
assign in_prdata  = (busy && delay_cnt == 0) ? data_buf : 32'h0;
assign in_pslverr = (busy && delay_cnt == 0) ? error_buf : 1'b0;
















  /*assign out_paddr   = in_paddr;
  assign out_psel    = in_psel;
  assign out_penable = in_penable;
  assign out_pprot   = in_pprot;
  assign out_pwrite  = in_pwrite;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;
  assign in_pready   = out_pready;
  assign in_prdata   = out_prdata;
  assign in_pslverr  = out_pslverr;*/
  // 参数化延时周期数


































// 配置固定延迟周期 
  /*parameter DELAY_CYCLES = 5;  // 设置为r-1的固定值即可实现近似比例延迟
  
  // 直接传递请求信号
  assign out_paddr   = in_paddr;
  assign out_psel    = in_psel;
  assign out_penable = in_penable;
  assign out_pprot   = in_pprot;
  assign out_pwrite  = in_pwrite;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;
  
  // 响应信号延迟寄存器链
  reg        delay_pready  [0:DELAY_CYCLES];
  reg [31:0] delay_prdata  [0:DELAY_CYCLES];
  reg        delay_pslverr [0:DELAY_CYCLES];
  
  // 初始化延迟链
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      for (int i = 0; i <= DELAY_CYCLES; i = i + 1) begin
        delay_pready[i]  <= 1'b0;
        delay_prdata[i]  <= 32'h0;
        delay_pslverr[i] <= 1'b0;
      end
    end else begin
      // 采样设备响应进入延迟链
      delay_pready[0]  <= out_pready;
      delay_prdata[0]  <= out_prdata;
      delay_pslverr[0] <= out_pslverr;
      
      // 延迟链移位
      for (int i = 1; i <= DELAY_CYCLES; i = i + 1) begin
        delay_pready[i]  <= delay_pready[i-1];
        delay_prdata[i]  <= delay_prdata[i-1];
        delay_pslverr[i] <= delay_pslverr[i-1];
      end
    end
  end
  
  // 将延迟后的响应信号传回主设备
  assign in_pready  = delay_pready[DELAY_CYCLES];
  assign in_prdata  = delay_prdata[DELAY_CYCLES];
  assign in_pslverr = delay_pslverr[DELAY_CYCLES];*/




  /*parameter DELAY_CYCLES = 5;  // 可根据需要调整
  
  // 请求信号延时寄存器组
  reg [31:0] delay_paddr   [0:DELAY_CYCLES-1];
  reg        delay_psel    [0:DELAY_CYCLES-1];
  reg        delay_penable [0:DELAY_CYCLES-1];
  reg [2:0]  delay_pprot   [0:DELAY_CYCLES-1];
  reg        delay_pwrite  [0:DELAY_CYCLES-1];
  reg [31:0] delay_pwdata  [0:DELAY_CYCLES-1];
  reg [3:0]  delay_pstrb   [0:DELAY_CYCLES-1];
  
  // 响应信号延时寄存器组
  reg        delay_pready  [0:DELAY_CYCLES-1];
  reg [31:0] delay_prdata  [0:DELAY_CYCLES-1];
  reg        delay_pslverr [0:DELAY_CYCLES-1];
  
  // 请求信号延时链
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      for (integer i = 0; i < DELAY_CYCLES; i = i + 1) begin
        delay_paddr[i]   <= 32'h0;
        delay_psel[i]    <= 1'b0;
        delay_penable[i] <= 1'b0;
        delay_pprot[i]   <= 3'h0;
        delay_pwrite[i]  <= 1'b0;
        delay_pwdata[i]  <= 32'h0;
        delay_pstrb[i]   <= 4'h0;
      end
    end else begin
      // 第一级寄存器采样输入
      delay_paddr[0]   <= in_paddr;
      delay_psel[0]    <= in_psel;
      delay_penable[0] <= in_penable;
      delay_pprot[0]   <= in_pprot;
      delay_pwrite[0]  <= in_pwrite;
      delay_pwdata[0]  <= in_pwdata;
      delay_pstrb[0]   <= in_pstrb;
      
      // 后续级联延时
      for (integer i = 1; i < DELAY_CYCLES; i = i + 1) begin
        delay_paddr[i]   <= delay_paddr[i-1];
        delay_psel[i]    <= delay_psel[i-1];
        delay_penable[i] <= delay_penable[i-1];
        delay_pprot[i]   <= delay_pprot[i-1];
        delay_pwrite[i]  <= delay_pwrite[i-1];
        delay_pwdata[i]  <= delay_pwdata[i-1];
        delay_pstrb[i]   <= delay_pstrb[i-1];
      end
    end
  end
  
  // 响应信号延时链
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      for (integer i = 0; i < DELAY_CYCLES; i = i + 1) begin
        delay_pready[i]  <= 1'b0;
        delay_prdata[i]  <= 32'h0;
        delay_pslverr[i] <= 1'b0;
      end
    end else begin
      // 第一级寄存器采样从设备响应
      delay_pready[0]  <= out_pready;
      delay_prdata[0]  <= out_prdata;
      delay_pslverr[0] <= out_pslverr;
      
      // 后续级联延时
      for (integer i = 1; i < DELAY_CYCLES; i = i + 1) begin
        delay_pready[i]  <= delay_pready[i-1];
        delay_prdata[i]  <= delay_prdata[i-1];
        delay_pslverr[i] <= delay_pslverr[i-1];
      end
    end
  end
  
  // 输出分配
  assign out_paddr   = delay_paddr[DELAY_CYCLES-1];
  assign out_psel    = delay_psel[DELAY_CYCLES-1];
  assign out_penable = delay_penable[DELAY_CYCLES-1];
  assign out_pprot   = delay_pprot[DELAY_CYCLES-1];
  assign out_pwrite  = delay_pwrite[DELAY_CYCLES-1];
  assign out_pwdata  = delay_pwdata[DELAY_CYCLES-1];
  assign out_pstrb   = delay_pstrb[DELAY_CYCLES-1];
  
  assign in_pready   = delay_pready[DELAY_CYCLES-1];
  assign in_prdata   = delay_prdata[DELAY_CYCLES-1];
  assign in_pslverr  = delay_pslverr[DELAY_CYCLES-1];*/
  

endmodule
