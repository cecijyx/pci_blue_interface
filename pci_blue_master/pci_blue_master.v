//===========================================================================
// $Id: pci_blue_master.v,v 1.27 2001-07-28 11:21:59 bbeaver Exp $
//
// Copyright 2001 Blue Beaver.  All Rights Reserved.
//
// Summary:  The synthesizable pci_blue_interface PCI Master module.
//           This module takes commands from the Request FIFO and initiates
//           PCI activity based on the FIFO contents.  It reports progress
//           and error activity to the Target interface, which is in
//           control of the Response FIFO.
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
// NOTE:  The Master State Machine does one of two things when it sees data
//        in it's Command FIFO:
//        1) Unload the data and use it as either a PCI Address, a PCI
//           Write Data value, or a PCI Read Strobe indication.  In these
//           cases, the data is also sent to the PCI Slave as documentation
//           of PCI Master Activity.
//        2) Unload the data and send it to the PCI Slave for interpretation.
//           This path, which does not need external bus activity, is used
//           when a local configuration register is to be changed, and is
//           also used when a Write Fence is handled.
//
// NOTE:  In all cases, the Master State Machine has to wait to unload data
//        from the Command FIFO until there is room in the Target State Machine
//        Response FIFO to receive the unloaded data.
//
// NOTE:  If there IS room in the PCI Target FIFO, the PCI Master may still
//        have to delay a transfer.  The PCI Target gets to decide which
//        state machine, Master or Target, gets to write the FIFO each clock.
//
// NOTE:  The Master State Machine might also wait even if there is room in the
//        Target State Machine Response FIFO if a Delayed Read is in progress,
//        and the Command FIFO contains either a Write Fence or a Read command.
//
// NOTE:  As events occur on the PCI Bus, the Master State Machine writes
//        Status data to the PCI Target State Machine.
//
// NOTE:  The Master State Machine will unload an entry from the Command FIFO and
//        insert the command into the Response FIFO when these conditions are met:
//        Command FIFO has data in it, and
//        Response FIFO has room to accept data,
//        and one of the following:
//          It's a Write Fence, or
//          It's a Local Configuration Reference, or
//          Master Enabled, and Bus Available, and Address Mode, and
//            It's a Read Address and Target not holding off Reads, or
//            It's a Write Address, or
//          Data Mode, and
//            It's Write Data and local IRDY and external TRDY is asserted, or
//            It's Read Strobes and local IRDY and external TRDY is asserted
//
// NOTE:  The writer of the FIFO must notice whether it is doing an IO reference
//        with the bottom 2 bits of the address not both 0.  If an IO reference
//        is done with at least 1 bit non-zero, the transfer must be a single
//        word transfer.  See the PCI Local Bus Specification Revision 2.2,
//        section 3.2.2.1 for details.
//
// NOTE:  This Master State Machine is an implementation of the Master State
//        Machine described in the PCI Local Bus Specification Revision 2.2,
//        Appendix B.  Locking is not supported.
//
// NOTE:  The Master State Machine must make sure that it can accept or
//        deliver data within the Master Data Latency time from when it
//        asserts FRAME Low, described in the PCI Local Bus Specification
//        Revision 2.2, section 3.5.2
//
// NOTE:  The Master State Machine has to concern itself with 2 timed events:
//        1) count down for master aborts, described in the PCI Local Bus
//           Specification Revision 2.2, section 3.3.3.1
//        2) count down Master Latency Timer when master, described in the
//           PCI Local Bus Specification Revision 2.2, section 3.5.4
//
//===========================================================================

