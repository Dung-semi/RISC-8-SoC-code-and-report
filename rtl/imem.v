//==============================================================================
// File        : imem.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Instruction memory (ROM), 256 words x 16 bits.
//               Loaded from a hex file with $readmemh at simulation start.
//               Combinational read: the instruction at addr is available in
//               the same clock (IF stage).
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module imem #(
    parameter IMEM_FILE = "program.hex"    // hex file, one 16-bit word per line
) (
    input  wire [7:0]  addr,               // program counter
    output wire [15:0] instr               // instruction at addr
);

    //--------------------------------------------------------------------------
    // Storage: 256 instructions x 16 bits
    //--------------------------------------------------------------------------
    reg [15:0] rom [0:255];
    integer i;                             // loop index

    //--------------------------------------------------------------------------
    // Initialisation: fill with NOP (0x0000), then load the program.
    // Words not present in the hex file stay NOP.
    //--------------------------------------------------------------------------
    initial begin
        for (i = 0; i < 256; i = i + 1)
            rom[i] = 16'h0000;
        $readmemh(IMEM_FILE, rom);
    end

    //--------------------------------------------------------------------------
    // Combinational read
    //--------------------------------------------------------------------------
    assign instr = rom[addr];

endmodule