//==============================================================================
// File        : tb_risc8_soc.v
// Project     : RISC-8 5-stage CPU + 8-bit Timer/ADC Peripheral
// Author      : Le Ky Dung
// Student ID  : SE190745
// Tool        : Vivado 2026.1
// Description : System testbench.
//               - 100 MHz clock, reset for 5 clocks
//               - runs the firmware soc_demo.hex until the CPU halts
//               - prints every I/O access (LD/ST to 0xF0..0xFF)
//               - checks 18 result bytes in RAM, the irq pin and the PWM duty
//==============================================================================
`timescale 1ns/1ps                         // time unit 1 ns, precision 1 ps

module tb_risc8_soc;

    //--------------------------------------------------------------------------
    // Clock and reset
    //--------------------------------------------------------------------------
    reg clk = 1'b0;
    reg rst = 1'b1;                        // active high
    always #5 clk = ~clk;                  // 10 ns period = 100 MHz

    //--------------------------------------------------------------------------
    // DUT wires
    //--------------------------------------------------------------------------
    wire       halted, irq, pwm_out, adc_sample, adc_cmp;
    wire [7:0] pc_out, adc_dac;
    wire [1:0] adc_ch;

    //--------------------------------------------------------------------------
    // Device under test (absolute path to the firmware file)
    //--------------------------------------------------------------------------
    risc8_soc #(
        .IMEM_FILE("C:/fpga/risc8_soc/soc_demo.hex")
    ) dut (
        .clk(clk), .rst(rst), .halted(halted), .pc_out(pc_out),
        .irq(irq), .pwm_out(pwm_out),
        .adc_sample(adc_sample), .adc_ch(adc_ch),
        .adc_dac(adc_dac), .adc_cmp(adc_cmp)
    );

    //--------------------------------------------------------------------------
    // Analog front end model
    //--------------------------------------------------------------------------
    afe_model u_afe (
        .sample(adc_sample), .ch(adc_ch), .dac(adc_dac), .cmp(adc_cmp)
    );

    //--------------------------------------------------------------------------
    // Counters and flags
    //--------------------------------------------------------------------------
    integer cycles = 0;                    // clocks until halt
    integer io_cnt = 0;                    // number of I/O accesses
    integer errors = 0;
    integer checks = 0;
    integer i, pwm_hi;
    reg     irq_seen = 1'b0;               // irq went high at least once

    //--------------------------------------------------------------------------
    // Monitor: count cycles, print every I/O access, watch irq
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && !halted) cycles = cycles + 1;
        if (dut.io_cs) begin
            io_cnt = io_cnt + 1;
            $display("[%0t] IO %s F%h  wdata=%h rdata=%h",
                     $time, dut.io_we ? "ST" : "LD",
                     dut.io_addr, dut.io_wdata, dut.io_rdata);
        end
        if (irq) irq_seen = 1'b1;
    end

    //--------------------------------------------------------------------------
    // Task: compare one RAM byte with the expected value
    //--------------------------------------------------------------------------
    task check;
        input [7:0]      addr;             // RAM address
        input [7:0]      exp;              // expected value
        input [8*40-1:0] msg;              // description
        reg   [7:0]      got;
        begin
            got    = dut.u_cpu.u_dmem.mem[addr];
            checks = checks + 1;
            if (got === exp)
                $display("PASS: MEM[%h] = %h  %0s", addr, got, msg);
            else begin
                errors = errors + 1;
                $display("FAIL: MEM[%h] = %h (expected %h)  %0s",
                         addr, got, exp, msg);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        // 1) hold reset for 5 clocks, release on a falling edge
        repeat (5) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 2) run until HLT (timeout after 20000 clocks)
        i = 0;
        while (!halted && i < 20000) begin
            @(posedge clk);
            i = i + 1;
        end
        if (!halted) begin
            errors = errors + 1;
            $display("FAIL: timeout, CPU never halted");
        end
        $display("CPU halted after %0d cycles, %0d I/O accesses",
                 cycles, io_cnt);

        // 3) check the results written by the firmware
        check(8'h80, 8'hA8, "A: ID register");
        check(8'h81, 8'h81, "B: ADC_RCH valid ch1");
        check(8'h82, 8'h56, "B: ch1 code 1.111V");
        check(8'h83, 8'h82, "C: ADC_RCH valid ch2");
        check(8'h84, 8'h9B, "C: ch2 code 2.0V");
        check(8'h85, 8'h82, "C: ADC_RCH valid ch2");
        check(8'h86, 8'h9B, "C: ch2 code 2.0V");
        check(8'h87, 8'h82, "C: ADC_RCH valid ch2");
        check(8'h88, 8'h9B, "C: ch2 code 2.0V");
        check(8'h89, 8'h82, "C: ADC_RCH valid ch2");
        check(8'h8A, 8'h9B, "C: ch2 code 2.0V");
        check(8'h8B, 8'h07, "C: IRQ_STAT OVF|CMP|EOC");
        check(8'h8C, 8'h03, "C: IRQ_STAT after W1C 0x04");
        check(8'h8D, 8'h0C, "D: IRQ_STAT EOC|WD");
        check(8'h8E, 8'hE8, "D: ch3 code 3.0V");
        check(8'h8F, 8'h1F, "F: 1st pop ch0 0.40V");
        check(8'h90, 8'h56, "F: 2nd pop ch1 1.111V");
        check(8'h91, 8'h10, "F: ADC_STAT empty");

        // 4) irq must have gone high in part D and be low now
        checks = checks + 1;
        if (irq_seen && !irq)
            $display("PASS: irq went high in part D and was cleared");
        else begin
            errors = errors + 1;
            $display("FAIL: irq seen=%b now=%b", irq_seen, irq);
        end

        // 5) PWM: count high clocks over 100 clocks, expect 30 (30 % duty)
        repeat (20) @(posedge clk);
        pwm_hi = 0;
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (pwm_out) pwm_hi = pwm_hi + 1;
        end
        checks = checks + 1;
        if (pwm_hi == 30)
            $display("PASS: PWM high for 30 of 100 clocks");
        else begin
            errors = errors + 1;
            $display("FAIL: PWM high %0d of 100", pwm_hi);
        end

        // 6) summary
        $display("--------------------------------------------------");
        if (errors == 0)
            $display("*** SOC TEST PASSED *** (%0d checks)", checks);
        else
            $display("*** SOC TEST FAILED *** (%0d errors / %0d checks)",
                     errors, checks);
        $display("--------------------------------------------------");
        $finish;
    end

endmodule