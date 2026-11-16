//==============================================================================
// File        : timer_adc8_top.v
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral for RISC-8 CPU
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Peripheral top level. Connects the four sub-blocks:
//                 u_regs  : apb_regs8    (16 registers + interrupt logic)
//                 u_timer : timer8       (prescaler, counter, compare, PWM)
//                 u_adc   : sar_adc_ctrl (SAR conversion state machine)
//                 u_fifo  : sync_fifo    (8-entry result queue)
//               External interface: 8-bit APB slave port, irq, PWM pin and
//               the control wires of the analog front end.
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module timer_adc8_top (
    input  wire       clk,                 // system clock
    input  wire       rst_n,               // asynchronous reset, active low
    //---------------- 8-bit APB slave port ----------------
    input  wire       psel,                // peripheral selected
    input  wire       penable,             // access phase
    input  wire       pwrite,              // 1 = write, 0 = read
    input  wire [3:0] paddr,               // register offset 0x0..0xF
    input  wire [7:0] pwdata,              // write data
    output wire [7:0] prdata,              // read data
    //---------------- outputs to the system ----------------
    output wire       irq,                 // interrupt request
    output wire       pwm_out,             // timer PWM output
    //---------------- analog front end ----------------
    output wire       adc_sample,          // 1 = track, 0 = hold
    output wire [1:0] adc_ch,              // analog MUX channel
    output wire [7:0] adc_dac,             // DAC code (current guess)
    input  wire       adc_cmp              // comparator: Vhold >= Vdac
);

    //--------------------------------------------------------------------------
    // Internal wires: registers <-> timer
    //--------------------------------------------------------------------------
    wire       tmr_en;                     // timer enable
    wire [7:0] tmr_presc;                  // prescaler value
    wire [7:0] tmr_load;                   // reload value
    wire [7:0] tmr_cmp;                    // compare value
    wire [7:0] tmr_cnt;                    // current count
    wire       tmr_ovf;                    // overflow pulse
    wire       tmr_cmp_hit;                // compare match pulse

    //--------------------------------------------------------------------------
    // Internal wires: registers <-> ADC controller
    //--------------------------------------------------------------------------
    wire       adc_en;                     // ADC enable
    wire       adc_start;                  // start pulse
    wire [1:0] adc_ch_cfg;                 // channel chosen by software
    wire [7:0] adc_smp;                    // sample window
    wire [7:0] adc_div;                    // clock divider
    wire       adc_busy;                   // conversion running
    wire       adc_eoc;                    // end of conversion pulse
    wire [7:0] adc_result;                 // conversion result
    wire [1:0] adc_result_ch;              // channel of the result

    //--------------------------------------------------------------------------
    // Internal wires: registers <-> FIFO
    //--------------------------------------------------------------------------
    wire       fifo_pop;                   // CPU read of ADC_DATA
    wire [9:0] fifo_dout;                  // oldest entry {ch, data}
    wire [3:0] fifo_level;                 // number of entries
    wire       fifo_empty;                 // FIFO empty
    wire       fifo_full;                  // FIFO full
    wire       fifo_ovf;                   // result dropped

    //--------------------------------------------------------------------------
    // Register block: the only block the CPU talks to
    //--------------------------------------------------------------------------
    apb_regs8 u_regs (
        .clk         (clk),
        .rst_n       (rst_n),
        // bus
        .psel        (psel),
        .penable     (penable),
        .pwrite      (pwrite),
        .paddr       (paddr),
        .pwdata      (pwdata),
        .prdata      (prdata),
        .irq         (irq),
        // timer
        .tmr_en      (tmr_en),
        .tmr_presc   (tmr_presc),
        .tmr_load    (tmr_load),
        .tmr_cmp     (tmr_cmp),
        .tmr_cnt     (tmr_cnt),
        .tmr_ovf     (tmr_ovf),
        .tmr_cmp_hit (tmr_cmp_hit),
        // ADC
        .adc_en      (adc_en),
        .adc_start   (adc_start),
        .adc_ch      (adc_ch_cfg),
        .adc_smp     (adc_smp),
        .adc_div     (adc_div),
        .adc_busy    (adc_busy),
        .adc_eoc     (adc_eoc),
        .adc_result  (adc_result),
        // FIFO
        .fifo_pop    (fifo_pop),
        .fifo_dout   (fifo_dout),
        .fifo_level  (fifo_level),
        .fifo_empty  (fifo_empty),
        .fifo_full   (fifo_full),
        .fifo_ovf    (fifo_ovf)
    );

    //--------------------------------------------------------------------------
    // Timer: generates overflow / compare events and the PWM output
    //--------------------------------------------------------------------------
    timer8 u_timer (
        .clk         (clk),
        .rst_n       (rst_n),
        .en          (tmr_en),
        .presc       (tmr_presc),
        .load        (tmr_load),
        .cmp         (tmr_cmp),
        .cnt         (tmr_cnt),
        .ovf_pulse   (tmr_ovf),
        .cmp_pulse   (tmr_cmp_hit),
        .pwm_out     (pwm_out)
    );

    //--------------------------------------------------------------------------
    // SAR ADC controller: 8-bit resolution
    //--------------------------------------------------------------------------
    sar_adc_ctrl #(
        .N           (8)
    ) u_adc (
        .clk         (clk),
        .rst_n       (rst_n),
        .en          (adc_en),
        .start       (adc_start),
        .ch_in       (adc_ch_cfg),
        .smp         (adc_smp),
        .div         (adc_div),
        .cmp         (adc_cmp),            // from the analog comparator
        .sample      (adc_sample),         // to the sample & hold switch
        .ch          (adc_ch),             // to the analog MUX
        .dac         (adc_dac),            // to the DAC
        .busy        (adc_busy),
        .eoc         (adc_eoc),
        .result      (adc_result),
        .result_ch   (adc_result_ch)
    );

    //--------------------------------------------------------------------------
    // Result FIFO: each EOC pushes {channel, result}
    //--------------------------------------------------------------------------
    sync_fifo #(
        .W           (10),                 // {ch[1:0], data[7:0]}
        .DEPTH       (8),                  // 8 entries
        .AW          (3)                   // log2(8)
    ) u_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .push        (adc_eoc),            // store every finished result
        .pop         (fifo_pop),           // CPU read of ADC_DATA
        .din         ({adc_result_ch, adc_result}),
        .dout        (fifo_dout),
        .level       (fifo_level),
        .empty       (fifo_empty),
        .full        (fifo_full),
        .overflow    (fifo_ovf)
    );

endmodule