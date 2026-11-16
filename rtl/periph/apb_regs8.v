//==============================================================================
// File        : apb_regs8.v
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral for RISC-8 CPU
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : 16-register block on an 8-bit APB slave port.
//               Holds the configuration registers, selects the ADC trigger,
//               collects six sticky event flags and drives the irq output.
//
//   Register map (offset : name : access)
//     0x0 TMR_CTRL   RW   [1] ONESHOT [0] EN
//     0x1 TMR_PRESC  RW   prescaler
//     0x2 TMR_LOAD   RW   reload value        (reset 0xFF)
//     0x3 TMR_CMP    RW   compare value       (reset 0x80)
//     0x4 TMR_CNT    RO   current count
//     0x5 ADC_CTRL   RW   [5:4] CH [3:2] TRIG_SEL [1] START(W) [0] EN
//     0x6 ADC_SMP    RW   sample window       (reset 0x04)
//     0x7 ADC_DIV    RW   ADC clock divider
//     0x8 ADC_THR_LO RW   window low limit
//     0x9 ADC_THR_HI RW   window high limit   (reset 0xFF)
//     0xA ADC_DATA   RO   oldest FIFO result, read pops the FIFO
//     0xB ADC_RCH    RO   [7] VALID [1:0] CH of oldest result (no pop)
//     0xC ADC_STAT   RO   [6] BUSY [5] FULL [4] EMPTY [3:0] LEVEL
//     0xD IRQ_EN     RW   interrupt enables
//     0xE IRQ_STAT   W1C  [5] TRIG_MISS [4] FIFO_OVR [3] ADC_WD
//                         [2] ADC_EOC   [1] TMR_CMP  [0] TMR_OVF
//     0xF ID         RO   always 0xA8
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module apb_regs8 (
    input  wire       clk,                 // system clock
    input  wire       rst_n,               // asynchronous reset, active low
    //---------------- 8-bit APB slave port ----------------
    input  wire       psel,                // peripheral selected
    input  wire       penable,             // access phase
    input  wire       pwrite,              // 1 = write, 0 = read
    input  wire [3:0] paddr,               // register offset 0x0..0xF
    input  wire [7:0] pwdata,              // write data
    output reg  [7:0] prdata,              // read data (0 when not selected)
    output wire       irq,                 // interrupt request to the CPU
    //---------------- timer side ----------------
    output wire       tmr_en,              // timer enable
    output wire [7:0] tmr_presc,           // prescaler
    output wire [7:0] tmr_load,            // reload value
    output wire [7:0] tmr_cmp,             // compare value
    input  wire [7:0] tmr_cnt,             // current count
    input  wire       tmr_ovf,             // overflow pulse
    input  wire       tmr_cmp_hit,         // compare match pulse
    //---------------- ADC side ----------------
    output wire       adc_en,              // ADC enable
    output wire       adc_start,           // start one conversion (pulse)
    output wire [1:0] adc_ch,              // channel select
    output wire [7:0] adc_smp,             // sample window
    output wire [7:0] adc_div,             // clock divider
    input  wire       adc_busy,            // conversion in progress
    input  wire       adc_eoc,             // end of conversion pulse
    input  wire [7:0] adc_result,          // new result (valid with eoc)
    //---------------- FIFO side ----------------
    output wire       fifo_pop,            // remove the oldest entry
    input  wire [9:0] fifo_dout,           // oldest entry {ch, data}
    input  wire [3:0] fifo_level,          // number of entries
    input  wire       fifo_empty,          // FIFO empty
    input  wire       fifo_full,           // FIFO full
    input  wire       fifo_ovf             // result dropped (pulse)
);

    //--------------------------------------------------------------------------
    // Register offsets
    //--------------------------------------------------------------------------
    localparam A_TMR_CTRL  = 4'h0;
    localparam A_TMR_PRESC = 4'h1;
    localparam A_TMR_LOAD  = 4'h2;
    localparam A_TMR_CMP   = 4'h3;
    localparam A_TMR_CNT   = 4'h4;
    localparam A_ADC_CTRL  = 4'h5;
    localparam A_ADC_SMP   = 4'h6;
    localparam A_ADC_DIV   = 4'h7;
    localparam A_THR_LO    = 4'h8;
    localparam A_THR_HI    = 4'h9;
    localparam A_ADC_DATA  = 4'hA;
    localparam A_ADC_RCH   = 4'hB;
    localparam A_ADC_STAT  = 4'hC;
    localparam A_IRQ_EN    = 4'hD;
    localparam A_IRQ_STAT  = 4'hE;
    localparam A_ID        = 4'hF;

    //--------------------------------------------------------------------------
    // Storage registers
    //--------------------------------------------------------------------------
    reg [1:0] r_tmr_ctrl;                  // [1] ONESHOT [0] EN
    reg [7:0] r_presc;
    reg [7:0] r_load;
    reg [7:0] r_cmp;
    reg [5:0] r_adc_ctrl;                  // [5:4] CH [3:2] TRIG [1] 0 [0] EN
    reg [7:0] r_smp;
    reg [7:0] r_div;
    reg [7:0] r_thr_lo;
    reg [7:0] r_thr_hi;
    reg [5:0] r_irq_en;                    // one enable per event flag
    reg [5:0] r_irq_stat;                  // sticky event flags
    reg       sw_start_q;                  // START bit, delayed one clock

    //--------------------------------------------------------------------------
    // Bus decode: one APB access = one clock (psel and penable both high)
    //--------------------------------------------------------------------------
    wire wr = psel & penable &  pwrite;    // register write this clock
    wire rd = psel & penable & ~pwrite;    // register read this clock

    //--------------------------------------------------------------------------
    // Configuration outputs to the timer and the ADC
    //--------------------------------------------------------------------------
    assign tmr_en    = r_tmr_ctrl[0];
    assign tmr_presc = r_presc;
    assign tmr_load  = r_load;
    assign tmr_cmp   = r_cmp;
    assign adc_en    = r_adc_ctrl[0];
    assign adc_ch    = r_adc_ctrl[5:4];
    assign adc_smp   = r_smp;
    assign adc_div   = r_div;

    //--------------------------------------------------------------------------
    // ADC trigger selection (ADC_CTRL.TRIG_SEL)
    //   0 = software START bit
    //   1 = timer overflow
    //   2 = timer compare match
    //   3 = continuous (restart as soon as the ADC is idle)
    //--------------------------------------------------------------------------
    wire [1:0] trig_sel  = r_adc_ctrl[3:2];

    wire hw_trig   = ((trig_sel == 2'd1) & tmr_ovf) |
                     ((trig_sel == 2'd2) & tmr_cmp_hit);

    // Any one-shot trigger request (software or hardware)
    wire trig_req  = adc_en & (sw_start_q | hw_trig);

    // Continuous mode: start whenever the ADC is not busy
    wire cont_trig = adc_en & (trig_sel == 2'd3) & ~adc_busy;

    // Start only if the ADC is free
    assign adc_start = (trig_req & ~adc_busy) | cont_trig;

    // Trigger arrived while a conversion was still running -> lost
    wire trig_miss = trig_req & adc_busy;

    //--------------------------------------------------------------------------
    // Event detection
    //--------------------------------------------------------------------------
    // Window comparator: result outside [THR_LO, THR_HI]
    wire wd_hit = adc_eoc &
                  ((adc_result < r_thr_lo) | (adc_result > r_thr_hi));

    // Six events, same bit order as IRQ_STAT / IRQ_EN
    wire [5:0] events = {trig_miss,        // bit 5
                         fifo_ovf,         // bit 4
                         wd_hit,           // bit 3
                         adc_eoc,          // bit 2
                         tmr_cmp_hit,      // bit 1
                         tmr_ovf};         // bit 0

    // Write-1-to-clear mask: bits written as 1 to IRQ_STAT
    wire [5:0] w1c = (wr && (paddr == A_IRQ_STAT)) ? pwdata[5:0] : 6'd0;

    //--------------------------------------------------------------------------
    // FIFO pop and interrupt output
    //--------------------------------------------------------------------------
    // Reading ADC_DATA removes the oldest result (only if there is one)
    assign fifo_pop = rd && (paddr == A_ADC_DATA) && !fifo_empty;

    // irq is high while any enabled flag is set
    assign irq = |(r_irq_stat & r_irq_en);

    //--------------------------------------------------------------------------
    // Register writes, one-shot clear and sticky flags
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                  // reset values from the spec
            r_tmr_ctrl <= 2'd0;
            r_presc    <= 8'h00;
            r_load     <= 8'hFF;
            r_cmp      <= 8'h80;
            r_adc_ctrl <= 6'd0;
            r_smp      <= 8'h04;
            r_div      <= 8'h00;
            r_thr_lo   <= 8'h00;
            r_thr_hi   <= 8'hFF;
            r_irq_en   <= 6'd0;
            r_irq_stat <= 6'd0;
            sw_start_q <= 1'b0;
        end else begin
            // START is used one clock after the write, when ADC_CTRL.EN
            // already holds its new value.
            sw_start_q <= wr && (paddr == A_ADC_CTRL) && pwdata[1];

            // CPU register writes
            if (wr) begin
                case (paddr)
                    A_TMR_CTRL:  r_tmr_ctrl <= pwdata[1:0];
                    A_TMR_PRESC: r_presc    <= pwdata;
                    A_TMR_LOAD:  r_load     <= pwdata;
                    A_TMR_CMP:   r_cmp      <= pwdata;
                    // START (bit 1) is not stored, it always reads back 0
                    A_ADC_CTRL:  r_adc_ctrl <= {pwdata[5:2], 1'b0, pwdata[0]};
                    A_ADC_SMP:   r_smp      <= pwdata;
                    A_ADC_DIV:   r_div      <= pwdata;
                    A_THR_LO:    r_thr_lo   <= pwdata;
                    A_THR_HI:    r_thr_hi   <= pwdata;
                    A_IRQ_EN:    r_irq_en   <= pwdata[5:0];
                    default: ;             // read-only or W1C: nothing here
                endcase
            end

            // One-shot mode: hardware clears EN after the first overflow
            if (tmr_ovf && r_tmr_ctrl[1])
                r_tmr_ctrl[0] <= 1'b0;

            // Sticky flags: clear the W1C bits, then set new events.
            // A new event in the same clock as a clear wins (never lost).
            r_irq_stat <= (r_irq_stat & ~w1c) | events;
        end
    end

    //--------------------------------------------------------------------------
    // Read multiplexer (combinational, data ready in the same clock).
    // Returns 0 when not selected so it can be OR-ed with other devices.
    //--------------------------------------------------------------------------
    always @(*) begin
        prdata = 8'h00;
        if (psel) begin
            case (paddr)
                A_TMR_CTRL:  prdata = {6'd0, r_tmr_ctrl};
                A_TMR_PRESC: prdata = r_presc;
                A_TMR_LOAD:  prdata = r_load;
                A_TMR_CMP:   prdata = r_cmp;
                A_TMR_CNT:   prdata = tmr_cnt;
                A_ADC_CTRL:  prdata = {2'd0, r_adc_ctrl};
                A_ADC_SMP:   prdata = r_smp;
                A_ADC_DIV:   prdata = r_div;
                A_THR_LO:    prdata = r_thr_lo;
                A_THR_HI:    prdata = r_thr_hi;
                A_ADC_DATA:  prdata = fifo_empty ? 8'h00 : fifo_dout[7:0];
                A_ADC_RCH:   prdata = {~fifo_empty, 5'd0, fifo_dout[9:8]};
                A_ADC_STAT:  prdata = {1'b0, adc_busy, fifo_full,
                                       fifo_empty, fifo_level};
                A_IRQ_EN:    prdata = {2'd0, r_irq_en};
                A_IRQ_STAT:  prdata = {2'd0, r_irq_stat};
                A_ID:        prdata = 8'hA8;
                default:     prdata = 8'h00;
            endcase
        end
    end

endmodule