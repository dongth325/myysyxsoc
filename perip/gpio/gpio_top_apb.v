module gpio_top_apb(
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
  output reg [31:0] in_prdata,
  output        in_pslverr,

  // --- 端口定义保持原始状态，完全不变 ---
  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

  // 地址定义
  localparam LED_REG_ADDR     = 32'h1000_2000;
  localparam SWITCH_REG_ADDR  = 32'h1000_2004;
  localparam SEG_REG_ADDR     = 32'h1000_2008;
  localparam RESERVED_ADDR    = 32'h1000_200C;

  // 内部寄存器
  reg [15:0] led_reg;
  reg [31:0] seg_reg;

  // APB 信号
  assign in_pready  = 1'b1;
  assign in_pslverr = 1'b0;

  // LED 输出
  assign gpio_out = led_reg;

  // 写操作 (包含对 seg_reg 的写入)
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      led_reg <= 16'h0000;
      seg_reg <= 32'h0000_0000;
    end else if (in_psel && in_penable && in_pwrite) begin
      case (in_paddr)
        LED_REG_ADDR: led_reg <= in_pwdata[15:0];
        SEG_REG_ADDR: seg_reg <= in_pwdata;
        default: begin end
      endcase
    end
  end

  // 读操作 (包含对 seg_reg 的读取)
  always @(*) begin
    case (in_paddr)
      LED_REG_ADDR:    in_prdata = {16'h0000, led_reg};
      SWITCH_REG_ADDR: in_prdata = {16'h0000, gpio_in};
      SEG_REG_ADDR:    in_prdata = seg_reg;
      RESERVED_ADDR:   in_prdata = 32'h0000_0000;
      default:         in_prdata = 32'h0000_0000;
    endcase
  end

  // 十六进制到七段数码管编码函数
  // 使用了 example/vsrc/seg.v 中被验证过是正确的编码值
  function [7:0] hex_to_seg;
    input [3:0] hex_digit;
    begin
      case (hex_digit)
        4'h0: hex_to_seg = 8'b11111100; // 0
        4'h1: hex_to_seg = 8'b01100000; // 来自 segs[1]
        4'h2: hex_to_seg = 8'b11011010; // 来自 segs[2]
        4'h3: hex_to_seg = 8'b11110010; // 来自 segs[3]
        4'h4: hex_to_seg = 8'b01100110; // 来自 segs[4]
        4'h5: hex_to_seg = 8'b10110110; // 来自 segs[5]
        4'h6: hex_to_seg = 8'b10111110; // 来自 segs[6]
        4'h7: hex_to_seg = 8'b11100000; // 来自 segs[7]
        // 对于 8-F, 暂时使用标准译码
        4'h8: hex_to_seg = 8'b11111110;

        //8之后的值还不确定是否正确！！
        4'h9: hex_to_seg = 8'b11110110; // 9
        4'hA: hex_to_seg = 8'b11101110; // A
        4'hB: hex_to_seg = 8'b00111110; // b
        4'hC: hex_to_seg = 8'b10011100; // C
        4'hD: hex_to_seg = 8'b01111010; // d
        4'hE: hex_to_seg = 8'b10011110; // E
        4'hF: hex_to_seg = 8'b10001110; // F
        default: hex_to_seg = 8'b00000000;
      endcase
    end
  endfunction

  // --- 最终的、正确的赋值逻辑 ---
  // 将 seg_reg 的值进行译码，并模仿 example/vsrc/seg.v 对输出进行按位取反
  assign gpio_seg_0 = ~hex_to_seg(seg_reg[3:0]);
  assign gpio_seg_1 = ~hex_to_seg(seg_reg[7:4]);
  assign gpio_seg_2 = ~hex_to_seg(seg_reg[11:8]);
  assign gpio_seg_3 = ~hex_to_seg(seg_reg[15:12]);
  assign gpio_seg_4 = ~hex_to_seg(seg_reg[19:16]);
  assign gpio_seg_5 = ~hex_to_seg(seg_reg[23:20]);
  assign gpio_seg_6 = ~hex_to_seg(seg_reg[27:24]);
  assign gpio_seg_7 = ~hex_to_seg(seg_reg[31:28]);

    // --- 新增: 导出 DPI-C 函数以获取开关状态 ---
  // --- 新增: 导出 DPI-C 函数以获取开关状态 (已修正返回值类型) ---
  export "DPI-C" function get_switch_value;
  function int get_switch_value();
    return {16'b0, gpio_in}; // 将16位的gpio_in扩展为32位的int
  endfunction

endmodule
/*module gpio_top_apb(
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
  output reg [31:0] in_prdata,
  output        in_pslverr,

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

  // GPIO控制器的地址定义
  localparam LED_REG_ADDR     = 32'h1000_2000;  // LED控制寄存器
  localparam SWITCH_REG_ADDR  = 32'h1000_2004;  // 拨码开关状态寄存器
  localparam SEG_REG_ADDR     = 32'h1000_2008;  // 数码管控制寄存器
  localparam RESERVED_ADDR    = 32'h1000_200C;  // 保留地址

  // 内部寄存器
  reg [15:0] led_reg;      // LED控制寄存器
  reg [31:0] seg_reg;      // 数码管控制寄存器

  // APB信号 - 固定值，因为GPIO是简单外设
  assign in_pready  = 1'b1;        // 总是准备好
  assign in_pslverr = 1'b0;        // 从不出错

  // GPIO输出直接连接到LED寄存器
  assign gpio_out = led_reg;

  // 写操作：时钟同步
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      led_reg <= 16'h0000;
      seg_reg <= 32'h0000_0000;
    end else if (in_psel && in_penable && in_pwrite) begin
      case (in_paddr)
        LED_REG_ADDR: begin
          led_reg <= in_pwdata[15:0];
        end
        SEG_REG_ADDR: begin
          seg_reg <= in_pwdata;
        end
        // 其他地址不处理，保持当前值
        default: begin
          // 不做任何操作
        end
      endcase
    end
  end

  // 读操作：组合逻辑
  always @(*) begin
    case (in_paddr)
      LED_REG_ADDR: begin
        in_prdata = {16'h0000, led_reg};
      end
      SWITCH_REG_ADDR: begin
        in_prdata = {16'h0000, gpio_in};
      end
      SEG_REG_ADDR: begin
        in_prdata = seg_reg;
      end
      RESERVED_ADDR: begin
        in_prdata = 32'h0000_0000;  // 保留地址返回0
      end
      default: begin
        in_prdata = 32'h0000_0000;  // 无效地址返回0
      end
    endcase
  end

  // 十六进制到七段数码管编码函数
  function [7:0] hex_to_seg;
    input [3:0] hex_digit;
    reg [6:0] segs;
    begin
      case (hex_digit)
        4'h0: segs = 7'b0111111; // 0: ABCDEF
        4'h1: segs = 7'b0000110; // 1: BC
        4'h2: segs = 7'b1011011; // 2: ABDEG
        4'h3: segs = 7'b1001111; // 3: ABCDG
        4'h4: segs = 7'b1100110; // 4: BCFG
        4'h5: segs = 7'b1101101; // 5: ACDFG
        4'h6: segs = 7'b1111101; // 6: ACDEFG
        4'h7: segs = 7'b0000111; // 7: ABC
        4'h8: segs = 7'b1111111; // 8: ABCDEFG
        4'h9: segs = 7'b1101111; // 9: ABCDFG
        4'hA: segs = 7'b1110111; // A: ABCEFG
        4'hB: segs = 7'b1111100; // B: CDEFG
        4'hC: segs = 7'b0111001; // C: ADEF
        4'hD: segs = 7'b1011110; // D: BCDEG
        4'hE: segs = 7'b1111001; // E: ADEFG
        4'hF: segs = 7'b1110001; // F: AEFG
        default: segs = 7'b0000000; // 灭
      endcase
      hex_to_seg = {1'b0, segs}; // {DP, G, F, E, D, C, B, A}
    end
  endfunction

  // 8个数码管输出
  assign gpio_seg_0 = hex_to_seg(seg_reg[3:0]);   // 最低4位
  assign gpio_seg_1 = hex_to_seg(seg_reg[7:4]);   // 次低4位
  assign gpio_seg_2 = hex_to_seg(seg_reg[11:8]);  // ...
  assign gpio_seg_3 = hex_to_seg(seg_reg[15:12]);
  assign gpio_seg_4 = hex_to_seg(seg_reg[19:16]);
  assign gpio_seg_5 = hex_to_seg(seg_reg[23:20]);
  assign gpio_seg_6 = hex_to_seg(seg_reg[27:24]);
  assign gpio_seg_7 = hex_to_seg(seg_reg[31:28]); // 最高4位

endmodule*/



/*module gpio_top_apb(
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

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

endmodule*/
