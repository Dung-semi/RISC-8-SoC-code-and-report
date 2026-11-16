//==============================================================================
// File        : alu.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : 8-bit Arithmetic Logic Unit used in the EX stage.
//               Produces the result y, the zero flag z and the carry flag c.
//
//   op  operation      y                c
//   0   ADD            a + b            carry out
//   1   SUB            a - b            borrow
//   2   AND            a & b            0
//   3   OR             a | b            0
//   4   XOR            a ^ b            0
//   5   SHL            a << 1           bit 7 of a
//   6   SHR            a >> 1           bit 0 of a
//   7   PASS           b                0   (used by LDI)
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module alu (
    input  wire [2:0] op,                  // operation select
    input  wire [7:0] a,                   // operand A (rs1)
    input  wire [7:0] b,                   // operand B (rs2 or immediate)
    output reg  [7:0] y,                   // result
    output wire       z,                   // zero flag: 1 when y == 0
    output reg        c                    // carry / borrow / shifted-out bit
);

    //--------------------------------------------------------------------------
    // Operation codes
    //--------------------------------------------------------------------------
    localparam ALU_ADD  = 3'd0;
    localparam ALU_SUB  = 3'd1;
    localparam ALU_AND  = 3'd2;
    localparam ALU_OR   = 3'd3;
    localparam ALU_XOR  = 3'd4;
    localparam ALU_SHL  = 3'd5;
    localparam ALU_SHR  = 3'd6;
    localparam ALU_PASS = 3'd7;

    //--------------------------------------------------------------------------
    // Combinational ALU
    //--------------------------------------------------------------------------
    always @(*) begin
        c = 1'b0;                          // default: no carry
        case (op)
            // 9-bit add/sub: bit 8 becomes the carry (or borrow) flag
            ALU_ADD:  {c, y} = {1'b0, a} + {1'b0, b};
            ALU_SUB:  {c, y} = {1'b0, a} - {1'b0, b};
            ALU_AND:  y = a & b;
            ALU_OR:   y = a | b;
            ALU_XOR:  y = a ^ b;
            // shift left: bit 7 of a goes out into c
            ALU_SHL:  {c, y} = {a, 1'b0};
            // shift right: bit 0 of a goes out into c
            ALU_SHR:  {y, c} = {1'b0, a};
            // PASS (LDI): result is operand B (the immediate)
            default:  y = b;
        endcase
    end

    //--------------------------------------------------------------------------
    // Zero flag: used by BZ / BNZ
    //--------------------------------------------------------------------------
    assign z = (y == 8'h00);

endmodule