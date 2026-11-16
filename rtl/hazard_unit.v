//==============================================================================
// File        : hazard_unit.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Data hazard handling for the 5-stage pipeline.
//               1) Load-use stall: if the instruction in ID needs a register
//                  that a LD in EX is about to load, stall one clock.
//               2) Forwarding to EX:
//                    fwd = 1 -> take the value from EX/MEM (ALU result)
//                    fwd = 2 -> take the value from MEM/WB (WB data)
//                    fwd = 0 -> use the value read from the register file
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module hazard_unit (
    //---------------- instruction in ID ----------------
    input  wire       ifid_valid,          // ID holds a real instruction
    input  wire       id_uses_a,           // it reads port A
    input  wire       id_uses_b,           // it reads port B
    input  wire [2:0] id_ra,               // port A register
    input  wire [2:0] id_rb,               // port B register
    //---------------- instruction in EX ----------------
    input  wire       idex_valid,          // EX holds a real instruction
    input  wire       idex_mem_to_reg,     // it is a LD
    input  wire [2:0] idex_rd,             // its destination
    input  wire [2:0] idex_ra,             // its port A register
    input  wire [2:0] idex_rb,             // its port B register
    //---------------- instructions in MEM and WB ----------------
    input  wire       exmem_reg_write,     // MEM writes a register (not LD)
    input  wire [2:0] exmem_rd,
    input  wire       memwb_reg_write,     // WB writes a register
    input  wire [2:0] memwb_rd,
    //---------------- outputs ----------------
    output wire       stall,               // freeze IF and ID one clock
    output wire [1:0] fwd_a,               // forwarding select, operand A
    output wire [1:0] fwd_b                // forwarding select, operand B
);

    //--------------------------------------------------------------------------
    // Load-use hazard: LD data is only ready at the end of MEM, too late
    // for the very next instruction's EX stage -> insert one bubble.
    //--------------------------------------------------------------------------
    assign stall = ifid_valid && idex_valid && idex_mem_to_reg &&
                   ((id_uses_a && (id_ra == idex_rd)) ||
                    (id_uses_b && (id_rb == idex_rd)));

    //--------------------------------------------------------------------------
    // Forwarding: the newest value wins (EX/MEM before MEM/WB)
    //--------------------------------------------------------------------------
    assign fwd_a = (exmem_reg_write && (exmem_rd == idex_ra)) ? 2'd1 :
                   (memwb_reg_write && (memwb_rd == idex_ra)) ? 2'd2 : 2'd0;

    assign fwd_b = (exmem_reg_write && (exmem_rd == idex_rb)) ? 2'd1 :
                   (memwb_reg_write && (memwb_rd == idex_rb)) ? 2'd2 : 2'd0;

endmodule