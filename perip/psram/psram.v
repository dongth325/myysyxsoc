/*module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

  assign dio = 4'bz;

endmodule*/
module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

  // 定义存储阵列 - 16MB (4M x 8bit)
  reg [7:0] mem [0:16*1024*1024-1];
  
  // 内部信号定义
  reg [3:0] dout;
  reg [3:0] doe;  // 数据输出使能
  
  // 三态逻辑实现
  assign dio = |doe ? dout : 4'bz;
  wire [3:0] din = dio;
  
  // 状态机定义
  localparam IDLE = 3'd0;
  localparam CMD = 3'd1;
  localparam ADDR = 3'd2;
  localparam READ_DUMMY = 3'd3;
  localparam READ_DATA = 3'd4;
  localparam WRITE_DATA = 3'd5;
  localparam QPI_MODE = 3'd6;//新增 qpi 模式ddddddddddd
  
  reg [2:0] state = IDLE;
  reg [2:0] next_state = IDLE;
   
  reg qpi_enabled = 1'b0;// qpi 模式使能信号
  
  // 命令和地址寄存器
  reg [7:0] cmd_reg;
  reg [23:0] addr_reg;
  reg [2:0] bit_counter;
  reg [2:0] byte_counter;
  reg [3:0] read_byte_counter;
  reg [3:0] data_buffer;

  reg [2:0] read_bit_counter;  // 用于读取操作的位计数器
