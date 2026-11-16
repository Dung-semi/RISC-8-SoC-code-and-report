//==============================================================================
// File        : dmem.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Data memory (RAM), 256 bytes, used in the MEM stage.
//               Synchronous write, combinational read.
//               After integration, addresses 0xF0..0xFF are routed to the
//               peripheral by the core, so this RAM is only written for
//               0x00..0xEF.
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module dmem (
    input  wire       clk,                 // system clock
    input  wire       we,                  // write enable (ST, not I/O page)
    input  wire [7:0] addr,                // byte address
    input  wire [7:0] wdata,               // store data
    output wire [7:0] rdata                // load data
);

    //--------------------------------------------------------------------------
    // Storage: 256 bytes. The testbench reads it as dut.u_cpu.u_dmem.mem[]
    //--------------------------------------------------------------------------
    reg [7:0] mem [0:255];
    integer i;                             // loop index

    //--------------------------------------------------------------------------
    // Clear the RAM at simulation start
    //--------------------------------------------------------------------------
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 8'h00;
    end

    //--------------------------------------------------------------------------
    // Synchronous write
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    //--------------------------------------------------------------------------
    // Combinational read (data ready in the same clock as the address)
    //--------------------------------------------------------------------------
    assign rdata = mem[addr];

endmodule