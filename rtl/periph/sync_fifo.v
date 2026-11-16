//==============================================================================
// File        : sync_fifo.v
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral for RISC-8 CPU
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Synchronous First-In-First-Out queue for ADC results.
//               Each entry is {channel[1:0], data[7:0]} = 10 bits.
//
//   - push when full (and no pop in the same clock) -> data is dropped,
//     overflow pulses for one clock
//   - pop when empty -> ignored
//   - push and pop in the same clock are both allowed, even when full
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module sync_fifo #(
    parameter W     = 10,                  // data width: {ch[1:0], data[7:0]}
    parameter DEPTH = 8,                   // number of entries (power of 2)
    parameter AW    = 3                    // address width = log2(DEPTH)
) (
    input  wire          clk,              // system clock
    input  wire          rst_n,            // asynchronous reset, active low
    input  wire          push,             // write request (ADC EOC)
    input  wire          pop,              // read request (CPU reads ADC_DATA)
    input  wire [W-1:0]  din,              // data to write
    output wire [W-1:0]  dout,             // oldest entry (head of the queue)
    output wire [AW:0]   level,            // number of stored entries, 0..8
    output wire          empty,            // 1 = no entries
    output wire          full,             // 1 = DEPTH entries stored
    output wire          overflow          // 1-clock pulse: push was dropped
);

    //--------------------------------------------------------------------------
    // Storage and pointers
    //--------------------------------------------------------------------------
    reg [W-1:0]  mem [0:DEPTH-1];          // circular buffer
    reg [AW-1:0] wp;                       // write pointer (next free slot)
    reg [AW-1:0] rp;                       // read pointer (oldest entry)
    reg [AW:0]   cnt;                      // fill level, one extra bit for 8

    //--------------------------------------------------------------------------
    // Accepted operations
    //--------------------------------------------------------------------------
    // A pop is accepted only if there is something to read.
    wire do_pop  = pop  && (cnt != 0);

    // A push is accepted if there is room, or if a pop frees a slot
    // in the same clock.
    wire do_push = push && ((cnt != DEPTH) || do_pop);

    //--------------------------------------------------------------------------
    // Status outputs
    //--------------------------------------------------------------------------
    assign overflow = push && !do_push;    // push requested but rejected
    assign dout     = mem[rp];             // show the head entry (no latency)
    assign level    = cnt;
    assign empty    = (cnt == 0);
    assign full     = (cnt == DEPTH);

    //--------------------------------------------------------------------------
    // Memory write (no reset needed for the data array)
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (do_push)
            mem[wp] <= din;
    end

    //--------------------------------------------------------------------------
    // Pointers and fill counter
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                  // reset: empty queue
            wp  <= {AW{1'b0}};
            rp  <= {AW{1'b0}};
            cnt <= {(AW+1){1'b0}};
        end else begin
            if (do_push) wp <= wp + 1'b1;  // wraps 7 -> 0 automatically
            if (do_pop)  rp <= rp + 1'b1;  // wraps 7 -> 0 automatically

            case ({do_push, do_pop})
                2'b10:   cnt <= cnt + 1'b1;  // push only: one more entry
                2'b01:   cnt <= cnt - 1'b1;  // pop only : one less entry
                default: cnt <= cnt;         // both or none: unchanged
            endcase
        end
    end

endmodule