`timescale 1ns / 1ps

module top (
    input wire USER_SI570_CLOCK_P,
    input wire USER_SI570_CLOCK_N,
    input wire USB_UART_TX,  // TX from FTDI => RX for FPGA
    output wire USB_UART_RX  // RX to FTDI  => TX from FPGA
);

  wire w_clk_50MHz;

  // UART signals
  wire [7:0] w_uart_rx_data;
  wire       w_uart_rx_dv;
  reg        r_uart_tx_dv   = 1'b0;
  reg  [7:0] r_uart_tx_data = 8'd0;
  wire       w_tx_busy;

  // Power-On Reset — Vivado FIFOs require an active-high reset on init.
  reg  [3:0] r_rst_cnt = 4'hF;
  wire       w_sys_rst = (r_rst_cnt != 0);

  always @(posedge w_clk_50MHz) begin
    if (r_rst_cnt != 0) r_rst_cnt <= r_rst_cnt - 1'b1;
  end

  // PLL / clock wizard
  clk_wiz_0 pll_50MHz_inst (
      .clk_in1_p(USER_SI570_CLOCK_P),
      .clk_in1_n(USER_SI570_CLOCK_N),
      .clk_out1 (w_clk_50MHz)
  );

  // UART receiver
  uart_rx #(
      .G_CLK_FREQ(50000000),
      .G_BAUDRATE (115200)
  ) uart_receiver (
      .i_clk         (w_clk_50MHz),
      .i_uart_rx     (USB_UART_TX),
      .o_uart_rx_data(w_uart_rx_data),
      .o_uart_rx_dv  (w_uart_rx_dv)
  );

  // UART transmitter
  uart_tx #(
      .G_CLK_FREQ(50000000),
      .G_BAUDRATE (115200)
  ) uart_transmitter (
      .i_clk      (w_clk_50MHz),
      .i_tx_dv    (r_uart_tx_dv),
      .i_tx_data  (r_uart_tx_data),
      .o_tx_serial(USB_UART_RX),
      .o_tx_busy  (w_tx_busy)
  );

  // -----------------------------------------------------------------------
  // RX FIFO  —  UART RX (producer) → application logic (consumer)
  // -----------------------------------------------------------------------
  wire [7:0] w_rx_fifo_dout;
  wire       w_rx_fifo_full;
  wire       w_rx_fifo_empty;
  wire       w_rx_wr_rst_busy;
  wire       w_rx_rd_rst_busy;
  reg        r_rx_fifo_rd_en = 1'b0;

  uart_fifo rx_fifo (
      .clk        (w_clk_50MHz),
      .srst       (w_sys_rst),
      .din        (w_uart_rx_data),
      .wr_en      (w_uart_rx_dv & ~w_rx_wr_rst_busy),
      .rd_en      (r_rx_fifo_rd_en),
      .dout       (w_rx_fifo_dout),
      .full       (w_rx_fifo_full),
      .empty      (w_rx_fifo_empty),
      .wr_rst_busy(w_rx_wr_rst_busy),
      .rd_rst_busy(w_rx_rd_rst_busy)
  );

  // -----------------------------------------------------------------------
  // TX FIFO  —  application logic (producer) → UART TX (consumer)
  // -----------------------------------------------------------------------
  wire [7:0] w_tx_fifo_dout;
  wire       w_tx_fifo_full;
  wire       w_tx_fifo_empty;
  wire       w_tx_wr_rst_busy;
  wire       w_tx_rd_rst_busy;
  reg  [7:0] r_tx_fifo_din   = 8'd0;
  reg        r_tx_fifo_wr_en = 1'b0;
  reg        r_tx_fifo_rd_en = 1'b0;

  uart_fifo tx_fifo (
      .clk        (w_clk_50MHz),
      .srst       (w_sys_rst),
      .din        (r_tx_fifo_din),
      .wr_en      (r_tx_fifo_wr_en & ~w_tx_wr_rst_busy),
      .rd_en      (r_tx_fifo_rd_en),
      .dout       (w_tx_fifo_dout),
      .full       (w_tx_fifo_full),
      .empty      (w_tx_fifo_empty),
      .wr_rst_busy(w_tx_wr_rst_busy),
      .rd_rst_busy(w_tx_rd_rst_busy)
  );

  // -----------------------------------------------------------------------
  // Echo FSM  —  application logic: RX FIFO → TX FIFO
  // Replace this FSM with your command parser / protocol handler later.
  // -----------------------------------------------------------------------
  localparam [1:0] ECHO_IDLE  = 2'd0,
                   ECHO_POP   = 2'd1,
                   ECHO_WRITE = 2'd2;
  reg [1:0] r_echo_state = ECHO_IDLE;

  always @(posedge w_clk_50MHz) begin
    if (w_sys_rst) begin
      r_echo_state    <= ECHO_IDLE;
      r_rx_fifo_rd_en <= 1'b0;
      r_tx_fifo_wr_en <= 1'b0;
    end else begin
      // Defaults — signals are pulses unless overridden below.
      r_rx_fifo_rd_en <= 1'b0;
      r_tx_fifo_wr_en <= 1'b0;

      case (r_echo_state)
        ECHO_IDLE: begin
          if (!w_rx_fifo_empty && !w_tx_fifo_full &&
              !w_rx_rd_rst_busy && !w_tx_wr_rst_busy) begin
            r_rx_fifo_rd_en <= 1'b1;
            r_echo_state    <= ECHO_POP;
          end
        end

        ECHO_POP: begin
          // One-cycle bubble for FIFO read latency.
          r_echo_state <= ECHO_WRITE;
        end

        ECHO_WRITE: begin
          r_tx_fifo_din   <= w_rx_fifo_dout;
          r_tx_fifo_wr_en <= 1'b1;
          r_echo_state    <= ECHO_IDLE;
        end

        default: r_echo_state <= ECHO_IDLE;
      endcase
    end
  end

  // -----------------------------------------------------------------------
  // TX Consumer FSM  —  TX FIFO → UART TX
  // -----------------------------------------------------------------------
  localparam [1:0] TX_IDLE = 2'd0,
                   TX_POP  = 2'd1,
                   TX_SEND = 2'd2;
  reg [1:0] r_tx_state = TX_IDLE;

  always @(posedge w_clk_50MHz) begin
    if (w_sys_rst) begin
      r_tx_state      <= TX_IDLE;
      r_tx_fifo_rd_en <= 1'b0;
      r_uart_tx_dv    <= 1'b0;
    end else begin
      // Defaults — signals are pulses unless overridden below.
      r_tx_fifo_rd_en <= 1'b0;
      r_uart_tx_dv    <= 1'b0;

      case (r_tx_state)
        TX_IDLE: begin
          if (!w_tx_fifo_empty && !w_tx_busy && !w_tx_rd_rst_busy) begin
            r_tx_fifo_rd_en <= 1'b1;
            r_tx_state      <= TX_POP;
          end
        end

        TX_POP: begin
          // One-cycle bubble for FIFO read latency.
          r_tx_state <= TX_SEND;
        end

        TX_SEND: begin
          r_uart_tx_data <= w_tx_fifo_dout;
          r_uart_tx_dv   <= 1'b1;
          r_tx_state     <= TX_IDLE;
        end

        default: r_tx_state <= TX_IDLE;
      endcase
    end
  end

endmodule