`timescale 1ns/10ps

module pci_blue_master (
// Signals driven to control the external PCI interface
  pci_req_out_oe_comb, pci_req_out_next,
  pci_gnt_in_prev,     pci_gnt_in_critical,
  pci_master_ad_out_oe_comb, pci_master_ad_out_next,
  pci_cbe_out_oe_comb, pci_cbe_l_out_next,
  pci_frame_in_critical, pci_frame_in_prev,
  pci_frame_out_oe_comb, pci_frame_out_next,
  pci_irdy_in_critical, pci_irdy_in_prev,
  pci_irdy_out_oe_comb, pci_irdy_out_next,
  pci_devsel_in_prev,    
  pci_trdy_in_critical,    pci_trdy_in_prev,
  pci_stop_in_critical,    pci_stop_in_prev,
  pci_perr_in_prev,
  pci_serr_in_prev,
// Signals to control shared AD bus, Parity, and SERR signals
  Master_Force_AD_to_Address_Data_Critical,
  Master_Exposes_Data_On_TRDY,
  Master_Captures_Data_On_TRDY,
  Master_Forces_PERR,
  PERR_Detected_While_Master_Read,
// Signal to control Request pin if on-chip PCI devices share it
  Master_Forced_Off_Bus_By_Target_Abort,
// Host Interface Request FIFO used to ask the PCI Interface to initiate
//   PCI References to an external PCI Target.
  pci_request_fifo_type,
  pci_request_fifo_cbe,
  pci_request_fifo_data,
  pci_request_fifo_data_available_meta,
  pci_request_fifo_two_words_available_meta,
  pci_request_fifo_data_unload,
  pci_request_fifo_error,
// Signals from the Master to the Target to insert Status Info into the Response FIFO.
  master_to_target_status_type,
  master_to_target_status_cbe,
  master_to_target_status_data,
  master_to_target_status_flush,
  master_to_target_status_available,
  master_to_target_status_unload,
  master_to_target_status_two_words_free,
// Signals from the Master to the Target to set bits in the Status Register
  master_got_parity_error,
  master_caused_serr,
  master_caused_master_abort,
  master_got_target_abort,
  master_caused_parity_error,
// Signals used to document Master Behavior
  master_asked_to_retry,
// Signals from the Config Regs to the Master to control it.
  master_enable,
  master_fast_b2b_en,
  master_perr_enable,
  master_latency_value,
  pci_clk,
  pci_reset_comb
);

`include "pci_blue_options.vh"
`include "pci_blue_constants.vh"

// Signals driven to control the external PCI interface
  output  pci_req_out_next;
  output  pci_req_out_oe_comb;
  input   pci_gnt_in_prev;
  input   pci_gnt_in_critical;
  output [PCI_BUS_DATA_RANGE:0] pci_master_ad_out_next;
  output  pci_master_ad_out_oe_comb;
  output [PCI_BUS_CBE_RANGE:0] pci_cbe_l_out_next;
  output  pci_cbe_out_oe_comb;
  input   pci_frame_in_critical;
  input   pci_frame_in_prev;
  output  pci_frame_out_next;
  output  pci_frame_out_oe_comb;
  input   pci_irdy_in_critical;
  input   pci_irdy_in_prev;
  output  pci_irdy_out_next;
  output  pci_irdy_out_oe_comb;
  input   pci_devsel_in_prev;
  input   pci_trdy_in_prev;
  input   pci_trdy_in_critical;
  input   pci_stop_in_prev;
  input   pci_stop_in_critical;
  input   pci_perr_in_prev;
  input   pci_serr_in_prev;
// Signals to control shared AD bus, Parity, and SERR signals
  output  Master_Force_AD_to_Address_Data_Critical;
  output  Master_Exposes_Data_On_TRDY;
  output  Master_Captures_Data_On_TRDY;
  output  Master_Forces_PERR;
  input   PERR_Detected_While_Master_Read;
// Signal to control Request pin if on-chip PCI devices share it
  output  Master_Forced_Off_Bus_By_Target_Abort;
// Host Interface Request FIFO used to ask the PCI Interface to initiate
//   PCI References to an external PCI Target.
  input  [2:0] pci_request_fifo_type;
  input  [PCI_FIFO_CBE_RANGE:0] pci_request_fifo_cbe;
  input  [PCI_FIFO_DATA_RANGE:0] pci_request_fifo_data;
  input   pci_request_fifo_data_available_meta;
  input   pci_request_fifo_two_words_available_meta;
  output  pci_request_fifo_data_unload;
  input   pci_request_fifo_error;  // NOTE: MAKE SURE THIS IS NOTED SOMEWHERE
// Signals from the Master to the Target to insert Status Info into the Response FIFO.
  output [2:0] master_to_target_status_type;
  output [PCI_BUS_CBE_RANGE:0] master_to_target_status_cbe;
  output [PCI_BUS_DATA_RANGE:0] master_to_target_status_data;
  output  master_to_target_status_flush;
  output  master_to_target_status_available;
  input   master_to_target_status_unload;
  input   master_to_target_status_two_words_free;
// Signals from the Master to the Target to set bits in the Status Register
  output  master_got_parity_error;
  output  master_caused_serr;
  output  master_caused_master_abort;
  output  master_got_target_abort;
  output  master_caused_parity_error;
// Signals used to document Master Behavior
  output  master_asked_to_retry;
// Signals from the Config Regs to the Master to control it.
  input   master_enable;
  input   master_fast_b2b_en;
  input   master_perr_enable;
  input  [7:0] master_latency_value;
  input   pci_clk;
  input   pci_reset_comb;

// Forward references, stuffed here to make the rest of the code compact
  wire    prefetching_request_fifo_data;
  wire    Master_Mark_Status_Entry_Flushed;
  reg     master_request_full;
  wire    Master_Consumes_Request_FIFO_Data_Unconditionally_Critical;
  wire    Master_Consumes_Request_FIFO_If_TRDY;
  wire    master_to_target_status_loadable;
  parameter NO_ADDR_NO_DATA_CAPTURED  = 2'b00;  // Neither Address nor Data captured
  parameter ADDR_BUT_NO_DATA_CAPTURED = 2'b10;  // Address but no Data captured
  parameter ADDR_DATA_CAPTURED        = 2'b11;  // Address plus Data captured
  reg     Master_Previously_Full;
  reg    [1:0] PCI_Master_Retry_State;
  wire    Master_Completed_Retry_Address;
  wire    Master_Completed_Retry_Data;
  wire    Master_Got_Retry;
  wire    Master_Clear_Master_Abort_Counter;
  wire    Master_Clear_Data_Latency_Counter;
  wire    Master_Clear_Bus_Latency_Timer;
  wire    Master_Using_Retry_Info;
  wire    Fast_Back_to_Back_Possible;
  wire    Master_Discards_Request_FIFO_Entry_After_Abort;

// The PCI Blue Master gets commands from the pci_request_fifo.
// There are 3 main types of entries:
// 1) Address/Data sequences which cause external PCI activity.
// 2) Config Accesses to the Local PCI Config Registers.
// 3) Write Fence tokens.  These act just like Register Reverences.
//
// The Host Interface is required to send Requests in this order:
//   Address, optionally several Data's, Data_Last.  Sequences of Address-Address,
//   Data-Address, Data_Last-Data, or Data_Last-Data_Last are all illegal.
//
// The PCI Blue Master sends all of the commands over to the Target
//   as Status as soon as they are acted on.  This is so that the reader
//   of the pci_response_fifo can keep track of the Master's progress.

// Use standard FIFO prefetch trick to allow a single flop to control the
//   unloading of the whole FIFO.
  reg    [2:0] request_fifo_type_reg;
  reg    [PCI_FIFO_CBE_RANGE:0] request_fifo_cbe_reg;
  reg    [PCI_FIFO_DATA_RANGE:0] request_fifo_data_reg;
  reg     request_fifo_flush_reg;

  always @(posedge pci_clk)
  begin
    if (prefetching_request_fifo_data == 1'b1)
    begin  // latch whenever data available and not already full
      request_fifo_type_reg[2:0] <= pci_request_fifo_type[2:0];
      request_fifo_cbe_reg[PCI_FIFO_CBE_RANGE:0] <=
                      pci_request_fifo_cbe[PCI_FIFO_CBE_RANGE:0];
      request_fifo_data_reg[PCI_FIFO_DATA_RANGE:0] <=
                      pci_request_fifo_data[PCI_FIFO_DATA_RANGE:0];
      request_fifo_flush_reg <= Master_Mark_Status_Entry_Flushed;
    end
    else if (prefetching_request_fifo_data == 1'b0)  // hold
    begin
      request_fifo_type_reg[2:0] <= request_fifo_type_reg[2:0];
      request_fifo_cbe_reg[PCI_FIFO_CBE_RANGE:0] <=
                      request_fifo_cbe_reg[PCI_FIFO_CBE_RANGE:0];
      request_fifo_data_reg[PCI_FIFO_DATA_RANGE:0] <=
                      request_fifo_data_reg[PCI_FIFO_DATA_RANGE:0];
      request_fifo_flush_reg <= request_fifo_flush_reg;
    end
// synopsys translate_off
    else
    begin
      request_fifo_type_reg[2:0] <= 3'hX;
      request_fifo_cbe_reg[PCI_FIFO_CBE_RANGE:0] <= `PCI_FIFO_CBE_X;
      request_fifo_data_reg[PCI_FIFO_DATA_RANGE:0] <= `PCI_FIFO_DATA_X;
      request_fifo_flush_reg <= 1'bX;
    end
// synopsys translate_on
  end

// Single FLOP used to control activity of this FIFO.
//
// FIFO data is consumed if Master_Consumes_Request_FIFO_Data_Unconditionally_Critical
//                       or Master_Captures_Request_FIFO_If_TRDY and TRDY
// If not unloading and not full and no data,  not full
// If not unloading and not full and data,     full
// If not unloading and full and no data,      full
// If not unloading and full and data,         full
// If unloading and not full and no data,      not full
// If unloading and not full and data,         not full
// If unloading and full and no data,          not full
// If unloading and full and data,             full
  wire    Master_Flushing_Housekeeping = prefetching_request_fifo_data
                      & (   (pci_request_fifo_type[2:0] ==  // new address
                                    PCI_HOST_REQUEST_SPARE)
                          | (pci_request_fifo_type[2:0] ==  // new address
                                    PCI_HOST_REQUEST_INSERT_WRITE_FENCE));
  wire    Master_Consumes_This_Entry_Critical =
                        Master_Consumes_Request_FIFO_Data_Unconditionally_Critical
                      | Master_Flushing_Housekeeping;

// Master Request Full bit indicates when data prefetched on the way to PCI bus
// NOTE: TRDY is VERY LATE.  This must be implemented to let TRDY operate quickly
  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      master_request_full <= 1'b0;
    end
    else if (pci_reset_comb == 1'b0)
    begin
      if (pci_trdy_in_critical == 1'b1)  // pci_trdy_in_critical is VERY LATE
        master_request_full <=
                      (   Master_Consumes_This_Entry_Critical
                        | Master_Consumes_Request_FIFO_If_TRDY)
                      ? (master_request_full & prefetching_request_fifo_data)   // unloading
                      : (master_request_full | prefetching_request_fifo_data);  // not unloading
      else if (pci_trdy_in_critical == 1'b0)
        master_request_full <=
                          Master_Consumes_This_Entry_Critical
                      ? (master_request_full & prefetching_request_fifo_data)   // unloading
                      : (master_request_full | prefetching_request_fifo_data);  // not unloading
// synopsys translate_off
      else
        master_request_full <= 1'bX;
// synopsys translate_on
    end
// synopsys translate_off
    else
      master_request_full <= 1'bX;
// synopsys translate_on
  end

// Deliver data to the IO pads when needed.
  wire   [2:0] pci_request_fifo_type_current =
                        prefetching_request_fifo_data
                      ? pci_request_fifo_type[2:0]
                      : request_fifo_type_reg[2:0];
  wire   [PCI_FIFO_DATA_RANGE:0] pci_request_fifo_data_current =
                        prefetching_request_fifo_data
                      ? pci_request_fifo_data[PCI_FIFO_DATA_RANGE:0]
                      : request_fifo_data_reg[PCI_FIFO_DATA_RANGE:0];
  wire   [PCI_FIFO_CBE_RANGE:0] pci_request_fifo_cbe_current =
                        prefetching_request_fifo_data
                      ? pci_request_fifo_cbe[PCI_FIFO_CBE_RANGE:0]
                      : request_fifo_cbe_reg[PCI_FIFO_CBE_RANGE:0];

// Create Data Available signals which depend on the FIFO, the Latch, AND the
//   input of the status datapath, which can prevent the unloading of data.
  wire    request_fifo_data_available_meta =
                        (   pci_request_fifo_data_available_meta
                          | master_request_full)  // available
                      & master_to_target_status_loadable;  // plus room
  wire    request_fifo_two_words_available_meta =
                        (   pci_request_fifo_two_words_available_meta
                          | (   pci_request_fifo_data_available_meta
                              & master_request_full))  // available
                      & master_to_target_status_loadable
                      & master_to_target_status_two_words_free;  // plus room

// Calculate whether to unload data from the Request FIFO
  assign  prefetching_request_fifo_data = pci_request_fifo_data_available_meta
                                        & ~master_request_full
                                        & master_to_target_status_loadable;
  assign  pci_request_fifo_data_unload = prefetching_request_fifo_data;  // drive outputs

// Re-use Request FIFO Prefetch Buffer to send Signals from the Request FIFO
//   to the Target to finally insert the Status Info into the Response FIFO.
// The Master will only make progress when this Buffer between
//   Master and Target is empty.
// Target Status Full bit indicates when the Target is done with the Status data.
  reg     master_to_target_status_full;

  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      master_to_target_status_full <= 1'b0;
    end
    else if (pci_reset_comb == 1'b0)
    begin
      master_to_target_status_full <= prefetching_request_fifo_data
                                    | (   master_to_target_status_full
                                        & ~master_to_target_status_unload);
    end
// synopsys translate_off
    else
      master_to_target_status_full <= 1'bX;
// synopsys translate_on
  end

// Create Buffer Available signal which can prevent the unloading of data.
  assign  master_to_target_status_loadable = ~master_to_target_status_full
                                           | master_to_target_status_unload;

// Send Status Data to Target.  This works because ALL request data goes
//   through the prefetch buffer, where it sits until it is replaced.
  assign  master_to_target_status_type[2:0] =                   // drive outputs
                      request_fifo_type_reg[2:0];
  assign  master_to_target_status_cbe[PCI_BUS_CBE_RANGE:0] =    // drive outputs
                      request_fifo_cbe_reg[PCI_BUS_CBE_RANGE:0];
  assign  master_to_target_status_data[PCI_BUS_DATA_RANGE:0] =  // drive outputs
                      request_fifo_data_reg[PCI_BUS_DATA_RANGE:0];
  assign  master_to_target_status_flush = request_fifo_flush_reg;  // drive outputs
  assign  master_to_target_status_available = master_to_target_status_full;  // drive outputs

// State Machine keeping track of Request FIFO Retry Information.
// Retry Information is needed when the Target does a Retry with or without
//   data, or when the Master ends a Burst early because of lack of data.
// All Address and Data items which have been offered to the PCI interface
//   may need to be retried.
// Unfortunately, it is not possible to look at the IRDY/TRDY signals
//   directly to see if the Address or Data item has been passed onto
//   the bus.
// Fortunately, it is possible to look at the Request FIFO Prefetch
//   buffer to find the same information.
// If an Address or Data item is written to an empty Prefetch buffer and the
//   buffer stays empty, the item passed to the PCI bus immediately.
// If an Address or Data item is in a full Prefetch buffer and the full
//   bit goes from 1 to 0, that means the item was unloaded to the
//   PCI buffer.
// In both cases, the Address or Data must be captured from the Prefetch
//   buffer and held in case a Retry is needed.
// When an Address is captured, the next Data will need to be retried to
//   the same Address.
// Each time a subsequent Data item is captured, the Address must be
//   incremented.  This is because a Data item will only be issued to
//   the PCI bus after the previous Data was consumed.  The new
//   Data must go to the Address 4 greater than the previous Data item.

// Delay the Full Flop, to see when when it transitions from Full to Empty,
//   or whenever it does not become full because of bypass.  In both cases
//   it is time to capture Address and Data items.
  wire    Master_Capturing_Retry_Data = Master_Previously_Full  // notice that data
                                      & ~master_request_full;   // transferred to PCI bus

// Classify Address and Data just sent out onto PCI bus
  wire    Master_Issued_Housekeeping = Master_Capturing_Retry_Data
                      & (   (request_fifo_type_reg[2:0] ==  // new address
                                    PCI_HOST_REQUEST_SPARE)
                          | (request_fifo_type_reg[2:0] ==  // new address
                                    PCI_HOST_REQUEST_INSERT_WRITE_FENCE));
  wire    Master_Issued_Address = Master_Capturing_Retry_Data
                      & (   (request_fifo_type_reg[2:0] ==  // new address
                                    PCI_HOST_REQUEST_ADDRESS_COMMAND)
                          | (request_fifo_type_reg[2:0] ==  // new address
                                    PCI_HOST_REQUEST_ADDRESS_COMMAND_SERR));
  wire    Master_Issued_Data = Master_Capturing_Retry_Data
                      & (   (request_fifo_type_reg[2:0] ==  // new data
                                    PCI_HOST_REQUEST_W_DATA_RW_MASK)
                          | (request_fifo_type_reg[2:0] ==  // new data
                                    PCI_HOST_REQUEST_W_DATA_RW_MASK_LAST)
                          | (request_fifo_type_reg[2:0] ==  // new data
                                    PCI_HOST_REQUEST_W_DATA_RW_MASK_PERR)
                          | (request_fifo_type_reg[2:0] ==  // new data
                                    PCI_HOST_REQUEST_W_DATA_RW_MASK_LAST_PERR));

// Keep track of the stored Address and Data validity
// NOTE: These signals are delayed from when the data goes onto the bus
  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      Master_Previously_Full <= 1'b0;
      PCI_Master_Retry_State[1:0] <= NO_ADDR_NO_DATA_CAPTURED;
    end
    else if (pci_reset_comb == 1'b0)
    begin
      if (Master_Completed_Retry_Address == 1'b1)
      begin
        Master_Previously_Full <= 1'b0;
        PCI_Master_Retry_State[1:0] <= NO_ADDR_NO_DATA_CAPTURED;
      end
      else if (Master_Completed_Retry_Address == 1'b0)
      begin
        Master_Previously_Full <= master_request_full | prefetching_request_fifo_data;
        case (PCI_Master_Retry_State[1:0])
        NO_ADDR_NO_DATA_CAPTURED:
          begin
            if (Master_Issued_Address == 1'b1)
              PCI_Master_Retry_State[1:0] <= ADDR_BUT_NO_DATA_CAPTURED;
            else if (Master_Issued_Address == 1'b0)
              PCI_Master_Retry_State[1:0] <= NO_ADDR_NO_DATA_CAPTURED;
// synopsys translate_off
            else
              PCI_Master_Retry_State[1:0] <= 2'bXX;
// synopsys translate_on
          end
        ADDR_BUT_NO_DATA_CAPTURED:
          begin
            if (Master_Issued_Housekeeping == 1'b1)
              PCI_Master_Retry_State[1:0] <= NO_ADDR_NO_DATA_CAPTURED;
            else if (Master_Issued_Address == 1'b1)  // fast back-to-back?
              PCI_Master_Retry_State[1:0] <= ADDR_BUT_NO_DATA_CAPTURED;
            else if (Master_Issued_Data == 1'b1)
              PCI_Master_Retry_State[1:0] <= ADDR_DATA_CAPTURED;
            else  // idle
              PCI_Master_Retry_State[1:0] <= ADDR_BUT_NO_DATA_CAPTURED;
          end
        ADDR_DATA_CAPTURED:
          begin
            if (Master_Issued_Housekeeping == 1'b1)
              PCI_Master_Retry_State[1:0] <= NO_ADDR_NO_DATA_CAPTURED;
            else if (Master_Completed_Retry_Data == 1'b1)  // disconnect with data
              PCI_Master_Retry_State[1:0] <= ADDR_BUT_NO_DATA_CAPTURED;
            else if (Master_Issued_Address == 1'b1)  // fast back-to-back?
              PCI_Master_Retry_State[1:0] <= ADDR_BUT_NO_DATA_CAPTURED;
            else if (Master_Issued_Data == 1'b1)
              PCI_Master_Retry_State[1:0] <= ADDR_DATA_CAPTURED;
            else  // idle
              PCI_Master_Retry_State[1:0] <= ADDR_DATA_CAPTURED;
          end
// synopsys translate_off
        default:
          begin
            PCI_Master_Retry_State[1:0] <= 2'bXX;
            $display ("*** %m PCI Master FIFO State Machine Unknown %x at time %t",
                           PCI_Master_Retry_State[1:0], $time);
          end
// synopsys translate_on
        endcase
      end
// synopsys translate_off
      else
      begin
        Master_Previously_Full <= 1'bX;
        PCI_Master_Retry_State[1:0] <= 2'bXX;
      end
// synopsys translate_on
    end
// synopsys translate_off
    else
    begin
      Master_Previously_Full <= 1'bX;
      PCI_Master_Retry_State[1:0] <= 2'bXX;
    end
// synopsys translate_on
  end

// NOTE: WORKING: These may need to be qualified to only be valid during retries
  wire    Retry_No_Addr_No_Data_Avail = (PCI_Master_Retry_State[1:0] == NO_ADDR_NO_DATA_CAPTURED) | 1'b1;
  wire    Retry_Addr_No_Data_Avail = (PCI_Master_Retry_State[1:0] == ADDR_BUT_NO_DATA_CAPTURED) & 1'b0;
  wire    Retry_Addr_Data_Avail = (PCI_Master_Retry_State[1:0] == ADDR_DATA_CAPTURED) & 1'b0;

// Make the signal which knows to increment the Address when Data is latched.
// NOTE: WORKING: This must increment both during retries and normal operation
  wire    Master_Inc_Address =
                        (   (Retry_Addr_Data_Avail)  // NOTE: wrong
                          & Master_Completed_Retry_Data)  // disconnect with data
                      | (   (Retry_Addr_Data_Avail)  // NOTE: wrong
                          & Master_Issued_Data);  // normal transfer of new data

// Keep track of the present PCI Address, so the Master can restart references
//   if it receives a Target Retry.
// The bottom 2 bits of a PCI Address have special meaning to the
// PCI Master and PCI Target.  See the PCI Local Bus Spec
// Revision 2.2 section 3.2.2.1 and 3.2.2.2 for details.
// The PCI Master will never do a Burst when the command is an IO command.
// NOTE: if 64-bit addressing implemented, need to capture BOTH
//   halves of the address before data can be allowed to proceed.
  reg    [PCI_BUS_DATA_RANGE:0] Master_Retry_Address;
  reg    [PCI_BUS_CBE_RANGE:0] Master_Retry_Command;
  reg    [2:0] Master_Retry_Address_Type;
  reg     Master_Retry_Write_Reg;

  always @(posedge pci_clk)
  begin
    if (Master_Issued_Address == 1'b1)  // hold or increment the Burst Address
    begin
      Master_Retry_Address_Type[2:0] <= request_fifo_type_reg[2:0];
      Master_Retry_Address[PCI_BUS_DATA_RANGE:0] <=
                         request_fifo_data_reg[PCI_BUS_DATA_RANGE:0]
                      & `PCI_BUS_Address_Mask;

      Master_Retry_Command[PCI_BUS_CBE_RANGE:0] <=
                      request_fifo_cbe_reg[PCI_BUS_CBE_RANGE:0];
      Master_Retry_Write_Reg <= (   request_fifo_cbe_reg[PCI_BUS_CBE_RANGE:0]
                                  & PCI_COMMAND_ANY_WRITE_MASK) != `PCI_FIFO_CBE_ZERO;
    end
    else if (Master_Issued_Address == 1'b0)
    begin
      Master_Retry_Address_Type[2:0] <= Master_Retry_Address_Type[2:0];
      if (Master_Inc_Address == 1'b1)
        Master_Retry_Address[PCI_BUS_DATA_RANGE:0]   <=
                         Master_Retry_Address[PCI_BUS_DATA_RANGE:0]
                      + `PCI_BUS_Address_Step;
      else if (Master_Inc_Address == 1'b0)
        Master_Retry_Address[PCI_BUS_DATA_RANGE:0] <=
                      Master_Retry_Address[PCI_BUS_DATA_RANGE:0];
// synopsys translate_off
      else
        Master_Retry_Address[PCI_BUS_DATA_RANGE:0] <= `PCI_BUS_DATA_X;
// synopsys translate_on
// If a Target Disconnect is received during a Memory Write and Invalidate,
//   the reference should be retried as a normal Memory Write.
//   See the PCI Local Bus Spec Revision 2.2 section 3.3.3.2.1 for details.
      if ((Master_Got_Retry == 1'b1)
           & (Master_Retry_Command[PCI_BUS_CBE_RANGE:0] ==
                 PCI_COMMAND_MEMORY_WRITE_INVALIDATE))
        Master_Retry_Command[PCI_BUS_CBE_RANGE:0] <= PCI_COMMAND_MEMORY_WRITE;
      else
        Master_Retry_Command[PCI_BUS_CBE_RANGE:0] <=
                      Master_Retry_Command[PCI_BUS_CBE_RANGE:0];
      Master_Retry_Write_Reg <= Master_Retry_Write_Reg;
    end
// synopsys translate_off
    else
    begin
      Master_Retry_Address_Type[2:0] <= 3'hX;
      Master_Retry_Address[PCI_BUS_DATA_RANGE:0] <= `PCI_BUS_DATA_X;
      Master_Retry_Command[PCI_BUS_CBE_RANGE:0] <= `PCI_BUS_CBE_X;
      Master_Retry_Write_Reg <= 1'bX;
    end
// synopsys translate_on
  end

// Create early version of Write signal to be used to de-OE AD bus after Addr
  wire    Master_Retry_Write = Master_Issued_Address
                             ? ((   request_fifo_cbe_reg[PCI_BUS_CBE_RANGE:0]
                                  & PCI_COMMAND_ANY_WRITE_MASK) != `PCI_FIFO_CBE_ZERO)
                             : Master_Retry_Write_Reg;

