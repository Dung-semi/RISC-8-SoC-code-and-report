//==============================================================================
// File        : afe_model.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : Behavioural model of the analog front end (SIMULATION ONLY,
//               not synthesizable). Replaces the real analog circuit:
//                 4-input MUX -> sample & hold -> comparator <- 8-bit DAC
//               cmp = 1 when the held input voltage >= DAC voltage.
//
//   Channel voltages (VREF = 3.3 V, 1 LSB = 12.9 mV)
//     ch0 = 0.400 V -> code  31 (0x1F)
//     ch1 = 1.111 V -> code  86 (0x56)
//     ch2 = 2.000 V -> code 155 (0x9B)
//     ch3 = 3.000 V -> code 232 (0xE8)
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module afe_model (
    input  wire       sample,              // 1 = track input, 0 = hold
    input  wire [1:0] ch,                  // MUX channel select
    input  wire [7:0] dac,                 // DAC code from the SAR controller
    output reg        cmp                  // comparator output
);

    //--------------------------------------------------------------------------
    // Analog quantities as real numbers (volts)
    //--------------------------------------------------------------------------
    real VREF;                             // ADC reference voltage
    real vin0, vin1, vin2, vin3;           // sensor voltages on ch0..ch3
    real vsel;                             // MUX output
    real vhold;                            // voltage stored on the hold cap
    real vdac;                             // DAC output voltage

    //--------------------------------------------------------------------------
    // Initial values (change vin0..vin3 to test other inputs)
    //--------------------------------------------------------------------------
    initial begin
        VREF  = 3.3;
        vin0  = 0.40;
        vin1  = 1.111;
        vin2  = 2.0;
        vin3  = 3.0;
        vhold = 0.0;
        cmp   = 1'b0;
    end

    //--------------------------------------------------------------------------
    // MUX + sample & hold:
    // while sample = 1 the capacitor follows the selected input,
    // when sample falls the last value is held.
    //--------------------------------------------------------------------------
    always @(sample or ch or vin0 or vin1 or vin2 or vin3) begin
        case (ch)
            2'd0:    vsel = vin0;
            2'd1:    vsel = vin1;
            2'd2:    vsel = vin2;
            default: vsel = vin3;
        endcase
        if (sample)
            vhold = vsel;
    end

    //--------------------------------------------------------------------------
    // 8-bit DAC + comparator: Vdac = code * VREF / 256
    //--------------------------------------------------------------------------
    always @(vhold or dac) begin
        vdac = dac * VREF / 256.0;
        cmp  = (vhold >= vdac);
    end

endmodule