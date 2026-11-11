`timescale 1ns/1ps

`ifndef CYCLE
    `define CYCLE 5.0
`endif
`define MAX_CYCLE 500000
`define RST_DELAY 2
`define OUTPUT_SIZE 4096
`define SDFFILE "../02_SYN/Netlist/core_syn.sdf"

// tb0 is the invalid-barcode case. tb1--tb6 cover every K/precision pair.
`ifdef tb0
    `define INFILE  "../00_TESTBED/PATTERNS/image_tb0.dat"
    `define WFILE   "../00_TESTBED/PATTERNS/weight_tb1.dat"
    `define GOLDEN  "../00_TESTBED/PATTERNS/golden_tb1.dat"
    `define K_SIZE 0
    `define W_PRECISION 0
    `define WEIGHT_COUNT 0
    `define VALID_OP 0
`elsif tb2
    `define INFILE  "../00_TESTBED/PATTERNS/image_tb2.dat"
    `define WFILE   "../00_TESTBED/PATTERNS/weight_tb2.dat"
    `define GOLDEN  "../00_TESTBED/PATTERNS/golden_tb2.dat"
    `define K_SIZE 3
    `define W_PRECISION 8
    `define WEIGHT_COUNT 9
    `define VALID_OP 1
`elsif tb3
    `define INFILE  "../00_TESTBED/PATTERNS/image_tb3.dat"
    `define WFILE   "../00_TESTBED/PATTERNS/weight_tb3.dat"
    `define GOLDEN  "../00_TESTBED/PATTERNS/golden_tb3.dat"
    `define K_SIZE 4
    `define W_PRECISION 4
    `define WEIGHT_COUNT 16
    `define VALID_OP 1
`elsif tb4
    `define INFILE  "../00_TESTBED/PATTERNS/image_tb4.dat"
    `define WFILE   "../00_TESTBED/PATTERNS/weight_tb4.dat"
    `define GOLDEN  "../00_TESTBED/PATTERNS/golden_tb4.dat"
    `define K_SIZE 4
    `define W_PRECISION 8
    `define WEIGHT_COUNT 16
    `define VALID_OP 1
`elsif tb5
    `define INFILE  "../00_TESTBED/PATTERNS/image_tb5.dat"
    `define WFILE   "../00_TESTBED/PATTERNS/weight_tb5.dat"
    `define GOLDEN  "../00_TESTBED/PATTERNS/golden_tb5.dat"
    `define K_SIZE 5
    `define W_PRECISION 4
    `define WEIGHT_COUNT 25
    `define VALID_OP 1
`elsif tb6
    `define INFILE  "../00_TESTBED/PATTERNS/image_tb6.dat"
    `define WFILE   "../00_TESTBED/PATTERNS/weight_tb6.dat"
    `define GOLDEN  "../00_TESTBED/PATTERNS/golden_tb6.dat"
    `define K_SIZE 5
    `define W_PRECISION 8
    `define WEIGHT_COUNT 25
    `define VALID_OP 1
`else
    // Default to tb1: K=3, W4.
    `define INFILE  "../00_TESTBED/PATTERNS/image_tb1.dat"
    `define WFILE   "../00_TESTBED/PATTERNS/weight_tb1.dat"
    `define GOLDEN  "../00_TESTBED/PATTERNS/golden_tb1.dat"
    `define K_SIZE 3
    `define W_PRECISION 4
    `define WEIGHT_COUNT 9
    `define VALID_OP 1
