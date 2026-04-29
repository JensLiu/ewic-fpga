`timescale 1ns / 1ps

// Protocol engine — FPGA side.
//
//   S_UNINIT       Sends OP_POLL every POLL_PERIOD cycles until OP_READY arrives.
//   S_IDLE         SDR is in RX mode. Routes incoming OP_DATA to core.
//                  On core write request: negotiates TX mode.
//   S_WAIT_ACK_TX  Sent OP_REQ_TX, waiting for OP_ACK_TX.
//   S_TX_STREAMING Sending OP_DATA packets from core to SDR.
//   S_TX_PAUSED    Received OP_PAUSE from SDR; holding until OP_RESUME.
//   S_WAIT_ACK_RX  Sent OP_END_TX, waiting for OP_ACK_RX.
//   S_RX_STREAMING Forwarding OP_DATA from SDR to core.

module sdr_ctrl_protocol_engine
  import pkg_sdr_ctrl_protocol::*;
#(
    parameter int unsigned POLL_PERIOD = 1000
) (
    input logic clk,
    input logic rst_n,
    // core_sdr interface (with test_core)
    input  logic        core_wr_valid,
    output logic        core_wr_ready,
    input  logic [31:0] core_wr_data,
    input  logic [7:0]  core_wr_len,
    output logic        core_rd_valid,
    input  logic        core_rd_ready,
    output logic [31:0] core_rd_data,
    output logic [7:0]  core_rd_len,
    // req: FPGA → SDR
    output logic      req_valid,
    input  logic      req_ready,
    output protocol_t req_data,
    // rsp: SDR → FPGA
    input  logic      rsp_valid,
    output logic      rsp_ready,
    input  protocol_t rsp_data
);

  if (MAX_PAYLOAD_BYTES > 255) begin : gen_payload_size_check
    $error("MAX_PAYLOAD_BYTES=%0d exceeds 8-bit len field", MAX_PAYLOAD_BYTES);
  end

  typedef enum logic [2:0] {
    S_UNINIT,
    S_IDLE,
    S_WAIT_ACK_TX,
    S_TX_STREAMING,
    S_TX_PAUSED,
    S_WAIT_ACK_RX,
    S_RX_STREAMING
  } state_t;

  state_t state, state_n;

  logic [$clog2(POLL_PERIOD)-1:0] poll_cnt, poll_cnt_n;

  logic    rsp_fire, req_fire, core_wr_fire, core_rd_fire;
  opcode_t rsp_op;
  assign rsp_fire     = rsp_valid  && rsp_ready;
  assign rsp_op       = rsp_data.opcode;
  assign req_fire     = req_valid  && req_ready;
  assign core_wr_fire = core_wr_valid && core_wr_ready;
  assign core_rd_fire = core_rd_valid && core_rd_ready;

  function automatic protocol_t ctrl_pkt(input opcode_t op);
    ctrl_pkt.opcode  = op;
    ctrl_pkt.len     = 8'h00;
    ctrl_pkt.payload = '0;
  endfunction

  always_comb begin
    state_n       = state;
    poll_cnt_n    = poll_cnt;
    req_valid     = 0;
    req_data      = ctrl_pkt(OP_POLL);
    rsp_ready     = 0;
    core_wr_ready = 0;
    core_rd_valid = 0;
    core_rd_data  = '0;
    core_rd_len   = '0;

    case (state)

      S_UNINIT: begin
        rsp_ready = 1;
        if (rsp_fire && rsp_op == OP_READY) begin
          state_n = S_IDLE;
        end else if (poll_cnt == 0) begin
          req_valid  = 1;
          req_data   = ctrl_pkt(OP_POLL);
          poll_cnt_n = ($clog2(POLL_PERIOD))'(POLL_PERIOD - 1);
        end else begin
          poll_cnt_n = poll_cnt - 1;
        end
      end

      S_IDLE: begin
        rsp_ready = 1;
        if (core_wr_valid) begin
          req_valid = 1;
          req_data  = ctrl_pkt(OP_REQ_TX);
          if (req_fire)
            state_n = S_WAIT_ACK_TX;
        end else if (rsp_fire && rsp_op == OP_DATA) begin
          core_rd_valid = 1;
          core_rd_data  = rsp_data.payload[$bits(core_rd_data)-1:0];
          core_rd_len   = rsp_data.len;
          if (core_rd_fire)
            state_n = S_RX_STREAMING;
        end
      end

      S_WAIT_ACK_TX: begin
        rsp_ready = 1;
        if (rsp_fire && rsp_op == OP_ACK_TX)
          state_n = S_TX_STREAMING;
      end

      S_TX_STREAMING: begin
        rsp_ready = 1;
        if (rsp_fire && rsp_op == OP_PAUSE) begin
          state_n = S_TX_PAUSED;
        end else if (core_wr_valid) begin
          assert (core_wr_len <= 8'(MAX_PAYLOAD_BYTES))
            else $fatal(1, "core_wr_len=%0d exceeds MAX_PAYLOAD_BYTES=%0d",
                        core_wr_len, MAX_PAYLOAD_BYTES);
          req_valid        = 1;
          req_data.opcode  = OP_DATA;
          req_data.len     = core_wr_len;
          req_data.payload = {{($bits(req_data.payload)-$bits(core_wr_data)){1'b0}}, core_wr_data};
          if (req_fire)
            core_wr_ready = 1;
        end else begin
          req_valid = 1;
          req_data  = ctrl_pkt(OP_END_TX);
          if (req_fire)
            state_n = S_WAIT_ACK_RX;
        end
      end

      S_TX_PAUSED: begin
        rsp_ready = 1;
        if (rsp_fire && rsp_op == OP_RESUME)
          state_n = S_TX_STREAMING;
      end

      S_WAIT_ACK_RX: begin
        rsp_ready = 1;
        if (rsp_fire && rsp_op == OP_ACK_RX)
          state_n = S_IDLE;
      end

      S_RX_STREAMING: begin
        rsp_ready = core_rd_ready;
        if (rsp_fire && rsp_op == OP_DATA) begin
          core_rd_valid = 1;
          core_rd_data  = rsp_data.payload[$bits(core_rd_data)-1:0];
          core_rd_len   = rsp_data.len;
        end else if (!rsp_valid) begin
          state_n = S_IDLE;
        end
      end

      default: $fatal(1, "Unreachable sdr_ctrl_protocol_engine state");

    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= S_UNINIT;
      poll_cnt <= '0;
    end else begin
      state    <= state_n;
      poll_cnt <= poll_cnt_n;
    end
  end

endmodule
