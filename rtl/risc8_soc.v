//==============================================================================
// File        : risc8_soc.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : System top level (SoC). Connects the RISC-8 CPU core to the
//               Timer + ADC peripheral through a 16-byte I/O page at
//               0xF0..0xFF.
//                 u_cpu  : risc8_5stage_core (IO_ENABLE = 1, IO_PAGE = F)
//                 u_tadc : timer_adc8_cpu_if
//               Shared clock. CPU reset is active high, peripheral reset is
//               active low, so the reset is inverted here.
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module risc8_soc #(
    parameter IMEM_FILE = "soc_demo.hex"   // firmware loaded into imem
) (
    input  wire       clk,                 // system clock
    input  wire       rst,                 // reset, active high (CPU style)
    output wire       halted,              // CPU executed HLT
    output wire [7:0] pc_out,              // current PC (debug)
    output wire       irq,                 // peripheral interrupt request
    output wire       pwm_out,             // timer PWM output
    output wire       adc_sample,          // analog: 1 = track, 0 = hold
    output wire [1:0] adc_ch,              // analog: MUX channel
    output wire [7:0] adc_dac,             // analog: DAC code
    input  wire       adc_cmp              // analog: comparator result
);

    //--------------------------------------------------------------------------
    // CPU <-> peripheral bus wires
    //--------------------------------------------------------------------------
    wire       io_cs;                      // chip select (one clock per LD/ST)
    wire       io_we;                      // 1 = store, 0 = load
    wire [3:0] io_addr;                    // register number 0x0..0xF
    wire [7:0] io_wdata;                   // store data
    wire [7:0] io_rdata;                   // load data

    //--------------------------------------------------------------------------
    // CPU core with the I/O page enabled
    //--------------------------------------------------------------------------
    risc8_5stage_core #(
        .IMEM_FILE (IMEM_FILE),
        .IO_ENABLE (1),                    // map 0xF0..0xFF to the io_* port
        .IO_PAGE   (4'hF)
    ) u_cpu (
        .clk        (clk),
        .rst        (rst),
        .halted     (halted),
        .pc_out     (pc_out),
        .flags_out  (),                    // debug output, not used here
        .instr_done (),                    // debug output, not used here
        .io_cs      (io_cs),
        .io_we      (io_we),
        .io_addr    (io_addr),
        .io_wdata   (io_wdata),
        .io_rdata   (io_rdata)
    );

    //--------------------------------------------------------------------------
    // Timer + ADC peripheral
    //--------------------------------------------------------------------------
    timer_adc8_cpu_if u_tadc (
        .clk        (clk),
        .rst_n      (~rst),                // polarity conversion
        .cs         (io_cs),
        .we         (io_we),
        .addr       (io_addr),
        .wdata      (io_wdata),
        .rdata      (io_rdata),
        .irq        (irq),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp),
        .pwm_out    (pwm_out)
    );

endmodule