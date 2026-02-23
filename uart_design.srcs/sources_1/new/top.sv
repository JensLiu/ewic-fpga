`timescale 1ns / 1ps

module top (
    input  wire USER_SI570_CLOCK_P,
    input  wire USER_SI570_CLOCK_N,
    input  wire USB_UART_TX,  // TX from FTDI => RX for FPGA
    output wire USB_UART_RX   // RX to FTDI  => TX from FPGA
);

    // Top-level FSM
    localparam [1:0]
        IDLE = 2'd0,
        CALC = 2'd1,
        SEND = 2'd2;

    reg [1:0] r_state = IDLE;

    wire       w_clk_50MHz;

    wire [7:0] w_uart_rx_data;
    wire       w_uart_rx_dv;
    reg  [7:0] r_uart_rx_data;
    reg        r_uart_rx_dv = 1'b0;

    reg        r_uart_tx_dv   = 1'b0;
    reg  [7:0] r_uart_tx_data = 8'd0;

    // PLL / clock wizard instance
    clk_wiz_0 pll_50MHz_inst (
        .clk_in1_p (USER_SI570_CLOCK_P),
        .clk_in1_n (USER_SI570_CLOCK_N),
        .clk_out1  (w_clk_50MHz)
    );

    // UART transmitter
    uart_tx #(
        .G_CLK_FREQ(50000000),
        .G_BAUDRATE(115200)
    ) uart_transmitter (
        .i_clk      (w_clk_50MHz),
        .i_tx_dv    (r_uart_tx_dv),
        .i_tx_data  (r_uart_tx_data),
        .o_tx_serial(USB_UART_RX)
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

    // Register received UART data and data-valid for use in the FSM
    always @(posedge w_clk_50MHz) begin
        r_uart_rx_data <= w_uart_rx_data;
        r_uart_rx_dv   <= w_uart_rx_dv;
    end

     always @(posedge w_clk_50MHz) begin : Echo
         case (r_state)
            IDLE: begin
                 r_uart_tx_dv <= 1'b0;
                 if (r_uart_rx_dv == 1'b1) begin
                     r_uart_tx_data <= r_uart_rx_data;
                     r_state        <= CALC;
                 end
             end

             CALC: begin
                 // One-cycle calc state (matches VHDL structure)
                 r_state <= SEND;
             end

             SEND: begin
                 r_uart_tx_dv <= 1'b1;
                 r_state      <= IDLE;
             end
         endcase
     end

//    // "Hello World\r\n" message ROM - synthesizable function
//    localparam integer MSG_LEN = 13;
//    function [7:0] get_msg_char;
//        input [3:0] idx;
//        begin
//            case (idx)
//                4'd0:  get_msg_char = "H";
//                4'd1:  get_msg_char = "e";
//                4'd2:  get_msg_char = "l";
//                4'd3:  get_msg_char = "l";
//                4'd4:  get_msg_char = "o";
//                4'd5:  get_msg_char = " ";
//                4'd6:  get_msg_char = "W";
//                4'd7:  get_msg_char = "o";
//                4'd8:  get_msg_char = "r";
//                4'd9:  get_msg_char = "l";
//                4'd10: get_msg_char = "d";
//                4'd11: get_msg_char = "\r";
//                4'd12: get_msg_char = "\n";
//                default: get_msg_char = " ";
//            endcase
//        end
//    endfunction

//    // Simple transmitter FSM to send message repeatedly
//    localparam [2:0]
//        TX_IDLE = 3'd0,
//        TX_LOAD = 3'd1,
//        TX_SEND = 3'd2,
//        TX_WAIT = 3'd3;

//    reg [2:0]  tx_state    = TX_IDLE;
//    reg [$clog2(MSG_LEN)-1:0] msg_idx = 0;

//    // Wait long enough for one full character to be sent before sending next
//    // UART TX takes: 1 start bit + 8 data bits + 1 stop bit = 10 bit periods
//    // Each bit period = G_CLK_FREQ / G_BAUDRATE = 50000000 / 115200 = 434 clocks
//    // Total for one character = 10 * 434 = 4340 clocks
//    // Add extra margin (100%) to ensure UART TX fully completes and returns to IDLE
//    localparam integer BIT_CLKS  = 50000000 / 115200;  // 434 clocks per bit
//    localparam integer CHAR_CLKS = BIT_CLKS * 20;      // 20 bit periods = 2x margin for safety
//    reg [31:0] wait_cnt = 0;

//    always @(posedge w_clk_50MHz) begin
//        case (tx_state)
//            TX_IDLE: begin
//                r_uart_tx_dv <= 1'b0;
//                wait_cnt <= 0;
//                // Load next character to send
//                r_uart_tx_data <= get_msg_char(msg_idx);
//                tx_state <= TX_LOAD;
//            end

//            TX_LOAD: begin
//                // Keep tx_dv low for at least one cycle to ensure edge detection works
//                r_uart_tx_dv <= 1'b0;
//                tx_state <= TX_SEND;
//            end

//            TX_SEND: begin
//                // One-cycle pulse on i_tx_dv to start uart_tx (rising edge detection)
//                r_uart_tx_dv <= 1'b1;
//                tx_state <= TX_WAIT;
//            end

//            TX_WAIT: begin
//                // Deassert tx_dv immediately - uart_tx has already latched the data
//                r_uart_tx_dv <= 1'b0;
//                if (wait_cnt >= CHAR_CLKS) begin
//                    // Character transmission complete, advance to next character
//                    if (msg_idx == MSG_LEN-1)
//                        msg_idx <= 0;
//                    else
//                        msg_idx <= msg_idx + 1'b1;
//                    tx_state <= TX_IDLE;  // send next character
//                end else begin
//                    wait_cnt <= wait_cnt + 1'b1;
//                end
//            end
//        endcase
//    end

endmodule
