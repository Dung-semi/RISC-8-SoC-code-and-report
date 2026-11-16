//==============================================================================
// File        : timer_adc8_cpu_if.v
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral for RISC-8 CPU
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : CPU bus wrapper. Turns the simple one-cycle CPU bus
//               (cs, we, addr, wdata -> rdata) into the 8-bit APB port
//               of timer_adc8_top.
//
//   - cs drives both PSEL and PENABLE, so every LD / ST is one APB
//     access completed in a single clock (no wait states)
//   - rdata is 0 when cs = 0, so it can be OR-ed with other devices
//   - keep cs high for exactly one clock per instruction: a read of
//     ADC_DATA pops one result from the FIFO
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module timer_adc8_cpu_if (
    input  wire       clk,                 // system clock (shared with CPU)
    input  wire       rst_n,               // asynchronous reset, active low
    //---------------- simple CPU bus ----------------
    input  wire       cs,                  // chip select from address decoder
    input  wire       we,                  // 1 = store (ST), 0 = load (LD)
    input  wire [3:0] addr,                // register number 0x0..0xF
    input  wire [7:0] wdata,               // store data
    output wire [7:0] rdata,               // load data, same clock
    //---------------- system outputs ----------------
    output wire       irq,                 // interrupt request
    output wire       pwm_out,             // timer PWM output
    //---------------- analog front end ----------------
    output wire       adc_sample,          // 1 = track, 0 = hold
    output wire [1:0] adc_ch,              // analog MUX channel
    output wire [7:0] adc_dac,             // DAC code
    input  wire       adc_cmp              // comparator result
);

    //--------------------------------------------------------------------------
    // Peripheral instance.
    // APB normally needs two clocks (setup, then access). Driving PSEL and
    // PENABLE from the same cs signal collapses this into one clock, which
    // matches the single-cycle MEM stage of the RISC-8 pipeline.
    //--------------------------------------------------------------------------
    timer_adc8_top u_periph (
        .clk        (clk),
        .rst_n      (rst_n),
        // bus mapping: CPU -> APB
        .psel       (cs),                  // selected when cs = 1
        .penable    (cs),                  // access phase in the same clock
        .pwrite     (we),                  // store = write, load = read
        .paddr      (addr),                // register offset
        .pwdata     (wdata),               // store data
        .prdata     (rdata),               // load data back to the CPU
        // system outputs
        .irq        (irq),
        .pwm_out    (pwm_out),
        // analog front end
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

endmodule