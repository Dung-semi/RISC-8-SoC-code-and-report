//==============================================================================
// File        : risc8_5stage_core.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : 8-bit RISC CPU with a classic 5-stage pipeline:
//                 IF  - fetch instruction from imem
//                 ID  - decode, read register file, detect load-use hazard
//                 EX  - ALU, forwarding, flags, branch decision
//                 MEM - data RAM or memory-mapped I/O page (0xF0..0xFF)
//                 WB  - write result to the register file
//               Branches/jumps are resolved in EX (2-cycle penalty).
//               The optional I/O port (IO_ENABLE = 1) is driven from MEM:
//               exactly one io_cs pulse per LD / ST to the I/O page.
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module risc8_5stage_core #(
    parameter       IMEM_FILE = "program.hex", // program loaded into imem
    parameter       IO_ENABLE = 0,             // 1 = map I/O page to io_*
    parameter [3:0] IO_PAGE   = 4'hF           // I/O page = 0xF0..0xFF
) (
    input  wire       clk,                 // system clock
    input  wire       rst,                 // synchronous reset, active high
    output reg        halted,              // 1 after HLT has left WB
    output wire [7:0] pc_out,              // current PC (debug)
    output wire [1:0] flags_out,           // {Z, C} flags (debug)
    output wire       instr_done,          // 1 when an instruction completes
    //---------------- I/O port (MEM stage) ----------------
    output wire       io_cs,               // LD/ST to the I/O page this clock
    output wire       io_we,               // 1 = store, 0 = load
    output wire [3:0] io_addr,             // register number in the page
    output wire [7:0] io_wdata,            // store data
    input  wire [7:0] io_rdata             // load data from the peripheral
);

    //==========================================================================
    // Stage 1: IF (instruction fetch)
    //==========================================================================
    reg  [7:0]  pc;                        // program counter
    wire [15:0] if_instr;                  // instruction at pc

    imem #(.IMEM_FILE(IMEM_FILE)) u_imem (.addr(pc), .instr(if_instr));

    // IF/ID pipeline register
    reg  [7:0]  ifid_pc;
    reg  [15:0] ifid_instr;
    reg         ifid_valid;                // 0 = bubble

    //==========================================================================
    // Stage 2: ID (decode + register read)
    //==========================================================================
    wire [3:0] id_op  = ifid_instr[15:12]; // opcode
    wire [2:0] id_rd  = ifid_instr[11:9];  // destination (or ST data)
    wire [2:0] id_ra  = ifid_instr[8:6];   // source 1 / address register
    wire [7:0] id_imm = ifid_instr[7:0];   // immediate / branch offset

    wire       c_reg_write, c_alu_imm, c_sets_flags, c_mem_to_reg, c_mem_we;
    wire       c_is_bz, c_is_bnz, c_is_jmp, c_is_halt, c_uses_a, c_uses_b, c_b_is_rd;
    wire [2:0] c_alu_op;

    control_unit u_ctrl (
        .opcode(id_op), .reg_write(c_reg_write), .alu_op(c_alu_op),
        .alu_imm(c_alu_imm), .sets_flags(c_sets_flags),
        .mem_to_reg(c_mem_to_reg), .mem_we(c_mem_we),
        .is_bz(c_is_bz), .is_bnz(c_is_bnz), .is_jmp(c_is_jmp),
        .is_halt(c_is_halt), .uses_a(c_uses_a), .uses_b(c_uses_b),
        .b_is_rd(c_b_is_rd)
    );

    // Port B reads rd for ST (store data), rs2 otherwise
    wire [2:0] id_rb = c_b_is_rd ? ifid_instr[11:9] : ifid_instr[5:3];

    wire       wb_we;                      // WB write enable
    wire [2:0] wb_rd;                      // WB destination
    wire [7:0] wb_data;                    // WB data
    wire [7:0] id_a, id_b;                 // register file outputs

    regfile u_rf (
        .clk(clk), .rst(rst),
        .ra(id_ra), .rb(id_rb), .rdata_a(id_a), .rdata_b(id_b),
        .we(wb_we), .wa(wb_rd), .wd(wb_data)
    );

    // ID/EX pipeline register
    reg        idex_valid;
    reg  [7:0] idex_pc, idex_a, idex_b, idex_imm;
    reg  [2:0] idex_rd, idex_ra, idex_rb, idex_alu_op;
    reg        idex_reg_write, idex_alu_imm, idex_sets_flags, idex_mem_to_reg;
    reg        idex_mem_we, idex_is_bz, idex_is_bnz, idex_is_jmp, idex_is_halt;

    // EX/MEM pipeline register
    reg        exmem_valid;
    reg  [7:0] exmem_alu_y, exmem_addr, exmem_store_data;
    reg  [2:0] exmem_rd;
    reg        exmem_reg_write, exmem_mem_to_reg, exmem_mem_we, exmem_is_halt;

    // MEM/WB pipeline register
    reg        memwb_valid;
    reg  [7:0] memwb_data;
    reg  [2:0] memwb_rd;
    reg        memwb_reg_write, memwb_is_halt;

    //==========================================================================
    // Hazard detection and forwarding
    //==========================================================================
    wire       stall;
    wire [1:0] fwd_a, fwd_b;

    hazard_unit u_hazard (
        .ifid_valid(ifid_valid), .id_uses_a(c_uses_a), .id_uses_b(c_uses_b),
        .id_ra(id_ra), .id_rb(id_rb),
        .idex_valid(idex_valid), .idex_mem_to_reg(idex_mem_to_reg),
        .idex_rd(idex_rd), .idex_ra(idex_ra), .idex_rb(idex_rb),
        // a LD in MEM cannot forward its ALU value (load-use stall covers it)
        .exmem_reg_write(exmem_reg_write && !exmem_mem_to_reg), .exmem_rd(exmem_rd),
        .memwb_reg_write(memwb_reg_write), .memwb_rd(memwb_rd),
        .stall(stall), .fwd_a(fwd_a), .fwd_b(fwd_b)
    );

    //==========================================================================
    // Stage 3: EX (execute)
    //==========================================================================
    // Forwarding multiplexers
    wire [7:0] ex_a = (fwd_a == 2'd1) ? exmem_alu_y :
                      (fwd_a == 2'd2) ? wb_data : idex_a;
    wire [7:0] ex_b = (fwd_b == 2'd1) ? exmem_alu_y :
                      (fwd_b == 2'd2) ? wb_data : idex_b;

    wire [7:0] alu_y;
    wire       alu_z, alu_c;

    alu u_alu (
        .op(idex_alu_op), .a(ex_a), .b(idex_alu_imm ? idex_imm : ex_b),
        .y(alu_y), .z(alu_z), .c(alu_c)
    );

    reg  [1:0] flags;                      // {Z, C}
    assign flags_out = flags;

    // Branch decision (flags were written by the previous ALU instruction)
    wire ex_take = idex_valid && ((idex_is_bz  &&  flags[1]) ||
                                  (idex_is_bnz && !flags[1]) ||
                                   idex_is_jmp);

    // JMP: absolute target. BZ/BNZ: PC-relative to the next instruction
    wire [7:0] ex_target = idex_is_jmp ? idex_imm : (idex_pc + 8'd1 + idex_imm);

    wire ex_halt = idex_valid && idex_is_halt; // HLT reached EX
    reg  stop_fetch;                       // 1 = PC frozen after HLT

    //==========================================================================
    // Stage 4: MEM (data RAM or I/O page)
    //==========================================================================
    wire [7:0] mem_rdata;
    wire mem_we = exmem_mem_we && !halted;

    // Address decode: upper nibble selects the I/O page
    wire io_hit = (IO_ENABLE != 0) && (exmem_addr[7:4] == IO_PAGE);

    // One clock per LD/ST, never for bubbles or ALU instructions
    assign io_cs    = io_hit && (exmem_mem_we || exmem_mem_to_reg) && !halted;
    assign io_we    = exmem_mem_we;
    assign io_addr  = exmem_addr[3:0];
    assign io_wdata = exmem_store_data;

    dmem u_dmem (
        .clk(clk), .we(mem_we && !io_hit), // RAM not written for the I/O page
        .addr(exmem_addr), .wdata(exmem_store_data), .rdata(mem_rdata)
    );

    // LD data: peripheral for the I/O page, RAM otherwise
    wire [7:0] ld_data    = io_hit ? io_rdata : mem_rdata;
    // Result leaving MEM: load data for LD, ALU result otherwise
    wire [7:0] mem_result = exmem_mem_to_reg ? ld_data : exmem_alu_y;

    //==========================================================================
    // Stage 5: WB (write back)
    //==========================================================================
    assign wb_we      = memwb_reg_write;
    assign wb_rd      = memwb_rd;
    assign wb_data    = memwb_data;
    assign instr_done = memwb_valid;
    assign pc_out     = pc;

    //==========================================================================
    // Sequential logic: PC and all pipeline registers
    //==========================================================================
    always @(posedge clk) begin
        if (rst) begin
            pc         <= 8'd0;
            stop_fetch <= 1'b0;
            flags      <= 2'b00;
            halted     <= 1'b0;
            ifid_valid <= 1'b0;  ifid_pc <= 8'd0;  ifid_instr <= 16'h0000;
            idex_valid <= 1'b0;
            idex_reg_write <= 1'b0; idex_mem_to_reg <= 1'b0; idex_mem_we <= 1'b0;
            idex_is_bz <= 1'b0; idex_is_bnz <= 1'b0; idex_is_jmp <= 1'b0;
            idex_is_halt <= 1'b0; idex_sets_flags <= 1'b0;
            exmem_valid <= 1'b0; exmem_reg_write <= 1'b0; exmem_mem_to_reg <= 1'b0;
            exmem_mem_we <= 1'b0; exmem_is_halt <= 1'b0;
            memwb_valid <= 1'b0; memwb_reg_write <= 1'b0; memwb_is_halt <= 1'b0;
        end else begin
            //------------------------------------------------------------------
            // PC: branch > halt/stop > stall > next instruction
            //------------------------------------------------------------------
            if (ex_take)                       pc <= ex_target;
            else if (ex_halt || stop_fetch)    pc <= pc;
            else if (!stall)                   pc <= pc + 8'd1;
            if (ex_halt) stop_fetch <= 1'b1;

            //------------------------------------------------------------------
            // IF/ID: flush on branch/halt, hold on stall
            //------------------------------------------------------------------
            if (ex_take || ex_halt || stop_fetch) begin
                ifid_valid <= 1'b0;
            end else if (!stall) begin
                ifid_valid <= 1'b1;
                ifid_pc    <= pc;
                ifid_instr <= if_instr;
            end

            //------------------------------------------------------------------
            // ID/EX: insert a bubble on branch, halt or stall
            //------------------------------------------------------------------
            if (ex_take || ex_halt || stall || !ifid_valid) begin
                idex_valid      <= 1'b0;
                idex_reg_write  <= 1'b0;
                idex_mem_to_reg <= 1'b0;
                idex_mem_we     <= 1'b0;
                idex_is_bz      <= 1'b0;
                idex_is_bnz     <= 1'b0;
                idex_is_jmp     <= 1'b0;
                idex_is_halt    <= 1'b0;
                idex_sets_flags <= 1'b0;
            end else begin
                idex_valid      <= 1'b1;
                idex_pc         <= ifid_pc;
                idex_a          <= id_a;
                idex_b          <= id_b;
                idex_imm        <= id_imm;
                idex_rd         <= id_rd;
                idex_ra         <= id_ra;
                idex_rb         <= id_rb;
                idex_alu_op     <= c_alu_op;
                idex_alu_imm    <= c_alu_imm;
                idex_reg_write  <= c_reg_write;
                idex_sets_flags <= c_sets_flags;
                idex_mem_to_reg <= c_mem_to_reg;
                idex_mem_we     <= c_mem_we;
                idex_is_bz      <= c_is_bz;
                idex_is_bnz     <= c_is_bnz;
                idex_is_jmp     <= c_is_jmp;
                idex_is_halt    <= c_is_halt;
            end

            //------------------------------------------------------------------
            // Flags: written when an ALU instruction leaves EX
            //------------------------------------------------------------------
            if (idex_valid && idex_sets_flags)
                flags <= {alu_z, alu_c};

            //------------------------------------------------------------------
            // EX/MEM: control bits are ANDed with valid (bubbles do nothing)
            //------------------------------------------------------------------
            exmem_valid      <= idex_valid;
            exmem_alu_y      <= alu_y;
            exmem_addr       <= ex_a;          // LD/ST address = rs1
            exmem_store_data <= ex_b;          // ST data = rd
            exmem_rd         <= idex_rd;
            exmem_reg_write  <= idex_valid && idex_reg_write;
            exmem_mem_to_reg <= idex_valid && idex_mem_to_reg;
            exmem_mem_we     <= idex_valid && idex_mem_we;
            exmem_is_halt    <= idex_valid && idex_is_halt;

            //------------------------------------------------------------------
            // MEM/WB
            //------------------------------------------------------------------
            memwb_valid      <= exmem_valid;
            memwb_data       <= mem_result;
            memwb_rd         <= exmem_rd;
            memwb_reg_write  <= exmem_reg_write && !halted;
            memwb_is_halt    <= exmem_is_halt;

            //------------------------------------------------------------------
            // Halt when HLT completes WB
            //------------------------------------------------------------------
            if (memwb_valid && memwb_is_halt)
                halted <= 1'b1;
        end
    end

endmodule