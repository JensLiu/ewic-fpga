// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2023.2.2 (lin64) Build 4126759 Thu Feb  8 23:52:05 MST 2024
// Date        : Thu Mar 19 16:49:19 2026
// Host        : hp-de-jens running 64-bit unknown
// Command     : write_verilog -force -mode synth_stub
//               /home/jens/Documents/academic/n3cat/vivado_projects/uart_design/uart_design.gen/sources_1/ip/uart_fifo/uart_fifo_stub.v
// Design      : uart_fifo
// Purpose     : Stub declaration of top-level module interface
// Device      : xcu280-fsvh2892-2L-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "fifo_generator_v13_2_9,Vivado 2023.2.2" *)
module uart_fifo(clk, srst, din, wr_en, rd_en, dout, full, empty, 
  wr_rst_busy, rd_rst_busy)
/* synthesis syn_black_box black_box_pad_pin="srst,din[7:0],wr_en,rd_en,dout[7:0],full,empty,wr_rst_busy,rd_rst_busy" */
/* synthesis syn_force_seq_prim="clk" */;
  input clk /* synthesis syn_isclock = 1 */;
  input srst;
  input [7:0]din;
  input wr_en;
  input rd_en;
  output [7:0]dout;
  output full;
  output empty;
  output wr_rst_busy;
  output rd_rst_busy;
endmodule