reg [23:0] read_addr_reg;    // 用于读取操作的地址寄存器
  
  // 命令定义
  localparam CMD_READ = 8'hEB;  // Quad IO Read
  localparam CMD_WRITE = 8'h38; // Quad IO Write
  localparam CMD_ENTER_QPI = 8'h35; // qpi 模式命令
  
  // 状态转换逻辑
  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end
  
  // 命令和地址接收逻辑
  always @(posedge sck) begin
    if (!ce_n) begin
      case (state)
        IDLE: begin
          // 初始化
                // 在IDLE状态下提前接收第一个命令位
          if(!qpi_enabled) begin
          cmd_reg <= {cmd_reg[6:0], din[0]};
          
          end else begin
          cmd_reg <= {cmd_reg[3:0], din};
          end





          bit_counter <= 1;
          byte_counter <= 0;
        
          doe <= 4'b0000;//不起作用，还是要在读取的时候清零 read data
        end
        
        CMD: begin
          // 接收命令 - 串行模式，只使用dio[0]
         if(!qpi_enabled) begin

          cmd_reg <= {cmd_reg[6:0], din[0]};
          bit_counter <= bit_counter + 1;
        
          if (bit_counter == 3'd7) begin
          
            bit_counter <= 0;
            byte_counter <= 0;
            addr_reg <= 24'h0;  // 防止读写寄存器重叠，刷新一下
          end
         end else begin
          cmd_reg <= {cmd_reg[3:0], din};
          bit_counter <= bit_counter + 1;
        
          if (bit_counter == 3'd1) begin
          
            bit_counter <= 0;
            byte_counter <= 0;
            addr_reg <= 24'h0;  // 防止读写寄存器重叠，刷新一下
          end
         end
        end
        
        ADDR: begin
          // 恢复使用移位方法接收地址，但确保正确处理
          addr_reg <= {addr_reg[19:0], din};
          byte_counter <= byte_counter + 1;

          
          // 打印每次接收到的地址部分
     
          if (byte_counter == 3'd5) begin
            byte_counter <= 0;
            bit_counter <= 0;
           
          end

           
          if(cmd_reg == CMD_ENTER_QPI) begin//卡在addr的最后一个周期对qpi enabled赋值
            qpi_enabled <= 1'b1;
          end


        end
        
        READ_DUMMY: begin
          // 延迟周期
          bit_counter <= bit_counter + 1;
          cmd_reg <= 8'h0;//在状态已经转入后清0,不能在idle中，因为要读取第一个数据
          if (bit_counter == 3'd5) begin
            bit_counter <= 0;
          end
        end
        
        READ_DATA: begin
          // 不需要在读取时接收数据
           // 在上升沿处理读取逻辑
          if(read_byte_counter < 4) begin
            

          
          
          doe <= 4'b1111;  // 启用数据输出
        
          // 根据bit_counter决定输出数据的高位或低位
          case (bit_counter)
            0: begin 
              dout <= mem[addr_reg][7:4];  
             
              bit_counter <= 1;
            end
            1: begin
              dout <= mem[addr_reg][3:0];  
          
              bit_counter <= 0;
              addr_reg <= addr_reg + 1;  // 读取完一个字节后递增地址

              read_byte_counter <= read_byte_counter + 1;
              
            end
            default: begin
              //bit_counter <= 0;//

             dout <= 4'b0000;
          end
          endcase
          end  else begin//防止dio过多读取mem值，导致读取错误，给下一次的cmdreg赋值错误
            dout <= 4'b0000;
            read_byte_counter <= 0;
            bit_counter <= 0;
            doe <= 4'b0000;//最后一个周期会执行到这里，表明read data结束，会对doe清0,要不然dio在最开始会是dout值，导致下一次cmdreg会出错
          end
      end
        
        WRITE_DATA: begin
          // 接收写入数据
          cmd_reg <= 8'h0;//在状态已经转入后清0,不能在idle中，因为要读取第一个数据
          data_buffer <= din;
          bit_counter <= bit_counter + 1;
          //写入的时候把最先来的放到高位，后来的放到低位，读取的时候则是从低位开始读取，先低位后高位，接着addr++到下一个字节
          //因为控制器里对line的赋值是高位低位相反传入的，这样再反一次可以正确取出写入的东西
          if (bit_counter == 3'd1) begin
            // 完成一个字节的接收，写入存储器
            mem[addr_reg] <= {data_buffer, din};
           
            addr_reg <= addr_reg + 1;
            bit_counter <= 0;
          end
          
        end
      
      QPI_MODE: begin //qpi模式
      //没什么用
      bit_counter <= 0;
      byte_counter <= 0;
      end




        default: begin
          // 处理未明确定义的状态
          bit_counter <= 0;
          byte_counter <= 0;
        end
      endcase
    end 
   
  end
  

  
  // 组合逻辑 - 状态转换
  always @(*) begin
    
    next_state = state;//新加，防止锁存器
    


    if (!ce_n) begin
      case (state)
        IDLE: begin
          next_state = CMD;
        end
        
        CMD: begin
          if (!qpi_enabled && bit_counter == 3'd7) begin   //对qpi和普通模式的计数器调整
            next_state = ADDR;
          end else if (qpi_enabled && bit_counter == 3'b1) begin
            next_state = ADDR;
          end
          
          
           else begin
            next_state = CMD;
          end
        end
        
        ADDR: begin
           /* if(state != QPI_MODE) begin//ddddddddddddddddddddddddd
            if(cmd_reg == CMD_ENTER_QPI)   //增加对qpi模式的判断
            next_state = QPI_MODE;
            

            end//ddddddddddddddddddddddd*/


          if (byte_counter == 3'd5) begin
           if (cmd_reg == CMD_READ)
              next_state = READ_DUMMY;
            else if (cmd_reg == CMD_WRITE)
              next_state = WRITE_DATA;
            else
              next_state = IDLE;
          end else begin
            next_state = ADDR;
          end
        end
        
        READ_DUMMY: begin
          if (bit_counter == 3'd5) begin
            next_state = READ_DATA;
          end else begin
            next_state = READ_DUMMY;
          end
        end
        
        READ_DATA: begin
          next_state = READ_DATA;
          
          if (ce_n)
            next_state = IDLE;
        end
        
        WRITE_DATA: begin
          next_state = WRITE_DATA;
          
          if (ce_n)
            next_state = IDLE;
        end
        QPI_MODE: begin
          //没什么用
        next_state = IDLE;
        end
        
        default:
          next_state = IDLE;

          
      endcase

    end
    
    
     else begin
      next_state = IDLE;
    end
  end



endmodule