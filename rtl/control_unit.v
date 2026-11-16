//==============================================================================
// File        : control_unit.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Instruction decoder (ID stage). Turns the 4-bit opcode into
//               the control signals used by the later pipeline stages.
//
//   Opcode map
//     0 NOP   1 ADD   2 SUB   3 AND   4 OR    5 XOR   6 SHL   7 SHR
//     8 LDI   9 LD    A ST    B BZ    C BNZ   D JMP   E (NOP) F HLT
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module control_unit (
    input  wire [3:0] opcode,              // instr[15:12]
    output reg        reg_write,           // write rd in WB
    output reg  [2:0] alu_op,              // ALU operation (see alu.v)
    output reg        alu_imm,             // 1 = ALU operand B is imm8
    output reg        sets_flags,          // 1 = update {Z, C} in EX
    output reg        mem_to_reg,          // 1 = LD (rd gets memory data)
    output reg        mem_we,              // 1 = ST (write memory)
    output reg        is_bz,               // branch if Z = 1
    output reg        is_bnz,              // branch if Z = 0
    output reg        is_jmp,              // unconditional jump
    output reg        is_halt,             // HLT
    output reg        uses_a,              // instruction reads port A (rs1)
    output reg        uses_b,              // instruction reads port B
    output reg        b_is_rd              // port B reads rd instead of rs2 (ST)
);

    //--------------------------------------------------------------------------
    // Opcodes
    //--------------------------------------------------------------------------
    localparam OP_NOP = 4'h0, OP_ADD = 4'h1, OP_SUB = 4'h2, OP_AND = 4'h3,
               OP_OR  = 4'h4, OP_XOR = 4'h5, OP_SHL = 4'h6, OP_SHR = 4'h7,
               OP_LDI = 4'h8, OP_LD  = 4'h9, OP_ST  = 4'hA, OP_BZ  = 4'hB,
               OP_BNZ = 4'hC, OP_JMP = 4'hD, OP_HLT = 4'hF;

    always @(*) begin
        //----------------------------------------------------------------------
        // Defaults: behave like NOP (no writes, no branch)
        //----------------------------------------------------------------------
        reg_write  = 1'b0;
        alu_op     = 3'd7;                 // PASS
        alu_imm    = 1'b0;
        sets_flags = 1'b0;
        mem_to_reg = 1'b0;
        mem_we     = 1'b0;
        is_bz      = 1'b0;
        is_bnz     = 1'b0;
        is_jmp     = 1'b0;
        is_halt    = 1'b0;
        uses_a     = 1'b0;
        uses_b     = 1'b0;
        b_is_rd    = 1'b0;

        case (opcode)
            //------------------------------------------------------------------
            // R-type ALU: rd = rs1 op rs2, update flags
            //------------------------------------------------------------------
            OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR: begin
                reg_write  = 1'b1;
                sets_flags = 1'b1;
                uses_a     = 1'b1;
                uses_b     = 1'b1;
                case (opcode)
                    OP_ADD:  alu_op = 3'd0;
                    OP_SUB:  alu_op = 3'd1;
                    OP_AND:  alu_op = 3'd2;
                    OP_OR:   alu_op = 3'd3;
                    default: alu_op = 3'd4;    // XOR
                endcase
            end

            //------------------------------------------------------------------
            // Shifts: rd = rs1 << 1 or rs1 >> 1, update flags
            //------------------------------------------------------------------
            OP_SHL, OP_SHR: begin
                reg_write  = 1'b1;
                sets_flags = 1'b1;
                uses_a     = 1'b1;
                alu_op     = (opcode == OP_SHL) ? 3'd5 : 3'd6;
            end

            //------------------------------------------------------------------
            // LDI rd, imm8: rd = imm8 (ALU PASS of the immediate)
            //------------------------------------------------------------------
            OP_LDI: begin
                reg_write = 1'b1;
                alu_imm   = 1'b1;
                alu_op    = 3'd7;
            end

            //------------------------------------------------------------------
            // LD rd, [rs1]: rd = MEM[rs1]
            //------------------------------------------------------------------
            OP_LD: begin
                reg_write  = 1'b1;
                mem_to_reg = 1'b1;
                uses_a     = 1'b1;
            end

            //------------------------------------------------------------------
            // ST rd, [rs1]: MEM[rs1] = rd  (rd is read through port B)
            //------------------------------------------------------------------
            OP_ST: begin
                mem_we  = 1'b1;
                uses_a  = 1'b1;
                uses_b  = 1'b1;
                b_is_rd = 1'b1;
            end

            //------------------------------------------------------------------
            // Control flow
            //------------------------------------------------------------------
            OP_BZ:  is_bz   = 1'b1;
            OP_BNZ: is_bnz  = 1'b1;
            OP_JMP: is_jmp  = 1'b1;
            OP_HLT: is_halt = 1'b1;

            default: ;                     // NOP and unused opcode 0xE
        endcase
    end

endmodule