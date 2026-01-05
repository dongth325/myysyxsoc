module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output reg miso
);
  // 接收和发送移位寄存器
  reg [7:0] rx_shift_reg;
  reg [7:0] tx_shift_reg;
  
  // 位计数器 (0-7)
  reg [2:0] bit_count;
  
  // 状态标志
  reg data_received;
  
  // 复位和状态管理 - 统一在SCK上升沿处理
  always @(posedge sck or posedge ss) begin
    if (ss) begin
      // SS无效时(高电平)异步复位
      bit_count <= 3'b000;
      data_received <= 1'b0;
      rx_shift_reg <= 8'h0;
      tx_shift_reg <= 8'h0;
      miso <= 1'b1;
    end
    else if (!data_received) begin
      // 接收模式 - 在SCK上升沿采样MOSI
      rx_shift_reg <= {rx_shift_reg[6:0], mosi};
      bit_count <= bit_count + 1'b1;
      
      // 收到完整8位数据后进行位翻转
      if (bit_count == 3'b111) begin
        data_received <= 1'b1;
        // 执行位翻转操作
        tx_shift_reg <= {
          mosi,
          rx_shift_reg[0],  // 原bit0 → 新bit7
          rx_shift_reg[1],  // 原bit1 → 新bit6
          rx_shift_reg[2],  // 原bit2 → 新bit5
          rx_shift_reg[3],  // 原bit3 → 新bit4
          rx_shift_reg[4],  // 原bit4 → 新bit3
          rx_shift_reg[5],  // 原bit5 → 新bit2
          rx_shift_reg[6]  // 原bit6 → 新bit1
            // 原bit7 → 新bit0
        };
        
        // 立即输出第一位
        miso <= rx_shift_reg[0];
        bit_count <= 3'b000;  // 
      end
    end 
    else if (data_received) begin
      // 发送模式 - 在SCK上升沿更新MISO
      miso <= tx_shift_reg[bit_count];
      bit_count <= bit_count + 1'b1;
      
      // 如果发送完8位，重置为接收模式
      if (bit_count == 3'b111) begin
        data_received <= 1'b0;
        bit_count <= 3'b000;
      end
    end
  end



  /*总体数据传输逻辑，最开始是12345678
                   从master高位开始 一个一个传给slave rx shift reg的低位，  1.2.3.。。。。12345678
                   卡到倒数第二位（具体细节如上）的时候反转为  87654321，并且将低位到高位开始传输，
                   最开始的1,存入spi master的rx寄存器的高位值，也就是从1,2...345678
我设置的lsb为0,也就是高位传输

                   总体来说 作为spi的master 比如传输八位数据，通道就是16位 len=charlen=16
                   最开始将master数据移动到通道的高位写入，比如输入87,得到最开始data=00008700
                   也就是比如16位通道的12345678 00000000
                   传输的时候从1到8传输，最后得到的数据是 从低8位的高位开始，比如说xxxxxxxx 12.。。。。。。8，其中前八位在bitrev被赋值
                   为1,因为规定miso不工作时赋值为1,最后在程序中对返回结果只取到后八位就行。



*/
                   // 初始状态
  initial begin
    miso = 1'b1;
    bit_count = 3'b000;
    data_received = 1'b0;
    rx_shift_reg = 8'h0;
    tx_shift_reg = 8'h0;
  end
endmodule