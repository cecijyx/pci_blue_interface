//===========================================================================
// $Id: pci_vendor_lib.v,v 1.1.1.1 2001-02-21 15:33:22 bbeaver Exp $
//
// Copyright 2001 Blue Beaver.  All Rights Reserved.
//
// Summary:  Modules which are manually instantiated in the pci_blue_interface.
//           These modules will be instantiated for performance reasons.
//           If a target device library has a component which is especially
//           well suited to perform a particular function, it should be
//           instantiated by name in this file.  Otherwise, the behaviorial
//           version of each module will be used.
//
// This library is free software; you can distribute it and/or modify it
// under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation; either version 2.1 of the License, or
// (at your option) any later version.
//
// This library is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this library.  If not, write to
// Free Software Foundation, Inc.
// 59 Temple Place, Suite 330
// Boston, MA 02111-1307 USA
//
// Author's note about this license:  The intention of the Author and of
// the Gnu Lesser General Public License is that users should be able to
// use this code for any purpose, including combining it with other source
// code, combining it with other logic, translated it into a gate-level
// representation, or projected it into gates in a programmable or
// hardwired chip, as long as the users of the resulting source, compiled
// source, or chip are given the means to get a copy of this source code
// with no new restrictions on redistribution of this source.
//
// If you make changes, even substantial changes, to this code, or use
// substantial parts of this code as an inseparable part of another work
// of authorship, the users of the resulting IP must be given the means
// to get a copy of the modified or combined source code, with no new
// restrictions on redistribution of the resulting source.
//
// Separate parts of the combined source code, compiled code, or chip,
// which are NOT derived from this source code do NOT need to be offered
// to the final user of the chip merely because they are used in
// combination with this code.  Other code is not forced to fall under
// the GNU Lesser General Public License when it is linked to this code.
// The license terms of other source code linked to this code might require
// that it NOT be made available to users.  The GNU Lesser General Public
// License does not prevent this code from being used in such a situation,
// as long as the user of the resulting IP is given the means to get a
// copy of this component of the IP with no new restrictions on
// redistribution of this source.
//
// This code was developed using VeriLogger Pro, by Synapticad.
// Their support is greatly appreciated.
//
// NOTE:  The PCI Spec requires a special pad driver.
//        It must have slew rate control and diode clamps.
//        The final chip must have 0 nSec hold time, with
//          respect to the clock input, as detailed in the
//          PCI Spec 2.2 section 7.6.4.2.
//
// NOTE:  This IO pad is motivated by personal experience
//          with timing problems in 3000 series Xilinx chips.
//        The later Xilinx chips incorporate flops on the
//          data and OE signals in the IO pads, instead of
//          immediately adjacent to them.  This module does
//          not require that the flops be in the pad.  However,
//          the user of this IO pad assumes that the flops are
//          either in or very near to the IO pads.
//
// NOTE:  The PCI Bus clock can operate from 0 Hz to 33.334 MHz.
//        The 0 Hz requirement means that the controller must be
//          able to respond to a Reset when the clock is not
//          operating.  These OP Pads and their associated flops
//          must go High-Z immediately upon seeing a PCI Reset,
//          and may NOT stay driven until the next clock edge.
//          Async resets on the OE flops are absolutely required.  
//
//===========================================================================

