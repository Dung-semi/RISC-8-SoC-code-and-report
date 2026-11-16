//==============================================================================
// File        : sar_adc_ctrl.v
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral for RISC-8 CPU
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Successive Approximation (SAR) ADC controller.
//               Drives the analog front end (MUX, sample & hold, DAC) and
//               reads one comparator bit per step, MSB first.
//
//   State flow : IDLE -> SAMPLE (SMP+1 ticks) -> CONVERT (N ticks) -> IDLE
//   Conversion : (SMP + 1 + N) * (DIV + 1) clocks
//   Abort      : clearing EN at any time returns to IDLE, no result
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module sar_adc_ctrl #(
    parameter N = 8                        // ADC resolution in bits
) (
    input  wire         clk,               // system clock
    input  wire         rst_n,             // asynchronous reset, active low
    input  wire         en,                // ADC enable (ADC_CTRL.EN)
    input  wire         start,             // 1-clock start request (trigger)
    input  wire [1:0]   ch_in,             // channel to measure (ADC_CTRL.CH)
    input  wire [7:0]   smp,               // sample window length (ADC_SMP)
    input  wire [7:0]   div,               // ADC clock divider (ADC_DIV)
    input  wire         cmp,               // comparator: 1 = Vhold >= Vdac
    output reg          sample,            // 1 = S&H tracks input, 0 = hold
    output reg  [1:0]   ch,                // channel select to the analog MUX
    output wire [N-1:0] dac,               // current guess sent to the DAC
    output wire         busy,              // 1 while a conversion runs
    output reg          eoc,               // end of conversion, 1-clock pulse
    output reg  [N-1:0] result,            // last conversion result
    output reg  [1:0]   result_ch          // channel of the last result
);

    //--------------------------------------------------------------------------
    // State encoding
    //--------------------------------------------------------------------------
    localparam IDLE    = 2'd0;             // waiting for a start request
    localparam SAMPLE  = 2'd1;             // sample & hold is tracking input
    localparam CONVERT = 2'd2;             // binary search, one bit per tick

    reg [1:0]   state;                     // current state
    reg [7:0]   divcnt;                    // clock divider counter
    reg [7:0]   smpcnt;                    // sample window counter
    reg [N-1:0] sar;                       // bits already decided
    reg [N-1:0] mask;                      // one-hot: bit being tested now

    //--------------------------------------------------------------------------
    // ADC tick: one step every (DIV + 1) clocks.
    // ">=" keeps the divider safe if software lowers DIV during a conversion.
    //--------------------------------------------------------------------------
    wire tick = (divcnt >= div);

    //--------------------------------------------------------------------------
    // Outputs that are pure functions of the state
    //--------------------------------------------------------------------------
    assign busy = (state != IDLE);         // busy in SAMPLE and CONVERT

    // During CONVERT the DAC shows "decided bits + bit under test".
    // Outside CONVERT the DAC is parked at 0.
    assign dac  = (state == CONVERT) ? (sar | mask) : {N{1'b0}};

    //--------------------------------------------------------------------------
    // Main state machine
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                  // reset: go idle, clear outputs
            state     <= IDLE;
            sample    <= 1'b0;
            ch        <= 2'd0;
            divcnt    <= 8'd0;
            smpcnt    <= 8'd0;
            sar       <= {N{1'b0}};
            mask      <= {N{1'b0}};
            eoc       <= 1'b0;
            result    <= {N{1'b0}};
            result_ch <= 2'd0;
        end else begin
            eoc <= 1'b0;                   // default: EOC is a 1-clock pulse

            if (!en) begin                 // ADC disabled: abort, no result
                state  <= IDLE;
                sample <= 1'b0;
                divcnt <= 8'd0;
            end else begin
                case (state)

                //--------------------------------------------------------------
                // IDLE: wait for a start request, then begin sampling
                //--------------------------------------------------------------
                IDLE: begin
                    if (start) begin
                        state  <= SAMPLE;
                        sample <= 1'b1;    // close the S&H switch (track)
                        ch     <= ch_in;   // latch the channel for this run
                        divcnt <= 8'd0;
                        smpcnt <= 8'd0;
                    end
                end

                //--------------------------------------------------------------
                // SAMPLE: let the hold capacitor charge for SMP+1 ticks
                //--------------------------------------------------------------
                SAMPLE: begin
                    if (tick) begin
                        divcnt <= 8'd0;
                        if (smpcnt >= smp) begin          // window finished
                            state  <= CONVERT;
                            sample <= 1'b0;               // open switch: hold
                            sar    <= {N{1'b0}};          // no bits decided
                            mask   <= {1'b1, {(N-1){1'b0}}}; // test MSB first
                        end else begin
                            smpcnt <= smpcnt + 8'd1;
                        end
                    end else begin
                        divcnt <= divcnt + 8'd1;
                    end
                end

                //--------------------------------------------------------------
                // CONVERT: binary search, one bit per tick, MSB first.
                // cmp = 1 -> input >= guess -> keep the bit.
                // cmp = 0 -> guess too big  -> clear the bit.
                //--------------------------------------------------------------
                CONVERT: begin
                    if (tick) begin
                        divcnt <= 8'd0;
                        if (mask[0]) begin                // LSB: last step
                            result    <= cmp ? (sar | mask) : sar;
                            result_ch <= ch;
                            eoc       <= 1'b1;            // result is ready
                            state     <= IDLE;
                        end else begin
                            sar  <= cmp ? (sar | mask) : sar;
                            mask <= mask >> 1;            // next lower bit
                        end
                    end else begin
                        divcnt <= divcnt + 8'd1;
                    end
                end

                default: state <= IDLE;    // safety: unknown state -> idle

                endcase
            end
        end
    end

endmodule