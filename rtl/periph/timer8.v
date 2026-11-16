//==============================================================================
// File        : timer8.v
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral for RISC-8 CPU
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : 8-bit timer with prescaler, auto-reload counter,
//               compare match and PWM output.
//
//   Formulas:
//     period  = (PRESC + 1) * (LOAD + 1)  clocks
//     compare = (CMP + 1)   * (PRESC + 1) clocks after start
//     duty    = CMP / (LOAD + 1)
//==============================================================================
`timescale 1ns/1ps                       // time unit 1 ns, precision 1 ps

module timer8 (
    input  wire       clk,               // system clock
    input  wire       rst_n,             // asynchronous reset, active low
    input  wire       en,                // timer enable (TMR_CTRL.EN)
    input  wire [7:0] presc,             // prescaler value (TMR_PRESC)
    input  wire [7:0] load,              // reload / top value (TMR_LOAD)
    input  wire [7:0] cmp,               // compare value (TMR_CMP)
    output reg  [7:0] cnt,               // current counter value (TMR_CNT)
    output wire       ovf_pulse,         // 1-clock pulse when counter wraps
    output wire       cmp_pulse,         // 1-clock pulse when cnt == CMP
    output reg        pwm_out            // PWM output pin
);

    //--------------------------------------------------------------------------
    // Prescaler: counts clocks from 0 to PRESC, then generates one "tick".
    // The main counter only advances on a tick, so the timer runs
    // (PRESC + 1) times slower than clk.
    //--------------------------------------------------------------------------
    reg  [7:0] psc;                      // prescaler counter

    // tick = 1 when the prescaler has reached PRESC.
    // ">=" (instead of "==") keeps the timer safe if software lowers PRESC
    // while psc is already above the new value.
    wire       tick = en && (psc >= presc);

    //--------------------------------------------------------------------------
    // Prescaler + main counter
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                // reset: clear everything
            psc <= 8'd0;
            cnt <= 8'd0;
        end else if (!en) begin          // timer disabled: hold at zero
            psc <= 8'd0;
            cnt <= 8'd0;
        end else if (tick) begin         // one prescaled tick
            psc <= 8'd0;                 // restart the prescaler
            if (cnt >= load)             // reached the top value
                cnt <= 8'd0;             //   -> wrap around to 0
            else
                cnt <= cnt + 8'd1;       //   -> count up
        end else begin
            psc <= psc + 8'd1;           // no tick yet: keep dividing
        end
    end

    //--------------------------------------------------------------------------
    // Event pulses (combinational, high for exactly one clock on a tick)
    //--------------------------------------------------------------------------
    // Overflow: the tick on which the counter is at LOAD (it wraps next).
    assign ovf_pulse = tick && (cnt >= load);

    // Compare match: the tick on which the counter equals CMP.
    assign cmp_pulse = tick && (cnt == cmp);

    //--------------------------------------------------------------------------
    // PWM output: high while cnt < CMP, so duty = CMP / (LOAD + 1).
    // Registered to avoid glitches on the output pin.
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pwm_out <= 1'b0;
        else
            pwm_out <= en && (cnt < cmp);
    end

endmodule