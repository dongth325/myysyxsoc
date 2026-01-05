// ... existing code ...
module vga_top_apb(
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

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

  // 模仿 nvboard/example/vsrc/vga_ctrl.v 的参数
  parameter h_frontporch = 96;
  parameter h_active     = 144; // 这是有效像素区域的起始点
  parameter h_backporch  = 784; // 这是有效像素区域的结束点
  parameter h_total      = 800;

  parameter v_frontporch = 2;
  parameter v_active     = 35;  // 这是有效扫描线的起始点
  parameter v_backporch  = 515; // 这是有效扫描线的结束点
  parameter v_total      = 525;

  // 模仿 nvboard/example/vsrc/top.v 中的 vmem
  localparam H_RES = 640;
  localparam V_RES = 480;
  reg [23:0] vga_mem [0:H_RES*V_RES-1];

  // APB Interface for writing to vga_mem
  assign in_pready  = 1'b1;
  assign in_pslverr = 1'b0;
  assign in_prdata  = 32'h0; // Read not supported

  /* verilator lint_off WIDTHTRUNC */
  wire [19:0] apb_addr = in_paddr[21:2]; // Word-aligned address
  wire        apb_we   = in_psel && in_penable && in_pwrite;

  always @(posedge clock) begin
    if (apb_we && apb_addr < H_RES*V_RES) begin
      vga_mem[apb_addr] <= in_pwdata[23:0]; // Write 24-bit color data
    end
  end
  /* verilator lint_on WIDTHTRUNC */

  // VGA Timing Generation, 模仿 vga_ctrl.v
  reg [9:0] x_cnt;
  reg [9:0] y_cnt;

  always @(posedge clock) begin
    if (reset) begin
      x_cnt <= 1;
      y_cnt <= 1;
    end else begin
      if (x_cnt == h_total) begin
        x_cnt <= 1;
        if (y_cnt == v_total) begin
          y_cnt <= 1;
        end else begin
          y_cnt <= y_cnt + 1;
        end
      end else begin
        x_cnt <= x_cnt + 1;
      end
    end
  end

  // 生成同步信号，模仿 vga_ctrl.v
  assign vga_hsync = (x_cnt > h_frontporch);
  assign vga_vsync = (y_cnt > v_frontporch);

  // 生成有效信号 (blank_n), 模仿 vga_ctrl.v
  wire h_valid = (x_cnt > h_active) & (x_cnt <= h_backporch);
  wire v_valid = (y_cnt > v_active) & (y_cnt <= v_backporch);
  assign vga_valid = h_valid & v_valid;

  // 计算像素坐标, 模仿 vga_ctrl.v
  wire [9:0] h_addr = h_valid ? (x_cnt - 10'd145) : 10'd0;
  wire [9:0] v_addr = v_valid ? (y_cnt - 10'd36) : 10'd0;

  // 从显存读取数据, 模仿 vmem
  wire [23:0] vga_data;
  /* verilator lint_off WIDTHEXPAND */
  assign vga_data = vga_mem[v_addr * H_RES + h_addr];
  /* verilator lint_on WIDTHEXPAND */
  
  // 设置颜色输出, 模仿 vga_ctrl.v
  assign vga_r = vga_data[23:16];
  assign vga_g = vga_data[15:8];
  assign vga_b = vga_data[7:0];

endmodule
// ... existing code ...







/*module vga_top_apb(
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

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

endmodule*/