`endif

module testbed;

    reg          clk;
    reg          rst_n;
    reg          in_valid;
    reg  [31:0]  in_data;
    wire         in_ready;
    wire [7:0]   out_data1, out_data2, out_data3, out_data4;
    wire [11:0]  out_addr1, out_addr2, out_addr3, out_addr4;
    wire         out_valid1, out_valid2, out_valid3, out_valid4;
    wire         exe_finish;

    reg [7:0] image_mem  [0:4095];
    reg [7:0] weight_mem [0:24];
    reg [7:0] golden_mem [0:4095];
    reg [7:0] out_mem    [0:4095];

    integer image_word;
    integer weight_word;
    integer base;
    integer index;
    integer cycle_count;
    integer execute_start_cycle;
    integer execute_end_cycle;
    integer config_errors;
    integer protocol_errors;
    integer data_errors;
    integer output_writes;
    reg config_done;
    reg weights_done;
    reg test_done;

    core u_core (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_in_valid(in_valid),
        .i_in_data(in_data),
        .o_in_ready(in_ready),
        .o_out_data1(out_data1),
        .o_out_data2(out_data2),
        .o_out_data3(out_data3),
        .o_out_data4(out_data4),
        .o_out_addr1(out_addr1),
        .o_out_addr2(out_addr2),
        .o_out_addr3(out_addr3),
        .o_out_addr4(out_addr4),
        .o_out_valid1(out_valid1),
        .o_out_valid2(out_valid2),
        .o_out_valid3(out_valid3),
        .o_out_valid4(out_valid4),
        .o_exe_finish(exe_finish)
    );
    //For gate-level simulation only
    `ifdef SDF
        initial $sdf_annotate(`SDFFILE, u_core);
        initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
    `endif

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("core.fsdb");
            $fsdbDumpvars(0, testbed, "+mda");
        end
    `endif

    initial begin
        $readmemh(`INFILE, image_mem);
        if (`VALID_OP) begin
            $readmemh(`WFILE, weight_mem);
            $readmemh(`GOLDEN, golden_mem);
        end
    end

    initial clk = 1'b0;
    always #(`CYCLE/2.0) clk = ~clk;

    initial begin
        rst_n = 1'b1;
        #(`CYCLE * 0.25);
        rst_n = 1'b0;
        #(`CYCLE * (`RST_DELAY + 0.7));
        rst_n = 1'b1;
    end

    initial begin
        cycle_count = 0;
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        forever @(posedge clk) cycle_count = cycle_count + 1;
    end

    initial begin
        wait (rst_n === 1'b1);
        #(`MAX_CYCLE * `CYCLE);
        if (!test_done) begin
            $display("[FAIL] Runtime exceeded %0d cycles.", `MAX_CYCLE);
            $finish;
        end
    end


    task send_word;
        input [31:0] word_value;
        begin
            @(negedge clk);
            in_valid = 1'b1;
            in_data = word_value;
            @(posedge clk);
            while (in_ready !== 1'b1)
                @(posedge clk);
        end
    endtask


    initial begin
        in_valid = 1'b0;
        in_data = 32'b0;
        weights_done = 1'b0;
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);

        for (image_word = 0; image_word < 1024; image_word = image_word + 1) begin
            base = image_word * 4;
            send_word({image_mem[base], image_mem[base+1],
                       image_mem[base+2], image_mem[base+3]});
        end
        @(negedge clk);
        in_valid = 1'b0;
        in_data = 32'b0;

        execute_start_cycle = cycle_count;
        wait (config_done === 1'b1);
        if (`VALID_OP && config_errors == 0) begin
            for (weight_word = 0;
                 weight_word < ((`WEIGHT_COUNT + 3) / 4);
                 weight_word = weight_word + 1) begin
                base = weight_word * 4;
                send_word({
                    weight_mem[base],
                    (base+1 < `WEIGHT_COUNT) ? weight_mem[base+1] : 8'b0,
                    (base+2 < `WEIGHT_COUNT) ? weight_mem[base+2] : 8'b0,
                    (base+3 < `WEIGHT_COUNT) ? weight_mem[base+3] : 8'b0
                });
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_data = 32'b0;
            weights_done = 1'b1;
        end
    end


    initial begin
        config_done = 1'b0;
        config_errors = 0;
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        $display("--------------------------------------------------");
        $display("          STAGE 1:  BARCODE DECODING");
        $display("--------------------------------------------------");
        wait (out_valid1 || out_valid2 || out_valid3 || out_valid4);
        @(negedge clk);

        if (out_valid1 !== 1'b1 || out_valid2 !== 1'b1 ||
            out_valid3 !== 1'b0 || out_valid4 !== 1'b0) begin
            $display("[CONFIG] Expected valid pattern 0011, got %b%b%b%b.",
                     out_valid4, out_valid3, out_valid2, out_valid1);
            config_errors = config_errors + 1;
        end
        if (out_data1 !== `K_SIZE || out_data2 !== `W_PRECISION) begin
            $display("[CONFIG] Expected K=%0d/W%0d, got K=%0d/W%0d.",
                     `K_SIZE, `W_PRECISION, out_data1, out_data2);
            config_errors = config_errors + 1;
        end
        if (out_data3 !== 8'b0 || out_data4 !== 8'b0) begin
            $display("[CONFIG] Unused data ports 3 and 4 must be zero.");
            config_errors = config_errors + 1;
        end
        if (config_errors != 0) begin
            $display("[FAIL] STAGE 1: Barcode configuration check failed.");
            $display("Permission Denied to Enter STAGE 2.");
        end else if (`VALID_OP) begin
            $display("All Configurations Correct! Permission Granted to Enter STAGE 2");
            $display("--------------------------------------------------");
            $display("          STAGE 2:  CONVOLUTION");
            $display("--------------------------------------------------");
        end else begin
            $display("Invalid configuration correctly rejected.");
            $display("STAGE 2 skipped: no weights or convolution expected.");
        end

        config_done = 1'b1;
    end


    initial begin
        protocol_errors = 0;
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        while (!test_done) begin
            @(negedge clk);
            if (in_valid && (out_valid1 || out_valid2 || out_valid3 || out_valid4)) begin
                $display("[PROTOCOL] Input and result valid overlap at time %0t.", $time);
                protocol_errors = protocol_errors + 1;
            end
        end
    end

    task capture_output;
        input valid_value;
        input [11:0] addr_value;
        input [7:0] data_value;
        input integer port_number;
        begin
            if (valid_value) begin
                if ((^addr_value) === 1'bx || (^data_value) === 1'bx) begin
                    $display("[OUTPUT] Port %0d contains X at time %0t.",
                             port_number, $time);
                    protocol_errors = protocol_errors + 1;
                end else begin

                    out_mem[addr_value] = data_value;
                    output_writes = output_writes + 1;
                end
            end
        end
    endtask

    task check_same_cycle_collisions;
        begin
            if (out_valid1 && out_valid2 && out_addr1 === out_addr2)
                protocol_errors = protocol_errors + 1;
            if (out_valid1 && out_valid3 && out_addr1 === out_addr3)
                protocol_errors = protocol_errors + 1;
            if (out_valid1 && out_valid4 && out_addr1 === out_addr4)
                protocol_errors = protocol_errors + 1;
            if (out_valid2 && out_valid3 && out_addr2 === out_addr3)
                protocol_errors = protocol_errors + 1;
            if (out_valid2 && out_valid4 && out_addr2 === out_addr4)
                protocol_errors = protocol_errors + 1;
            if (out_valid3 && out_valid4 && out_addr3 === out_addr4)
                protocol_errors = protocol_errors + 1;
        end
    endtask

    initial begin
        data_errors = 0;
        output_writes = 0;
        execute_start_cycle = 0;
        execute_end_cycle = 0;
        test_done = 1'b0;
        for (index = 0; index < `OUTPUT_SIZE; index = index + 1)
            out_mem[index] = 8'hxx;

        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        wait (config_done === 1'b1);

        if (config_errors != 0) begin

        end else if (!`VALID_OP) begin
            wait (exe_finish === 1'b1);
        end else begin
            wait (weights_done === 1'b1);
            while (exe_finish !== 1'b1) begin
                @(negedge clk);

                check_same_cycle_collisions;
                capture_output(out_valid1, out_addr1, out_data1, 1);
                capture_output(out_valid2, out_addr2, out_data2, 2);
                capture_output(out_valid3, out_addr3, out_data3, 3);
                capture_output(out_valid4, out_addr4, out_data4, 4);
            end
            execute_end_cycle = cycle_count;

            for (index = 0; index < `OUTPUT_SIZE; index = index + 1) begin
                if (out_mem[index] !== golden_mem[index]) begin
                    if (data_errors < 20)
                        $display("[DATA %0d] expected %02h, got %02h",
                                 index, golden_mem[index], out_mem[index]);
                    data_errors = data_errors + 1;
                end
            end
        end

        test_done = 1'b1;
        $display("");
        $display("    *************************************");
        $display("    *    OVERALL COMPARISON RESULTS      *");
        $display("    *************************************");
        $display("--------------------------------------------------");
        $display("Case: K=%0d, W%0d, valid=%0d", `K_SIZE, `W_PRECISION, `VALID_OP);
        if (`VALID_OP && config_errors == 0) begin
            $display("Result writes: %0d", output_writes);
            $display("Execution cycles: %0d", execute_end_cycle - execute_start_cycle);
        end
        if (config_errors == 0 && protocol_errors == 0 && data_errors == 0) begin
            $display("");
            $display("         #    ###############    _   _ ");
            $display("        #     #             #    *   * ");
            $display("   #   #      #   CORRECT   #      |   ");
            $display("    # #       #             #    \\___/ ");
            $display("     #        ###############          ");
            $display("");
            $display("--------------------------------------------------");
            $display("        CONGRATULATION! ALL DATA PASS!            ");
        end else begin
            $display("");
            $display("    #   #     ################# ");
            $display("     # #      #               # ");
            $display("      #       #   INCORRECT   # ");
            $display("     # #      #               # ");
            $display("    #   #     ################# ");
            $display("");
            $display("--------------------------------------------------");
            $display("       Wrong! Total Error: %0d", 
                     config_errors + protocol_errors + data_errors);
        end
        $display("--------------------------------------------------");
        $display("Total SPEC Error: %0d", config_errors + protocol_errors);
        #(`CYCLE * 2);
        $finish;
    end

endmodule
