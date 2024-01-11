// Copyright 2023 Barcelona Supercomputing Center (BSC)
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Licensed under the Solderpad Hardware License v 2.1 (the “License”);
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at

// https://solderpad.org/licenses/SHL-2.1/

// Unless required by applicable law or agreed to in writing, any work
// distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations
// under the License.

//
// Juan Miguel de Haro <juan.deharoruiz@bsc.es>
//

interface QueueWrite #(parameter WIDTH = 0);

    logic write;
    logic full;
    logic [WIDTH-1:0] din;

    modport master (output write, input full, output din);
    modport slave (input write, output full, input din);

endinterface

interface QueueRead #(parameter WIDTH = 0);

    logic read;
    logic empty;
    logic [WIDTH-1:0] dout;

    modport master (output read, input empty, input dout);
    modport slave (input read, output empty, output dout);

endinterface

interface AXI4Lite #(parameter WIDTH = 0, parameter ADDR_WIDTH = 0);

    logic arvalid;
    logic arready;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [2:0] arprot;

    logic rvalid;
    logic rready;
    logic [WIDTH-1:0] rdata;
    logic [1:0] rresp;

    logic awvalid;
    logic awready;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [2:0] awprot;

    logic wvalid;
    logic wready;
    logic [WIDTH-1:0] wdata;
    logic [WIDTH/8-1:0] wstrb;

    logic bvalid;
    logic bready;
    logic [1:0] bresp;

    modport master(output arvalid, input arready, output araddr, output arprot, input rvalid, output rready, input rdata, input rresp,
                   output awvalid, input awready, output awaddr, output awprot, output wvalid, input wready, output wdata, output wstrb,
                   input bvalid, output bready, input bresp);
    modport slave(input arvalid, output arready, input araddr, input arprot, output rvalid, input rready, output rdata, output rresp,
                  input awvalid, output awready, input awaddr, input awprot, input wvalid, output wready, input wdata, input wstrb,
                  output bvalid, input bready, output bresp);

endinterface

interface DebugCounter #(parameter LEN = 0);

    logic incr;
    logic [$clog2(LEN)-1:0] addr;

    modport producer (output incr, output addr);
    modport register (input incr, input addr);

endinterface

module unpacked_to_AXI_LITE (
    input slv_arvalid,
    output slv_arready,
    input [31:0] slv_araddr,
    input [2:0] slv_arprot,
    output slv_rvalid,
    input slv_rready,
    output [31:0] slv_rdata,
    output [1:0] slv_rresp,
    input slv_awvalid,
    output slv_awready,
    input [31:0] slv_awaddr,
    input [2:0] slv_awprot,
    input slv_wvalid,
    output slv_wready,
    input [31:0] slv_wdata,
    input [3:0] slv_wstrb,
    output slv_bvalid,
    input slv_bready,
    output [1:0] slv_bresp,
    AXI_LITE.Master mst
);

    assign mst.ar_valid = slv_arvalid;
    assign slv_arready = mst.ar_ready;
    assign mst.ar_addr = slv_araddr;
    assign mst.ar_prot = slv_arprot;
    assign slv_rvalid = mst.r_valid;
    assign mst.r_ready = slv_rready;
    assign slv_rdata = mst.r_data;
    assign slv_rresp = mst.r_resp;
    assign mst.aw_valid = slv_awvalid;
    assign slv_awready = mst.aw_ready;
    assign mst.aw_addr = slv_awaddr;
    assign mst.aw_prot = slv_awprot;
    assign mst.w_valid = slv_wvalid;
    assign slv_wready = mst.w_ready;
    assign mst.w_data = slv_wdata;
    assign mst.w_strb = slv_wstrb;
    assign slv_bvalid = mst.b_valid;
    assign mst.b_ready = slv_bready;
    assign slv_bresp = mst.b_resp;

endmodule

