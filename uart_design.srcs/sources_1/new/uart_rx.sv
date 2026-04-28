`timescale 1ns / 1ps

module uart_rx #(
    parameter integer G_CLK_FREQ = 156250000,
    parameter integer G_BAUDRATE = 115200
)(
    input  wire        i_clk,
    input  wire        i_reset,
    input  wire        i_uart_rx,
    output reg  [7:0]  o_uart_rx_data,
    output reg         o_uart_rx_dv
);

    // -----------------------------------------------------------------
    // 2-flop metastability synchroniser for the async RX line
    // -----------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg r_rx_meta = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg r_rx_sync = 1'b1;

    always @(posedge i_clk) begin
        if (i_reset) begin
            r_rx_meta <= 1'b1;   // idle state of UART line is high
            r_rx_sync <= 1'b1;
        end else begin
            r_rx_meta <= i_uart_rx;
            r_rx_sync <= r_rx_meta;
        end
    end

    // -----------------------------------------------------------------
    // FSM states
    // -----------------------------------------------------------------
    localparam [1:0]
        IDLE      = 2'd0,
        START_BIT = 2'd1,
        DATA_BITS = 2'd2,
        STOP_BIT  = 2'd3;

    reg [1:0] r_state = IDLE;

    // Timing parameters
    localparam integer R_CLOCKS_PER_BIT   = G_CLK_FREQ / G_BAUDRATE;
    localparam integer R_MIDDLE_BIT_COUNT = R_CLOCKS_PER_BIT / 2;

    integer   r_clk_count     = 0;
    reg [2:0] r_rx_data_index = 3'd0;

    // -----------------------------------------------------------------
    // Clock counter — only runs outside IDLE
    // -----------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_reset) begin
            r_clk_count <= 0;
        end else begin
            if (r_state != IDLE) begin
                if (r_clk_count < R_CLOCKS_PER_BIT - 1)
                    r_clk_count <= r_clk_count + 1;
                else
                    r_clk_count <= 0;
            end
        end
    end

    // -----------------------------------------------------------------
    // RX FSM — uses r_rx_sync (synchronised line) instead of raw pin
    // -----------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_reset) begin
            r_state         <= IDLE;
            r_rx_data_index <= 3'd0;
            o_uart_rx_data  <= 8'h00;
            o_uart_rx_dv    <= 1'b0;
        end else begin
            case (r_state)
                IDLE: begin
                    o_uart_rx_dv <= 1'b0;
                    if (r_rx_sync == 1'b0)       // start bit detected
                        r_state <= START_BIT;
                end

                START_BIT: begin
                    // Verify line is still low at mid-bit; bail if glitch
                    if (r_clk_count == R_MIDDLE_BIT_COUNT) begin
                        if (r_rx_sync == 1'b1)
                            r_state <= IDLE;       // glitch — abort
                    end else if (r_clk_count == R_CLOCKS_PER_BIT - 1) begin
                        r_state <= DATA_BITS;
                    end
                end

                DATA_BITS: begin
                    o_uart_rx_dv <= 1'b0;
                    if (r_clk_count == R_MIDDLE_BIT_COUNT) begin
                        o_uart_rx_data[r_rx_data_index] <= r_rx_sync;
                    end else if (r_clk_count == R_CLOCKS_PER_BIT - 1) begin
                        if (r_rx_data_index == 3'd7) begin
                            r_rx_data_index <= 3'd0;
                            r_state         <= STOP_BIT;
                        end else begin
                            r_rx_data_index <= r_rx_data_index + 1'b1;
                        end
                    end
                end

                STOP_BIT: begin
                    if (r_clk_count == R_MIDDLE_BIT_COUNT) begin
                        if (r_rx_sync == 1'b0) begin   // framing error
                            r_state      <= IDLE;
                            o_uart_rx_dv <= 1'b0;
                        end
                    end else if (r_clk_count == R_CLOCKS_PER_BIT - 1) begin
                        r_state      <= IDLE;
                        o_uart_rx_dv <= 1'b1;          // valid byte ready
                    end
                end
            endcase
        end
    end

endmodule