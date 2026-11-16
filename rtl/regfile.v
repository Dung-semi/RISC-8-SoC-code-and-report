//==============================================================================
// File        : regfile.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Register file with 8 registers (R0..R7), 8 bits each.
//               Two combinational read ports (ID stage) and one synchronous
//               write port (WB stage).
//               Internal bypass: if WB writes the register that ID reads in
//               the same clock, the new value is returned immediately.
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module regfile (
    input  wire       clk,                 // system clock
    input  wire       rst,                 // synchronous reset, active high
    input  wire [2:0] ra,                  // read address A (rs1)
    input  wire [2:0] rb,                  // read address B (rs2 or rd for ST)
    output wire [7:0] rdata_a,             // read data A
    output wire [7:0] rdata_b,             // read data B
    input  wire       we,                  // write enable (from WB stage)
    input  wire [2:0] wa,                  // write address (rd)
    input  wire [7:0] wd                   // write data
);

    //--------------------------------------------------------------------------
    // Storage: 8 registers x 8 bits
    //--------------------------------------------------------------------------
    reg [7:0] regs [0:7];
    integer i;                             // loop index for reset

    //--------------------------------------------------------------------------
    // Synchronous write (and reset of all registers to 0)
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 8; i = i + 1)
                regs[i] <= 8'h00;
        end else if (we) begin
            regs[wa] <= wd;
        end
    end

    //--------------------------------------------------------------------------
    // Combinational read with write-first bypass.
    // Removes the WB -> ID hazard without an extra stall.
    //--------------------------------------------------------------------------
    assign rdata_a = (we && (wa == ra)) ? wd : regs[ra];
    assign rdata_b = (we && (wa == rb)) ? wd : regs[rb];

endmodule