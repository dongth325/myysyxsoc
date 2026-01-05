/*module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,//13位地址
  input [ 1:0] ba,//2位bank地址
  input [ 1:0] dqm,//数据mask
  inout [15:0] dq//16位数据
);

  assign dq = 16'bz;


endmodule*/
module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  //input [12:0] a,
  input [13:0] a,//字扩展
  input [ 1:0] ba,
  input [ 3:0] dqm,
  inout [31:0] dq
);



// 时钟使能控制
//wire cke_pair0 = cke & ~a[13];
//wire cke_pair1 = cke & a[13];
  // 使用寄存器锁存芯片选择信号
reg chip_select;
  
// 在ACTIVE命令时锁存芯片选择信号
always @(posedge clk) begin
  if (cke && !cs && !ras && cas && we) begin  // ACTIVE命令
    chip_select <= a[13];  // 锁存a[13]
  end
end

// 使用锁存的芯片选择信号
wire cke_pair0 = cke & ~chip_select;
wire cke_pair1 = cke & chip_select;


  

  // 第一对SDRAM芯片 (位扩展)
  sdram_pair pair0 (
    .clk(clk),
    .cke(cke_pair0),
    .cs(cs),
    .ras(ras),
    .cas(cas),
    .we(we),
    .a(a[12:0]),  // 只传递低13位给SDRAM芯片
    .ba(ba),
    .dqm(dqm),
    .dq(dq)
   
  );
  
  // 第二对SDRAM芯片 (位扩展)
  sdram_pair pair1 (
    .clk(clk),
    .cke(cke_pair1),
    .cs(cs),
    .ras(ras),
    .cas(cas),
    .we(we),
    .a(a[12:0]),  // 只传递低13位给SDRAM芯片
    .ba(ba),
    .dqm(dqm),
    .dq(dq)
   
  );

endmodule
module sdram_pair(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 3:0] dqm,
  inout [31:0] dq
  
  
  
);

  // 实例化两个SDRAM芯片
sdram_chip chip0 (
  .clk(clk),
  .cke(cke),
  .cs(cs),
  .ras(ras),
  .cas(cas),
  .we(we),
  .a(a),
  .ba(ba),
  .dqm(dqm[1:0]),
  .dq(dq[15:0])
);

sdram_chip chip1 (
  .clk(clk),
  .cke(cke),
  .cs(cs),
  .ras(ras),
  .cas(cas),
  .we(we),
  .a(a),
  .ba(ba),
  .dqm(dqm[3:2]),
  .dq(dq[31:16])
);

endmodule




module sdram_chip(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,
  inout [15:0] dq
  
);




