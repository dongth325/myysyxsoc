module ps2_top_apb(
  // APB Bus Interface
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

  // PS/2 Keyboard Interface
  input         ps2_clk,
  input         ps2_data
);

  //================================================================
  // 1. APB Interface Logic
  //================================================================
  assign in_pready  = 1'b1; // Zero wait-state slave
  assign in_pslverr = 1'b0; // No errors
  
  wire read_strobe = in_psel && in_penable && !in_pwrite && (in_paddr[2:0] == 3'b000);

  //================================================================
  // 2. Clock Domain Crossing and Edge Detection
  //================================================================
  reg [2:0] ps2_clk_sync;
  reg [2:0] ps2_data_sync;

  always @(posedge clock) begin
    ps2_clk_sync  <= {ps2_clk_sync[1:0], ps2_clk};
    ps2_data_sync <= {ps2_data_sync[1:0], ps2_data};
  end

  wire ps2_data_synced = ps2_data_sync[1];
  wire ps2_clk_falling_edge = ps2_clk_sync[2] & ~ps2_clk_sync[1];

  //================================================================
  // 3. PS/2 Frame Receiver FSM and Data Register
  //================================================================
  localparam S_IDLE = 2'b00;
  localparam S_RECV = 2'b01;
  localparam S_DONE = 2'b10;

  reg [1:0] state;
  reg [3:0] bit_count;
  reg [7:0] shift_reg;
  
  reg [7:0] scancode_reg;
  reg       scancode_valid;
  
  always @(posedge clock) begin
    if (reset) begin
      state          <= S_IDLE;
      bit_count      <= 4'd0;
      shift_reg      <= 8'd0;
      scancode_reg   <= 8'd0;
      scancode_valid <= 1'b0;
    end else begin
      // Default assignments
      if (state == S_DONE) begin
        state <= S_IDLE;
      end

      /* verilator lint_off CASEINCOMPLETE */
      case (state)
        S_IDLE: begin
          if (ps2_clk_falling_edge && ~ps2_data_synced) begin // Start bit detected
            state     <= S_RECV;
            bit_count <= 4'd1; // Already received start bit, waiting for data bit 0
          end
        end
        S_RECV: begin
          if (ps2_clk_falling_edge) begin
            if (bit_count < 9) begin // 8 data bits
              shift_reg <= {ps2_data_synced, shift_reg[7:1]};
              bit_count <= bit_count + 1;
            end else begin // All data bits, parity, and stop bit are done
              state <= S_DONE;
            end
          end
        end
        S_DONE: begin
          // Data is valid for one cycle in this state
          state <= S_IDLE;
        end
        default: begin
          // Cover the missing case (2'b11), do nothing or reset to idle
          state <= S_IDLE;
        end
      endcase
      /* verilator lint_on CASEINCOMPLETE */

      // Handle scancode register and valid flag
      if (state == S_DONE) begin // New scancode is ready
        scancode_reg   <= shift_reg;
        scancode_valid <= 1'b1;
      end else if (read_strobe) begin // CPU reads the scancode
        scancode_valid <= 1'b0;
      end
    end
  end

  assign in_prdata = (scancode_valid) ? {24'h0, scancode_reg} : 32'h0;

endmodule

/*module ps2_top_apb(
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

  input         ps2_clk,
  input         ps2_data
);

endmodule*/