`include "pci_blue_options.vh"
`include "pci_blue_constants.vh"
`timescale 1ns/1ps

// special IO pad which leads directly to the PCI Clock Distribution PLL
module pci_clock_input_pad (
  clk_ext, clk_ref_in
);
  input   clk_ext;
  output  clk_ref_in;
  assign  clk_ref_in = clk_ext;
endmodule

// PLL used to drive PCI Clock around the chip with near zero skew
module pci_clock_pll (
        clk_ref_in,
        clk_feedback,
        pll_bypass,
        pci_clk
);
  input   clk_ref_in, clk_feedback;
  input   pll_bypass;
  output  pci_clk;
  wire   #5 clk_delay = clk_ref_in;
  assign  pci_clk = pll_bypass ? clk_delay : clk_ref_in;
endmodule

// pad to drive and receive unclocked PCI signals besides the clock reference
module pci_combinational_io_pad (
  d_in_comb, d_out_comb, d_out_oe_comb, d_ext
);
  output  d_in_comb;
  input   d_out_comb, d_out_oe_comb;
  inout   d_ext;
  assign  d_in_comb = d_ext;
  assign  d_ext = d_out_oe_comb ? d_out_comb : 1'bz;
endmodule

// IO pads contain an internal flip-flop on output data, output OE
module pci_registered_io_pad (
  pci_clk,
  pci_ad_in_comb, pci_ad_in_prev,
  pci_ad_out_next, pci_ad_out_en_next,
  pci_ad_out_oe_comb,
  pci_ad_ext
);
  input   pci_clk;
  output  pci_ad_in_comb;
  output  pci_ad_in_prev;
  input   pci_ad_out_next, pci_ad_out_en_next;
  input   pci_ad_out_oe_comb;
  inout   pci_ad_ext;

// These flops are timing critical, and should be in or near the IO pad.
  reg     pci_ad_out_hold;
  always @(posedge pci_clk)
  begin
    pci_ad_out_hold <= pci_ad_out_en_next ? pci_ad_out_next : pci_ad_out_hold;
  end

  wire    pci_ad_out_hold_dly1, pci_ad_out_hold_dly2;
  assign #`PAD_MIN_DATA_DLY pci_ad_out_hold_dly1 = pci_ad_out_hold;
  assign #`PAD_MAX_DATA_DLY pci_ad_out_hold_dly2 = pci_ad_out_hold;

  wire    pci_ad_oe_comb_dly1, pci_ad_oe_comb_dly2;
  assign #`PAD_MIN_OE_DLY pci_ad_oe_comb_dly1= pci_ad_out_oe_comb;
  assign #`PAD_MAX_OE_DLY pci_ad_oe_comb_dly2 = pci_ad_out_oe_comb;

  wire    force_x = (pci_ad_oe_comb_dly1 != pci_ad_oe_comb_dly2)
                  | (pci_ad_out_oe_comb
                        & (pci_ad_out_hold_dly1 !== pci_ad_out_hold_dly2));
  assign  pci_ad_ext = force_x ? 1'bX
                     : ((pci_ad_oe_comb_dly2) ? pci_ad_out_hold_dly2 : 1'bZ);

`ifdef SIMULTANEOUS_MASTER_TARGET
// Have to look at Internal signals when driving and receiving at the same
// time.  See the PCI Local Bus Spec Revision 2.2 section 3.10 item 9.
// Two ways to implement the required bypass.
`ifdef Post_Flop_Bypass
// 1) bypass the inputs from the output flop, by accessing the signals
//    between the output flop and the IO Pad.
// This flop is timing critical, because of the small external data valid window
  reg     pci_ad_in_grab;
  always @(posedge pci_clk)
  begin
    pci_ad_in_grab <= pci_ad_out_oe_comb ? pci_ad_out_hold : pci_ad_ext;
  end
  assign  pci_ad_in_comb = pci_ad_out_oe_comb ? pci_ad_out_hold : pci_ad_ext;
  assign  pci_ad_in_prev = pci_ad_in_grab;

`else // Post_Flop_Bypass
// 2) duplicate the output flops to let the outgoing data be captured,
//    and bypass using the duplicated data.
// The pci_ad_out_en_next and pci_ad_in_comb signals might be timing critical.
// Care must be used in the placement of all flops.
  reg     pci_ad_out_shadow, pci_ad_out_prev, pci_ad_out_oe_prev, pci_ad_in_grab;
  always @(posedge pci_clk)
  begin
    pci_ad_out_shadow <= pci_ad_out_en_next ? pci_ad_out_next : pci_ad_out_shadow;
    pci_ad_out_prev <= pci_ad_out_shadow;
    pci_ad_out_oe_prev <= pci_ad_out_en_next;
    pci_ad_in_grab <= pci_ad_ext;  // probably in the IO pad
  end
  assign  pci_ad_in_comb = pci_ad_out_oe_comb ? pci_ad_out_shadow : pci_ad_ext;
  assign  pci_ad_in_prev = pci_ad_out_oe_prev ? pci_ad_out_prev : pci_ad_in_grab;
`endif // Post_Flop_Bypass

`else // SIMULTANEOUS_MASTER_TARGET
// External signals from other masters are always settled in time to use
// This flop is timing critical, because of the small external data valid window
  reg     pci_ad_in_grab;
  always @(posedge pci_clk)
  begin
    pci_ad_in_grab <= pci_ad_ext;
  end
  assign  pci_ad_in_comb = pci_ad_ext;  // probably in the IO pad
  assign  pci_ad_in_prev = pci_ad_in_grab;
`endif // SIMULTANEOUS_MASTER_TARGET

// synopsys translate_off
  always @(posedge pci_clk)
  begin
    if (pci_ad_out_oe_comb & (pci_ad_out_hold !== pci_ad_ext))
    begin
      $display (" ***** PCI Pad drives one value while receiving another %h, %h, %h, at %t",
                  pci_ad_out_oe_comb, pci_ad_out_hold, pci_ad_ext, $time);
    end
    `NO_ELSE;
  end
// synopsys translate_on
endmodule

// Mux which might need to be carefully placed to satisfy timing constraints
module pci_critical_MUX (
  d_0, d_1, sel, q
);
  input   d_0, d_1, sel;
  output  q;
  assign  q = sel ? d_1 : d_0;
endmodule

// Mux which might need to be carefully placed to satisfy timing constraints
module pci_critical_AND_MUX (
  d_0, d_1, sel_0, sel_1, q
);
  input   d_0, d_1, sel_0, sel_1;
  output  q;
  assign  q = (sel_0 & sel_1) ? d_1 : d_0;
endmodule

// Mux which might need to be carefully placed to satisfy timing constraints
// The And terms will be most timing critical.
module pci_critical_AO221 (
  a_0, a_1, b_0, b_1, c_0, q
);
  input   a_0, a_1, b_0, b_1, c_0;
  output  q;
  assign  q = (a_0 & a_1) | (b_0 & b_1) | c_0;
endmodule

// whatever it takes to distribute a clock signal with near zero skew
module pci_clock_tree (
  pci_clk_pll_out, pci_clk
);
  input   pci_clk_pll_out;
  output  pci_clk;
  assign  pci_clk = pci_clk_pll_out;
endmodule

// If the vendor has a flop which is particularly good at settling out of
//   metastability, it should be used here.
module pci_synchronizer_flop (
  data_in, clk_out, sync_data_out, async_reset
);
  input   data_in;
  input   clk_out;
  output  sync_data_out;
  input   async_reset;

  reg     sync_data_out;

  always @(posedge clk_out or posedge async_reset)
  begin
    if (async_reset == 1'b1)
    begin
      sync_data_out <= 1'b0;
    end
    else
    begin
      sync_data_out <= data_in;
    end
  end
endmodule

`ifdef HOST_FIFOS_ARE_MADE_FROM_FLOPS
`else  // HOST_FIFOS_ARE_MADE_FROM_FLOPS
// A dual-port SRAM.  This SRAM must latch the address for both the read
//   port and the write port on the rising edge of the corresponding clock.
// Enables must also be latched on the rising edge.
// Write data is latched on the same rising edge as it's associated address
//   and chip enable.
// Data out comes some time after the rising clock edge in which Read_Enable
//   is asserted.
// If Read_Enable is NOT asserted, the SRAM returns garbage.
module pci_2port_sram_16x1 (
  write_clk, write_capture_data,
  write_address, write_data,
  read_clk, read_enable,
  read_address, read_data
);
  input   write_clk, write_capture_data;
  input  [3:0] write_address;
  input   write_data;
  input   read_clk, read_enable;
  input  [3:0] read_address;
  output  read_data;

// store 16 bits of state
  reg     PCI_Fifo_Mem [0:15];  // address limits, not bits in address

// write port
  always @(posedge write_clk)
  begin
    if (write_capture_data)
    begin
      PCI_Fifo_Mem[write_address[3:0]] <= write_data;
    end
    `NO_ELSE;  // can't do blah <= blah, because address may be unknown
  end
// Xilinx 4000 series and newer FPGAs contain a dual-port SRAM primitive with
//   synchronous write and asynchronous read.  Latch the read address to make
//   this primitive behave like a synchronous read SRAM
  reg    [3:0] latched_read_address;
  reg     latched_read_enable;
  always @(posedge read_clk)
  begin
    latched_read_address[3:0] <= read_address[3:0];
    latched_read_enable <= read_enable;
  end

  assign  read_data = (latched_read_enable)
                    ? PCI_Fifo_Mem[latched_read_address[3:0]] : 1'bX;
endmodule
`endif  // HOST_FIFOS_ARE_MADE_FROM_FLOPS

`ifdef UNUSED
// IO pads contain NO internal flip-flop on output data, output OE
module pci_direct_io_pad (
  pci_clk,
  pci_ad_in, pci_ad_in_reg,
  pci_direct_data_out, pci_direct_data_out_oe,
  pci_ad_ext
);
  input   pci_clk;
  output  pci_ad_in;
  output  pci_ad_in_reg;
  input   pci_direct_data_out;
  input   pci_direct_data_out_oe;
  inout   pci_ad_ext;

  reg     pci_ad_in_reg_int;

  always @(posedge pci_clk)
  begin
    pci_ad_in_reg_int <= pci_ad_ext;
  end

  assign  pci_ad_ext = (pci_direct_data_out_oe) ? pci_direct_data_out : 1'bz;
  assign  pci_ad_in_reg = pci_ad_in_reg_int;
  assign  pci_ad_in = pci_ad_ext;
// The paramater `PCI_IO_PAD_LIBRARY_NAME can be used to call out a pad.
endmodule
`endif  // UNUSED