module AXI4Lite_to_unpacked (
    AXI4Lite.slave slv,
    output mst_arvalid,
    input mst_arready,
    output [31:0] mst_araddr,
    output [2:0] mst_arprot,
    input mst_rvalid,
    output mst_rready,
    input [31:0] mst_rdata,
    input [1:0] mst_rresp,
    output mst_awvalid,
    input mst_awready,
    output [31:0] mst_awaddr,
    output [2:0] mst_awprot,
    output mst_wvalid,
    input mst_wready,
    output [31:0] mst_wdata,
    output [3:0] mst_wstrb,
    input mst_bvalid,
    output mst_bready,
    input [1:0] mst_bresp
);

    assign mst_arvalid = slv.arvalid;
    assign slv.arready = mst_arready;
    assign mst_araddr = slv.araddr;
    assign mst_arprot = slv.arprot;
    assign slv.rvalid = mst_rvalid;
    assign mst_rready = slv.rready;
    assign slv.rdata = mst_rdata;
    assign slv.rresp = mst_rresp;
    assign mst_awvalid = slv.awvalid;
    assign slv.awready = mst_awready;
    assign mst_awaddr = slv.awaddr;
    assign mst_awprot = slv.awprot;
    assign mst_wvalid = slv.wvalid;
    assign slv.wready = mst_wready;
    assign mst_wdata = slv.wdata;
    assign mst_wstrb = slv.wstrb;
    assign slv.bvalid = mst_bvalid;
    assign mst_bready = slv.bready;
    assign slv.bresp = mst_bresp;

endmodule

module AXI_LITE_assign (
    AXI_LITE.Slave slave,
    AXI_LITE.Master master
);

    assign master.ar_valid = slave.ar_valid;
    assign slave.ar_ready = master.ar_ready;
    assign master.ar_addr = slave.ar_addr;
    assign master.ar_prot = slave.ar_prot;
    assign slave.r_valid = master.r_valid;
    assign master.r_ready = slave.r_ready;
    assign slave.r_data = master.r_data;
    assign slave.r_resp = master.r_resp;
    assign master.aw_valid = slave.aw_valid;
    assign slave.aw_ready = master.aw_ready;
    assign master.aw_addr = slave.aw_addr;
    assign master.aw_prot = slave.aw_prot;
    assign master.w_valid = slave.w_valid;
    assign slave.w_ready = master.w_ready;
    assign master.w_data = slave.w_data;
    assign master.w_strb = slave.w_strb;
    assign slave.b_valid = master.b_valid;
    assign master.b_ready = slave.b_ready;
    assign slave.b_resp = master.b_resp;

endmodule

module AXI_LITE_to_AXI4Lite (
    AXI_LITE.Slave slave,
    AXI4Lite.master master
);

    assign master.arvalid = slave.ar_valid;
    assign slave.ar_ready = master.arready;
    assign master.araddr = slave.ar_addr;
    assign master.arprot = slave.ar_prot;
    assign slave.r_valid = master.rvalid;
    assign master.rready = slave.r_ready;
    assign slave.r_data = master.rdata;
    assign slave.r_resp = master.rresp;
    assign master.awvalid = slave.aw_valid;
    assign slave.aw_ready = master.awready;
    assign master.awaddr = slave.aw_addr;
    assign master.awprot = slave.aw_prot;
    assign master.wvalid = slave.w_valid;
    assign slave.w_ready = master.wready;
    assign master.wdata = slave.w_data;
    assign master.wstrb = slave.w_strb;
    assign slave.b_valid = master.bvalid;
    assign master.bready = slave.b_ready;
    assign slave.b_resp = master.bresp;

endmodule

module AXI4Lite_to_AXI_LITE (
    AXI4Lite.slave slave,
    AXI_LITE.Master master
);

    assign master.ar_valid = slave.arvalid;
    assign slave.arready = master.ar_ready;
    assign master.ar_addr = slave.araddr;
    assign master.ar_prot = slave.arprot;
    assign slave.rvalid = master.r_valid;
    assign master.r_ready = slave.rready;
    assign slave.rdata = master.r_data;
    assign slave.rresp = master.r_resp;
    assign master.aw_valid = slave.awvalid;
    assign slave.awready = master.aw_ready;
    assign master.aw_addr = slave.awaddr;
    assign master.aw_prot = slave.awprot;
    assign master.w_valid = slave.wvalid;
    assign slave.wready = master.w_ready;
    assign master.w_data = slave.wdata;
    assign master.w_strb = slave.wstrb;
    assign slave.bvalid = master.b_valid;
    assign master.b_ready = slave.bready;
    assign slave.bresp = master.b_resp;

endmodule
