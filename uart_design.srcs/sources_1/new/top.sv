`timescale 1ns / 1ps

module top (
    input wire USER_SI570_CLOCK_P,
    input wire USER_SI570_CLOCK_N,
    input wire USB_UART_TX,  // TX from FTDI => RX for FPGA
    output wire USB_UART_RX  // RX to FTDI  => TX from FPGA
);

  wire       w_clk_50MHz;

  // UART signals
  wire [7:0] w_uart_rx_data;
  wire       w_uart_rx_dv;
  reg        r_uart_tx_dv = 1'b0;
  reg  [7:0] r_uart_tx_data = 8'd0;
  wire       w_tx_busy;

  // FIFO signals
  wire [7:0] w_fifo_dout;
  wire       w_fifo_full;
  wire       w_fifo_empty;
  wire       w_wr_rst_busy;
  wire       w_rd_rst_busy;
  reg        r_fifo_rd_en = 1'b0;

  // --- Power-On Reset Generator for FIFO ---
  // Vivado FIFOs require an active-high reset to initialize properly.
  reg  [3:0] r_rst_cnt = 4'hF;
  wire       w_sys_rst = (r_rst_cnt != 0);

  always @(posedge w_clk_50MHz) begin
    if (r_rst_cnt != 0) r_rst_cnt <= r_rst_cnt - 1'b1;
  end

  // PLL / clock wizard instance
  clk_wiz_0 pll_50MHz_inst (
      .clk_in1_p(USER_SI570_CLOCK_P),
      .clk_in1_n(USER_SI570_CLOCK_N),
      .clk_out1 (w_clk_50MHz)
  );

  // UART receiver
  uart_rx #(
      .G_CLK_FREQ(50000000),
      .G_BAUDRATE(115200)
  ) uart_receiver (
      .i_clk         (w_clk_50MHz),
      .i_uart_rx     (USB_UART_TX),
      .o_uart_rx_data(w_uart_rx_data),
      .o_uart_rx_dv  (w_uart_rx_dv)
  );

  // UART transmitter
  uart_tx #(
      .G_CLK_FREQ(50000000),
      .G_BAUDRATE(115200)
  ) uart_transmitter (
      .i_clk      (w_clk_50MHz),
      .i_tx_dv    (r_uart_tx_dv),
      .i_tx_data  (r_uart_tx_data),
      .o_tx_serial(USB_UART_RX),
      .o_tx_busy  (w_tx_busy)
  );
  // --- The FIFO ---
  // The Producer (uart_rx) writes directly into the FIFO
  uart_fifo fifo (
      .clk        (w_clk_50MHz),
      .srst       (w_sys_rst),
      .din        (w_uart_rx_data),
      .wr_en      (w_uart_rx_dv & ~w_wr_rst_busy),  // Only write if valid and not resetting
      .rd_en      (r_fifo_rd_en),
      .dout       (w_fifo_dout),
      .full       (w_fifo_full),
      .empty      (w_fifo_empty),
      .wr_rst_busy(w_wr_rst_busy),
      .rd_rst_busy(w_rd_rst_busy)
  );

  // --- The Consumer (FIFO to UART TX FSM) ---
  localparam [1:0] TX_IDLE = 2'd0, TX_POP = 2'd1, TX_SEND = 2'd2;
  reg [1:0] r_tx_state = TX_IDLE;

  always @(posedge w_clk_50MHz) begin
    if (w_sys_rst) begin
      r_tx_state   <= TX_IDLE;
      r_fifo_rd_en <= 1'b0;
      r_uart_tx_dv <= 1'b0;
    end else begin
      case (r_tx_state)
        TX_IDLE: begin
          r_uart_tx_dv <= 1'b0;
          r_fifo_rd_en <= 1'b0;
          // If FIFO has data, TX is not busy, and FIFO is out of reset
          if (!w_fifo_empty && !w_tx_busy && !w_rd_rst_busy) begin
            r_fifo_rd_en <= 1'b1;  // Pulse read enable
            r_tx_state   <= TX_POP;
          end
        end

        TX_POP: begin
          r_fifo_rd_en <= 1'b0;
          r_tx_state   <= TX_SEND;  // Wait 1 cycle for standard FIFO latency
        end

        TX_SEND: begin
          r_uart_tx_data <= w_fifo_dout;  // Latch data from FIFO
          r_uart_tx_dv   <= 1'b1;  // Tell UART TX to fire
          r_tx_state     <= TX_IDLE;
        end
      endcase
    end
  end


endmodule