// 命令定义 - 与控制器保持一致
localparam CMD_W           = 4;            // 命令宽度
localparam CMD_NOP        = 4'b0111;      // 空操作
localparam CMD_ACTIVE     = 4'b0011;      // 激活行
localparam CMD_READ       = 4'b0101;      // 读命令
localparam CMD_WRITE      = 4'b0100;      // 写命令
localparam CMD_PRECHARGE  = 4'b0010;      // 预充电
localparam CMD_REFRESH    = 4'b0001;      // 刷新
localparam CMD_LOAD_MODE  = 4'b0000;      // 加载模式寄存器

  // 内存存储数组 - 4个bank，8192行，256列（注意：实际只使用偶数列）
  reg [15:0] mem_array [3:0][8191:0][255:0];
  
  // 当前活跃的行
  reg [12:0] active_row [3:0];
  reg [3:0] bank_active;
  
  // 行缓冲区
  reg [15:0] row_buffer [3:0][255:0];
  
  // 读写控制信号
  reg read_active;
  reg write_active;
  reg [1:0] active_bank;
  reg [7:0] col_addr;        // 8位列地址
  
  // 数据输出控制
  reg dq_output_enable;
  reg [15:0] dq_output;
  
  // 模式寄存器
  reg [2:0] burst_length_code;  // 突发长度编码
  reg [2:0] cas_latency;        // CAS延迟
  reg [2:0] cas_counter;        // CAS计数器
  reg [7:0] burst_counter;      // 突发计数器  改成8位 to match col addr 
  wire [7:0] burst_max;         // 突发长度    改成8位 to match burst_counter
  assign burst_max = 8'd1;  // 固定突发长度为1 位扩展dddddd
  // 命令解码
  wire [3:0] cmd = {cs, ras, cas, we};
  
  // 双向数据总线控制
  assign dq = dq_output_enable ? dq_output : 16'bz;
  
  // 根据模式寄存器解码突发长度
  assign burst_max = (burst_length_code == 3'b000) ? 8'd1 :        //burst max 固定为2
                    (burst_length_code == 3'b001) ? 8'd2 :
                    (burst_length_code == 3'b010) ? 8'd4 :
                    (burst_length_code == 3'b011) ? 8'd8 : 8'd1;
  
  // 初始化
  initial begin
    bank_active = 4'b0000;
    read_active = 0;
    write_active = 0;
    dq_output_enable = 0;
    cas_counter = 0;
    burst_counter = 0;
  end
  
  // 主状态机
  always @(posedge clk) begin
   // if (cke) begin  //修改为只对active以外的命令有效
   //   case (cmd)
        // ACTIVE命令
    if (cmd == 4'b0011) begin
      
          bank_active[ba] = 1'b1;
          active_row[ba] = a;
          // 将数据从存储单元加载到行缓冲区
          for (integer i = 0; i < 256; i = i + 1) begin
            row_buffer[ba][i] = mem_array[ba][a][i];
          end
       
      end
      if(cmd == 4'b0000) begin
        burst_length_code = a[2:0];    
        cas_latency = a[6:4];          
      end

    if (cke) begin  

      case (cmd)
        // READ命令
        CMD_READ: begin


          if (bank_active[ba]) begin
            read_active = 1'b1;
            write_active = 1'b0;
            active_bank = ba;
            col_addr = a[8:1];  // 使用8位列地址
            burst_counter = 0;
            cas_counter = cas_latency; // 2   read命令重启cas 计数器
            dq_output_enable = 0;
          end
          //读操作cas latency倒计时
          if (read_active && cas_counter > 0) begin
            cas_counter = cas_counter - 1;
            if (cas_counter == 0) begin
              dq_output_enable = 1;
              dq_output = row_buffer[active_bank][col_addr];
              burst_counter = 1;
            end
          end
        
        end
        
        // WRITE命令
        CMD_WRITE: begin
          if (bank_active[ba]) begin
            write_active = 1'b1;
            read_active = 1'b0;
            active_bank = ba;
            col_addr = a[8:1];  // 使用8位列地址
            burst_counter = 1;
            // 写入第一个数据
            if (!dqm[0]) row_buffer[ba][col_addr][7:0] = dq[7:0];
            if (!dqm[1]) row_buffer[ba][col_addr][15:8] = dq[15:8];
            mem_array[ba][active_row[ba]][col_addr] = row_buffer[ba][col_addr];
            write_active = 0;  // 立即完成写入，不等待NOP  位扩展ddddddd
          end
        end
        
 
        
        // LOAD MODE REGISTER命令
      /*  CMD_LOAD_MODE: begin
          burst_length_code = a[2:0];    // 突发长度编码   4bytes               001
          cas_latency = a[6:4];          // CAS延迟       cas latency = 2     010
        end*/
        
        // PRECHARGE和AUTO REFRESH命令 - 简化为NOP
        CMD_PRECHARGE, CMD_REFRESH: begin
          // NOP
        end
        
       //NOP - 处理突发传输  读写数据的第二段
     CMD_NOP: begin
          // 处理读操作的突发传输
          if (read_active && cas_counter == 0) begin
            if (burst_counter < burst_max) begin
              dq_output = row_buffer[active_bank][col_addr + burst_counter];
              burst_counter = burst_counter + 1;
            end else begin
              read_active = 0;
              dq_output_enable = 0;
            end
          end

          //读操作的cas latency倒计时，在read命令-1一次，在nop-1一次然后在这里传出第一次结果，剩下一次在下一周期的上面
          if (read_active && cas_counter > 0) begin
            cas_counter = cas_counter - 1;
            if (cas_counter == 0) begin
              dq_output_enable = 1;
              dq_output = row_buffer[active_bank][col_addr];
              burst_counter = 1;
            end
          end



     


        end

        default: begin
          
        end


      endcase

      end


     

      // CAS延迟计数器
    /*  if (read_active && cas_counter > 0) begin
        cas_counter = cas_counter - 1;
        if (cas_counter == 0) begin
          dq_output_enable = 1;
          dq_output = row_buffer[active_bank][col_addr];
          burst_counter = 1;
        end
      end */


   // end  原本对cke的判断
  end

endmodule