// Grab Data to allow retries if disconnect without data
  reg    [PCI_BUS_DATA_RANGE:0] Master_Retry_Data;
  reg    [PCI_BUS_CBE_RANGE:0] Master_Retry_Data_Byte_Enables;
  reg    [2:0] Master_Retry_Data_Type;

  always @(posedge pci_clk)
  begin
    if (Master_Issued_Data == 1'b1)  // hold or increment the Burst Address
    begin
      Master_Retry_Data_Type[2:0] <= request_fifo_type_reg[2:0];
      Master_Retry_Data[PCI_BUS_DATA_RANGE:0] <=
                      request_fifo_data_reg[PCI_BUS_DATA_RANGE:0];
      Master_Retry_Data_Byte_Enables[PCI_BUS_CBE_RANGE:0] <=
                      request_fifo_cbe_reg[PCI_BUS_CBE_RANGE:0];
    end
    else if (Master_Issued_Data == 1'b0)
    begin
      Master_Retry_Data_Type[2:0] <= Master_Retry_Data_Type[2:0];
      Master_Retry_Data[PCI_BUS_DATA_RANGE:0] <=
                      Master_Retry_Data[PCI_BUS_DATA_RANGE:0];
      Master_Retry_Data_Byte_Enables[PCI_BUS_CBE_RANGE:0] <=
                      Master_Retry_Data_Byte_Enables[PCI_BUS_CBE_RANGE:0];
    end
// synopsys translate_off
    else
    begin
      Master_Retry_Data_Type[2:0] <= 3'hX;
      Master_Retry_Data[PCI_BUS_DATA_RANGE:0] <= `PCI_BUS_DATA_X;
      Master_Retry_Data_Byte_Enables[PCI_BUS_CBE_RANGE:0] <= `PCI_BUS_CBE_X;
    end
// synopsys translate_on
  end

// Master Aborts are detected when the Master asserts FRAME, and does
// not see DEVSEL in a timely manner.  See the PCI Local Bus Spec
// Revision 2.2 section 3.3.3.1 for details.
  reg    [2:0] Master_Abort_Counter;
  reg     Master_Got_Devsel, Master_Abort_Detected_Reg;

  always @(posedge pci_clk)
  begin
    if (Master_Clear_Master_Abort_Counter == 1'b1)
    begin
      Master_Abort_Counter[2:0] <= 3'h0;
      Master_Got_Devsel <= 1'b0;
      Master_Abort_Detected_Reg <= 1'b0;
    end
    else if (Master_Clear_Master_Abort_Counter == 1'b0)
    begin
      Master_Abort_Counter[2:0] <= Master_Abort_Counter[2:0] + 3'h1;
      Master_Got_Devsel <= pci_devsel_in_prev | Master_Got_Devsel;
      Master_Abort_Detected_Reg <= Master_Abort_Detected_Reg
                      | (   ~Master_Got_Devsel
                          & (Master_Abort_Counter[2:0] == 3'h5));
    end
// synopsys translate_off
    else
    begin
      Master_Abort_Counter[2:0] <= 3'hX;
      Master_Got_Devsel <= 1'bX;
      Master_Abort_Detected_Reg <= 1'bX;
    end
// synopsys translate_on
  end

  wire    Master_Abort_Detected =  Master_Abort_Detected_Reg
                                & ~Master_Clear_Master_Abort_Counter;

// Master Data Latency Counter.  Must make progress within 8 Bus Clocks.
// See the PCI Local Bus Spec Revision 2.2 section 3.5.2 for details.
// NOTE: This counter can be sloppy, as long as it never takes too LONG to
//   time out.  This is because I don't expect it to ever be used.  I
//   expect the Master interface to always have data available in a timely
//   fashion.  If the timer times out early, then extra retries will be
//   done.  Since this is unlikely, let it happen without worry.
  reg    [2:0] Master_Data_Latency_Counter;
  reg     Master_Data_Latency_Disconnect_Reg;

  always @(posedge pci_clk)
  begin
    if (Master_Clear_Data_Latency_Counter == 1'b1)
    begin
      Master_Data_Latency_Counter[2:0] <= 3'h0;
      Master_Data_Latency_Disconnect_Reg <= 1'b0;
    end
    else if (Master_Clear_Data_Latency_Counter == 1'b0)
    begin
      Master_Data_Latency_Counter[2:0] <= Master_Data_Latency_Counter[2:0] + 3'h1;
      Master_Data_Latency_Disconnect_Reg <= Master_Data_Latency_Disconnect_Reg
                      | (Master_Data_Latency_Counter[2:0] >= 3'h6);
    end
// synopsys translate_off
    else
    begin
      Master_Data_Latency_Counter[2:0] <= 3'hX;
      Master_Data_Latency_Disconnect_Reg <= 1'bX;
    end
// synopsys translate_on
  end

  wire    Master_Data_Latency_Disconnect =  Master_Data_Latency_Disconnect_Reg
                                         & ~Master_Clear_Data_Latency_Counter;

// The Master Bus Latency Counter is needed to force the Master off the bus
//   in a timely fashion if it is in the middle of a burst when it's Grant is
//   removed.  See the PCI Local Bus Spec Revision 2.2 section 3.5.4 for details.
  reg    [7:0] Master_Bus_Latency_Timer;
  reg     Master_Bus_Latency_Disconnect;

  always @(posedge pci_clk)
  begin
    if (Master_Clear_Bus_Latency_Timer == 1'b1)
    begin
      Master_Bus_Latency_Timer[7:0]    <= 8'h00;
      Master_Bus_Latency_Disconnect <= 1'b0;
    end
    else if (Master_Clear_Bus_Latency_Timer == 1'b0)
    begin
      Master_Bus_Latency_Timer[7:0] <= pci_gnt_in_prev ? 8'h00
                                     : Master_Bus_Latency_Timer[7:0] + 8'h01;
      Master_Bus_Latency_Disconnect <= Master_Bus_Latency_Disconnect
                      | (Master_Bus_Latency_Timer[7:0]
                                 == master_latency_value[7:0]);
    end
// synopsys translate_off
    else
    begin
      Master_Bus_Latency_Timer[7:0] <= 8'hXX;
      Master_Bus_Latency_Disconnect <= 1'bX;
    end
// synopsys translate_on
  end

// EXTREME NIGHTMARE.  A PCI Master must assert Valid Write Enables
//   on all clocks, EVEN if IRDY is not asserted.  See the PCI Local
//   Bus Spec Revision 2.2 section 3.2.2 and 3.3.1 for details.
//   This means that the Master CAN'T assert an Address until the NEXT
//   Data Strobes are available, and can't assert IRDY on data unless
//   the Data is either the LAST data, or the NEXT data is available.
//   In the case of a Timeout, the Master has to convert a Data into
//   a Data_Last, so that it doesn't need to come up with the NEXT
//   Data Byte Enables.  The reference can only be continued once the
//   late data becomes available.
//
// The Request FIFO can be unloaded only of ALL of these three things are true:
// 1) Room available in Status FIFO to accept data
// 2) Address + Next Data, or Data + Next Data, or Data_Last, or Reg_Ref,
//    or Fence, in FIFO
// 3) If Data Phase, External Device on PCI bus allows transfer using TRDY,
//    otherwise send data immediately into PCI buffers.
// Other logic will mix in the various timeouts which can happen.

// Classify the activity commanded in the head of the Request FIFO.  In some
//   cases, the entry AFTER the first word needs to be known before the
//   entry can properly be classified.  If so, pertend that the FIFO is
//   empty until the needed data is available.

// Either Address in FIFO plus next Data in FIFO containing Byte Strobes,
//   or Stored Address plus next Data in FIFO containing Byte Strobes,
//   or Stored Address plus Stored Data containing Byte Strobes.
  wire   [2:0] Next_Request_Type = Master_Using_Retry_Info
                      ? Master_Retry_Address_Type[2:0]
                      : pci_request_fifo_type_current[2:0];
  wire    Request_FIFO_CONTAINS_ADDRESS =  // NOTE: WORKING: Only true IF target can receive 2 words during initial transfer!
               master_enable  // only start (or retry) a reference if enabled
             & (   (   Retry_No_Addr_No_Data_Avail
                     &  request_fifo_two_words_available_meta)  // address plus data
                 | (   Retry_Addr_No_Data_Avail
                     &  request_fifo_data_available_meta)  // stored address plus data
                 | (    Retry_Addr_Data_Avail))  // both stored
             & (   (Next_Request_Type[2:0] ==
                                PCI_HOST_REQUEST_ADDRESS_COMMAND)
                 | (Next_Request_Type[2:0] ==
                                PCI_HOST_REQUEST_ADDRESS_COMMAND_SERR));

// Classify PCI Command to decide whether to do address stepping o Config references
  wire   [PCI_FIFO_CBE_RANGE:0] Next_Request_Command = Master_Using_Retry_Info
                      ? Master_Retry_Command[PCI_BUS_CBE_RANGE:0]
                      : pci_request_fifo_cbe_current[PCI_BUS_CBE_RANGE:0];
  wire    Master_Doing_Config_Reference =
               (   (Next_Request_Command[PCI_BUS_CBE_RANGE:0] ==
                                PCI_COMMAND_CONFIG_READ)  // captured data used
                 | (Next_Request_Command[PCI_BUS_CBE_RANGE:0] ==
                                PCI_COMMAND_CONFIG_WRITE));  // captured data used

// Either Data or Data Last must follow the Address item
  wire   [2:0] Next_Data_Type = Master_Using_Retry_Info
                      ? Master_Retry_Data_Type[2:0]
                      : pci_request_fifo_type_current[2:0];

  wire    Request_FIFO_CONTAINS_DATA_TWO_MORE =  // could happen at same time as FIFO_CONTAINS_ADDRESS
                   (   (   (   ~Master_Using_Retry_Info
                             &  request_fifo_two_words_available_meta)
                         | (    Master_Using_Retry_Info  // stored address plus data
                             &  Retry_Addr_Data_Avail
                             &  request_fifo_data_available_meta) )
                     & (   (Next_Data_Type[2:0] ==
                                PCI_HOST_REQUEST_W_DATA_RW_MASK)
                         | (Next_Data_Type[2:0] ==
                                PCI_HOST_REQUEST_W_DATA_RW_MASK_PERR)));

  wire    Request_FIFO_CONTAINS_DATA_MORE =  // could happen at same time as FIFO_CONTAINS_ADDRESS
                   (   (   (   ~Master_Using_Retry_Info
                             &  request_fifo_data_available_meta)
                         | (    Master_Using_Retry_Info  // stored address plus data
                             &  Retry_Addr_Data_Avail) )
                     & (   (Next_Data_Type[2:0] ==
                                PCI_HOST_REQUEST_W_DATA_RW_MASK)
                         | (Next_Data_Type[2:0] ==
                                PCI_HOST_REQUEST_W_DATA_RW_MASK_PERR)));
  wire    Request_FIFO_CONTAINS_DATA_LAST =  // could happen with FIFO_CONTAINS_ADDRESS
                   (   (   (   ~Master_Using_Retry_Info
                             &  request_fifo_data_available_meta)
                         | (    Master_Using_Retry_Info  // stored address plus data
                             &  Retry_Addr_Data_Avail) )
                     & (   (Next_Data_Type[2:0] ==
                                PCI_HOST_REQUEST_W_DATA_RW_MASK_LAST)
                         | (Next_Data_Type[2:0] ==
                                PCI_HOST_REQUEST_W_DATA_RW_MASK_LAST_PERR)));

// This only needs to look at the next item in the FIFO, because Housekeeping info
//   is never stored in the Retry registers.  Also, this will only be looked at (if
//   at all) after the data stored in the Retry registers is used.
  wire    Request_FIFO_CONTAINS_HOUSEKEEPING_DATA =
                  request_fifo_data_available_meta  // only 1 word, never saved for retry
               & (   (pci_request_fifo_type_current[2:0] ==
                                PCI_HOST_REQUEST_INSERT_WRITE_FENCE)  // also Reg Refs
                   | (pci_request_fifo_type_current[2:0] ==
                                PCI_HOST_REQUEST_SPARE));

// The Master State Machine as described in the PCI Local Bus Spec
//   Revision 2.2 Appendix B.
// No Lock State Machine is implemented.
// This design only supports a 32-bit FIFO.
// This design supports only 32-bit addresses, no Dual-Address cycles.
// This design supports only the 32-bit PCI bus.
// This design does not implement Interrupt Acknowledge Cycles.
// This design does not implement Special Cycles.
// This design does not enforce any Data rules for Memory Write and Invalidate.
//
// At the beginning of a transfer, the Master asserts FRAME and
//   not IRDY for 1 clock, independent of all other signals, to
//   indicate Address Valid.  This is the PCI_MASTER_ADDR state.
//
// The Master then might choose to insert Wait States.  A Wait
//   State is when FRAME and not IRDY are asserted.  The Wait
//   State can be ended when the Master has data to transfer, or the
//   Wait State might also end when a Target Disconnect with no
//   data or a Target Abort happens.  The Wait State will not
//   end if a Target Disconnect With Data happens, unless the
//   Master is also ready to transfer data.  This is the
//   PCI_MASTER_DATA_OR_WAIT state.
//
// At the end of the address phase or a wait state, the Master
//   will either assert FRAME with IRDY to indicate that data is
//   ready and that more data will be available, or it will assert
//   no FRAME and IRDY to indicate that the last data is available.
//   The Data phase will end when the Target indicates that a
//   Target Disconnect with no data or a Target Abort has occurred,
//   fror that the Target has transferred data.  The Target can also
//   indicate that this should be a target disconnect with data.
//   This is also the PCI_MASTER_DATA_OR_WAIT state.
//
// In some situations, like when a Master Abort happens, or when
//   certain Target Aborts happen, the Master will have to transition
//   om asserting FRAME and not IRDY to no FRAME and IRDY, to let
//   the target end the transfer state sequence correctly.
//   This is the PCI_MASTER_STOP_TURN state
//
// There is one other thing to mention (if not covered above).  Sometimes
//   the Master may have a large burst, and the Target may accept it.
//   As the burst proceeds, one of 2 things may make the burst end in
//   an unusual way.  1) Master data not available soon enough, causing
//   master to time itself off the bus, or 2) GNT removed, causing
//   master to have to get off bus when the Latency Timer runs out.
//   In both cases, the Master has to fake a Last Data Transfer, then
//   has to re-arbitrate for the bus.  It must then continue the transfer,
//   using the incremented DMA address.  It acts partially like it had
//   received a Target Retry, but with itself causing the disconnect.
//
// Here is my interpretation of the Master State Machine:
//
// The Master is in one of 3 states when transferring data:
// 1) Waiting,
// 2) Transferring data with more to come,
// 3) Transferring the last Data item.
//
// NOTE: The PCI Spec says that the Byte Enables driven by the Master
//   must be valid on all clocks.  Therefore, the Master cannot
//   allow one transfer to complete until it knows that both data for
//   that transfer is available AND byte enables for the next transfer
//   are available.  This requirement means that this logic must be
//   aware of the top 2 entries in the Request FIFO.  The Master might
//   need to do a master disconnect, and a later reference retry,
//   solely because the Byte Enables for the NEXT reference aren't
//   available early enough.  See the PCI Local Bus Spec Revision 2.2
//   section 3.2.2 and 3.3.1 for details.
//
// The Request FIFO can indicate that it
// 1) contains no Data,
// 2) contains Data which is not the last,
// 3) contains the last Data
//
// When the Result FIFO has no room, this holds off Master State Machine
// activity the same as if no Write Data or Read Strobes were available.
//
// The Target can say that it wants a Wait State, that it wants
// to transfer Data, that it wants to transfer the Last Data,
// or that it wants to do a Disconnect, Retry, or Target Abort.
// (This last condition will be called Target DRA below.)
//
// The State Sequence is as follows:
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_IDLE,        FIFO Empty           0      0
// Target Don't Care   X      X                0      0  -> MASTER_IDLE
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_IDLE         FIFO Address + Data  0      0
// Target Don't Care   X      X                1      0  -> MASTER_ADDR
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_ADDR         FIFO Don't care      1      0
// Target Don't Care   X      X                1      0  -> MASTER_NO_IRDY
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_NO_IRDY,     FIFO Empty           1      0
// Master Abort        X      X                0      1  -> MASTER_STOP_TURN
// Target Wait         0      0                1      0  -> MASTER_NO_IRDY
// Target DRA          0      1                0      1  -> MASTER_STOP_TURN
// Target Data         1      0                1      0  -> MASTER_NO_IRDY
// Target Last Data    1      1                1      0  -> MASTER_NO_IRDY
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_NO_IRDY,     FIFO non-Last Data   1      0
// Master Abort        X      X                0      1  -> MASTER_STOP_TURN
// Target Wait         0      0                1      1  -> MASTER_DATA_MORE
// Target DRA          0      1                0      1  -> MASTER_STOP_TURN
// Target Data         1      0                1      1  -> MASTER_DATA_MORE
// Target Last Data    1      1                0      1  -> MASTER_DATA_LAST
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_NO_IRDY,     FIFO Last Data       1      0
// Master Abort        X      X                0      1  -> MASTER_STOP_TURN
// Target Wait         0      0                0      1  -> MASTER_DATA_LAST
// Target DRA          0      1                0      1  -> MASTER_STOP_TURN
// Target Data         1      0                0      1  -> MASTER_DATA_LAST
// Target Last Data    1      1                0      1  -> MASTER_DATA_LAST
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_DATA_MORE,   FIFO Empty           1      1
// Master Abort        X      X                0      1  -> MASTER_STOP_TURN
// Target Wait         0      0                1      1  -> MASTER_DATA_MORE
// Target DRA          0      1                0      1  -> MASTER_STOP_TURN
// Target Data         1      0                1      0  -> MASTER_NO_IRDY
// Target Last Data    1      1                0      1  -> MASTER_DATA_TURN
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_DATA_MORE,   FIFO non-Last Data   1      1
// Master Abort        X      X                0      1  -> MASTER_STOP_TURN
// Target Wait         0      0                1      1  -> MASTER_DATA_MORE
// Target DRA          0      1                0      1  -> MASTER_STOP_TURN
// Target Data         1      0                1      1  -> MASTER_DATA_MORE
// Target Last Data    1      1                0      1  -> MASTER_DATA_TURN
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_DATA_MORE,   FIFO Last Data       1      1
// Master Abort        X      X                0      1  -> MASTER_STOP_TURN
// Target Wait         0      0                1      1  -> MASTER_DATA_MORE
// Target DRA          0      1                0      1  -> MASTER_STOP_TURN
// Target Data         1      0                0      1  -> MASTER_DATA_LAST
// Target Last Data    1      1                0      1  -> MASTER_DATA_TURN
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_DATA_LAST,   FIFO Empty           0      1 (or if no Fast Back-to-Back)
// Master Abort        X      X                0      1  -> MASTER_IDLE
// Target Wait         0      0                0      1  -> MASTER_DATA_LAST
// Target DRA          0      1                0      0  -> MASTER_IDLE
// Target Data         1      0                0      0  -> MASTER_IDLE
// Target Last Data    1      1                0      0  -> MASTER_IDLE
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_DATA_LAST,   FIFO Address         0      1 (step and if Fast Back-to-Back)
// Master Abort        X      X                0      1  -> MASTER_IDLE
// Target Wait         0      0                0      1  -> MASTER_DATA_LAST
// Target DRA          0      1                0      0  -> MASTER_IDLE
// Target Data         1      0                0      0  -> MASTER_IDLE
// Target Last Data    1      1                0      0  -> MASTER_IDLE
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_DATA_LAST,   FIFO Address + Data  0      1 (no step and if Fast Back-to-Back)
// Master Abort        X      X                0      1  -> MASTER_IDLE
// Target Wait         0      0                0      1  -> MASTER_DATA_LAST
// Target DRA          0      1                0      0  -> MASTER_IDLE
// Target Data         1      0                1      0  -> MASTER_ADDR
// Target Last Data    1      1                1      0  -> MASTER_ADDR
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_STOP_TURN,   FIFO Empty           0      1 (don't care Fast Back-to-Back)
// Handling Master Abort or Target Abort       0      0  -> MASTER_FLUSH
// Target Don't Care   X      X                0      0  -> MASTER_IDLE
//                    TRDY   STOP            FRAME   IRDY
//    MASTER_STOP_TURN,   FIFO Address         0      1 (don't care Fast Back-to-Back)
// Handling Master Abort or Target Abort       0      0  -> MASTER_FLUSH
// Target Don't Care   X      X                0      0  -> MASTER_IDLE
//
// NOTE: In all cases, the FRAME and IRDY signals are calculated
//   based on the TRDY and STOP signals, which are very late and very
//   timing critical.
// The functions will be implemented as a 4-1 MUX using TRDY and STOP
//   as the selection variables.
// The inputs to the FRAME and IRDY MUX's will be decided based on the state
//   the Master is in, and also on the contents of the Request FIFO.
// NOTE: For both FRAME and IRDY, there are 5 possible functions of
//   TRDY and STOP.  Both output bits might be all 0's, all 1's, and
//   each has 3 functions which are not all 0's nor all 1's.
// NOTE: These extremely timing critical functions will each be implemented
//   as a single CLB in a Xilinx chip, with a 3-bit Function Selection
//   paramater.  The 3 bits plus TRDY plus STOP use up a 5-input LUT.
//
// The functions are as follows:
//    Function Sel [2:0]  TRDY  STOP  ->  FRAME  IRDY
//                  000    X     X          0     0  // FRAME_0, IRDY_0
//
//                  1XX    X     X          1     1  // FRAME_1, IRDY_1
//
// Target Wait      001    0     0          1     0  // FRAME_UNLESS_STOP
// Target DRA       001    0     1          0     1  // IRDY_IF_STOP
// Target Data      001    1     0          1     0
// Target Last Data 001    1     1          1     0
//
// Target Wait      010    0     0          1     1  // FRAME_UNLESS_LAST
// Target DRA       010    0     1          0     1  // IRDY_UNLESS_MORE
// Target Data      010    1     0          1     0
// Target Last Data 010    1     1          0     1
//
// Target Wait      011    0     0          1     1  // FRAME_WHILE_WAIT
// Target DRA       011    0     1          0     0  // IRDY_WHILE_WAIT
// Target Data      011    1     0          0     0
// Target Last Data 011    1     1          0     0
//
// NOTE: WORKING: new value here for fast back-to-back.
//
// For each state, use the function:       F(Frame) F(IRDY)
//    MASTER_IDLE,        FIFO Empty          000     000 (no FRAME, IRDY)
//    MASTER_IDLE         FIFO Address        100     000 (Always FRAME)
//    MASTER_ADDR         FIFO Don't care     100     000 (Always FRAME)
//    MASTER_NO_IRDY,     FIFO Empty          001     001 (FRAME unless DRA)
//    MASTER_NO_IRDY,     FIFO non-Last Data  010     100
//    MASTER_NO_IRDY,     FIFO Last Data      000     100
//    MASTER_DATA_MORE,   FIFO Empty          010     010
//    MASTER_DATA_MORE,   FIFO non-Last Data  010     100
//    MASTER_DATA_MORE,   FIFO Last Data      011     100
//    MASTER_DATA_LAST,   FIFO Empty          000     011 (or if no Fast Back-to-Back)
//    MASTER_DATA_LAST,   FIFO Address        100     000 (and if Fast Back-to-Back)
// NOTE:  what about Step?  Punt to Idle!
//    MASTER_STOP_TURN,   FIFO Empty          000     000 (or if no Fast Back-to-Back)
//    MASTER_STOP_TURN,   FIFO Address        100     000 (and if Fast Back-to-Back)
//    MASTER_PARK_BUS,    FIFO Empty          000     000 (no FRAME, IRDY)
//    MASTER_PARK_BUS,    FIFO_Address        100     000 (Always FRAME)

// NOTE: these declarations are duplicated in the Vendor Library.
  parameter FRAME_0                 = 3'b000;
  parameter FRAME_UNLESS_STOP       = 3'b001;
  parameter FRAME_UNLESS_LAST       = 3'b010;
  parameter FRAME_WHILE_WAIT        = 3'b011;
  parameter FRAME_BACK_TO_BACK      = 3'b100;
  parameter FRAME_1                 = 3'b101;
  parameter FRAME_IF_GNT            = 3'b110;
  parameter FRAME_IF_GNT_IDLE       = 3'b111;

  parameter IRDY_0                  = 3'b000;
  parameter IRDY_IF_STOP            = 3'b001;
  parameter IRDY_UNLESS_MORE        = 3'b010;
  parameter IRDY_WHILE_WAIT         = 3'b011;
  parameter IRDY_1                  = 3'b100;

// State Variables are closely related to PCI Control Signals:
// This nightmare is actually the product of 3 State Machines: PCI, R/W, Retry A/D
//  They are (in order) CBE_OE, FRAME_L, IRDY_L, State_[1,0]
  parameter PCI_MASTER_IDLE              = 5'b0_00_00;  // Master in IDLE state
  parameter PCI_MASTER_PARK              = 5'b1_00_00;  // Bus Park
  parameter PCI_MASTER_STEP              = 5'b1_00_01;  // Address Step

  parameter PCI_MASTER_ADDR              = 5'b1_10_00;  // Master Drives Address
  parameter PCI_MASTER_ADDR64            = 5'b1_10_01;  // Master Drives Address in 64-bit Address mode

  parameter PCI_MASTER_LAST_PENDING      = 5'b1_10_11;  // Sending Last Data as First Word
  parameter PCI_MASTER_MORE_PENDING      = 5'b1_10_10;  // Waiting for Master Data

  parameter PCI_MASTER_DATA_MORE         = 5'b1_11_10;  // Master Transfers Data

  parameter PCI_MASTER_NODATA_TURN       = 5'b1_01_00;  // Target Transfers More Data as Last, then No Data
  parameter PCI_MASTER_STOP_TURN         = 5'b1_01_01;  // Stop makes Turn Around

  parameter PCI_MASTER_DATA_LAST         = 5'b1_01_10;  // Master Transfers Last Data
  parameter PCI_MASTER_DATA_MORE_TO_LAST = 5'b1_01_11;  // Master Transfers Regular Data as Last

  parameter PCI_MASTER_LAST_IDLE         = 5'b0_00_01;  // Master goes Idle, but data not transferred

  parameter MS_Range = 4;
  parameter MS_X = {(MS_Range+1){1'bX}};

// Classify the activity of the External Target.
// These correspond to            {trdy, stop}
  parameter TARGET_IDLE             = 2'b00;
  parameter TARGET_TAR              = 2'b01;
  parameter TARGET_DATA_MORE        = 2'b10;
  parameter TARGET_DATA_LAST        = 2'b11;

// Experience with the PCI Master Interface teaches that the signals
//   TRDY and STOP are extremely time critical.  These signals cannot be
//   latched in the IO pads.  The signals must be acted upon by the
//   Master State Machine as combinational inputs.
//
// The combinational logic is below.  This feeds into an Output Flop
//   which is right at the IO pad.  The State Machine uses the DEVSEL,
//   TRDY, and STOP signals which are latched in the input pads.
//   Therefore, all the fast stuff is in the gates below this case statement.

// NOTE:  The Master is not allowed to drive FRAME unless GNT is asserted.
// NOTE:  GNT_L is VERY LATE.  (However, it is not as late as the signals
//   TRDY_L and STOP_L.)    Make sure that this logic places the GNT
//   dependency on the fast branch.  See the PCI Local Bus Spec
//   Revision 2.2 section 3.4.1 and 7.6.4.2 for details.
// NOTE:  The Master is not allowed to take the bus from someone else until
//   FRAME and IRDY are both unasserted.  When fast back-to-back transfers
//   are happening, the state machine can drive Frame when it is driving
//   IRDY the previous clock.

// NOTE: FRAME and IRDY are VERY LATE.  This logic is in the critical path.
// See the PCI Local Bus Spec Revision 2.2 section 3.4.1 for details.

// Given a present Master State and all appropriate inputs, calculate the next state.
// Here is how to think of it for now: When a clock happens, this says what to do now
function [MS_Range:0] Master_Next_State;
  input  [MS_Range:0] Master_Present_State;
  input   pci_bus_available_critical;
  input   FIFO_CONTAINS_ADDRESS;
  input   Doing_Config_Reference;
  input   FIFO_CONTAINS_DATA_TWO_MORE;
  input   FIFO_CONTAINS_DATA_MORE;
  input   FIFO_CONTAINS_DATA_LAST;
  input   Master_Abort;
  input   Timeout_Forces_Disconnect;
  input   pci_trdy_in;
  input   pci_stop_in;
  input   Back_to_Back_Possible;

  begin
// synopsys translate_off
      if (   ( $time > 0)
           & (   ((pci_trdy_in ^ pci_trdy_in) === 1'bX)
               | ((pci_stop_in ^ pci_stop_in) === 1'bX)))
      begin
        Master_Next_State[MS_Range:0] = MS_X;  // error
        $display ("*** %m PCI Master Wait TRDY, STOP Unknown %x %x at time %t",
                    pci_trdy_in, pci_stop_in, $time);
      end
      else
// synopsys translate_on

      case (Master_Present_State[MS_Range:0])
      PCI_MASTER_IDLE:
        begin
          if (pci_bus_available_critical == 1'b1)
          begin                  // external_pci_bus_available_critical is VERY LATE
            if (FIFO_CONTAINS_ADDRESS == 1'b0)  // bus park
              Master_Next_State[MS_Range:0] = PCI_MASTER_PARK;
            else if (Doing_Config_Reference == 1'b1)
              Master_Next_State[MS_Range:0] = PCI_MASTER_STEP;
            else  // must be regular reference.
              Master_Next_State[MS_Range:0] = PCI_MASTER_ADDR;
          end
          else
            Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
        end
      PCI_MASTER_PARK:
        begin
          if (pci_bus_available_critical == 1'b1)  // only needs GNT, but this OK
          begin                  // external_pci_bus_available_critical is VERY LATE
            if (FIFO_CONTAINS_ADDRESS == 1'b0)  // bus park
              Master_Next_State[MS_Range:0] = PCI_MASTER_PARK;
            else if (Doing_Config_Reference == 1'b1)
              Master_Next_State[MS_Range:0] = PCI_MASTER_STEP;
            else  // must be rgular reference.
              Master_Next_State[MS_Range:0] = PCI_MASTER_ADDR;
          end
          else
            Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
        end
      PCI_MASTER_STEP:
        begin                    // external_pci_bus_available_critical is VERY LATE
          if (pci_bus_available_critical == 1'b1)  // only needs GNT, but this OK
            Master_Next_State[MS_Range:0] = PCI_MASTER_ADDR;
          else
            Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
        end
      PCI_MASTER_ADDR:
        begin  // when 64-bit Address added, -> PCI_MASTER_ADDR64
          if (FIFO_CONTAINS_DATA_LAST == 1'b1)
            Master_Next_State[MS_Range:0] = PCI_MASTER_LAST_PENDING;
          else
            Master_Next_State[MS_Range:0] = PCI_MASTER_MORE_PENDING;
        end
      PCI_MASTER_ADDR64:
        begin  // Not implemented yet. Will be identical to Addr above + Wait
          if (FIFO_CONTAINS_DATA_LAST == 1'b1)
            Master_Next_State[MS_Range:0] = PCI_MASTER_LAST_PENDING;
          else
            Master_Next_State[MS_Range:0] = PCI_MASTER_MORE_PENDING;
        end
// Enter LAST_PENDING state when this knows a Last Data is next.  Want to keep
//   the timing the same as for normal data transfers
      PCI_MASTER_LAST_PENDING:
        begin
            Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_LAST;
        end
// Enter MORE_PENDING state when Master has 1 data item available, but needs a second.
// The second item is needed because the Byte Strobes must be available immediately
//   when the TRDY signal consumes the first data item.
      PCI_MASTER_MORE_PENDING:
        begin
          if (Master_Abort == 1'b1)
          begin
            Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
          end
          else if (   (FIFO_CONTAINS_DATA_MORE == 1'b0)
                    & (FIFO_CONTAINS_DATA_LAST == 1'b0)
                    & (Timeout_Forces_Disconnect == 1'b0))  // no Master data or bus removed
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_MORE_PENDING;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_MORE_PENDING;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE_TO_LAST;
            `NO_DEFAULT;
            endcase
          end
          else if (Timeout_Forces_Disconnect == 1'b1)  // NOTE: shortcut; even if no data
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE_TO_LAST;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE_TO_LAST;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE_TO_LAST;
            `NO_DEFAULT;
            endcase
          end
          else if (   (FIFO_CONTAINS_DATA_MORE == 1'b1)
                    | (FIFO_CONTAINS_DATA_LAST == 1'b1))
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE_TO_LAST;
            `NO_DEFAULT;
            endcase
          end
          else  // Fifo has something wrong with it.  Bug.
          begin
            Master_Next_State[MS_Range:0] = MS_X;  // error
// synopsys translate_off
            $display ("*** %m PCI Master WAIT Fifo Contents Unknown %x at time %t",
                           Master_Next_State[MS_Range:0], $time);
// synopsys translate_on
          end
        end
// Enter Data_More State when Master ready to send non-last Data, plus 1 more data item.
      PCI_MASTER_DATA_MORE:
        begin
          if (Master_Abort == 1'b1)
          begin
            Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
          end
          else if (   (FIFO_CONTAINS_DATA_TWO_MORE == 1'b0)
                    & (FIFO_CONTAINS_DATA_LAST == 1'b0)  // no Master data ready
                    & (Timeout_Forces_Disconnect == 1'b0))  // no Master data or bus removed
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_MORE_PENDING;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_NODATA_TURN;
            `NO_DEFAULT;
            endcase
          end
          else if (FIFO_CONTAINS_DATA_LAST == 1'b1)
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_LAST;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_NODATA_TURN;
            `NO_DEFAULT;
            endcase
          end
          else if (Timeout_Forces_Disconnect == 1'b1)  // NOTE: shortcut; even if no data
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE_TO_LAST;  // bug?
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_NODATA_TURN;
            `NO_DEFAULT;
            endcase
          end
          else if (FIFO_CONTAINS_DATA_TWO_MORE == 1'b1)
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_STOP_TURN;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_NODATA_TURN;
            `NO_DEFAULT;
            endcase
          end
          else  // Fifo has something wrong with it.  Bug.
          begin
            Master_Next_State[MS_Range:0] = MS_X;  // error
// synopsys translate_off
            $display ("*** %m PCI Master Data More Fifo Contents Unknown %x at time %t",
                           Master_Next_State[MS_Range:0], $time);
// synopsys translate_on
          end
        end
// Enter NODATA_TURN State when Master says More, but Target says Last
// The present data is transferred, the next data is not.
// NOTE: No specific term to get to Bus Park.  It is not necessary to go directly
//    to a parked condition.  Get to park by going through IDLE.  See the PCI
//    Local Bus Spec Revision 2.2 section 3.4.3 for details.
      PCI_MASTER_NODATA_TURN:
        begin
          Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
        end
// Enter STOP_TURN when Master asserting FRAME and either IRDY or not IRDY,
//   and either a Master Abort happens, or a Target Abort happens, or a
//   Target Retry with no data transferred happens.
// The waiting data is not transferred.
// NOTE: No specific term to get to Bus Park.  It is not necessary to go directly
//    to a parked condition.  Get to park by going through IDLE.  See the PCI
//    Local Bus Spec Revision 2.2 section 3.4.3 for details.
      PCI_MASTER_STOP_TURN:
        begin
          Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
        end
// Enter Last State when Master ready to send Last Data
// NOTE: No specific term to get to Bus Park.  It is not necessary to go directly
//    to a parked condition.  Get to park by going through IDLE.  See the PCI
//    Local Bus Spec Revision 2.2 section 3.4.3 for details.
      PCI_MASTER_DATA_LAST:
        begin
          if (Master_Abort == 1'b1)
          begin
            Master_Next_State[MS_Range:0] = PCI_MASTER_LAST_IDLE;
          end
          else if (   (FIFO_CONTAINS_ADDRESS == 1'b0)
                    | (   (FIFO_CONTAINS_ADDRESS == 1'b1)
                        & (Doing_Config_Reference == 1'b1) )
                    | (Back_to_Back_Possible == 1'b0))  // go idle
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_LAST;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_LAST_IDLE;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
            `NO_DEFAULT;
            endcase
          end
          else if (   (FIFO_CONTAINS_ADDRESS == 1'b1)
                    & (Doing_Config_Reference == 1'b0)
                    & (Back_to_Back_Possible == 1'b1))  // don't be tricky on config refs.
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_LAST;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_LAST_IDLE;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_ADDR;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_ADDR;
            `NO_DEFAULT;
            endcase
          end
          else  // Fifo has something wrong with it.  Bug.
          begin
            Master_Next_State[MS_Range:0] = MS_X;  // error
// synopsys translate_off
            $display ("*** %m PCI Master Data More Fifo Contents Unknown %x at time %t",
                           Master_Next_State[MS_Range:0], $time);
// synopsys translate_on
          end
        end
// Enter MORE_TO_LAST State for 1 of several reasons:
// 1) Master waiting for second Data to become available, and Target says early Last.
//      Make the datain escrow into an early Last.
// 2) Master waiting for Target to accept More Data, and bus timeout occurs,
//      and Target says More.  Make the NEW data into an early Last.
// The data sent is sent as a Last Data, even if it is a More Data.
// NOTE in case 2 above, the LAST might terminate with a STOP!
// NOTE: No specific term to get to Bus Park.  It is not necessary to go directly
//    to a parked condition.  Get to park by going through IDLE.  See the PCI
//    Local Bus Spec Revision 2.2 section 3.4.3 for details.
      PCI_MASTER_DATA_MORE_TO_LAST:
        begin
          begin
            case ({pci_trdy_in, pci_stop_in})
            TARGET_IDLE:      Master_Next_State[MS_Range:0] = PCI_MASTER_DATA_MORE_TO_LAST;
            TARGET_TAR:       Master_Next_State[MS_Range:0] = PCI_MASTER_LAST_IDLE;
            TARGET_DATA_MORE: Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
            TARGET_DATA_LAST: Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
            `NO_DEFAULT;
            endcase
          end
        end
// Enter LAST_IDLE when Master asserting IRDY and not FRAME, and a Master Abort
//   happens, or a Target Stop happens.
// The waiting data is not transferred.
// NOTE: No specific term to get to Bus Park.  It is not necessary to go directly
//    to a parked condition.  Get to park by going through IDLE.  See the PCI
//    Local Bus Spec Revision 2.2 section 3.4.3 for details.
      PCI_MASTER_LAST_IDLE:
        begin
          Master_Next_State[MS_Range:0] = PCI_MASTER_IDLE;
        end
      default:
        begin
          Master_Next_State[MS_Range:0] = MS_X;  // error
// synopsys translate_off
          if ($time > 0)
            $display ("*** %m PCI Master State Machine Unknown %x at time %t",
                           Master_Next_State[MS_Range:0], $time);
// synopsys translate_on
        end
      endcase
  end
endfunction

// Start a reference when the bus is idle, or immediately if fast back-to-back.
// pci_frame_in_critical and pci_irdy_in_critical are VERY LATE.
// pci_gnt_in_critical is VERY LATE, but not as late as the other two.
// NOTE: WORKING: Very Subtle point.  The PCI Master may NOT look at the value
//   of signals it drove itself the previous clock.  The driver of a PCI bus
//   receives the value it drove later than all other devices.  See the PCI
//   Local Bus Spec Revision 2.2 section 3.10 item 9 for details.
//   FRAME isn't a problem, because it is driven 1 clock before IRDY.
//   This must therefore NOT look at IRDY unless it very sure that the the
//   data is constant for 2 clocks.  How?
// NOTE: It seems that FRAME and IRDY in must use the output value when they are driving
// NOTE: WORKING: Make sure Frame and IRDY are internally fed back when locally driven
  wire    external_pci_bus_available_critical = pci_gnt_in_critical
                        & ~pci_frame_in_critical & ~pci_irdy_in_critical;

// State Machine controlling the PCI Master.
//   Every clock, this State Machine transitions based on the LATCHED
//   versions of TRDY and STOP.  At the same time, combinational logic
//   below has already sent out the NEXT info to the PCI bus.
//  (These two actions had better be consistent.)
// The way to think about this is that the State Machine reflects the
//   PRESENT state of the PCI wires.  When you are in the Address state,
//   the Address is valid on the bus.
  reg    [MS_Range:0] PCI_Master_State;

  wire   [MS_Range:0] PCI_Master_Next_State =
              Master_Next_State (
                PCI_Master_State[MS_Range:0],
                external_pci_bus_available_critical,
                Request_FIFO_CONTAINS_ADDRESS,
                Master_Doing_Config_Reference,
                Request_FIFO_CONTAINS_DATA_TWO_MORE,
                Request_FIFO_CONTAINS_DATA_MORE,
                Request_FIFO_CONTAINS_DATA_LAST,
                Master_Abort_Detected,
                Master_Data_Latency_Disconnect, // | Master_Bus_Latency_Disconnect,
                pci_trdy_in_critical,
                pci_stop_in_critical,
                Fast_Back_to_Back_Possible
              );

// Actual State Machine includes async reset
  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      PCI_Master_State[MS_Range:0] <= PCI_MASTER_IDLE;
    end
    else
    begin
      PCI_Master_State[MS_Range:0] <= PCI_Master_Next_State[MS_Range:0];
    end
  end

// Classify the Present State to make the terms below easier to understand.
  wire    Master_In_Idle_State =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_IDLE);

  wire    Master_In_Park_State =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_STEP);

  wire    Master_In_Step_State =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_STEP);

  wire    Master_In_Idle_Park_Step_State =
                      (Master_In_Idle_State == 1'b1)
                    | (Master_In_Park_State == 1'b1)
                    | (Master_In_Step_State == 1'b1);

  wire    Master_In_Addr_State =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR)
                    | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR64);

  wire    Master_In_No_IRDY_State =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING)
                    | (PCI_Master_State[MS_Range:0] == PCI_MASTER_LAST_PENDING);
  wire    Master_In_Data_More_State =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE);
  wire    Master_In_Data_Last_State =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST)
                    | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_TO_LAST);
  wire    Master_In_Stop_Turn_State =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_STOP_TURN);

  wire    Master_Transfering_Data_If_TRDY =
                      (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE)
                    | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST)
                    | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_TO_LAST);

  wire    Master_Transfering_Read_Data_If_TRDY = ~Master_Retry_Write
                    & (   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE)
                        | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST)
                        | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_TO_LAST));

  wire    Master_In_Read_State =  ~Master_Retry_Write // NOTE: WORKING: Not Early enough?
                    &  (   (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR)
                         | (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING)
                         | (PCI_Master_State[MS_Range:0] == PCI_MASTER_LAST_PENDING)
                         | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE)
                         | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST)
                         | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_TO_LAST) );

// Calculate several control signals used to direct data and control
// These signals depend on the present state of the PCI Master State
//   Machine and the LATCHED versions of DEVSEL, TRDY, STOP, PERR, SERR
// The un-latched versions can't be used, because they are too late.

// During Address Phase and First Data Phase, always update the PCI Bus.
// After those two clocks, the PCI bus will only update when IRDY and TRDY.

// Controls the unloading of the Request FIFO.  Only unload when previous data done.
  assign  Master_Consumes_Request_FIFO_Data_Unconditionally_Critical =
                  (   (Request_FIFO_CONTAINS_ADDRESS == 1'b1)  // Address
                    & (external_pci_bus_available_critical == 1'b1)  // Have bus
                    & (   (Master_In_Idle_State == 1'b1)
                        | (Master_In_Park_State == 1'b1)) )
                | (Master_In_Addr_State == 1'b1)  // First Data
//              | 1'b0;  // NOTE: WORKING  Need Fast Back-to-Back Address term
                | Master_Discards_Request_FIFO_Entry_After_Abort;

// This signal controls the actual PCI IO Pads, and results in data the next clock.
  assign  Master_Force_AD_to_Address_Data_Critical =  // drive outputs
                  (   (Request_FIFO_CONTAINS_ADDRESS == 1'b1)  // Address
                    & (external_pci_bus_available_critical == 1'b1)  // Have bus
                    & (   (Master_In_Idle_State == 1'b1)
                        | (Master_In_Park_State == 1'b1)))
                | (Master_In_Addr_State == 1'b1);  // First Data
//              | 1'b0;  // NOTE: WORKING  Need Fast Back-to-Back Address term

// This signal controls the unloading of the Request FIFO in this module.
  assign  Master_Consumes_Request_FIFO_If_TRDY = Master_In_Data_More_State
                | 1'b0;  // NOTE: WORKING  Might put fast back-to-back term here!

// This signal controls the actual PCI IO Pads, and results in data the next clock.
  assign  Master_Exposes_Data_On_TRDY = Master_Consumes_Request_FIFO_If_TRDY;  // drive outputs  // NOTE: WORKING  Only on READS!

// This signal tells the Target to grab data from the PCI bus this clock.
  assign  Master_Captures_Data_On_TRDY = Master_Consumes_Request_FIFO_If_TRDY;  // drive outputs  // NOTE: WORKING  Only on READS!

// Start the DEVSEL counter whenever an Address is sent out.
  assign  Master_Clear_Master_Abort_Counter =
                        (Master_In_Idle_Park_Step_State == 1'b1)
                      | (Master_In_Addr_State == 1'b1);  // NOTE: WORKING: fast back-to-back

// Start the Data Latency Counter whenever Address or IRDY & TRDY
  assign  Master_Clear_Data_Latency_Counter =
                        (Master_In_Idle_Park_Step_State == 1'b1)
                      | (Master_In_Addr_State == 1'b1)
                      | 1'b0;  // NOTE: WORKING: IRDY_TRDY term

// Bus Latency Timer counts whenever GNT not asserted.
  assign  Master_Clear_Bus_Latency_Timer = 1'b0;  // NOTE: WORKING

// This signal muxes the Stored Address onto the PCI bus during retries.
  wire    Master_Select_Stored_Address =
                  (   Retry_Addr_No_Data_Avail | Retry_Addr_Data_Avail)
                & (Master_In_Idle_Park_Step_State == 1'b1);  // NOTE: WORKING add fast back-to-back

// This signal muxes the Stored Data onto the PCI bus during retries.
  wire    Master_Select_Stored_Data =
                        Retry_Addr_Data_Avail
                      & (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR);


  assign  Master_Mark_Status_Entry_Flushed = 1'b0;  // NOTE: WORKING
  assign  Master_Discards_Request_FIFO_Entry_After_Abort = 1'b0;  // NOTE: WORKING
  assign  Master_Using_Retry_Info = 1'b0;  // NOTE: WORKING
  assign  Master_Completed_Retry_Address = 1'b0;  // NOTE: WORKING
  assign  Master_Completed_Retry_Data = 1'b0;  // NOTE: WORKING
  assign  Master_Got_Retry = 1'b0;  // NOTE WORKING

// NOTE: WORKING: this plays in to the idea that fast back-to-back does NOT
//   need to look at the FRAME and IRDY.  IT just lunges ahead, until it
//   sees the Bus Latency Timer time out.  Fast Back-to-Back therefore depends
//   on whether the timeout happens.
  assign  Fast_Back_to_Back_Possible = 1'b0;  // NOTE: WORKING
  assign  Master_Forced_Off_Bus_By_Target_Abort = 1'b0;  // NOTE: WORKING
  assign  Master_Forces_PERR = 1'b0;  // NOTE: WORKING

  assign  master_got_parity_error = 1'b0;  // NOTE: WORKING
  assign  master_caused_serr = 1'b0;  // NOTE: WORKING
  assign  master_caused_master_abort = 1'b0;  // NOTE: WORKING
  assign  master_got_target_abort = 1'b0;  // NOTE: WORKING
  assign  master_caused_parity_error = 1'b0;  // NOTE: WORKING
  assign  master_asked_to_retry = 1'b0;  // NOTE: WORKING

// Whenever the Master is told to get off the bus due to a Target Termination,
// it must remove it's Request for one clock when the bus goes idle and
// one other clock, either before or after the time the bus goes idle.
// See the PCI Local Bus Spec Revision 2.2 section 3.4.1 for details.
// Request whenever enabled, and an Address is available in the Master FIFO
// or a retried address is available.
// NOTE: WORKING: needs a Flop to make this Glitch-Free.  But no extra clocks?
  assign  pci_req_out_next = Request_FIFO_CONTAINS_ADDRESS
                           & (Master_In_Idle_Park_Step_State == 1'b1);

// PCI Request is tri-stated when Reset is asserted.
//   See the PCI Local Bus Spec Revision 2.2 section 2.2.4 for details.
  assign  pci_req_out_oe_comb = ~pci_reset_comb;

// NOTE: WORKING: duplicate logic until fast path is written

  reg     pci_master_ad_out_now, pci_master_cbe_out_now;
  reg     pci_frame_out_now, pci_irdy_out_now;
  reg     pci_frame_out_prev, pci_irdy_out_prev;
  always @(posedge pci_clk or posedge pci_reset_comb)
  begin
    if (pci_reset_comb == 1'b1)
    begin
      pci_master_ad_out_now <= 1'b0;
      pci_master_cbe_out_now <= 1'b0;
      pci_frame_out_now <= 1'b0;
      pci_irdy_out_now <= 1'b0;
      pci_frame_out_prev <= 1'b0;
      pci_irdy_out_prev <= 1'b0;
    end
    else
    begin
      pci_master_ad_out_now <= PCI_Master_Next_State[4] & ~Master_In_Read_State;
      pci_master_cbe_out_now <= PCI_Master_Next_State[4];
      pci_frame_out_now <= PCI_Master_Next_State[3];
      pci_irdy_out_now <= PCI_Master_Next_State[2];
      pci_frame_out_prev <= pci_frame_out_now;
      pci_irdy_out_prev <= pci_irdy_out_now;
    end
  end

  assign  pci_master_ad_out_next[PCI_BUS_DATA_RANGE:0] =
                         Master_Select_Stored_Address
                      ?  Master_Retry_Address[PCI_BUS_DATA_RANGE:0]
                      : (Master_Select_Stored_Data
                      ?  Master_Retry_Data[PCI_BUS_DATA_RANGE:0]
                      :  pci_request_fifo_data_current[PCI_BUS_DATA_RANGE:0]);

  assign  pci_master_ad_out_oe_comb =  pci_master_ad_out_now;

  assign  pci_cbe_l_out_next[PCI_BUS_CBE_RANGE:0] =
                         Master_Select_Stored_Address
                      ?  Master_Retry_Command[PCI_BUS_CBE_RANGE:0]
                      : (Master_Select_Stored_Data
                      ?  Master_Retry_Data_Byte_Enables[PCI_BUS_CBE_RANGE:0]
                      :  pci_request_fifo_cbe_current[PCI_BUS_CBE_RANGE:0]);

  assign  pci_cbe_out_oe_comb = pci_master_cbe_out_now;

  assign  pci_frame_out_next = PCI_Master_Next_State[3];
  assign  pci_frame_out_oe_comb = pci_frame_out_now | pci_frame_out_prev;

  assign  pci_irdy_out_next = PCI_Master_Next_State[2];
  assign  pci_irdy_out_oe_comb = pci_irdy_out_now | pci_irdy_out_prev;



`ifdef NOT_YET  // First get things working, then get it working fast!
  wire    Waiting_For_External_PCI_Bus_To_Go_Idle_Prev;
  assign  Waiting_For_External_PCI_Bus_To_Go_Idle_Prev = 1'b1;  // NOTE: WORKING
  wire    external_pci_bus_prev = pci_gnt_in_prev
                        & (   (   Waiting_For_External_PCI_Bus_To_Go_Idle_Prev
                                & ~pci_frame_in_prev & ~pci_irdy_in_prev)
                            | (  ~Waiting_For_External_PCI_Bus_To_Go_Idle_Prev
                                & Fast_Back_to_Back_Possible) );

// The PCI Bus gets either data directly from the FIFO, or it gets the stored
//   address which has been incrementing until the previous Target Retry was
//   received, or the stored data if the reference ended without data.
// The IO pads contain output flops
  assign  pci_master_ad_out_next[PCI_BUS_DATA_RANGE:0] =
                         Master_Select_Stored_Address
                      ?  Master_Retry_Address[PCI_BUS_DATA_RANGE:0]
                      : (Master_Select_Stored_Data
                      ?  Master_Retry_Data[PCI_BUS_DATA_RANGE:0]
                      :  pci_request_fifo_data_current[PCI_BUS_DATA_RANGE:0]);

// NOTE: WORKING: Maybe Remove this: Make a glitch-free output enable
`ifdef NOT
  reg     pci_master_ad_out_oe_comb;
  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      pci_master_ad_out_oe_comb <= 1'b0;
    end
    else
    begin
      pci_master_ad_out_oe_comb <= 
                        (   (Master_In_Idle_State == 1'b1)
                          & (external_pci_bus_prev == 1'b1))  // external_pci_bus_available_critical is VERY LATE
                      | (   (Master_In_Park_State == 1'b1)
                          & (pci_gnt_in_prev == 1'b1))  // pci_gnt_in_critical is VERY LATE
                      | (   (Master_In_Step_State == 1'b1)
                          & (pci_gnt_in_prev == 1'b1))  // pci_gnt_in_critical is VERY LATE
                      | (Master_In_Addr_State == 1'b1)
                      | (   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING)
                          & Master_Retry_Write)
                      | (   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE)
                          & Master_Retry_Write)
                      | (   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST)
                          & Master_Retry_Write)
                      | 1'b0;  // NOTE: WORKING
    end
  end
`endif
  assign  pci_master_ad_out_oe_comb = 
                        (   (Master_In_Idle_State == 1'b1)
                          & (external_pci_bus_prev == 1'b1))  // external_pci_bus_available_critical is VERY LATE
                      | (   (Master_In_Park_State == 1'b1)
                          & (pci_gnt_in_prev == 1'b1))  // pci_gnt_in_critical is VERY LATE
                      | (   (Master_In_Step_State == 1'b1)
                          & (pci_gnt_in_prev == 1'b1))  // pci_gnt_in_critical is VERY LATE
                      | (Master_In_Addr_State == 1'b1)
                      | (Master_In_Write_State == 1'b1)
                      | 1'b0;  // NOTE: WORKING

// The IO pads contain output flops
  assign  pci_cbe_l_out_next[PCI_BUS_CBE_RANGE:0] =
                         Master_Select_Stored_Address
                      ?  Master_Retry_Command[PCI_BUS_CBE_RANGE:0]
                      : (Master_Select_Stored_Data
                      ?  Master_Retry_Data_Byte_Enables[PCI_BUS_CBE_RANGE:0]
                      :  pci_request_fifo_cbe_current[PCI_BUS_CBE_RANGE:0]);
// NOTE: WORKING: Maybe Remove this: Make a glitch-free output enable
`ifdef NOT
  reg     pci_cbe_out_oe_comb;
  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      pci_cbe_out_oe_comb <= 1'b0;
    end
    else
    begin
      pci_cbe_out_oe_comb <=
                        (   (Master_In_Idle_State == 1'b1)
                          & (external_pci_bus_prev == 1'b1))  // external_pci_bus_available_critical is VERY LATE
                      | (   (Master_In_Park_State == 1'b1)
                          & (pci_gnt_in_prev == 1'b1))  // pci_gnt_in_critical is VERY LATE
                      | (   (Master_In_Step_State == 1'b1)
                          & (pci_gnt_in_prev == 1'b1))  // pci_gnt_in_critical is VERY LATE
                      | (Master_In_Addr_State == 1'b1)
                      | (Master_In_Write_State == 1'b1)
                      | (Master_In_Read_State == 1'b1)
                      | 1'b0;  // NOTE: WORKING
    end
  end
`endif
  assign  pci_cbe_out_oe_comb =
                        (   (Master_In_Idle_State == 1'b1)
                          & (external_pci_bus_prev == 1'b1))  // external_pci_bus_available_critical is VERY LATE
                      | (   (Master_In_Park_State == 1'b1)
                          & (pci_gnt_in_prev == 1'b1))  // pci_gnt_in_critical is VERY LATE
                      | (   (Master_In_Step_State == 1'b1)
                          & (pci_gnt_in_prev == 1'b1))  // pci_gnt_in_critical is VERY LATE
                      | (Master_In_Addr_State == 1'b1)
                      | (Master_In_Write_State == 1'b1)
                      | (Master_In_Read_State == 1'b1)
                      | 1'b0;  // NOTE: WORKING

// As quickly as possible, decide whether to present new Master Control Info
//   on Master Control bus, or to continue sending old data.  The state machine
//   needs to know what happened too, so it can prepare the Control info for
//   next time.
// NOTE: IRDY and TRDY are very late.  3 nSec before clock edge!
// NOTE: The FRAME_Next and IRDY_Next signals are latched in the
//       outputs pad in the IO pad module.

  wire   [2:0] PCI_Next_FRAME_Code =
                ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_IDLE)
                   &  Request_FIFO_CONTAINS_ADDRESS
                   & ~Master_Doing_Config_Reference)
                                                 ? FRAME_1 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_PARK)
                   &  Request_FIFO_CONTAINS_ADDRESS
                   & ~Master_Doing_Config_Reference)
                                                 ? FRAME_1 : FRAME_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_STEP)
                                                 ? FRAME_1 : FRAME_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR)
                                                 ? FRAME_1 : FRAME_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR64)
                                                 ? FRAME_1 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_R)
                   & (Master_Abort_Detected == 1'b1))               
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_W)
                   & (Master_Abort_Detected == 1'b1))               
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_R)
                   & (Master_Abort_Detected == 1'b0)
                   & (Request_FIFO_CONTAINS_DATA_MORE == 1'b0)
                   & (Request_FIFO_CONTAINS_DATA_LAST == 1'b0))
                                                 ? FRAME_UNLESS_STOP : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_W)
                   & (Master_Abort_Detected == 1'b0)
                   & (Request_FIFO_CONTAINS_DATA_MORE == 1'b0)
                   & (Request_FIFO_CONTAINS_DATA_LAST == 1'b0))
                                                 ? FRAME_UNLESS_STOP : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_R)
                   & (Master_Abort_Detected == 1'b0)
                   & (Request_FIFO_CONTAINS_DATA_MORE == 1'b1))
                                                 ? FRAME_UNLESS_LAST : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_W)
                   & (Master_Abort_Detected == 1'b0)
                   & (Request_FIFO_CONTAINS_DATA_LAST == 1'b1))
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_R)
                   & (Master_Abort_Detected == 1'b1))               
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_W)
                   & (Master_Abort_Detected == 1'b1))               
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_R)
                   & (Master_Abort_Detected == 1'b0))
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_W)
                   & (Master_Abort_Detected == 1'b0))
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_R)
                   & (Master_Abort_Detected == 1'b1))               
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_W)
                   & (Master_Abort_Detected == 1'b1))               
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_R)
                   & (Master_Abort_Detected == 1'b0))               
                                                 ? FRAME_0 : FRAME_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_W)
                   & (Master_Abort_Detected == 1'b0))               
                                                 ? FRAME_0 : FRAME_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_STOP_TURN_R)
                                                 ? FRAME_0 : FRAME_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_STOP_TURN_W)
                                                 ? FRAME_0 : FRAME_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_FLUSH)
                                                 ? FRAME_0 : FRAME_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_FLUSH_PARK)
                                                 ? FRAME_0 : FRAME_0);
// The IO pad contains an output flop
pci_critical_next_frame pci_critical_next_frame (
  .PCI_Next_FRAME_Code        (PCI_Next_FRAME_Code[2:0]),
  .pci_gnt_in_critical        (pci_gnt_in_critical),
  .pci_frame_in_critical      (pci_frame_in_critical),
  .pci_irdy_in_critical       (pci_irdy_in_critical),
  .pci_trdy_in_critical       (pci_trdy_in_critical),
  .pci_stop_in_critical       (pci_stop_in_critical),
  .pci_frame_out_next         (pci_frame_out_next)
);
// NOTE: WORKING: Maybe Remove this: Make a glitch-free output enable
`ifdef NOT
  reg     pci_frame_out_oe_comb;
  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      pci_frame_out_oe_comb <= 1'b0;
    end
    else
    begin
      pci_frame_out_oe_comb <=
                (PCI_Master_State[MS_Range:0] == PCI_MASTER_STEP)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR64)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE);  // NOTE: WORKING
    end
  end
`endif
  assign  pci_frame_out_oe_comb =
                (PCI_Master_State[MS_Range:0] == PCI_MASTER_STEP)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR64)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_R)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_W)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_R)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_W);  // NOTE: WORKING

// NOTE: WORKING: Make into a giant OR, not an if-the-else
  wire   [2:0] PCI_Next_IRDY_Code =  // NOTE: WORKING
                (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_IDLE)
                                                 ? IRDY_0 : IRDY_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_PARK)
                                                 ? IRDY_0 : IRDY_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_STEP)
                                                 ? IRDY_0 : IRDY_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR)
                                                 ? IRDY_0 : IRDY_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR64)
                                                 ? IRDY_0 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_R)
                   & (Master_Abort_Detected == 1'b1))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_W)
                   & (Master_Abort_Detected == 1'b1))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_R)
                   & (Master_Abort_Detected == 1'b0))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_W)
                   & (Master_Abort_Detected == 1'b0))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_R)
                   & (Master_Abort_Detected == 1'b1))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_W)
                   & (Master_Abort_Detected == 1'b1))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_R)
                   & (Master_Abort_Detected == 1'b0))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_W)
                   & (Master_Abort_Detected == 1'b0))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_R)
                   & (Master_Abort_Detected == 1'b1))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_W)
                   & (Master_Abort_Detected == 1'b1))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_R)
                   & (Master_Abort_Detected == 1'b0))
                                                 ? IRDY_1 : IRDY_0)
              | ((   (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_W)
                   & (Master_Abort_Detected == 1'b0))
                                                 ? IRDY_1 : IRDY_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_STOP_TURN_R)
                                                 ? IRDY_0 : IRDY_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_STOP_TURN_W)
                                                 ? IRDY_0 : IRDY_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_FLUSH)
                                                 ? IRDY_0 : IRDY_0)
              | (    (PCI_Master_State[MS_Range:0] == PCI_MASTER_FLUSH_PARK)
                                                 ? IRDY_0 : IRDY_0);
// The IO pad contains an output flop
pci_critical_next_irdy pci_critical_next_irdy (
  .PCI_Next_IRDY_Code         (PCI_Next_IRDY_Code[2:0]),
  .pci_trdy_in_critical       (pci_trdy_in_critical),
  .pci_stop_in_critical       (pci_stop_in_critical),
  .pci_irdy_out_next          (pci_irdy_out_next)
);
// NOTE: WORKING: Maybe Remove this: Make a glitch-free output enable
`ifdef NOT
  reg     pci_irdy_out_oe_comb;
  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      pci_irdy_out_oe_comb <= 1'b0;
    end
    else
    begin
      pci_irdy_out_oe_comb <=
                (PCI_Master_State[MS_Range:0] == PCI_MASTER_STEP)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR64)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_R)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_W)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_R)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_W)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_R)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_W);  // NOTE: WORKING
    end
  end
`endif
  assign  pci_irdy_out_oe_comb =
                (PCI_Master_State[MS_Range:0] == PCI_MASTER_STEP)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_ADDR64)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_R)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_MORE_PENDING_W)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_R)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_MORE_W)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_R)
              | (PCI_Master_State[MS_Range:0] == PCI_MASTER_DATA_LAST_W);  // NOTE: WORKING

`endif  // NOT_YET  // First get things working, then get it working fast!

// synopsys translate_off
// Check that the Request FIFO is getting entries in the allowed order
//   Address->Data->Data_Last.  Anything else is an error.
//   NOTE: ONLY CHECKED IN SIMULATION.  In the real circuit, the FIFO
//         FILLER is responsible for only writing valid stuff into the FIFO.
  parameter PCI_REQUEST_FIFO_WAITING_FOR_ADDRESS = 1'b0;
  parameter PCI_REQUEST_FIFO_WAITING_FOR_LAST    = 1'b1;
  reg     request_fifo_state;  // tracks no_address, address, data, data_last;
  reg     master_request_fifo_error;  // Notices FIFO error, or FIFO Contents out of sequence

  always @(posedge pci_clk or posedge pci_reset_comb) // async reset!
  begin
    if (pci_reset_comb == 1'b1)
    begin
      master_request_fifo_error <= 1'b0;
      request_fifo_state <= PCI_REQUEST_FIFO_WAITING_FOR_ADDRESS;
    end
    else
    begin
      if (prefetching_request_fifo_data == 1'b1)
      begin
        if (request_fifo_state == PCI_REQUEST_FIFO_WAITING_FOR_ADDRESS)
        begin
          if (  (pci_request_fifo_type_current[2:0] == PCI_HOST_REQUEST_SPARE)
              | (pci_request_fifo_type_current[2:0] == PCI_HOST_REQUEST_W_DATA_RW_MASK)
              | (pci_request_fifo_type_current[2:0]
                                == PCI_HOST_REQUEST_W_DATA_RW_MASK_LAST)
              | (pci_request_fifo_type_current[2:0]
                                == PCI_HOST_REQUEST_W_DATA_RW_MASK_PERR) 
              | (pci_request_fifo_type_current[2:0]
                                == PCI_HOST_REQUEST_W_DATA_RW_MASK_LAST_PERR) )
          begin
            master_request_fifo_error <= 1'b1;
            request_fifo_state <= PCI_REQUEST_FIFO_WAITING_FOR_ADDRESS;
          end
          else if (pci_request_fifo_type_current[2:0]
                                == PCI_HOST_REQUEST_INSERT_WRITE_FENCE)
          begin
            master_request_fifo_error <= pci_request_fifo_error;
            request_fifo_state <= PCI_REQUEST_FIFO_WAITING_FOR_ADDRESS;
          end
          else
          begin  // Either type of Address entry is OK
            master_request_fifo_error <= pci_request_fifo_error;
            request_fifo_state <= PCI_REQUEST_FIFO_WAITING_FOR_LAST;
          end
        end
        else  // PCI_FIFO_WAITING_FOR_LAST
        begin
          if (  (pci_request_fifo_type_current[2:0] == PCI_HOST_REQUEST_SPARE)
              | (pci_request_fifo_type_current[2:0] == PCI_HOST_REQUEST_ADDRESS_COMMAND)
              | (pci_request_fifo_type_current[2:0]
                                == PCI_HOST_REQUEST_ADDRESS_COMMAND_SERR)
              | (pci_request_fifo_type_current[2:0]
                                == PCI_HOST_REQUEST_INSERT_WRITE_FENCE) )
          begin
            master_request_fifo_error <= 1'b1;
            request_fifo_state <= PCI_REQUEST_FIFO_WAITING_FOR_ADDRESS;
          end
          else if (  (pci_request_fifo_type_current[2:0]
                         == PCI_HOST_REQUEST_W_DATA_RW_MASK_LAST)
                   | (pci_request_fifo_type_current[2:0]
                         == PCI_HOST_REQUEST_W_DATA_RW_MASK_LAST_PERR) )
          begin
            master_request_fifo_error <= pci_request_fifo_error;
            request_fifo_state <= PCI_REQUEST_FIFO_WAITING_FOR_ADDRESS;
          end
          else
          begin  // Either type of Data without Last
            master_request_fifo_error <= pci_request_fifo_error;
            request_fifo_state <= PCI_REQUEST_FIFO_WAITING_FOR_LAST;
          end
        end
      end
      else  // (prefetching_request_fifo_data == 1'b0)
      begin
        master_request_fifo_error <= pci_request_fifo_error;
        request_fifo_state <= request_fifo_state;
      end
    end
  end

  always @(posedge pci_clk)
  begin
    if ((pci_reset_comb == 1'b0) & (master_request_fifo_error == 1'b1))
    begin
      $display ("*** %m PCI Master Request Fifo Unload Error at time %t", $time);
    end
  end
/*
  initial
    $monitor ("request_fifo_data 0x%x, 1_word_avail %x, 2_word_available %x, req %x, gnt %x, frame_in %x, irdy_in %x\n ad_out %x, ad_out_oe %x, cbe_out %x, cbe_oe %x,\n frame_out %x, frame_oe %x, irdy_out %x, irdy_oe %x\n devsel_in %x, trdy_in %x, stop_in %x",
               pci_request_fifo_data[31:0], request_fifo_data_available_meta,
               request_fifo_two_words_available_meta, pci_request_fifo_data_unload,
               pci_req_out_next, pci_gnt_in_critical, pci_frame_in_critical, pci_irdy_in_critical,
               pci_master_ad_out_next, pci_master_ad_out_oe_comb, pci_cbe_l_out_next, pci_cbe_out_oe_comb,
               pci_frame_out_next, pci_frame_out_oe_comb, pci_irdy_out_next, pci_irdy_out_oe_comb,
               pci_devsel_in_prev, pci_trdy_in_critical, pci_stop_in_critical);
*/

/*
  initial $monitor ("%x State %x Next %x %x %x %x %x %x %x %x %x %x %x %t",
            pci_reset_comb,
            PCI_Master_State,
            PCI_Master_Next_State,
            external_pci_bus_available_critical,
            Request_FIFO_CONTAINS_ADDRESS,
            Master_Doing_Config_Reference,
            Master_Abort_Detected,
            Request_FIFO_CONTAINS_DATA_MORE,
            Request_FIFO_CONTAINS_DATA_LAST,
            pci_trdy_in_critical,
            pci_stop_in_critical,
            Fast_Back_to_Back_Possible,
            request_fifo_data_available_meta,
 $time);
*/
// synopsys translate_on
endmodule

