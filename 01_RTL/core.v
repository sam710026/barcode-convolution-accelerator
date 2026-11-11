// Generated assembly: edit rtl_parts, then tools/assemble_core.py --write.
module core (                       // Don't modify interface
    input               i_clk,
    input               i_rst_n,
    input               i_in_valid,
    input       [31:0]  i_in_data,

    output reg          o_in_ready,

    output reg  [7:0]   o_out_data1,
    output reg  [7:0]   o_out_data2,
    output reg  [7:0]   o_out_data3,
    output reg  [7:0]   o_out_data4,

    output reg  [11:0]  o_out_addr1,
    output reg  [11:0]  o_out_addr2,
    output reg  [11:0]  o_out_addr3,
    output reg  [11:0]  o_out_addr4,

    output reg          o_out_valid1,
    output reg          o_out_valid2,
    output reg          o_out_valid3,
    output reg          o_out_valid4,

    output reg          o_exe_finish
);

    // Asynchronous assertion is retained for every external output.
    // Release the core reset from a rising-edge register, rather than sending
    // an externally timed deassertion directly to the large reset tree.
    // Only these two release flops receive the raw reset input. No reset path
    // is waived: the fresh mapped design still requires recovery/removal checks.
    reg [1:0] reset_release;
    wire core_rst_n = reset_release[1];
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            reset_release <= 2'b00;
        else
            reset_release <= {reset_release[0], 1'b1};
    end

    localparam [3:0] ST_BOOT           = 4'd0,
                     ST_IMAGE_ACCEPT   = 4'd1,
                     ST_IMAGE_WRITE    = 4'd2,
                     ST_IMAGE_DRAIN    = 4'd4,
                     ST_CONFIG         = 4'd5,
                     ST_CONFIG_DRAIN   = 4'd6,
                     ST_WEIGHT_LOAD    = 4'd7,
                     ST_STREAM         = 4'd9,
                     ST_STREAM_FLUSH   = 4'd10,
                     ST_FINISH         = 4'd12;

    reg [3:0] state;
    reg [31:0] image_word;
    reg [1:0] image_lane;
    reg [11:0] image_addr;

    // At x>=45, the previous 45 pixels and current LSB form one full code.
    // Nineteen rotating records retain the consecutive-row streak per origin.
    // Exactly 19 updates per row return origin zero to the queue head.
    reg [44:0] barcode_row_shift;
    reg [2:0] barcode_ids [0:18];
    reg [3:0] barcode_counts [0:18];
    reg barcode_found;
    reg [2:0] kernel_size;
    reg [3:0] weight_precision;
    wire [45:0] barcode_pattern = {barcode_row_shift, image_word[24]};
    reg [2:0] barcode_identity;
    reg [2:0] decoded_kernel;
    reg [3:0] decoded_precision;

    // Same-edge view of the final pixel's barcode update (ST_IMAGE_WRITE, lane 3,
    // x=63 >= 45): identical condition to the registered match below.
    wire final_match = !barcode_found && (barcode_identity != 3'd0) &&
                       (barcode_counts[0] >= 4'd9) && (barcode_ids[0] == barcode_identity);
    wire [2:0] final_kernel = final_match ? decoded_kernel : kernel_size;
    wire [3:0] final_precision = final_match ? decoded_precision : weight_precision;

    reg [5:0] weight_count;
    reg [5:0] weight_total;

    // Traverse each four-column stripe from y=0 through y=63. Decode the
    // arithmetic mode once on accepted barcode, before receiving weights.
    reg compact_k3_w8;
    reg slow_precision_mode;
    reg issue_pause;
    reg window_second_phase;
    reg [10:0] stream_group;
    // Group bits [9:6] select the stripe and [5:0] select its output row.
    // Every request has one capture edge, including the two bottom-zero rows
    // that fetch the following stripe's prefix rather than the current row.
    reg read_valid;
    reg [10:0] read_group;
    wire [11:0] output_base = {read_group[5:0], read_group[9:6], 2'b00};

    // The older four logical rows are already permuted and zero-padded.
    // Physical-bank capture is unconditional and directly follows SRAM Q;
    // permutation/padding is after these registers, outside the SRAM path.
    reg [7:0] retained_rows [0:31];
    wire [7:0] raw_bank [0:7];
    reg [7:0] prefix_rows [0:15];
    // Decode the prefix write enables before their payload-capture edge.
    // Seed bytes and one-hot tags move together inside image loading.
    reg [15:0] prefix_seed_write;
    reg [7:0] prefix_seed_data;
    reg prefix_boot_clear;
    reg prefix_stream_write;
    wire [7:0] newest_pixels [0:7];
    wire [7:0] forwarded_prefix [0:7];
    wire [7:0] next_prefix [0:7];
    wire [7:0] window_pixels [0:39];

    // Each tag is the base address of four consecutive output pixels. Bases
    // are multiples of four, so no vector crosses an image-row boundary.
    reg window_valid;
    reg [11:0] window_addr;
    // Captured with window_addr; move bounds/mode decode before pixel masks.
    // Payload flags become observable only after the first valid read.
    reg [4:0] window_row_valid;
    reg [2:0] normal_row_valid;
    reg [3:1] compact_row_valid;
    reg first_column, last_column;
    // Prefetch supplies one earlier pixel-capture edge, preserving heap timing.
    reg frontend_valid;
    reg frontend_last;
    reg [11:0] frontend_addr;
    reg [7:0] frontend_pixels [0:54];
    wire prime_request = (state == ST_CONFIG_DRAIN) && barcode_found;
    reg [4:0] heap_valid;
    reg [4:0] heap_last;
    reg [11:0] heap_addr [0:4];
    reg merge_valid;
    reg [11:0] merge_addr;
    reg adder_valid;
    reg [11:0] adder_addr;
    wire final_valid = adder_valid;
    wire [11:0] final_addr = adder_addr;
    integer tag_index;
    integer payload_tag_index;
    wire [7:0] result_data [0:3];

    // Bank=x%8 and address={y,x/8}. A stripe read has one byte per bank and
    // only three shared horizontal address blocks, selected by stripe parity.
    reg [7:0] sram_cen_n;
    reg [7:0] sram_wen_n;
    reg [8:0] sram_addr [0:7];
    reg [7:0] sram_data;
    wire [7:0] sram_q [0:7];

    integer barcode_index;
    integer retained_index;
    integer address_bank;
    integer reset_index;

    wire request_bottom = (stream_group[5:0] >= 6'd62);
    wire [3:0] request_stripe = request_bottom ? stream_group[9:6] + 4'd1 :
                                                               stream_group[9:6];
    wire [5:0] request_row = request_bottom ? {5'd0,stream_group[0]} :
                                                        stream_group[5:0] + 6'd2;
    wire [2:0] request_block_mid = request_stripe[3:1];
    wire [2:0] request_block_low = request_block_mid + {2'd0,request_stripe[0]};
    wire [2:0] request_block_high = request_block_mid - {2'd0,!request_stripe[0]};
    wire request_has_data = !request_bottom || (stream_group[9:6] != 4'd15);

    genvar memory_bank;
    genvar stripe_column;
    generate
        for (memory_bank = 0; memory_bank < 8; memory_bank = memory_bank + 1) begin: g_image_bank
            sram_512x8 u_image_sram (
                .Q   (sram_q[memory_bank]),
                .CLK (i_clk),
                .CEN (sram_cen_n[memory_bank]),
                .WEN (sram_wen_n[memory_bank]),
                .A   (sram_addr[memory_bank]),
                .D   (sram_data)
            );
            // SRAM Q -> raw capture is the tightest GLS path (SRAM clk-to-Q ~2.1 ns):
            // fixed fast-setup flops (DFFHQX8 under SYNTHESIS, kept by syn.tcl).
            cap_ff8 u_raw_cap (.clk(i_clk), .d(sram_q[memory_bank]), .q(raw_bank[memory_bank]));
        end
        for (stripe_column = 0; stripe_column < 8; stripe_column = stripe_column + 1) begin: g_stripe_column
            // Both choices are fixed wiring; stripe parity selects one.
            wire [7:0] even_pixel = raw_bank[(stripe_column+6)%8];
            wire [7:0] odd_pixel = raw_bank[(stripe_column+2)%8];
            wire current_column_valid =
                !(((stripe_column < 2) && first_column) ||
                  ((stripe_column >= 6) && last_column));
            wire forwarded_column_valid =
                !(((stripe_column < 2) && (read_group[9:6] == 4'd0)) ||
                  ((stripe_column >= 6) && (read_group[9:6] == 4'd15)));
            // next_prefix is only consumed for a nonfinal stripe's row63.
            wire next_column_valid = !((stripe_column >= 6) &&
                                                       (read_group[9:6] == 4'd14));
            assign newest_pixels[stripe_column] =
                (window_row_valid[4] && current_column_valid) ?
                (window_addr[2] ? odd_pixel : even_pixel) : 8'd0;
            assign forwarded_prefix[stripe_column] = forwarded_column_valid ?
                (read_group[6] ? odd_pixel : even_pixel) : 8'd0;
            assign next_prefix[stripe_column] = next_column_valid ?
                (read_group[6] ? even_pixel : odd_pixel) : 8'd0;
            assign window_pixels[stripe_column] = retained_rows[stripe_column];
            assign window_pixels[8+stripe_column] = retained_rows[8+stripe_column];
            assign window_pixels[16+stripe_column] = retained_rows[16+stripe_column];
            assign window_pixels[24+stripe_column] = retained_rows[24+stripe_column];
            assign window_pixels[32+stripe_column] = newest_pixels[stripe_column];
        end
    endgenerate

    // Address/data select only depends on the FSM. Reset still inhibits
    // every SRAM access through CEN/WEN, without a reset gate on A or D.
    // SRAM samples the current request at the same edge that records its tag.
    always @* begin
        sram_data = 8'd0;
        for (address_bank = 0; address_bank < 8; address_bank = address_bank + 1) begin
            sram_addr[address_bank] = 9'd0;
            if (state == ST_IMAGE_WRITE)
                sram_addr[address_bank] = image_addr[11:3];
            else if (prime_request)
                sram_addr[address_bank] = 9'd16; // row2, block0; banks0..5 only
            else if ((state == ST_STREAM) && !issue_pause) begin
                if (address_bank < 2)
                    sram_addr[address_bank] = {request_row,request_block_low};
                else if (address_bank < 6)
                    sram_addr[address_bank] = {request_row,request_block_mid};
                else
                    sram_addr[address_bank] = {request_row,request_block_high};
            end
        end
        if (state == ST_IMAGE_WRITE)
            sram_data = image_word[31:24];
    end

    always @* begin
        sram_cen_n = 8'hff;
        sram_wen_n = 8'hff;
        if (core_rst_n) begin
            if (state == ST_IMAGE_WRITE) begin
                sram_cen_n[image_addr[2:0]] = 1'b0;
                sram_wen_n[image_addr[2:0]] = 1'b0;
            end else if (prime_request) begin
                sram_cen_n = 8'hc0; // first stripe columns0..5, left pad disabled
            end else if ((state == ST_STREAM) && !issue_pause && request_has_data) begin
                sram_cen_n = 8'h00;
                if (request_stripe == 4'd0)
                    sram_cen_n[7:6] = 2'b11;
                if (request_stripe == 4'd15)
                    sram_cen_n[1:0] = 2'b11;
            end
        end
    end

    // Map each received coefficient once into the fixed 5x5 window. Unused
    // positions retain reset zero; no kernel-dependent mux is needed at MAC.
    function automatic [4:0] weight_grid_index;
        input [5:0] packed_index;
        input [2:0] grid_kernel;
        begin
            case (grid_kernel)
                3'd3: begin
                    case (packed_index)
                        6'd0: weight_grid_index = 5'd6;
                        6'd1: weight_grid_index = 5'd7;
                        6'd2: weight_grid_index = 5'd8;
                        6'd3: weight_grid_index = 5'd11;
                        6'd4: weight_grid_index = 5'd12;
                        6'd5: weight_grid_index = 5'd13;
                        6'd6: weight_grid_index = 5'd16;
                        6'd7: weight_grid_index = 5'd17;
                        6'd8: weight_grid_index = 5'd18;
                        default: weight_grid_index = 5'd0;
                    endcase
                end
                3'd4: begin
                    case (packed_index)
                        6'd0: weight_grid_index = 5'd6;
                        6'd1: weight_grid_index = 5'd7;
                        6'd2: weight_grid_index = 5'd8;
                        6'd3: weight_grid_index = 5'd9;
                        6'd4: weight_grid_index = 5'd11;
                        6'd5: weight_grid_index = 5'd12;
                        6'd6: weight_grid_index = 5'd13;
                        6'd7: weight_grid_index = 5'd14;
                        6'd8: weight_grid_index = 5'd16;
                        6'd9: weight_grid_index = 5'd17;
                        6'd10: weight_grid_index = 5'd18;
                        6'd11: weight_grid_index = 5'd19;
                        6'd12: weight_grid_index = 5'd21;
                        6'd13: weight_grid_index = 5'd22;
                        6'd14: weight_grid_index = 5'd23;
                        6'd15: weight_grid_index = 5'd24;
                        default: weight_grid_index = 5'd0;
                    endcase
                end
                default: weight_grid_index = packed_index[4:0];
            endcase
        end
    endfunction

    // These are the six legal protocol structures, not image-specific answers.
    // A nonzero identity uniquely determines every one of the 46 modules.
    always @* begin
        barcode_identity = 3'd0;
        case (barcode_pattern)
            {11'b11010011100, 11'b10010011000, 11'b10010001100,
             13'b1100011101011}: barcode_identity = 3'd1;
            {11'b11010011100, 11'b10010011000, 11'b10001100100,
             13'b1100011101011}: barcode_identity = 3'd2;
            {11'b11010011100, 11'b10010001100, 11'b10010001100,
             13'b1100011101011}: barcode_identity = 3'd3;
            {11'b11010011100, 11'b10010001100, 11'b10001100100,
             13'b1100011101011}: barcode_identity = 3'd4;
            {11'b11010011100, 11'b10001001100, 11'b10010001100,
             13'b1100011101011}: barcode_identity = 3'd5;
            {11'b11010011100, 11'b10001001100, 11'b10001100100,
             13'b1100011101011}: barcode_identity = 3'd6;
            default: barcode_identity = 3'd0;
        endcase

        decoded_kernel = 3'd0;
        case (barcode_identity)
            3'd1, 3'd2: decoded_kernel = 3'd3;
            3'd3, 3'd4: decoded_kernel = 3'd4;
            3'd5, 3'd6: decoded_kernel = 3'd5;
            default: decoded_kernel = 3'd0;
        endcase

        decoded_precision = 4'd0;
        case (barcode_identity)
            3'd1, 3'd3, 3'd5: decoded_precision = 4'd4;
            3'd2, 3'd4, 3'd6: decoded_precision = 4'd8;
            default: decoded_precision = 4'd0;
        endcase
    end

    always @* begin
        case (kernel_size)
            3'd3: weight_total = 6'd9;
            3'd4: weight_total = 6'd16;
            3'd5: weight_total = 6'd25;
            default: weight_total = 6'd0;
        endcase
    end

    // Slot 0..8 are the center 3x3. Other slots cover the outer ring.
    function automatic integer slot_grid;
        input integer slot;
        begin
            case (slot)
                0: slot_grid = 6;
                1: slot_grid = 7;
                2: slot_grid = 8;
                3: slot_grid = 11;
                4: slot_grid = 12;
                5: slot_grid = 13;
                6: slot_grid = 16;
                7: slot_grid = 17;
                8: slot_grid = 18;
                9: slot_grid = 0;
                10: slot_grid = 1;
                11: slot_grid = 2;
                12: slot_grid = 3;
                13: slot_grid = 4;
                14: slot_grid = 5;
                15: slot_grid = 9;
                16: slot_grid = 10;
                17: slot_grid = 14;
                18: slot_grid = 15;
                19: slot_grid = 19;
                20: slot_grid = 20;
                21: slot_grid = 21;
                22: slot_grid = 22;
                23: slot_grid = 23;
                24: slot_grid = 24;
                default: slot_grid = 0;
            endcase
        end
    endfunction

    // Load-time one-hot magnitude: bit0=enable_x, bit1=enable_2x,
    // bit2=negative. Pixel paths need parallel AND/OR, not nested muxes.
    function automatic [2:0] digit_code;
        input signed [3:0] digit;
        begin
            case (digit)
                -4'sd2: digit_code = 3'b110;
                -4'sd1: digit_code = 3'b101;
                 4'sd1: digit_code = 3'b001;
                 4'sd2: digit_code = 3'b010;
                default: digit_code = 3'b000;
            endcase
        end
    endfunction
    function automatic [5:0] component_code;
        input signed [4:0] value;
        reg signed [5:0] extended_value;
        reg signed [3:0] upper_digit;
        reg signed [3:0] lower_digit;
        begin
            extended_value = {value[4], value};
            upper_digit = (extended_value + 6'sd2) >>> 2;
            case (value[1:0])
                2'd0: lower_digit = 4'sd0;
                2'd1: lower_digit = 4'sd1;
                2'd2: lower_digit = -4'sd2;
                default: lower_digit = -4'sd1;
            endcase
            component_code = {digit_code(upper_digit), digit_code(lower_digit)};
        end
    endfunction
    function automatic [11:0] weight_code;
        input [7:0] raw_weight;
        reg signed [4:0] high_component;
        reg signed [4:0] low_component;
        begin
            // floor((w+8)/16) = signed high nibble + low nibble sign.
            high_component = $signed({raw_weight[7],raw_weight[7:4]}) +
                             $signed({4'b0000,raw_weight[3]});
            low_component = $signed({raw_weight[3],raw_weight[3:0]});
            weight_code = {component_code(high_component), component_code(low_component)};
        end
    endfunction

    // Input capture precedes recoding: no long decode on the half-cycle port path.
    reg weight_pending;
    reg [31:0] pending_weight_word;
    reg [5:0] pending_weight_index;
    wire accept_weight = (state == ST_WEIGHT_LOAD) && i_in_valid && o_in_ready;
    wire final_weight_accept = accept_weight && ((weight_count + 6'd4) >= weight_total);
    // Final codes commit at L1; only then arm the already primed window.
    wire launch_first_window = (state == ST_STREAM) && weight_pending &&
                              ((pending_weight_index + 6'd4) >= weight_total);
    always @(posedge i_clk or negedge core_rst_n) begin
        if (!core_rst_n)
            weight_pending <= 1'b0;
        else
            weight_pending <= accept_weight;
    end
    always @(posedge i_clk) begin
        if (accept_weight) begin
            pending_weight_word <= i_in_data;
            pending_weight_index <= weight_count;
        end
    end

    wire [11:0] decoded_weight [0:3];
    wire [149:0] first_codes;
    wire [149:0] second_codes;
    // First bank is always the current phase. Swap the existing banks AFTER
    // each consumed slow-mode phase, removing the global phase mux before MAC.
    // The last high phase in STREAM_FLUSH must also rotate back to low.
    wire rotate_phase_banks = slow_precision_mode && frontend_valid;
    wire [149:0] active_codes = first_codes;
    genvar weight_lane;
    genvar coefficient_slot;
    generate
        for (weight_lane = 0; weight_lane < 4; weight_lane = weight_lane + 1) begin: g_weight_decode
            assign decoded_weight[weight_lane] = weight_code(pending_weight_word[31-8*weight_lane -: 8]);
        end
        for (coefficient_slot = 0; coefficient_slot < 25; coefficient_slot = coefficient_slot + 1) begin: g_slot_weight
            reg [5:0] first_code;
            reg [5:0] second_code;
            integer load_lane;
            wire [4:0] source_grid = (compact_k3_w8 && (coefficient_slot >= 9) &&
                                      (coefficient_slot < 18)) ?
                                      slot_grid(coefficient_slot-9) : slot_grid(coefficient_slot);
            wire first_is_high = !slow_precision_mode &&
                                 !(compact_k3_w8 && (coefficient_slot >= 9));
            assign first_codes[6*coefficient_slot +: 6] = first_code;
            assign second_codes[6*coefficient_slot +: 6] = second_code;
            always @(posedge i_clk) begin
                // All payload is overwritten before use, including after replay reset.
                if (state == ST_CONFIG_DRAIN) begin
                    first_code <= 6'd0;
                    second_code <= 6'd0;
                end else if (weight_pending && (!compact_k3_w8 || (coefficient_slot < 18))) begin
                    for (load_lane = 0; load_lane < 4; load_lane = load_lane + 1) begin
                        if (((pending_weight_index + load_lane) < weight_total) &&
                            (weight_grid_index(pending_weight_index + load_lane, kernel_size) == source_grid)) begin
                            first_code <= first_is_high ? decoded_weight[load_lane][11:6] :
                                                         decoded_weight[load_lane][5:0];
                            second_code <= decoded_weight[load_lane][11:6];
                        end
                    end
                end else if (rotate_phase_banks) begin
                    first_code <= second_code;
                    second_code <= first_code;
                end
            end
        end
    endgenerate

    // Unsigned heap payloads need one full-weight correction per image:
    // C = -511 * sum(16*n(high) + n(low)) modulo 2^21.
    // Codes settle one edge after final acceptance. Groups/pairs/count then
    // settle on edges L2/L3/L4, and the completion tag freezes C on L5.
    // Later code-bank rotation must never change this transaction's C.
    wire [6:0] sign_weight [0:24];
    reg [8:0] sign_group [0:4];
    reg [9:0] sign_pair0, sign_pair1;
    reg [8:0] sign_tail;
    reg [11:0] sign_count;
    reg [20:0] full_correction;
    reg [4:0] correction_tag;
    reg correction_valid;
    always @(posedge i_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            correction_tag <= 5'd0;
            correction_valid <= 1'b0;
        end else begin
            correction_tag <= {correction_tag[3:0], final_weight_accept};
            if (final_weight_accept)
                correction_valid <= 1'b0;
            else if (correction_tag[4])
                correction_valid <= 1'b1;
        end
    end
    genvar sign_slot;
    genvar sign_group_index;
    generate
        for (sign_slot = 0; sign_slot < 25; sign_slot = sign_slot + 1) begin: g_sign_weight
            wire [2:0] first_count = {first_codes[6*sign_slot+5],1'b0,first_codes[6*sign_slot+2]};
            wire [2:0] second_count = {second_codes[6*sign_slot+5],1'b0,second_codes[6*sign_slot+2]};
            // Each count is at most five. The low three bits and high count
            // shifted by four are disjoint, so concatenation is exact.
            assign sign_weight[sign_slot] = slow_precision_mode ?
                {second_count,1'b0,first_count} :
                (compact_k3_w8 && (sign_slot >= 18)) ? 7'd0 :
                (compact_k3_w8 && (sign_slot >= 9)) ? {4'b0000,first_count} :
                {first_count,4'b0000};
        end
        for (sign_group_index = 0; sign_group_index < 5;
             sign_group_index = sign_group_index + 1) begin: g_sign_group
            always @(posedge i_clk) begin
                sign_group[sign_group_index] <=
                    ({2'b00,sign_weight[5*sign_group_index]} + {2'b00,sign_weight[5*sign_group_index+1]}) +
                    ({2'b00,sign_weight[5*sign_group_index+2]} + {2'b00,sign_weight[5*sign_group_index+3]}) +
                    {2'b00,sign_weight[5*sign_group_index+4]};
            end
        end
    endgenerate
    always @(posedge i_clk) begin
        sign_pair0 <= {1'b0,sign_group[0]} + {1'b0,sign_group[1]};
        sign_pair1 <= {1'b0,sign_group[2]} + {1'b0,sign_group[3]};
        sign_tail <= sign_group[4];
        sign_count <= {2'b00,sign_pair0} + {2'b00,sign_pair1} + {3'b000,sign_tail};
        // N can be 2125. Both operands are explicitly 21 bits; C is modulo,
        // not a saturating signed value (its mathematical minimum is -1085875).
        if (correction_tag[4])
            full_correction <= {9'd0,sign_count} - {sign_count,9'd0};
    end

    // Decode bounds alongside window_addr, before the arithmetic input edge.
    // Internal payload is overwritten before any valid heap token after reset.
    // Remappable slots use normal rows 0..2 or compact rows 1..3. Qualify
    // these six flags here so mode distribution ends before the pixel masks.
    always @(posedge i_clk) begin
        if (read_valid) begin
            window_row_valid <= {(output_base[11:6] <= 6'd61),
                                 (output_base[11:6] <= 6'd62), 1'b1,
                                 (output_base[11:6] >= 6'd1),
                                 (output_base[11:6] >= 6'd2)};
            normal_row_valid <= {!compact_k3_w8,
                                 !compact_k3_w8 && (output_base[11:6] >= 6'd1),
                                 !compact_k3_w8 && (output_base[11:6] >= 6'd2)};
            compact_row_valid <= {compact_k3_w8 && (output_base[11:6] <= 6'd62),
                                  compact_k3_w8,
                                  compact_k3_w8 && (output_base[11:6] >= 6'd1)};
            first_column <= (output_base[5:2] == 4'd0);
            last_column <= (output_base[5:2] == 4'd15);
        end
    end
    // Shared physical expressions: 28 fixed bytes and 27 mode-selected bytes.
    // All payload captures are unconditional; reset clears their valid tag.
    always @(posedge i_clk) begin
        frontend_pixels[0] <= window_pixels[9];
        frontend_pixels[1] <= window_pixels[10];
        frontend_pixels[2] <= window_pixels[11];
        frontend_pixels[3] <= window_pixels[17];
        frontend_pixels[4] <= window_pixels[18];
        frontend_pixels[5] <= window_pixels[19];
        frontend_pixels[6] <= window_pixels[25];
        frontend_pixels[7] <= window_pixels[26];
        frontend_pixels[8] <= window_pixels[27];
        frontend_pixels[9] <= (window_pixels[0] & {8{normal_row_valid[0]}}) | (window_pixels[9] & {8{compact_row_valid[1]}});
        frontend_pixels[10] <= (window_pixels[1] & {8{normal_row_valid[0]}}) | (window_pixels[10] & {8{compact_row_valid[1]}});
        frontend_pixels[11] <= (window_pixels[2] & {8{normal_row_valid[0]}}) | (window_pixels[11] & {8{compact_row_valid[1]}});
        frontend_pixels[12] <= (window_pixels[3] & {8{normal_row_valid[0]}}) | (window_pixels[17] & {8{compact_row_valid[2]}});
        frontend_pixels[13] <= (window_pixels[4] & {8{normal_row_valid[0]}}) | (window_pixels[18] & {8{compact_row_valid[2]}});
        frontend_pixels[14] <= (window_pixels[8] & {8{normal_row_valid[1]}}) | (window_pixels[19] & {8{compact_row_valid[2]}});
        frontend_pixels[15] <= (window_pixels[12] & {8{normal_row_valid[1]}}) | (window_pixels[25] & {8{compact_row_valid[3]}});
        frontend_pixels[16] <= (window_pixels[16] & {8{normal_row_valid[2]}}) | (window_pixels[26] & {8{compact_row_valid[3]}});
        frontend_pixels[17] <= (window_pixels[20] & {8{normal_row_valid[2]}}) | (window_pixels[27] & {8{compact_row_valid[3]}});
        frontend_pixels[18] <= window_pixels[24];
        frontend_pixels[19] <= window_pixels[28];
        frontend_pixels[20] <= window_pixels[32];
        frontend_pixels[21] <= window_pixels[33];
        frontend_pixels[22] <= window_pixels[34];
        frontend_pixels[23] <= window_pixels[35];
        frontend_pixels[24] <= window_pixels[36];
        frontend_pixels[25] <= window_pixels[12];
        frontend_pixels[26] <= window_pixels[20];
        frontend_pixels[27] <= (window_pixels[3] & {8{normal_row_valid[0]}}) | (window_pixels[12] & {8{compact_row_valid[1]}});
        frontend_pixels[28] <= (window_pixels[5] & {8{normal_row_valid[0]}}) | (window_pixels[19] & {8{compact_row_valid[2]}});
        frontend_pixels[29] <= (window_pixels[9] & {8{normal_row_valid[1]}}) | (window_pixels[20] & {8{compact_row_valid[2]}});
        frontend_pixels[30] <= (window_pixels[13] & {8{normal_row_valid[1]}}) | (window_pixels[26] & {8{compact_row_valid[3]}});
        frontend_pixels[31] <= (window_pixels[17] & {8{normal_row_valid[2]}}) | (window_pixels[27] & {8{compact_row_valid[3]}});
        frontend_pixels[32] <= (window_pixels[21] & {8{normal_row_valid[2]}}) | (window_pixels[28] & {8{compact_row_valid[3]}});
        frontend_pixels[33] <= window_pixels[29];
        frontend_pixels[34] <= window_pixels[37];
        frontend_pixels[35] <= window_pixels[13];
        frontend_pixels[36] <= window_pixels[21];
        frontend_pixels[37] <= (window_pixels[4] & {8{normal_row_valid[0]}}) | (window_pixels[13] & {8{compact_row_valid[1]}});
        frontend_pixels[38] <= (window_pixels[6] & {8{normal_row_valid[0]}}) | (window_pixels[20] & {8{compact_row_valid[2]}});
        frontend_pixels[39] <= (window_pixels[10] & {8{normal_row_valid[1]}}) | (window_pixels[21] & {8{compact_row_valid[2]}});
        frontend_pixels[40] <= (window_pixels[14] & {8{normal_row_valid[1]}}) | (window_pixels[27] & {8{compact_row_valid[3]}});
        frontend_pixels[41] <= (window_pixels[18] & {8{normal_row_valid[2]}}) | (window_pixels[28] & {8{compact_row_valid[3]}});
        frontend_pixels[42] <= (window_pixels[22] & {8{normal_row_valid[2]}}) | (window_pixels[29] & {8{compact_row_valid[3]}});
        frontend_pixels[43] <= window_pixels[30];
        frontend_pixels[44] <= window_pixels[38];
        frontend_pixels[45] <= window_pixels[14];
        frontend_pixels[46] <= window_pixels[22];
        frontend_pixels[47] <= (window_pixels[5] & {8{normal_row_valid[0]}}) | (window_pixels[14] & {8{compact_row_valid[1]}});
        frontend_pixels[48] <= (window_pixels[7] & {8{normal_row_valid[0]}}) | (window_pixels[21] & {8{compact_row_valid[2]}});
        frontend_pixels[49] <= (window_pixels[11] & {8{normal_row_valid[1]}}) | (window_pixels[22] & {8{compact_row_valid[2]}});
        frontend_pixels[50] <= (window_pixels[15] & {8{normal_row_valid[1]}}) | (window_pixels[28] & {8{compact_row_valid[3]}});
        frontend_pixels[51] <= (window_pixels[19] & {8{normal_row_valid[2]}}) | (window_pixels[29] & {8{compact_row_valid[3]}});
        frontend_pixels[52] <= (window_pixels[23] & {8{normal_row_valid[2]}}) | (window_pixels[30] & {8{compact_row_valid[3]}});
        frontend_pixels[53] <= window_pixels[31];
        frontend_pixels[54] <= window_pixels[39];
    end

    // Used only with generate constants; this is fixed wiring.
    function automatic integer frontend_index;
        input integer lane;
        input integer slot;
        begin
            case (25*lane + slot)
                0: frontend_index = 0;
                1: frontend_index = 1;
                2: frontend_index = 2;
                3: frontend_index = 3;
                4: frontend_index = 4;
                5: frontend_index = 5;
                6: frontend_index = 6;
                7: frontend_index = 7;
                8: frontend_index = 8;
                9: frontend_index = 9;
                10: frontend_index = 10;
                11: frontend_index = 11;
                12: frontend_index = 12;
                13: frontend_index = 13;
                14: frontend_index = 14;
                15: frontend_index = 15;
                16: frontend_index = 16;
                17: frontend_index = 17;
                18: frontend_index = 18;
                19: frontend_index = 19;
                20: frontend_index = 20;
                21: frontend_index = 21;
                22: frontend_index = 22;
                23: frontend_index = 23;
                24: frontend_index = 24;
                25: frontend_index = 1;
                26: frontend_index = 2;
                27: frontend_index = 25;
                28: frontend_index = 4;
                29: frontend_index = 5;
                30: frontend_index = 26;
                31: frontend_index = 7;
                32: frontend_index = 8;
                33: frontend_index = 19;
                34: frontend_index = 10;
                35: frontend_index = 11;
                36: frontend_index = 27;
                37: frontend_index = 13;
                38: frontend_index = 28;
                39: frontend_index = 29;
                40: frontend_index = 30;
                41: frontend_index = 31;
                42: frontend_index = 32;
                43: frontend_index = 6;
                44: frontend_index = 33;
                45: frontend_index = 21;
                46: frontend_index = 22;
                47: frontend_index = 23;
                48: frontend_index = 24;
                49: frontend_index = 34;
                50: frontend_index = 2;
                51: frontend_index = 25;
                52: frontend_index = 35;
                53: frontend_index = 5;
                54: frontend_index = 26;
                55: frontend_index = 36;
                56: frontend_index = 8;
                57: frontend_index = 19;
                58: frontend_index = 33;
                59: frontend_index = 11;
                60: frontend_index = 27;
                61: frontend_index = 37;
                62: frontend_index = 28;
                63: frontend_index = 38;
                64: frontend_index = 39;
                65: frontend_index = 40;
                66: frontend_index = 41;
                67: frontend_index = 42;
                68: frontend_index = 7;
                69: frontend_index = 43;
                70: frontend_index = 22;
                71: frontend_index = 23;
                72: frontend_index = 24;
                73: frontend_index = 34;
                74: frontend_index = 44;
                75: frontend_index = 25;
                76: frontend_index = 35;
                77: frontend_index = 45;
                78: frontend_index = 26;
                79: frontend_index = 36;
                80: frontend_index = 46;
                81: frontend_index = 19;
                82: frontend_index = 33;
                83: frontend_index = 43;
                84: frontend_index = 27;
                85: frontend_index = 37;
                86: frontend_index = 47;
                87: frontend_index = 38;
                88: frontend_index = 48;
                89: frontend_index = 49;
                90: frontend_index = 50;
                91: frontend_index = 51;
                92: frontend_index = 52;
                93: frontend_index = 8;
                94: frontend_index = 53;
                95: frontend_index = 23;
                96: frontend_index = 24;
                97: frontend_index = 34;
                98: frontend_index = 44;
                99: frontend_index = 54;
                default: frontend_index = 0;
            endcase
        end
    endfunction

    genvar output_lane;
    genvar tap_slot;
    generate
        for (output_lane = 0; output_lane < 4; output_lane = output_lane + 1) begin: g_output_lane
            wire [199:0] masked_pixels;
            wire [199:0] heap_pixels;
            for (tap_slot = 0; tap_slot < 25; tap_slot = tap_slot + 1) begin: g_tap
                assign heap_pixels[8*tap_slot +: 8] = frontend_pixels[frontend_index(output_lane, tap_slot)];
                if ((tap_slot >= 9) && (tap_slot < 18)) begin: g_remappable
                    assign masked_pixels[8*tap_slot +: 8] =
                        (window_pixels[8*(slot_grid(tap_slot)/5)+(slot_grid(tap_slot)%5)+output_lane] &
                         {8{normal_row_valid[slot_grid(tap_slot)/5]}}) |
                        (window_pixels[8*(slot_grid(tap_slot-9)/5)+(slot_grid(tap_slot-9)%5)+output_lane] &
                         {8{compact_row_valid[slot_grid(tap_slot-9)/5]}});
                end else begin: g_fixed
                    assign masked_pixels[8*tap_slot +: 8] =
                        window_pixels[8*(slot_grid(tap_slot)/5)+(slot_grid(tap_slot)%5)+output_lane];
                end
            end

            wire [20:0] heap_sum, heap_carry;
            hw3_fused_heap u_heap (.i_clk(i_clk), .pixels(heap_pixels),
                .codes(active_codes), .compact_high_shift(compact_k3_w8),
                .sum(heap_sum), .carry(heap_carry));
            reg [20:0] merged_sum, merged_carry;
            wire slow_high = slow_precision_mode && heap_last[4];
            wire shift4 = (!slow_precision_mode && !compact_k3_w8) || slow_high;
            wire [20:0] merge_a = shift4 ? {heap_sum[16:0],4'b0000} : heap_sum;
            wire [20:0] merge_b = shift4 ? {heap_carry[16:0],4'b0000} : heap_carry;
            // Low tokens seed the feedback pair with R(low)+C; the following
            // high token adds 16*R(high). CPA reads the old completed pair on
            // the same edge that the next low token reuses these registers.
            wire [20:0] merge_c = slow_high ? merged_sum : full_correction;
            wire [20:0] merge_d = slow_high ? merged_carry : 21'd0;
            wire [20:0] sum0 = merge_a ^ merge_b ^ merge_c;
            wire [20:0] carry0 = ((merge_a & merge_b) | (merge_a & merge_c) | (merge_b & merge_c)) << 1;
            reg [10:0] adder_low;
            reg adder_carry;
            reg [9:0] adder_high_a, adder_high_b;
            wire [11:0] low_add = {1'b0,merged_sum[10:0]} + {1'b0,merged_carry[10:0]};
            wire [9:0] high_add = adder_high_a + adder_high_b + {9'd0,adder_carry};
            wire [20:0] final_sum = {high_add,adder_low};
            wire [8:0] rounded_byte = {1'b0,final_sum[14:7]} + {8'd0,final_sum[6]};
            always @(posedge i_clk) begin
                merged_sum <= sum0 ^ carry0 ^ merge_d;
                merged_carry <= ((sum0 & carry0) | (sum0 & merge_d) | (carry0 & merge_d)) << 1;
                adder_low <= low_add[10:0];
                adder_carry <= low_add[11];
                adder_high_a <= merged_sum[20:11];
                adder_high_b <= merged_carry[20:11];
            end
            // Negative results clamp to zero; only positive half-up rounding matters.
            assign result_data[output_lane] = final_sum[20] ? 8'd0 :
                ((|final_sum[19:15]) || rounded_byte[8]) ? 8'd255 : rounded_byte[7:0];
        end
    endgenerate

    // Image seeds commit one edge later, well before the initial prime read.
    // Stream control is decoded on the issue edge, so its registered value is
    // aligned with the OLD raw prefix0 and read_group at the row63 capture.
    always @(posedge i_clk)
        prefix_seed_data <= image_word[31:24];

    always @(posedge i_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            prefix_boot_clear <= 1'b0;
            prefix_stream_write <= 1'b0;
        end else begin
            prefix_boot_clear <= (state == ST_BOOT);
            prefix_stream_write <= (state == ST_STREAM) && !issue_pause &&
                                   (stream_group[5:0] == 6'd63) &&
                                   (stream_group[9:6] != 4'd15);
        end
    end

    genvar prefix_index;
    generate
        for (prefix_index = 0; prefix_index < 16; prefix_index = prefix_index + 1) begin: g_prefix_control
            if ((prefix_index % 8) >= 2) begin: g_seed
                wire [5:0] seed_row = prefix_index / 8;
                wire [5:0] seed_column = (prefix_index % 8) - 2;
                always @(posedge i_clk or negedge core_rst_n) begin
                    if (!core_rst_n)
                        prefix_seed_write[prefix_index] <= 1'b0;
                    else
                        prefix_seed_write[prefix_index] <=
                            (state == ST_IMAGE_WRITE) &&
                            (image_addr[11:6] == seed_row) &&
                            (image_addr[5:0] == seed_column);
                end
            end else begin: g_no_seed
                always @(posedge i_clk or negedge core_rst_n) begin
                    if (!core_rst_n)
                        prefix_seed_write[prefix_index] <= 1'b0;
                    else
                        prefix_seed_write[prefix_index] <= 1'b0;
                end
            end

            // State-separated seed/stream/clear controls are mutually exclusive.
            // Parallel masks retain zero clear data without a priority mux.
            if (prefix_index < 8) begin: g_first_row
                if (prefix_index < 2) begin: g_left_pad
                    always @(posedge i_clk) begin
                        if (prefix_seed_write[prefix_index] | prefix_stream_write | prefix_boot_clear)
                            prefix_rows[prefix_index] <=
                                (prefix_seed_data & {8{prefix_seed_write[prefix_index]}}) |
                                (next_prefix[prefix_index] & {8{prefix_stream_write}});
                    end
                end else begin: g_pixels
                    always @(posedge i_clk) begin
                        if (prefix_seed_write[prefix_index] | prefix_stream_write)
                            prefix_rows[prefix_index] <=
                                (prefix_seed_data & {8{prefix_seed_write[prefix_index]}}) |
                                (next_prefix[prefix_index] & {8{prefix_stream_write}});
                    end
                end
            end else if (prefix_index < 10) begin: g_second_left_pad
                always @(posedge i_clk) begin
                    if (prefix_boot_clear)
                        prefix_rows[prefix_index] <= 8'd0;
                end
            end else begin: g_second_pixels
                always @(posedge i_clk) begin
                    if (prefix_seed_write[prefix_index])
                        prefix_rows[prefix_index] <= prefix_seed_data;
                end
            end
        end
    endgenerate

    // Barcode shifting and retained-row advancement keep their original edges.
    always @(posedge i_clk) begin
        if (state == ST_IMAGE_WRITE)
            barcode_row_shift <= {barcode_row_shift[43:0],image_word[24]};
        if (read_valid) begin
            for (retained_index = 0; retained_index < 8; retained_index = retained_index + 1) begin
                if (read_group[5:0] == 6'd0) begin
                    retained_rows[retained_index] <= 8'd0;
                    retained_rows[8+retained_index] <= 8'd0;
                    retained_rows[16+retained_index] <= prefix_rows[retained_index];
                    // At a stripe boundary OLD raw already contains prefix1;
                    // the simultaneous new raw capture supplies row2. Do not
                    // read a prefix1 FF updated by this same nonblocking edge.
                    retained_rows[24+retained_index] <= (read_group[9:6] == 4'd0) ?
                        prefix_rows[8+retained_index] : forwarded_prefix[retained_index];
                end else begin
                    retained_rows[retained_index] <= retained_rows[8+retained_index];
                    retained_rows[8+retained_index] <= retained_rows[16+retained_index];
                    retained_rows[16+retained_index] <= retained_rows[24+retained_index];
                    retained_rows[24+retained_index] <= newest_pixels[retained_index];
                end
            end
        end
    end

    // Input payload is initialized by its accepting phase. BOOT establishes
    // address zero on the same edge that first raises ready after any reset.
    always @(posedge i_clk) begin
        if (state == ST_BOOT)
            image_addr <= 12'd0;
        else if ((state == ST_IMAGE_WRITE) && (image_addr != 12'd4095))
            image_addr <= image_addr + 12'd1;

        if ((state == ST_IMAGE_ACCEPT) && i_in_valid && o_in_ready) begin
            image_word <= i_in_data;
            image_lane <= 2'd0;
        end else if (state == ST_IMAGE_WRITE) begin
            image_word <= {image_word[23:0], 8'd0};
            if (image_lane != 2'd3)
                image_lane <= image_lane + 2'd1;
        end

        if ((state == ST_CONFIG_DRAIN) && barcode_found)
            weight_count <= 6'd0;
        else if (accept_weight && ((weight_count + 6'd4) < weight_total))
            weight_count <= weight_count + 6'd4;
    end

    // Reset clears the corresponding valid pipeline. Each payload tag is
    // overwritten along that same pipeline before a valid consumer can use it.
    always @(posedge i_clk) begin
        if (prime_request)
            read_group <= 11'd0;
        else if ((state == ST_STREAM) && !issue_pause)
            read_group <= stream_group;
        if (read_valid)
            window_addr <= output_base;
        frontend_last <= !slow_precision_mode || window_second_phase;
        frontend_addr <= window_addr;
        heap_last[0] <= frontend_last;
        heap_addr[0] <= frontend_addr;
        for (payload_tag_index = 1; payload_tag_index < 5;
             payload_tag_index = payload_tag_index + 1) begin
            heap_last[payload_tag_index] <= heap_last[payload_tag_index-1];
            heap_addr[payload_tag_index] <= heap_addr[payload_tag_index-1];
        end
        merge_addr <= heap_addr[4];
        adder_addr <= merge_addr;
    end

    always @(posedge i_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            state <= ST_BOOT;
            o_in_ready <= 1'b0;
            o_out_data1 <= 8'd0;
            o_out_data2 <= 8'd0;
            o_out_data3 <= 8'd0;
            o_out_data4 <= 8'd0;
            o_out_addr1 <= 12'd0;
            o_out_addr2 <= 12'd0;
            o_out_addr3 <= 12'd0;
            o_out_addr4 <= 12'd0;
            o_out_valid1 <= 1'b0;
            o_out_valid2 <= 1'b0;
            o_out_valid3 <= 1'b0;
            o_out_valid4 <= 1'b0;
            o_exe_finish <= 1'b0;

            barcode_found <= 1'b0;
            kernel_size <= 3'd0;
            weight_precision <= 4'd0;
            compact_k3_w8 <= 1'b0;
            slow_precision_mode <= 1'b0;
            stream_group <= 11'd0;
            issue_pause <= 1'b0;
            window_second_phase <= 1'b0;
            read_valid <= 1'b0;
            window_valid <= 1'b0;
            frontend_valid <= 1'b0;
            heap_valid <= 5'd0;
            merge_valid <= 1'b0;
            adder_valid <= 1'b0;

            for (reset_index = 0; reset_index < 19; reset_index = reset_index + 1) begin
                barcode_counts[reset_index] <= 4'd0;
                barcode_ids[reset_index] <= 3'd0;
            end
        end else begin
            o_out_valid1 <= 1'b0;
            o_out_valid2 <= 1'b0;
            o_out_valid3 <= 1'b0;
            o_out_valid4 <= 1'b0;
            read_valid <= 1'b0;
            window_valid <= 1'b0;

            // The prime response initializes payload during weights, without
            // issuing arithmetic. L1 launches group0; later reads launch normally.
            if ((read_valid && (state != ST_WEIGHT_LOAD)) || launch_first_window)
                window_valid <= 1'b1;

            window_second_phase <= slow_precision_mode && window_valid;
            frontend_valid <= window_valid || window_second_phase;
            heap_valid[0] <= frontend_valid;
            for (tag_index = 1; tag_index < 5; tag_index = tag_index + 1) begin
                heap_valid[tag_index] <= heap_valid[tag_index-1];
            end
            merge_valid <= heap_valid[4] && heap_last[4];
            adder_valid <= merge_valid;

            if (final_valid) begin
                o_out_data1 <= result_data[0];
                o_out_data2 <= result_data[1];
                o_out_data3 <= result_data[2];
                o_out_data4 <= result_data[3];
                o_out_addr1 <= final_addr;
                o_out_addr2 <= final_addr + 12'd1;
                o_out_addr3 <= final_addr + 12'd2;
                o_out_addr4 <= final_addr + 12'd3;
                o_out_valid1 <= 1'b1;
                o_out_valid2 <= 1'b1;
                o_out_valid3 <= 1'b1;
                o_out_valid4 <= 1'b1;
            end

            case (state)
                ST_BOOT: begin
                    o_in_ready <= 1'b1;
                    state <= ST_IMAGE_ACCEPT;
                end

                ST_IMAGE_ACCEPT: begin
                    if (i_in_valid && o_in_ready) begin
                        o_in_ready <= 1'b0;
                        state <= ST_IMAGE_WRITE;
                    end
                end

                ST_IMAGE_WRITE: begin
                    // The SRAM commits this same byte/address at this edge.
                    if (image_addr[5:0] >= 6'd45) begin
                        for (barcode_index = 0; barcode_index < 18;
                             barcode_index = barcode_index + 1) begin
                            barcode_counts[barcode_index] <= barcode_counts[barcode_index+1];
                            barcode_ids[barcode_index] <= barcode_ids[barcode_index+1];
                        end
                        barcode_ids[18] <= barcode_identity;

                        if (barcode_identity == 3'd0) begin
                            barcode_counts[18] <= 4'd0;
                        end else if ((barcode_counts[0] != 4'd0) &&
                                     (barcode_ids[0] == barcode_identity)) begin
                            if (barcode_counts[0] < 4'd10)
                                barcode_counts[18] <= barcode_counts[0] + 4'd1;
                            else
                                barcode_counts[18] <= 4'd10;
                        end else begin
                            barcode_counts[18] <= 4'd1;
                        end

                        // A match is the tenth identical legal row at this
                        // origin. Serialization visits origins in row-major order.
                        if (!barcode_found && (barcode_identity != 3'd0) &&
                            (barcode_counts[0] >= 4'd9) &&
                            (barcode_ids[0] == barcode_identity)) begin
                            barcode_found <= 1'b1;
                            kernel_size <= decoded_kernel;
                            weight_precision <= decoded_precision;
                            compact_k3_w8 <= (decoded_kernel == 3'd3) && (decoded_precision == 4'd8);
                            slow_precision_mode <= (decoded_kernel != 3'd3) && (decoded_precision == 4'd8);
                        end
                    end

                    if (image_lane == 2'd3) begin
                        if (image_addr == 12'd4095) begin
                            // Config-early: the final pixel's barcode match is folded in
                            // combinationally, so the one-cycle config response leaves at
                            // this same edge (former ST_CONFIG work). If the source has
                            // not yet retired (i_in_valid), fall back to ST_CONFIG.
                            if (!i_in_valid) begin
                                o_out_data1 <= {5'd0, final_kernel};
                                o_out_data2 <= {4'd0, final_precision};
                                o_out_data3 <= 8'd0;
                                o_out_data4 <= 8'd0;
                                o_out_valid1 <= 1'b1;
                                o_out_valid2 <= 1'b1;
                                state <= ST_CONFIG_DRAIN;
                            end else begin
                                state <= ST_CONFIG;
                            end
                        end else begin
                            o_in_ready <= 1'b1;
                            state <= ST_IMAGE_ACCEPT;
                        end
                    end
                end

                ST_IMAGE_DRAIN: begin
                    state <= ST_CONFIG;
                end

                ST_CONFIG: begin
                    // The source must have retired its final image word before
                    // the one-cycle configuration response is made visible.
                    // Invalid-cycle data may appear early; response valid and
                    // its state transition still wait for the source to retire.
                    o_out_data1 <= {5'd0, kernel_size};
                    o_out_data2 <= {4'd0, weight_precision};
                    o_out_data3 <= 8'd0;
                    o_out_data4 <= 8'd0;
                    if (!i_in_valid) begin
                        o_out_valid1 <= 1'b1;
                        o_out_valid2 <= 1'b1;
                        state <= ST_CONFIG_DRAIN;
                    end
                end

                ST_CONFIG_DRAIN: begin
                    o_out_data1 <= 8'd0;
                    o_out_data2 <= 8'd0;
                    if (barcode_found) begin
                        // This same edge issues row2; normal read_valid captures
                        // the initial prefix/zero rows and flags on the next edge.
                        read_valid <= 1'b1;
                        o_in_ready <= 1'b1;
                        state <= ST_WEIGHT_LOAD;
                    end else begin
                        o_exe_finish <= 1'b1;
                        state <= ST_FINISH;
                    end
                end

                ST_WEIGHT_LOAD: begin
                    if (i_in_valid && o_in_ready) begin
                        if ((weight_count + 6'd4) >= weight_total) begin
                            o_in_ready <= 1'b0;
                            // Group0 is primed. Pixel capture L2, heap L3..L7,
                            // correction L5 and merge L8 retain parent output timing.
                            stream_group <= 11'd1;
                            issue_pause <= slow_precision_mode;
                            state <= ST_STREAM;
                        end
                    end
                end

                ST_STREAM: begin
                    issue_pause <= slow_precision_mode && !issue_pause;
                    if (!issue_pause) begin
                        read_valid <= 1'b1;
                        if (stream_group == 11'd1023) begin
                            state <= ST_STREAM_FLUSH;
                        end else begin
                            stream_group <= stream_group + 11'd1;
                        end
                    end
                end

                ST_STREAM_FLUSH: begin
                    // TA Q7: completion may share the last valid output cycle.
                    // The global final_valid branch commits all four outputs at
                    // this same edge; ST_FINISH clears their valids next cycle.
                    if (final_valid && (final_addr == 12'd4092)) begin
                        o_exe_finish <= 1'b1;
                        state <= ST_FINISH;
                    end
                end

                ST_FINISH: begin
                    o_in_ready <= 1'b0;
                    o_exe_finish <= 1'b1;
                end

                default: begin
                    o_in_ready <= 1'b0;
                    state <= ST_BOOT;
                end
            endcase
        end
    end

endmodule

// 8-bit capture register built from fast-setup library flops (no reset, like the
// original raw_bank). Behavioral in RTL simulation.
module cap_ff8 (input clk, input [7:0] d, output [7:0] q);
`ifdef SYNTHESIS
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin: g_bit
            DFFHQX8 u_ff (.D(d[i]), .CK(clk), .Q(q[i]));
        end
    endgenerate
`else
    reg [7:0] r;
    always @(posedge clk) r <= d;
    assign q = r;
`endif
endmodule

// Generated by tools/generate_fused_heap.py; DO NOT EDIT.
// A/B remain separate through level 3; first capture is after level 2.
// First boundary: 209 payload FF after level 2; mode = 1 FF.
// Routed level 3: 172 bits; levels 4..12: 121,87,66,48,39,31,29,28,27.
// Cuts 2/4/7/10/12: 209+121+48+29+27 = 434 payload FF; five boundaries.
// Every FA conserves a+b+c = sum+2*carry; bit-21 carries discarded modulo 2^21.
module hw3_fused_heap(input i_clk, input [199:0] pixels,
 input [149:0] codes, input compact_high_shift,
 output [20:0] sum, output [20:0] carry);
wire [8:0] t0_0_mag;
wire [8:0] t0_0_payload;
assign t0_0_mag = ({1'b0,pixels[7:0]} & {9{codes[0]}}) | ({pixels[7:0],1'b0} & {9{codes[1]}});
assign t0_0_payload = t0_0_mag ^ {9{codes[2]}};
wire [8:0] t0_1_mag;
wire [8:0] t0_1_payload;
assign t0_1_mag = ({1'b0,pixels[7:0]} & {9{codes[3]}}) | ({pixels[7:0],1'b0} & {9{codes[4]}});
assign t0_1_payload = t0_1_mag ^ {9{codes[5]}};
wire [8:0] t1_0_mag;
wire [8:0] t1_0_payload;
assign t1_0_mag = ({1'b0,pixels[15:8]} & {9{codes[6]}}) | ({pixels[15:8],1'b0} & {9{codes[7]}});
assign t1_0_payload = t1_0_mag ^ {9{codes[8]}};
wire [8:0] t1_1_mag;
wire [8:0] t1_1_payload;
assign t1_1_mag = ({1'b0,pixels[15:8]} & {9{codes[9]}}) | ({pixels[15:8],1'b0} & {9{codes[10]}});
assign t1_1_payload = t1_1_mag ^ {9{codes[11]}};
wire [8:0] t2_0_mag;
wire [8:0] t2_0_payload;
assign t2_0_mag = ({1'b0,pixels[23:16]} & {9{codes[12]}}) | ({pixels[23:16],1'b0} & {9{codes[13]}});
assign t2_0_payload = t2_0_mag ^ {9{codes[14]}};
wire [8:0] t2_1_mag;
wire [8:0] t2_1_payload;
assign t2_1_mag = ({1'b0,pixels[23:16]} & {9{codes[15]}}) | ({pixels[23:16],1'b0} & {9{codes[16]}});
assign t2_1_payload = t2_1_mag ^ {9{codes[17]}};
wire [8:0] t3_0_mag;
wire [8:0] t3_0_payload;
assign t3_0_mag = ({1'b0,pixels[31:24]} & {9{codes[18]}}) | ({pixels[31:24],1'b0} & {9{codes[19]}});
assign t3_0_payload = t3_0_mag ^ {9{codes[20]}};
wire [8:0] t3_1_mag;
wire [8:0] t3_1_payload;
assign t3_1_mag = ({1'b0,pixels[31:24]} & {9{codes[21]}}) | ({pixels[31:24],1'b0} & {9{codes[22]}});
assign t3_1_payload = t3_1_mag ^ {9{codes[23]}};
wire [8:0] t4_0_mag;
wire [8:0] t4_0_payload;
assign t4_0_mag = ({1'b0,pixels[39:32]} & {9{codes[24]}}) | ({pixels[39:32],1'b0} & {9{codes[25]}});
assign t4_0_payload = t4_0_mag ^ {9{codes[26]}};
wire [8:0] t4_1_mag;
wire [8:0] t4_1_payload;
assign t4_1_mag = ({1'b0,pixels[39:32]} & {9{codes[27]}}) | ({pixels[39:32],1'b0} & {9{codes[28]}});
assign t4_1_payload = t4_1_mag ^ {9{codes[29]}};
wire [8:0] t5_0_mag;
wire [8:0] t5_0_payload;
assign t5_0_mag = ({1'b0,pixels[47:40]} & {9{codes[30]}}) | ({pixels[47:40],1'b0} & {9{codes[31]}});
assign t5_0_payload = t5_0_mag ^ {9{codes[32]}};
wire [8:0] t5_1_mag;
wire [8:0] t5_1_payload;
assign t5_1_mag = ({1'b0,pixels[47:40]} & {9{codes[33]}}) | ({pixels[47:40],1'b0} & {9{codes[34]}});
assign t5_1_payload = t5_1_mag ^ {9{codes[35]}};
wire [8:0] t6_0_mag;
wire [8:0] t6_0_payload;
assign t6_0_mag = ({1'b0,pixels[55:48]} & {9{codes[36]}}) | ({pixels[55:48],1'b0} & {9{codes[37]}});
assign t6_0_payload = t6_0_mag ^ {9{codes[38]}};
wire [8:0] t6_1_mag;
wire [8:0] t6_1_payload;
assign t6_1_mag = ({1'b0,pixels[55:48]} & {9{codes[39]}}) | ({pixels[55:48],1'b0} & {9{codes[40]}});
assign t6_1_payload = t6_1_mag ^ {9{codes[41]}};
wire [8:0] t7_0_mag;
wire [8:0] t7_0_payload;
assign t7_0_mag = ({1'b0,pixels[63:56]} & {9{codes[42]}}) | ({pixels[63:56],1'b0} & {9{codes[43]}});
assign t7_0_payload = t7_0_mag ^ {9{codes[44]}};
wire [8:0] t7_1_mag;
wire [8:0] t7_1_payload;
assign t7_1_mag = ({1'b0,pixels[63:56]} & {9{codes[45]}}) | ({pixels[63:56],1'b0} & {9{codes[46]}});
assign t7_1_payload = t7_1_mag ^ {9{codes[47]}};
wire [8:0] t8_0_mag;
wire [8:0] t8_0_payload;
assign t8_0_mag = ({1'b0,pixels[71:64]} & {9{codes[48]}}) | ({pixels[71:64],1'b0} & {9{codes[49]}});
assign t8_0_payload = t8_0_mag ^ {9{codes[50]}};
wire [8:0] t8_1_mag;
wire [8:0] t8_1_payload;
assign t8_1_mag = ({1'b0,pixels[71:64]} & {9{codes[51]}}) | ({pixels[71:64],1'b0} & {9{codes[52]}});
assign t8_1_payload = t8_1_mag ^ {9{codes[53]}};
wire [8:0] t9_0_mag;
wire [8:0] t9_0_payload;
assign t9_0_mag = ({1'b0,pixels[79:72]} & {9{codes[54]}}) | ({pixels[79:72],1'b0} & {9{codes[55]}});
assign t9_0_payload = t9_0_mag ^ {9{codes[56]}};
wire [8:0] t9_1_mag;
wire [8:0] t9_1_payload;
assign t9_1_mag = ({1'b0,pixels[79:72]} & {9{codes[57]}}) | ({pixels[79:72],1'b0} & {9{codes[58]}});
assign t9_1_payload = t9_1_mag ^ {9{codes[59]}};
wire [8:0] t10_0_mag;
wire [8:0] t10_0_payload;
assign t10_0_mag = ({1'b0,pixels[87:80]} & {9{codes[60]}}) | ({pixels[87:80],1'b0} & {9{codes[61]}});
assign t10_0_payload = t10_0_mag ^ {9{codes[62]}};
wire [8:0] t10_1_mag;
wire [8:0] t10_1_payload;
assign t10_1_mag = ({1'b0,pixels[87:80]} & {9{codes[63]}}) | ({pixels[87:80],1'b0} & {9{codes[64]}});
assign t10_1_payload = t10_1_mag ^ {9{codes[65]}};
wire [8:0] t11_0_mag;
wire [8:0] t11_0_payload;
assign t11_0_mag = ({1'b0,pixels[95:88]} & {9{codes[66]}}) | ({pixels[95:88],1'b0} & {9{codes[67]}});
assign t11_0_payload = t11_0_mag ^ {9{codes[68]}};
wire [8:0] t11_1_mag;
wire [8:0] t11_1_payload;
assign t11_1_mag = ({1'b0,pixels[95:88]} & {9{codes[69]}}) | ({pixels[95:88],1'b0} & {9{codes[70]}});
assign t11_1_payload = t11_1_mag ^ {9{codes[71]}};
wire [8:0] t12_0_mag;
wire [8:0] t12_0_payload;
assign t12_0_mag = ({1'b0,pixels[103:96]} & {9{codes[72]}}) | ({pixels[103:96],1'b0} & {9{codes[73]}});
assign t12_0_payload = t12_0_mag ^ {9{codes[74]}};
wire [8:0] t12_1_mag;
wire [8:0] t12_1_payload;
assign t12_1_mag = ({1'b0,pixels[103:96]} & {9{codes[75]}}) | ({pixels[103:96],1'b0} & {9{codes[76]}});
assign t12_1_payload = t12_1_mag ^ {9{codes[77]}};
wire [8:0] t13_0_mag;
wire [8:0] t13_0_payload;
assign t13_0_mag = ({1'b0,pixels[111:104]} & {9{codes[78]}}) | ({pixels[111:104],1'b0} & {9{codes[79]}});
assign t13_0_payload = t13_0_mag ^ {9{codes[80]}};
wire [8:0] t13_1_mag;
wire [8:0] t13_1_payload;
assign t13_1_mag = ({1'b0,pixels[111:104]} & {9{codes[81]}}) | ({pixels[111:104],1'b0} & {9{codes[82]}});
assign t13_1_payload = t13_1_mag ^ {9{codes[83]}};
wire [8:0] t14_0_mag;
wire [8:0] t14_0_payload;
assign t14_0_mag = ({1'b0,pixels[119:112]} & {9{codes[84]}}) | ({pixels[119:112],1'b0} & {9{codes[85]}});
assign t14_0_payload = t14_0_mag ^ {9{codes[86]}};
wire [8:0] t14_1_mag;
wire [8:0] t14_1_payload;
assign t14_1_mag = ({1'b0,pixels[119:112]} & {9{codes[87]}}) | ({pixels[119:112],1'b0} & {9{codes[88]}});
assign t14_1_payload = t14_1_mag ^ {9{codes[89]}};
wire [8:0] t15_0_mag;
wire [8:0] t15_0_payload;
assign t15_0_mag = ({1'b0,pixels[127:120]} & {9{codes[90]}}) | ({pixels[127:120],1'b0} & {9{codes[91]}});
assign t15_0_payload = t15_0_mag ^ {9{codes[92]}};
wire [8:0] t15_1_mag;
wire [8:0] t15_1_payload;
assign t15_1_mag = ({1'b0,pixels[127:120]} & {9{codes[93]}}) | ({pixels[127:120],1'b0} & {9{codes[94]}});
assign t15_1_payload = t15_1_mag ^ {9{codes[95]}};
wire [8:0] t16_0_mag;
wire [8:0] t16_0_payload;
assign t16_0_mag = ({1'b0,pixels[135:128]} & {9{codes[96]}}) | ({pixels[135:128],1'b0} & {9{codes[97]}});
assign t16_0_payload = t16_0_mag ^ {9{codes[98]}};
wire [8:0] t16_1_mag;
wire [8:0] t16_1_payload;
assign t16_1_mag = ({1'b0,pixels[135:128]} & {9{codes[99]}}) | ({pixels[135:128],1'b0} & {9{codes[100]}});
assign t16_1_payload = t16_1_mag ^ {9{codes[101]}};
wire [8:0] t17_0_mag;
wire [8:0] t17_0_payload;
assign t17_0_mag = ({1'b0,pixels[143:136]} & {9{codes[102]}}) | ({pixels[143:136],1'b0} & {9{codes[103]}});
assign t17_0_payload = t17_0_mag ^ {9{codes[104]}};
wire [8:0] t17_1_mag;
wire [8:0] t17_1_payload;
assign t17_1_mag = ({1'b0,pixels[143:136]} & {9{codes[105]}}) | ({pixels[143:136],1'b0} & {9{codes[106]}});
assign t17_1_payload = t17_1_mag ^ {9{codes[107]}};
wire [8:0] t18_0_mag;
wire [8:0] t18_0_payload;
assign t18_0_mag = ({1'b0,pixels[151:144]} & {9{codes[108]}}) | ({pixels[151:144],1'b0} & {9{codes[109]}});
assign t18_0_payload = t18_0_mag ^ {9{codes[110]}};
wire [8:0] t18_1_mag;
wire [8:0] t18_1_payload;
assign t18_1_mag = ({1'b0,pixels[151:144]} & {9{codes[111]}}) | ({pixels[151:144],1'b0} & {9{codes[112]}});
assign t18_1_payload = t18_1_mag ^ {9{codes[113]}};
wire [8:0] t19_0_mag;
wire [8:0] t19_0_payload;
assign t19_0_mag = ({1'b0,pixels[159:152]} & {9{codes[114]}}) | ({pixels[159:152],1'b0} & {9{codes[115]}});
assign t19_0_payload = t19_0_mag ^ {9{codes[116]}};
wire [8:0] t19_1_mag;
wire [8:0] t19_1_payload;
assign t19_1_mag = ({1'b0,pixels[159:152]} & {9{codes[117]}}) | ({pixels[159:152],1'b0} & {9{codes[118]}});
assign t19_1_payload = t19_1_mag ^ {9{codes[119]}};
wire [8:0] t20_0_mag;
wire [8:0] t20_0_payload;
assign t20_0_mag = ({1'b0,pixels[167:160]} & {9{codes[120]}}) | ({pixels[167:160],1'b0} & {9{codes[121]}});
assign t20_0_payload = t20_0_mag ^ {9{codes[122]}};
wire [8:0] t20_1_mag;
wire [8:0] t20_1_payload;
assign t20_1_mag = ({1'b0,pixels[167:160]} & {9{codes[123]}}) | ({pixels[167:160],1'b0} & {9{codes[124]}});
assign t20_1_payload = t20_1_mag ^ {9{codes[125]}};
wire [8:0] t21_0_mag;
wire [8:0] t21_0_payload;
assign t21_0_mag = ({1'b0,pixels[175:168]} & {9{codes[126]}}) | ({pixels[175:168],1'b0} & {9{codes[127]}});
assign t21_0_payload = t21_0_mag ^ {9{codes[128]}};
wire [8:0] t21_1_mag;
wire [8:0] t21_1_payload;
assign t21_1_mag = ({1'b0,pixels[175:168]} & {9{codes[129]}}) | ({pixels[175:168],1'b0} & {9{codes[130]}});
assign t21_1_payload = t21_1_mag ^ {9{codes[131]}};
wire [8:0] t22_0_mag;
wire [8:0] t22_0_payload;
assign t22_0_mag = ({1'b0,pixels[183:176]} & {9{codes[132]}}) | ({pixels[183:176],1'b0} & {9{codes[133]}});
assign t22_0_payload = t22_0_mag ^ {9{codes[134]}};
wire [8:0] t22_1_mag;
wire [8:0] t22_1_payload;
assign t22_1_mag = ({1'b0,pixels[183:176]} & {9{codes[135]}}) | ({pixels[183:176],1'b0} & {9{codes[136]}});
assign t22_1_payload = t22_1_mag ^ {9{codes[137]}};
wire [8:0] t23_0_mag;
wire [8:0] t23_0_payload;
assign t23_0_mag = ({1'b0,pixels[191:184]} & {9{codes[138]}}) | ({pixels[191:184],1'b0} & {9{codes[139]}});
assign t23_0_payload = t23_0_mag ^ {9{codes[140]}};
wire [8:0] t23_1_mag;
wire [8:0] t23_1_payload;
assign t23_1_mag = ({1'b0,pixels[191:184]} & {9{codes[141]}}) | ({pixels[191:184],1'b0} & {9{codes[142]}});
assign t23_1_payload = t23_1_mag ^ {9{codes[143]}};
wire [8:0] t24_0_mag;
wire [8:0] t24_0_payload;
assign t24_0_mag = ({1'b0,pixels[199:192]} & {9{codes[144]}}) | ({pixels[199:192],1'b0} & {9{codes[145]}});
assign t24_0_payload = t24_0_mag ^ {9{codes[146]}};
wire [8:0] t24_1_mag;
wire [8:0] t24_1_payload;
assign t24_1_mag = ({1'b0,pixels[199:192]} & {9{codes[147]}}) | ({pixels[199:192],1'b0} & {9{codes[148]}});
assign t24_1_payload = t24_1_mag ^ {9{codes[149]}};
wire a1_s0, a1_c0;
csa_fa u_a1_fa0 (.a(t0_0_payload[0]), .b(t1_0_payload[0]), .ci(t2_0_payload[0]), .s(a1_s0), .co(a1_c0));
wire a1_s1, a1_c1;
csa_fa u_a1_fa1 (.a(t3_0_payload[0]), .b(t4_0_payload[0]), .ci(t5_0_payload[0]), .s(a1_s1), .co(a1_c1));
wire a1_s2, a1_c2;
csa_fa u_a1_fa2 (.a(t6_0_payload[0]), .b(t7_0_payload[0]), .ci(t8_0_payload[0]), .s(a1_s2), .co(a1_c2));
wire a1_s3, a1_c3;
csa_fa u_a1_fa3 (.a(t0_0_payload[1]), .b(t1_0_payload[1]), .ci(t2_0_payload[1]), .s(a1_s3), .co(a1_c3));
wire a1_s4, a1_c4;
csa_fa u_a1_fa4 (.a(t3_0_payload[1]), .b(t4_0_payload[1]), .ci(t5_0_payload[1]), .s(a1_s4), .co(a1_c4));
wire a1_s5, a1_c5;
csa_fa u_a1_fa5 (.a(t6_0_payload[1]), .b(t7_0_payload[1]), .ci(t8_0_payload[1]), .s(a1_s5), .co(a1_c5));
wire a1_s6, a1_c6;
csa_fa u_a1_fa6 (.a(t0_0_payload[2]), .b(t0_1_payload[0]), .ci(t1_0_payload[2]), .s(a1_s6), .co(a1_c6));
wire a1_s7, a1_c7;
csa_fa u_a1_fa7 (.a(t1_1_payload[0]), .b(t2_0_payload[2]), .ci(t2_1_payload[0]), .s(a1_s7), .co(a1_c7));
wire a1_s8, a1_c8;
csa_fa u_a1_fa8 (.a(t3_0_payload[2]), .b(t3_1_payload[0]), .ci(t4_0_payload[2]), .s(a1_s8), .co(a1_c8));
wire a1_s9, a1_c9;
csa_fa u_a1_fa9 (.a(t4_1_payload[0]), .b(t5_0_payload[2]), .ci(t5_1_payload[0]), .s(a1_s9), .co(a1_c9));
wire a1_s10, a1_c10;
csa_fa u_a1_fa10 (.a(t6_0_payload[2]), .b(t6_1_payload[0]), .ci(t7_0_payload[2]), .s(a1_s10), .co(a1_c10));
wire a1_s11, a1_c11;
csa_fa u_a1_fa11 (.a(t7_1_payload[0]), .b(t8_0_payload[2]), .ci(t8_1_payload[0]), .s(a1_s11), .co(a1_c11));
wire a1_s12, a1_c12;
csa_fa u_a1_fa12 (.a(t0_0_payload[3]), .b(t0_1_payload[1]), .ci(t1_0_payload[3]), .s(a1_s12), .co(a1_c12));
wire a1_s13, a1_c13;
csa_fa u_a1_fa13 (.a(t1_1_payload[1]), .b(t2_0_payload[3]), .ci(t2_1_payload[1]), .s(a1_s13), .co(a1_c13));
wire a1_s14, a1_c14;
csa_fa u_a1_fa14 (.a(t3_0_payload[3]), .b(t3_1_payload[1]), .ci(t4_0_payload[3]), .s(a1_s14), .co(a1_c14));
wire a1_s15, a1_c15;
csa_fa u_a1_fa15 (.a(t4_1_payload[1]), .b(t5_0_payload[3]), .ci(t5_1_payload[1]), .s(a1_s15), .co(a1_c15));
wire a1_s16, a1_c16;
csa_fa u_a1_fa16 (.a(t6_0_payload[3]), .b(t6_1_payload[1]), .ci(t7_0_payload[3]), .s(a1_s16), .co(a1_c16));
wire a1_s17, a1_c17;
csa_fa u_a1_fa17 (.a(t7_1_payload[1]), .b(t8_0_payload[3]), .ci(t8_1_payload[1]), .s(a1_s17), .co(a1_c17));
wire a1_s18, a1_c18;
csa_fa u_a1_fa18 (.a(t0_0_payload[4]), .b(t0_1_payload[2]), .ci(t1_0_payload[4]), .s(a1_s18), .co(a1_c18));
wire a1_s19, a1_c19;
csa_fa u_a1_fa19 (.a(t1_1_payload[2]), .b(t2_0_payload[4]), .ci(t2_1_payload[2]), .s(a1_s19), .co(a1_c19));
wire a1_s20, a1_c20;
csa_fa u_a1_fa20 (.a(t3_0_payload[4]), .b(t3_1_payload[2]), .ci(t4_0_payload[4]), .s(a1_s20), .co(a1_c20));
wire a1_s21, a1_c21;
csa_fa u_a1_fa21 (.a(t4_1_payload[2]), .b(t5_0_payload[4]), .ci(t5_1_payload[2]), .s(a1_s21), .co(a1_c21));
wire a1_s22, a1_c22;
csa_fa u_a1_fa22 (.a(t6_0_payload[4]), .b(t6_1_payload[2]), .ci(t7_0_payload[4]), .s(a1_s22), .co(a1_c22));
wire a1_s23, a1_c23;
csa_fa u_a1_fa23 (.a(t7_1_payload[2]), .b(t8_0_payload[4]), .ci(t8_1_payload[2]), .s(a1_s23), .co(a1_c23));
wire a1_s24, a1_c24;
csa_fa u_a1_fa24 (.a(t0_0_payload[5]), .b(t0_1_payload[3]), .ci(t1_0_payload[5]), .s(a1_s24), .co(a1_c24));
wire a1_s25, a1_c25;
csa_fa u_a1_fa25 (.a(t1_1_payload[3]), .b(t2_0_payload[5]), .ci(t2_1_payload[3]), .s(a1_s25), .co(a1_c25));
wire a1_s26, a1_c26;
csa_fa u_a1_fa26 (.a(t3_0_payload[5]), .b(t3_1_payload[3]), .ci(t4_0_payload[5]), .s(a1_s26), .co(a1_c26));
wire a1_s27, a1_c27;
csa_fa u_a1_fa27 (.a(t4_1_payload[3]), .b(t5_0_payload[5]), .ci(t5_1_payload[3]), .s(a1_s27), .co(a1_c27));
wire a1_s28, a1_c28;
csa_fa u_a1_fa28 (.a(t6_0_payload[5]), .b(t6_1_payload[3]), .ci(t7_0_payload[5]), .s(a1_s28), .co(a1_c28));
wire a1_s29, a1_c29;
csa_fa u_a1_fa29 (.a(t7_1_payload[3]), .b(t8_0_payload[5]), .ci(t8_1_payload[3]), .s(a1_s29), .co(a1_c29));
wire a1_s30, a1_c30;
csa_fa u_a1_fa30 (.a(t0_0_payload[6]), .b(t0_1_payload[4]), .ci(t1_0_payload[6]), .s(a1_s30), .co(a1_c30));
wire a1_s31, a1_c31;
csa_fa u_a1_fa31 (.a(t1_1_payload[4]), .b(t2_0_payload[6]), .ci(t2_1_payload[4]), .s(a1_s31), .co(a1_c31));
wire a1_s32, a1_c32;
csa_fa u_a1_fa32 (.a(t3_0_payload[6]), .b(t3_1_payload[4]), .ci(t4_0_payload[6]), .s(a1_s32), .co(a1_c32));
wire a1_s33, a1_c33;
csa_fa u_a1_fa33 (.a(t4_1_payload[4]), .b(t5_0_payload[6]), .ci(t5_1_payload[4]), .s(a1_s33), .co(a1_c33));
wire a1_s34, a1_c34;
csa_fa u_a1_fa34 (.a(t6_0_payload[6]), .b(t6_1_payload[4]), .ci(t7_0_payload[6]), .s(a1_s34), .co(a1_c34));
wire a1_s35, a1_c35;
csa_fa u_a1_fa35 (.a(t7_1_payload[4]), .b(t8_0_payload[6]), .ci(t8_1_payload[4]), .s(a1_s35), .co(a1_c35));
wire a1_s36, a1_c36;
csa_fa u_a1_fa36 (.a(t0_0_payload[7]), .b(t0_1_payload[5]), .ci(t1_0_payload[7]), .s(a1_s36), .co(a1_c36));
wire a1_s37, a1_c37;
csa_fa u_a1_fa37 (.a(t1_1_payload[5]), .b(t2_0_payload[7]), .ci(t2_1_payload[5]), .s(a1_s37), .co(a1_c37));
wire a1_s38, a1_c38;
csa_fa u_a1_fa38 (.a(t3_0_payload[7]), .b(t3_1_payload[5]), .ci(t4_0_payload[7]), .s(a1_s38), .co(a1_c38));
wire a1_s39, a1_c39;
csa_fa u_a1_fa39 (.a(t4_1_payload[5]), .b(t5_0_payload[7]), .ci(t5_1_payload[5]), .s(a1_s39), .co(a1_c39));
wire a1_s40, a1_c40;
csa_fa u_a1_fa40 (.a(t6_0_payload[7]), .b(t6_1_payload[5]), .ci(t7_0_payload[7]), .s(a1_s40), .co(a1_c40));
wire a1_s41, a1_c41;
csa_fa u_a1_fa41 (.a(t7_1_payload[5]), .b(t8_0_payload[7]), .ci(t8_1_payload[5]), .s(a1_s41), .co(a1_c41));
wire a1_s42, a1_c42;
csa_fa u_a1_fa42 (.a(t0_0_payload[8]), .b(t0_1_payload[6]), .ci(t1_0_payload[8]), .s(a1_s42), .co(a1_c42));
wire a1_s43, a1_c43;
csa_fa u_a1_fa43 (.a(t1_1_payload[6]), .b(t2_0_payload[8]), .ci(t2_1_payload[6]), .s(a1_s43), .co(a1_c43));
wire a1_s44, a1_c44;
csa_fa u_a1_fa44 (.a(t3_0_payload[8]), .b(t3_1_payload[6]), .ci(t4_0_payload[8]), .s(a1_s44), .co(a1_c44));
wire a1_s45, a1_c45;
csa_fa u_a1_fa45 (.a(t4_1_payload[6]), .b(t5_0_payload[8]), .ci(t5_1_payload[6]), .s(a1_s45), .co(a1_c45));
wire a1_s46, a1_c46;
csa_fa u_a1_fa46 (.a(t6_0_payload[8]), .b(t6_1_payload[6]), .ci(t7_0_payload[8]), .s(a1_s46), .co(a1_c46));
wire a1_s47, a1_c47;
csa_fa u_a1_fa47 (.a(t7_1_payload[6]), .b(t8_0_payload[8]), .ci(t8_1_payload[6]), .s(a1_s47), .co(a1_c47));
wire a1_s48, a1_c48;
csa_fa u_a1_fa48 (.a(t0_1_payload[7]), .b(t1_1_payload[7]), .ci(t2_1_payload[7]), .s(a1_s48), .co(a1_c48));
wire a1_s49, a1_c49;
csa_fa u_a1_fa49 (.a(t3_1_payload[7]), .b(t4_1_payload[7]), .ci(t5_1_payload[7]), .s(a1_s49), .co(a1_c49));
wire a1_s50, a1_c50;
csa_fa u_a1_fa50 (.a(t6_1_payload[7]), .b(t7_1_payload[7]), .ci(t8_1_payload[7]), .s(a1_s50), .co(a1_c50));
wire a1_s51, a1_c51;
csa_fa u_a1_fa51 (.a(t0_1_payload[8]), .b(t1_1_payload[8]), .ci(t2_1_payload[8]), .s(a1_s51), .co(a1_c51));
wire a1_s52, a1_c52;
csa_fa u_a1_fa52 (.a(t3_1_payload[8]), .b(t4_1_payload[8]), .ci(t5_1_payload[8]), .s(a1_s52), .co(a1_c52));
wire a1_s53, a1_c53;
csa_fa u_a1_fa53 (.a(t6_1_payload[8]), .b(t7_1_payload[8]), .ci(t8_1_payload[8]), .s(a1_s53), .co(a1_c53));
// a1: 54 full adders; 108 live bits; column heights 3,6,9,12,12,12,12,12,12,9,6,3,0,0,0,0,0,0,0,0,0
wire b1_s0, b1_c0;
csa_fa u_b1_fa0 (.a(t9_0_payload[0]), .b(t10_0_payload[0]), .ci(t11_0_payload[0]), .s(b1_s0), .co(b1_c0));
wire b1_s1, b1_c1;
csa_fa u_b1_fa1 (.a(t12_0_payload[0]), .b(t13_0_payload[0]), .ci(t14_0_payload[0]), .s(b1_s1), .co(b1_c1));
wire b1_s2, b1_c2;
csa_fa u_b1_fa2 (.a(t15_0_payload[0]), .b(t16_0_payload[0]), .ci(t17_0_payload[0]), .s(b1_s2), .co(b1_c2));
wire b1_s3, b1_c3;
csa_fa u_b1_fa3 (.a(t18_0_payload[0]), .b(t19_0_payload[0]), .ci(t20_0_payload[0]), .s(b1_s3), .co(b1_c3));
wire b1_s4, b1_c4;
csa_fa u_b1_fa4 (.a(t21_0_payload[0]), .b(t22_0_payload[0]), .ci(t23_0_payload[0]), .s(b1_s4), .co(b1_c4));
wire b1_s5, b1_c5;
csa_fa u_b1_fa5 (.a(t9_0_payload[1]), .b(t10_0_payload[1]), .ci(t11_0_payload[1]), .s(b1_s5), .co(b1_c5));
wire b1_s6, b1_c6;
csa_fa u_b1_fa6 (.a(t12_0_payload[1]), .b(t13_0_payload[1]), .ci(t14_0_payload[1]), .s(b1_s6), .co(b1_c6));
wire b1_s7, b1_c7;
csa_fa u_b1_fa7 (.a(t15_0_payload[1]), .b(t16_0_payload[1]), .ci(t17_0_payload[1]), .s(b1_s7), .co(b1_c7));
wire b1_s8, b1_c8;
csa_fa u_b1_fa8 (.a(t18_0_payload[1]), .b(t19_0_payload[1]), .ci(t20_0_payload[1]), .s(b1_s8), .co(b1_c8));
wire b1_s9, b1_c9;
csa_fa u_b1_fa9 (.a(t21_0_payload[1]), .b(t22_0_payload[1]), .ci(t23_0_payload[1]), .s(b1_s9), .co(b1_c9));
wire b1_s10, b1_c10;
csa_fa u_b1_fa10 (.a(t9_0_payload[2]), .b(t9_1_payload[0]), .ci(t10_0_payload[2]), .s(b1_s10), .co(b1_c10));
wire b1_s11, b1_c11;
csa_fa u_b1_fa11 (.a(t10_1_payload[0]), .b(t11_0_payload[2]), .ci(t11_1_payload[0]), .s(b1_s11), .co(b1_c11));
wire b1_s12, b1_c12;
csa_fa u_b1_fa12 (.a(t12_0_payload[2]), .b(t12_1_payload[0]), .ci(t13_0_payload[2]), .s(b1_s12), .co(b1_c12));
wire b1_s13, b1_c13;
csa_fa u_b1_fa13 (.a(t13_1_payload[0]), .b(t14_0_payload[2]), .ci(t14_1_payload[0]), .s(b1_s13), .co(b1_c13));
wire b1_s14, b1_c14;
csa_fa u_b1_fa14 (.a(t15_0_payload[2]), .b(t15_1_payload[0]), .ci(t16_0_payload[2]), .s(b1_s14), .co(b1_c14));
wire b1_s15, b1_c15;
csa_fa u_b1_fa15 (.a(t16_1_payload[0]), .b(t17_0_payload[2]), .ci(t17_1_payload[0]), .s(b1_s15), .co(b1_c15));
wire b1_s16, b1_c16;
csa_fa u_b1_fa16 (.a(t18_0_payload[2]), .b(t18_1_payload[0]), .ci(t19_0_payload[2]), .s(b1_s16), .co(b1_c16));
wire b1_s17, b1_c17;
csa_fa u_b1_fa17 (.a(t19_1_payload[0]), .b(t20_0_payload[2]), .ci(t20_1_payload[0]), .s(b1_s17), .co(b1_c17));
wire b1_s18, b1_c18;
csa_fa u_b1_fa18 (.a(t21_0_payload[2]), .b(t21_1_payload[0]), .ci(t22_0_payload[2]), .s(b1_s18), .co(b1_c18));
wire b1_s19, b1_c19;
csa_fa u_b1_fa19 (.a(t22_1_payload[0]), .b(t23_0_payload[2]), .ci(t23_1_payload[0]), .s(b1_s19), .co(b1_c19));
wire b1_s20, b1_c20;
csa_fa u_b1_fa20 (.a(t9_0_payload[3]), .b(t9_1_payload[1]), .ci(t10_0_payload[3]), .s(b1_s20), .co(b1_c20));
wire b1_s21, b1_c21;
csa_fa u_b1_fa21 (.a(t10_1_payload[1]), .b(t11_0_payload[3]), .ci(t11_1_payload[1]), .s(b1_s21), .co(b1_c21));
wire b1_s22, b1_c22;
csa_fa u_b1_fa22 (.a(t12_0_payload[3]), .b(t12_1_payload[1]), .ci(t13_0_payload[3]), .s(b1_s22), .co(b1_c22));
wire b1_s23, b1_c23;
csa_fa u_b1_fa23 (.a(t13_1_payload[1]), .b(t14_0_payload[3]), .ci(t14_1_payload[1]), .s(b1_s23), .co(b1_c23));
wire b1_s24, b1_c24;
csa_fa u_b1_fa24 (.a(t15_0_payload[3]), .b(t15_1_payload[1]), .ci(t16_0_payload[3]), .s(b1_s24), .co(b1_c24));
wire b1_s25, b1_c25;
csa_fa u_b1_fa25 (.a(t16_1_payload[1]), .b(t17_0_payload[3]), .ci(t17_1_payload[1]), .s(b1_s25), .co(b1_c25));
wire b1_s26, b1_c26;
csa_fa u_b1_fa26 (.a(t18_0_payload[3]), .b(t18_1_payload[1]), .ci(t19_0_payload[3]), .s(b1_s26), .co(b1_c26));
wire b1_s27, b1_c27;
csa_fa u_b1_fa27 (.a(t19_1_payload[1]), .b(t20_0_payload[3]), .ci(t20_1_payload[1]), .s(b1_s27), .co(b1_c27));
wire b1_s28, b1_c28;
csa_fa u_b1_fa28 (.a(t21_0_payload[3]), .b(t21_1_payload[1]), .ci(t22_0_payload[3]), .s(b1_s28), .co(b1_c28));
wire b1_s29, b1_c29;
csa_fa u_b1_fa29 (.a(t22_1_payload[1]), .b(t23_0_payload[3]), .ci(t23_1_payload[1]), .s(b1_s29), .co(b1_c29));
wire b1_s30, b1_c30;
csa_fa u_b1_fa30 (.a(t9_0_payload[4]), .b(t9_1_payload[2]), .ci(t10_0_payload[4]), .s(b1_s30), .co(b1_c30));
wire b1_s31, b1_c31;
csa_fa u_b1_fa31 (.a(t10_1_payload[2]), .b(t11_0_payload[4]), .ci(t11_1_payload[2]), .s(b1_s31), .co(b1_c31));
wire b1_s32, b1_c32;
csa_fa u_b1_fa32 (.a(t12_0_payload[4]), .b(t12_1_payload[2]), .ci(t13_0_payload[4]), .s(b1_s32), .co(b1_c32));
wire b1_s33, b1_c33;
csa_fa u_b1_fa33 (.a(t13_1_payload[2]), .b(t14_0_payload[4]), .ci(t14_1_payload[2]), .s(b1_s33), .co(b1_c33));
wire b1_s34, b1_c34;
csa_fa u_b1_fa34 (.a(t15_0_payload[4]), .b(t15_1_payload[2]), .ci(t16_0_payload[4]), .s(b1_s34), .co(b1_c34));
wire b1_s35, b1_c35;
csa_fa u_b1_fa35 (.a(t16_1_payload[2]), .b(t17_0_payload[4]), .ci(t17_1_payload[2]), .s(b1_s35), .co(b1_c35));
wire b1_s36, b1_c36;
csa_fa u_b1_fa36 (.a(t18_0_payload[4]), .b(t18_1_payload[2]), .ci(t19_0_payload[4]), .s(b1_s36), .co(b1_c36));
wire b1_s37, b1_c37;
csa_fa u_b1_fa37 (.a(t19_1_payload[2]), .b(t20_0_payload[4]), .ci(t20_1_payload[2]), .s(b1_s37), .co(b1_c37));
wire b1_s38, b1_c38;
csa_fa u_b1_fa38 (.a(t21_0_payload[4]), .b(t21_1_payload[2]), .ci(t22_0_payload[4]), .s(b1_s38), .co(b1_c38));
wire b1_s39, b1_c39;
csa_fa u_b1_fa39 (.a(t22_1_payload[2]), .b(t23_0_payload[4]), .ci(t23_1_payload[2]), .s(b1_s39), .co(b1_c39));
wire b1_s40, b1_c40;
csa_fa u_b1_fa40 (.a(t9_0_payload[5]), .b(t9_1_payload[3]), .ci(t10_0_payload[5]), .s(b1_s40), .co(b1_c40));
wire b1_s41, b1_c41;
csa_fa u_b1_fa41 (.a(t10_1_payload[3]), .b(t11_0_payload[5]), .ci(t11_1_payload[3]), .s(b1_s41), .co(b1_c41));
wire b1_s42, b1_c42;
csa_fa u_b1_fa42 (.a(t12_0_payload[5]), .b(t12_1_payload[3]), .ci(t13_0_payload[5]), .s(b1_s42), .co(b1_c42));
wire b1_s43, b1_c43;
csa_fa u_b1_fa43 (.a(t13_1_payload[3]), .b(t14_0_payload[5]), .ci(t14_1_payload[3]), .s(b1_s43), .co(b1_c43));
wire b1_s44, b1_c44;
csa_fa u_b1_fa44 (.a(t15_0_payload[5]), .b(t15_1_payload[3]), .ci(t16_0_payload[5]), .s(b1_s44), .co(b1_c44));
wire b1_s45, b1_c45;
csa_fa u_b1_fa45 (.a(t16_1_payload[3]), .b(t17_0_payload[5]), .ci(t17_1_payload[3]), .s(b1_s45), .co(b1_c45));
wire b1_s46, b1_c46;
csa_fa u_b1_fa46 (.a(t18_0_payload[5]), .b(t18_1_payload[3]), .ci(t19_0_payload[5]), .s(b1_s46), .co(b1_c46));
wire b1_s47, b1_c47;
csa_fa u_b1_fa47 (.a(t19_1_payload[3]), .b(t20_0_payload[5]), .ci(t20_1_payload[3]), .s(b1_s47), .co(b1_c47));
wire b1_s48, b1_c48;
csa_fa u_b1_fa48 (.a(t21_0_payload[5]), .b(t21_1_payload[3]), .ci(t22_0_payload[5]), .s(b1_s48), .co(b1_c48));
wire b1_s49, b1_c49;
csa_fa u_b1_fa49 (.a(t22_1_payload[3]), .b(t23_0_payload[5]), .ci(t23_1_payload[3]), .s(b1_s49), .co(b1_c49));
wire b1_s50, b1_c50;
csa_fa u_b1_fa50 (.a(t9_0_payload[6]), .b(t9_1_payload[4]), .ci(t10_0_payload[6]), .s(b1_s50), .co(b1_c50));
wire b1_s51, b1_c51;
csa_fa u_b1_fa51 (.a(t10_1_payload[4]), .b(t11_0_payload[6]), .ci(t11_1_payload[4]), .s(b1_s51), .co(b1_c51));
wire b1_s52, b1_c52;
csa_fa u_b1_fa52 (.a(t12_0_payload[6]), .b(t12_1_payload[4]), .ci(t13_0_payload[6]), .s(b1_s52), .co(b1_c52));
wire b1_s53, b1_c53;
csa_fa u_b1_fa53 (.a(t13_1_payload[4]), .b(t14_0_payload[6]), .ci(t14_1_payload[4]), .s(b1_s53), .co(b1_c53));
wire b1_s54, b1_c54;
csa_fa u_b1_fa54 (.a(t15_0_payload[6]), .b(t15_1_payload[4]), .ci(t16_0_payload[6]), .s(b1_s54), .co(b1_c54));
wire b1_s55, b1_c55;
csa_fa u_b1_fa55 (.a(t16_1_payload[4]), .b(t17_0_payload[6]), .ci(t17_1_payload[4]), .s(b1_s55), .co(b1_c55));
wire b1_s56, b1_c56;
csa_fa u_b1_fa56 (.a(t18_0_payload[6]), .b(t18_1_payload[4]), .ci(t19_0_payload[6]), .s(b1_s56), .co(b1_c56));
wire b1_s57, b1_c57;
csa_fa u_b1_fa57 (.a(t19_1_payload[4]), .b(t20_0_payload[6]), .ci(t20_1_payload[4]), .s(b1_s57), .co(b1_c57));
wire b1_s58, b1_c58;
csa_fa u_b1_fa58 (.a(t21_0_payload[6]), .b(t21_1_payload[4]), .ci(t22_0_payload[6]), .s(b1_s58), .co(b1_c58));
wire b1_s59, b1_c59;
csa_fa u_b1_fa59 (.a(t22_1_payload[4]), .b(t23_0_payload[6]), .ci(t23_1_payload[4]), .s(b1_s59), .co(b1_c59));
wire b1_s60, b1_c60;
csa_fa u_b1_fa60 (.a(t9_0_payload[7]), .b(t9_1_payload[5]), .ci(t10_0_payload[7]), .s(b1_s60), .co(b1_c60));
wire b1_s61, b1_c61;
csa_fa u_b1_fa61 (.a(t10_1_payload[5]), .b(t11_0_payload[7]), .ci(t11_1_payload[5]), .s(b1_s61), .co(b1_c61));
wire b1_s62, b1_c62;
csa_fa u_b1_fa62 (.a(t12_0_payload[7]), .b(t12_1_payload[5]), .ci(t13_0_payload[7]), .s(b1_s62), .co(b1_c62));
wire b1_s63, b1_c63;
csa_fa u_b1_fa63 (.a(t13_1_payload[5]), .b(t14_0_payload[7]), .ci(t14_1_payload[5]), .s(b1_s63), .co(b1_c63));
wire b1_s64, b1_c64;
csa_fa u_b1_fa64 (.a(t15_0_payload[7]), .b(t15_1_payload[5]), .ci(t16_0_payload[7]), .s(b1_s64), .co(b1_c64));
wire b1_s65, b1_c65;
csa_fa u_b1_fa65 (.a(t16_1_payload[5]), .b(t17_0_payload[7]), .ci(t17_1_payload[5]), .s(b1_s65), .co(b1_c65));
wire b1_s66, b1_c66;
csa_fa u_b1_fa66 (.a(t18_0_payload[7]), .b(t18_1_payload[5]), .ci(t19_0_payload[7]), .s(b1_s66), .co(b1_c66));
wire b1_s67, b1_c67;
csa_fa u_b1_fa67 (.a(t19_1_payload[5]), .b(t20_0_payload[7]), .ci(t20_1_payload[5]), .s(b1_s67), .co(b1_c67));
wire b1_s68, b1_c68;
csa_fa u_b1_fa68 (.a(t21_0_payload[7]), .b(t21_1_payload[5]), .ci(t22_0_payload[7]), .s(b1_s68), .co(b1_c68));
wire b1_s69, b1_c69;
csa_fa u_b1_fa69 (.a(t22_1_payload[5]), .b(t23_0_payload[7]), .ci(t23_1_payload[5]), .s(b1_s69), .co(b1_c69));
wire b1_s70, b1_c70;
csa_fa u_b1_fa70 (.a(t9_0_payload[8]), .b(t9_1_payload[6]), .ci(t10_0_payload[8]), .s(b1_s70), .co(b1_c70));
wire b1_s71, b1_c71;
csa_fa u_b1_fa71 (.a(t10_1_payload[6]), .b(t11_0_payload[8]), .ci(t11_1_payload[6]), .s(b1_s71), .co(b1_c71));
wire b1_s72, b1_c72;
csa_fa u_b1_fa72 (.a(t12_0_payload[8]), .b(t12_1_payload[6]), .ci(t13_0_payload[8]), .s(b1_s72), .co(b1_c72));
wire b1_s73, b1_c73;
csa_fa u_b1_fa73 (.a(t13_1_payload[6]), .b(t14_0_payload[8]), .ci(t14_1_payload[6]), .s(b1_s73), .co(b1_c73));
wire b1_s74, b1_c74;
csa_fa u_b1_fa74 (.a(t15_0_payload[8]), .b(t15_1_payload[6]), .ci(t16_0_payload[8]), .s(b1_s74), .co(b1_c74));
wire b1_s75, b1_c75;
csa_fa u_b1_fa75 (.a(t16_1_payload[6]), .b(t17_0_payload[8]), .ci(t17_1_payload[6]), .s(b1_s75), .co(b1_c75));
wire b1_s76, b1_c76;
csa_fa u_b1_fa76 (.a(t18_0_payload[8]), .b(t18_1_payload[6]), .ci(t19_0_payload[8]), .s(b1_s76), .co(b1_c76));
wire b1_s77, b1_c77;
csa_fa u_b1_fa77 (.a(t19_1_payload[6]), .b(t20_0_payload[8]), .ci(t20_1_payload[6]), .s(b1_s77), .co(b1_c77));
wire b1_s78, b1_c78;
csa_fa u_b1_fa78 (.a(t21_0_payload[8]), .b(t21_1_payload[6]), .ci(t22_0_payload[8]), .s(b1_s78), .co(b1_c78));
wire b1_s79, b1_c79;
csa_fa u_b1_fa79 (.a(t22_1_payload[6]), .b(t23_0_payload[8]), .ci(t23_1_payload[6]), .s(b1_s79), .co(b1_c79));
wire b1_s80, b1_c80;
csa_fa u_b1_fa80 (.a(t9_1_payload[7]), .b(t10_1_payload[7]), .ci(t11_1_payload[7]), .s(b1_s80), .co(b1_c80));
wire b1_s81, b1_c81;
csa_fa u_b1_fa81 (.a(t12_1_payload[7]), .b(t13_1_payload[7]), .ci(t14_1_payload[7]), .s(b1_s81), .co(b1_c81));
wire b1_s82, b1_c82;
csa_fa u_b1_fa82 (.a(t15_1_payload[7]), .b(t16_1_payload[7]), .ci(t17_1_payload[7]), .s(b1_s82), .co(b1_c82));
wire b1_s83, b1_c83;
csa_fa u_b1_fa83 (.a(t18_1_payload[7]), .b(t19_1_payload[7]), .ci(t20_1_payload[7]), .s(b1_s83), .co(b1_c83));
wire b1_s84, b1_c84;
csa_fa u_b1_fa84 (.a(t21_1_payload[7]), .b(t22_1_payload[7]), .ci(t23_1_payload[7]), .s(b1_s84), .co(b1_c84));
wire b1_s85, b1_c85;
csa_fa u_b1_fa85 (.a(t9_1_payload[8]), .b(t10_1_payload[8]), .ci(t11_1_payload[8]), .s(b1_s85), .co(b1_c85));
wire b1_s86, b1_c86;
csa_fa u_b1_fa86 (.a(t12_1_payload[8]), .b(t13_1_payload[8]), .ci(t14_1_payload[8]), .s(b1_s86), .co(b1_c86));
wire b1_s87, b1_c87;
csa_fa u_b1_fa87 (.a(t15_1_payload[8]), .b(t16_1_payload[8]), .ci(t17_1_payload[8]), .s(b1_s87), .co(b1_c87));
wire b1_s88, b1_c88;
csa_fa u_b1_fa88 (.a(t18_1_payload[8]), .b(t19_1_payload[8]), .ci(t20_1_payload[8]), .s(b1_s88), .co(b1_c88));
wire b1_s89, b1_c89;
csa_fa u_b1_fa89 (.a(t21_1_payload[8]), .b(t22_1_payload[8]), .ci(t23_1_payload[8]), .s(b1_s89), .co(b1_c89));
// b1: 90 full adders; 198 live bits; column heights 6,11,17,22,22,22,22,22,22,16,11,5,0,0,0,0,0,0,0,0,0
wire a2_s0, a2_c0;
csa_fa u_a2_fa0 (.a(a1_s0), .b(a1_s1), .ci(a1_s2), .s(a2_s0), .co(a2_c0));
wire a2_s1, a2_c1;
csa_fa u_a2_fa1 (.a(a1_c0), .b(a1_c1), .ci(a1_c2), .s(a2_s1), .co(a2_c1));
wire a2_s2, a2_c2;
csa_fa u_a2_fa2 (.a(a1_s3), .b(a1_s4), .ci(a1_s5), .s(a2_s2), .co(a2_c2));
wire a2_s3, a2_c3;
csa_fa u_a2_fa3 (.a(a1_c3), .b(a1_c4), .ci(a1_c5), .s(a2_s3), .co(a2_c3));
wire a2_s4, a2_c4;
csa_fa u_a2_fa4 (.a(a1_s6), .b(a1_s7), .ci(a1_s8), .s(a2_s4), .co(a2_c4));
wire a2_s5, a2_c5;
csa_fa u_a2_fa5 (.a(a1_s9), .b(a1_s10), .ci(a1_s11), .s(a2_s5), .co(a2_c5));
wire a2_s6, a2_c6;
csa_fa u_a2_fa6 (.a(a1_c6), .b(a1_c7), .ci(a1_c8), .s(a2_s6), .co(a2_c6));
wire a2_s7, a2_c7;
csa_fa u_a2_fa7 (.a(a1_c9), .b(a1_c10), .ci(a1_c11), .s(a2_s7), .co(a2_c7));
wire a2_s8, a2_c8;
csa_fa u_a2_fa8 (.a(a1_s12), .b(a1_s13), .ci(a1_s14), .s(a2_s8), .co(a2_c8));
wire a2_s9, a2_c9;
csa_fa u_a2_fa9 (.a(a1_s15), .b(a1_s16), .ci(a1_s17), .s(a2_s9), .co(a2_c9));
wire a2_s10, a2_c10;
csa_fa u_a2_fa10 (.a(a1_c12), .b(a1_c13), .ci(a1_c14), .s(a2_s10), .co(a2_c10));
wire a2_s11, a2_c11;
csa_fa u_a2_fa11 (.a(a1_c15), .b(a1_c16), .ci(a1_c17), .s(a2_s11), .co(a2_c11));
wire a2_s12, a2_c12;
csa_fa u_a2_fa12 (.a(a1_s18), .b(a1_s19), .ci(a1_s20), .s(a2_s12), .co(a2_c12));
wire a2_s13, a2_c13;
csa_fa u_a2_fa13 (.a(a1_s21), .b(a1_s22), .ci(a1_s23), .s(a2_s13), .co(a2_c13));
wire a2_s14, a2_c14;
csa_fa u_a2_fa14 (.a(a1_c18), .b(a1_c19), .ci(a1_c20), .s(a2_s14), .co(a2_c14));
wire a2_s15, a2_c15;
csa_fa u_a2_fa15 (.a(a1_c21), .b(a1_c22), .ci(a1_c23), .s(a2_s15), .co(a2_c15));
wire a2_s16, a2_c16;
csa_fa u_a2_fa16 (.a(a1_s24), .b(a1_s25), .ci(a1_s26), .s(a2_s16), .co(a2_c16));
wire a2_s17, a2_c17;
csa_fa u_a2_fa17 (.a(a1_s27), .b(a1_s28), .ci(a1_s29), .s(a2_s17), .co(a2_c17));
wire a2_s18, a2_c18;
csa_fa u_a2_fa18 (.a(a1_c24), .b(a1_c25), .ci(a1_c26), .s(a2_s18), .co(a2_c18));
wire a2_s19, a2_c19;
csa_fa u_a2_fa19 (.a(a1_c27), .b(a1_c28), .ci(a1_c29), .s(a2_s19), .co(a2_c19));
wire a2_s20, a2_c20;
csa_fa u_a2_fa20 (.a(a1_s30), .b(a1_s31), .ci(a1_s32), .s(a2_s20), .co(a2_c20));
wire a2_s21, a2_c21;
csa_fa u_a2_fa21 (.a(a1_s33), .b(a1_s34), .ci(a1_s35), .s(a2_s21), .co(a2_c21));
wire a2_s22, a2_c22;
csa_fa u_a2_fa22 (.a(a1_c30), .b(a1_c31), .ci(a1_c32), .s(a2_s22), .co(a2_c22));
wire a2_s23, a2_c23;
csa_fa u_a2_fa23 (.a(a1_c33), .b(a1_c34), .ci(a1_c35), .s(a2_s23), .co(a2_c23));
wire a2_s24, a2_c24;
csa_fa u_a2_fa24 (.a(a1_s36), .b(a1_s37), .ci(a1_s38), .s(a2_s24), .co(a2_c24));
wire a2_s25, a2_c25;
csa_fa u_a2_fa25 (.a(a1_s39), .b(a1_s40), .ci(a1_s41), .s(a2_s25), .co(a2_c25));
wire a2_s26, a2_c26;
csa_fa u_a2_fa26 (.a(a1_c36), .b(a1_c37), .ci(a1_c38), .s(a2_s26), .co(a2_c26));
wire a2_s27, a2_c27;
csa_fa u_a2_fa27 (.a(a1_c39), .b(a1_c40), .ci(a1_c41), .s(a2_s27), .co(a2_c27));
wire a2_s28, a2_c28;
csa_fa u_a2_fa28 (.a(a1_s42), .b(a1_s43), .ci(a1_s44), .s(a2_s28), .co(a2_c28));
wire a2_s29, a2_c29;
csa_fa u_a2_fa29 (.a(a1_s45), .b(a1_s46), .ci(a1_s47), .s(a2_s29), .co(a2_c29));
wire a2_s30, a2_c30;
csa_fa u_a2_fa30 (.a(a1_c42), .b(a1_c43), .ci(a1_c44), .s(a2_s30), .co(a2_c30));
wire a2_s31, a2_c31;
csa_fa u_a2_fa31 (.a(a1_c45), .b(a1_c46), .ci(a1_c47), .s(a2_s31), .co(a2_c31));
wire a2_s32, a2_c32;
csa_fa u_a2_fa32 (.a(a1_s48), .b(a1_s49), .ci(a1_s50), .s(a2_s32), .co(a2_c32));
wire a2_s33, a2_c33;
csa_fa u_a2_fa33 (.a(a1_c48), .b(a1_c49), .ci(a1_c50), .s(a2_s33), .co(a2_c33));
wire a2_s34, a2_c34;
csa_fa u_a2_fa34 (.a(a1_s51), .b(a1_s52), .ci(a1_s53), .s(a2_s34), .co(a2_c34));
wire a2_s35, a2_c35;
csa_fa u_a2_fa35 (.a(a1_c51), .b(a1_c52), .ci(a1_c53), .s(a2_s35), .co(a2_c35));
// a2: 36 full adders; 72 live bits; column heights 1,3,5,7,8,8,8,8,8,7,5,3,1,0,0,0,0,0,0,0,0
wire b2_s0, b2_c0;
csa_fa u_b2_fa0 (.a(b1_s0), .b(b1_s1), .ci(b1_s2), .s(b2_s0), .co(b2_c0));
wire b2_s1, b2_c1;
csa_fa u_b2_fa1 (.a(b1_s3), .b(b1_s4), .ci(t24_0_payload[0]), .s(b2_s1), .co(b2_c1));
wire b2_s2, b2_c2;
csa_fa u_b2_fa2 (.a(b1_c0), .b(b1_c1), .ci(b1_c2), .s(b2_s2), .co(b2_c2));
wire b2_s3, b2_c3;
csa_fa u_b2_fa3 (.a(b1_c3), .b(b1_c4), .ci(b1_s5), .s(b2_s3), .co(b2_c3));
wire b2_s4, b2_c4;
csa_fa u_b2_fa4 (.a(b1_s6), .b(b1_s7), .ci(b1_s8), .s(b2_s4), .co(b2_c4));
wire b2_s5, b2_c5;
csa_fa u_b2_fa5 (.a(b1_c5), .b(b1_c6), .ci(b1_c7), .s(b2_s5), .co(b2_c5));
wire b2_s6, b2_c6;
csa_fa u_b2_fa6 (.a(b1_c8), .b(b1_c9), .ci(b1_s10), .s(b2_s6), .co(b2_c6));
wire b2_s7, b2_c7;
csa_fa u_b2_fa7 (.a(b1_s11), .b(b1_s12), .ci(b1_s13), .s(b2_s7), .co(b2_c7));
wire b2_s8, b2_c8;
csa_fa u_b2_fa8 (.a(b1_s14), .b(b1_s15), .ci(b1_s16), .s(b2_s8), .co(b2_c8));
wire b2_s9, b2_c9;
csa_fa u_b2_fa9 (.a(b1_s17), .b(b1_s18), .ci(b1_s19), .s(b2_s9), .co(b2_c9));
wire b2_s10, b2_c10;
csa_fa u_b2_fa10 (.a(b1_c10), .b(b1_c11), .ci(b1_c12), .s(b2_s10), .co(b2_c10));
wire b2_s11, b2_c11;
csa_fa u_b2_fa11 (.a(b1_c13), .b(b1_c14), .ci(b1_c15), .s(b2_s11), .co(b2_c11));
wire b2_s12, b2_c12;
csa_fa u_b2_fa12 (.a(b1_c16), .b(b1_c17), .ci(b1_c18), .s(b2_s12), .co(b2_c12));
wire b2_s13, b2_c13;
csa_fa u_b2_fa13 (.a(b1_c19), .b(b1_s20), .ci(b1_s21), .s(b2_s13), .co(b2_c13));
wire b2_s14, b2_c14;
csa_fa u_b2_fa14 (.a(b1_s22), .b(b1_s23), .ci(b1_s24), .s(b2_s14), .co(b2_c14));
wire b2_s15, b2_c15;
csa_fa u_b2_fa15 (.a(b1_s25), .b(b1_s26), .ci(b1_s27), .s(b2_s15), .co(b2_c15));
wire b2_s16, b2_c16;
csa_fa u_b2_fa16 (.a(b1_s28), .b(b1_s29), .ci(t24_0_payload[3]), .s(b2_s16), .co(b2_c16));
wire b2_s17, b2_c17;
csa_fa u_b2_fa17 (.a(b1_c20), .b(b1_c21), .ci(b1_c22), .s(b2_s17), .co(b2_c17));
wire b2_s18, b2_c18;
csa_fa u_b2_fa18 (.a(b1_c23), .b(b1_c24), .ci(b1_c25), .s(b2_s18), .co(b2_c18));
wire b2_s19, b2_c19;
csa_fa u_b2_fa19 (.a(b1_c26), .b(b1_c27), .ci(b1_c28), .s(b2_s19), .co(b2_c19));
wire b2_s20, b2_c20;
csa_fa u_b2_fa20 (.a(b1_c29), .b(b1_s30), .ci(b1_s31), .s(b2_s20), .co(b2_c20));
wire b2_s21, b2_c21;
csa_fa u_b2_fa21 (.a(b1_s32), .b(b1_s33), .ci(b1_s34), .s(b2_s21), .co(b2_c21));
wire b2_s22, b2_c22;
csa_fa u_b2_fa22 (.a(b1_s35), .b(b1_s36), .ci(b1_s37), .s(b2_s22), .co(b2_c22));
wire b2_s23, b2_c23;
csa_fa u_b2_fa23 (.a(b1_s38), .b(b1_s39), .ci(t24_0_payload[4]), .s(b2_s23), .co(b2_c23));
wire b2_s24, b2_c24;
csa_fa u_b2_fa24 (.a(b1_c30), .b(b1_c31), .ci(b1_c32), .s(b2_s24), .co(b2_c24));
wire b2_s25, b2_c25;
csa_fa u_b2_fa25 (.a(b1_c33), .b(b1_c34), .ci(b1_c35), .s(b2_s25), .co(b2_c25));
wire b2_s26, b2_c26;
csa_fa u_b2_fa26 (.a(b1_c36), .b(b1_c37), .ci(b1_c38), .s(b2_s26), .co(b2_c26));
wire b2_s27, b2_c27;
csa_fa u_b2_fa27 (.a(b1_c39), .b(b1_s40), .ci(b1_s41), .s(b2_s27), .co(b2_c27));
wire b2_s28, b2_c28;
csa_fa u_b2_fa28 (.a(b1_s42), .b(b1_s43), .ci(b1_s44), .s(b2_s28), .co(b2_c28));
wire b2_s29, b2_c29;
csa_fa u_b2_fa29 (.a(b1_s45), .b(b1_s46), .ci(b1_s47), .s(b2_s29), .co(b2_c29));
wire b2_s30, b2_c30;
csa_fa u_b2_fa30 (.a(b1_s48), .b(b1_s49), .ci(t24_0_payload[5]), .s(b2_s30), .co(b2_c30));
wire b2_s31, b2_c31;
csa_fa u_b2_fa31 (.a(b1_c40), .b(b1_c41), .ci(b1_c42), .s(b2_s31), .co(b2_c31));
wire b2_s32, b2_c32;
csa_fa u_b2_fa32 (.a(b1_c43), .b(b1_c44), .ci(b1_c45), .s(b2_s32), .co(b2_c32));
wire b2_s33, b2_c33;
csa_fa u_b2_fa33 (.a(b1_c46), .b(b1_c47), .ci(b1_c48), .s(b2_s33), .co(b2_c33));
wire b2_s34, b2_c34;
csa_fa u_b2_fa34 (.a(b1_c49), .b(b1_s50), .ci(b1_s51), .s(b2_s34), .co(b2_c34));
wire b2_s35, b2_c35;
csa_fa u_b2_fa35 (.a(b1_s52), .b(b1_s53), .ci(b1_s54), .s(b2_s35), .co(b2_c35));
wire b2_s36, b2_c36;
csa_fa u_b2_fa36 (.a(b1_s55), .b(b1_s56), .ci(b1_s57), .s(b2_s36), .co(b2_c36));
wire b2_s37, b2_c37;
csa_fa u_b2_fa37 (.a(b1_s58), .b(b1_s59), .ci(t24_0_payload[6]), .s(b2_s37), .co(b2_c37));
wire b2_s38, b2_c38;
csa_fa u_b2_fa38 (.a(b1_c50), .b(b1_c51), .ci(b1_c52), .s(b2_s38), .co(b2_c38));
wire b2_s39, b2_c39;
csa_fa u_b2_fa39 (.a(b1_c53), .b(b1_c54), .ci(b1_c55), .s(b2_s39), .co(b2_c39));
wire b2_s40, b2_c40;
csa_fa u_b2_fa40 (.a(b1_c56), .b(b1_c57), .ci(b1_c58), .s(b2_s40), .co(b2_c40));
wire b2_s41, b2_c41;
csa_fa u_b2_fa41 (.a(b1_c59), .b(b1_s60), .ci(b1_s61), .s(b2_s41), .co(b2_c41));
wire b2_s42, b2_c42;
csa_fa u_b2_fa42 (.a(b1_s62), .b(b1_s63), .ci(b1_s64), .s(b2_s42), .co(b2_c42));
wire b2_s43, b2_c43;
csa_fa u_b2_fa43 (.a(b1_s65), .b(b1_s66), .ci(b1_s67), .s(b2_s43), .co(b2_c43));
wire b2_s44, b2_c44;
csa_fa u_b2_fa44 (.a(b1_s68), .b(b1_s69), .ci(t24_0_payload[7]), .s(b2_s44), .co(b2_c44));
wire b2_s45, b2_c45;
csa_fa u_b2_fa45 (.a(b1_c60), .b(b1_c61), .ci(b1_c62), .s(b2_s45), .co(b2_c45));
wire b2_s46, b2_c46;
csa_fa u_b2_fa46 (.a(b1_c63), .b(b1_c64), .ci(b1_c65), .s(b2_s46), .co(b2_c46));
wire b2_s47, b2_c47;
csa_fa u_b2_fa47 (.a(b1_c66), .b(b1_c67), .ci(b1_c68), .s(b2_s47), .co(b2_c47));
wire b2_s48, b2_c48;
csa_fa u_b2_fa48 (.a(b1_c69), .b(b1_s70), .ci(b1_s71), .s(b2_s48), .co(b2_c48));
wire b2_s49, b2_c49;
csa_fa u_b2_fa49 (.a(b1_s72), .b(b1_s73), .ci(b1_s74), .s(b2_s49), .co(b2_c49));
wire b2_s50, b2_c50;
csa_fa u_b2_fa50 (.a(b1_s75), .b(b1_s76), .ci(b1_s77), .s(b2_s50), .co(b2_c50));
wire b2_s51, b2_c51;
csa_fa u_b2_fa51 (.a(b1_s78), .b(b1_s79), .ci(t24_0_payload[8]), .s(b2_s51), .co(b2_c51));
wire b2_s52, b2_c52;
csa_fa u_b2_fa52 (.a(b1_c70), .b(b1_c71), .ci(b1_c72), .s(b2_s52), .co(b2_c52));
wire b2_s53, b2_c53;
csa_fa u_b2_fa53 (.a(b1_c73), .b(b1_c74), .ci(b1_c75), .s(b2_s53), .co(b2_c53));
wire b2_s54, b2_c54;
csa_fa u_b2_fa54 (.a(b1_c76), .b(b1_c77), .ci(b1_c78), .s(b2_s54), .co(b2_c54));
wire b2_s55, b2_c55;
csa_fa u_b2_fa55 (.a(b1_c79), .b(b1_s80), .ci(b1_s81), .s(b2_s55), .co(b2_c55));
wire b2_s56, b2_c56;
csa_fa u_b2_fa56 (.a(b1_s82), .b(b1_s83), .ci(b1_s84), .s(b2_s56), .co(b2_c56));
wire b2_s57, b2_c57;
csa_fa u_b2_fa57 (.a(b1_c80), .b(b1_c81), .ci(b1_c82), .s(b2_s57), .co(b2_c57));
wire b2_s58, b2_c58;
csa_fa u_b2_fa58 (.a(b1_c83), .b(b1_c84), .ci(b1_s85), .s(b2_s58), .co(b2_c58));
wire b2_s59, b2_c59;
csa_fa u_b2_fa59 (.a(b1_s86), .b(b1_s87), .ci(b1_s88), .s(b2_s59), .co(b2_c59));
wire b2_s60, b2_c60;
csa_fa u_b2_fa60 (.a(b1_c85), .b(b1_c86), .ci(b1_c87), .s(b2_s60), .co(b2_c60));
// b2: 61 full adders; 137 live bits; column heights 2,7,10,13,15,15,15,15,15,13,10,6,1,0,0,0,0,0,0,0,0
reg [71:0] cut2_a;
always @(posedge i_clk) cut2_a <= {a2_c35,a2_s35,a2_c34,a2_c33,a2_s34,a2_s33,a2_c32,a2_c31,a2_c30,a2_s32,a2_s31,a2_s30,a2_c29,a2_c28,a2_c27,a2_c26,a2_s29,a2_s28,a2_s27,a2_s26,a2_c25,a2_c24,a2_c23,a2_c22,a2_s25,a2_s24,a2_s23,a2_s22,a2_c21,a2_c20,a2_c19,a2_c18,a2_s21,a2_s20,a2_s19,a2_s18,a2_c17,a2_c16,a2_c15,a2_c14,a2_s17,a2_s16,a2_s15,a2_s14,a2_c13,a2_c12,a2_c11,a2_c10,a2_s13,a2_s12,a2_s11,a2_s10,a2_c9,a2_c8,a2_c7,a2_c6,a2_s9,a2_s8,a2_s7,a2_s6,a2_c5,a2_c4,a2_c3,a2_s5,a2_s4,a2_s3,a2_c2,a2_c1,a2_s2,a2_s1,a2_c0,a2_s0};
reg [136:0] cut2_b;
always @(posedge i_clk) cut2_b <= {b2_c60,b1_c89,b1_c88,b2_s60,b2_c59,b2_c58,b2_c57,t24_1_payload[8],b1_s89,b2_s59,b2_s58,b2_s57,b2_c56,b2_c55,b2_c54,b2_c53,b2_c52,t24_1_payload[7],b2_s56,b2_s55,b2_s54,b2_s53,b2_s52,b2_c51,b2_c50,b2_c49,b2_c48,b2_c47,b2_c46,b2_c45,t24_1_payload[6],b2_s51,b2_s50,b2_s49,b2_s48,b2_s47,b2_s46,b2_s45,b2_c44,b2_c43,b2_c42,b2_c41,b2_c40,b2_c39,b2_c38,t24_1_payload[5],b2_s44,b2_s43,b2_s42,b2_s41,b2_s40,b2_s39,b2_s38,b2_c37,b2_c36,b2_c35,b2_c34,b2_c33,b2_c32,b2_c31,t24_1_payload[4],b2_s37,b2_s36,b2_s35,b2_s34,b2_s33,b2_s32,b2_s31,b2_c30,b2_c29,b2_c28,b2_c27,b2_c26,b2_c25,b2_c24,t24_1_payload[3],b2_s30,b2_s29,b2_s28,b2_s27,b2_s26,b2_s25,b2_s24,b2_c23,b2_c22,b2_c21,b2_c20,b2_c19,b2_c18,b2_c17,t24_1_payload[2],b2_s23,b2_s22,b2_s21,b2_s20,b2_s19,b2_s18,b2_s17,b2_c16,b2_c15,b2_c14,b2_c13,b2_c12,b2_c11,b2_c10,t24_1_payload[1],b2_s16,b2_s15,b2_s14,b2_s13,b2_s12,b2_s11,b2_s10,b2_c9,b2_c8,b2_c7,b2_c6,b2_c5,t24_1_payload[0],t24_0_payload[2],b2_s9,b2_s8,b2_s7,b2_s6,b2_s5,b2_c4,b2_c3,b2_c2,t24_0_payload[1],b1_s9,b2_s4,b2_s3,b2_s2,b2_c1,b2_c0,b2_s1,b2_s0};
reg cut2_mode;
always @(posedge i_clk) cut2_mode <= compact_high_shift;
wire a3_s0, a3_c0;
csa_fa u_a3_fa0 (.a(cut2_a[1]), .b(cut2_a[2]), .ci(cut2_a[3]), .s(a3_s0), .co(a3_c0));
wire a3_s1, a3_c1;
csa_fa u_a3_fa1 (.a(cut2_a[4]), .b(cut2_a[5]), .ci(cut2_a[6]), .s(a3_s1), .co(a3_c1));
wire a3_s2, a3_c2;
csa_fa u_a3_fa2 (.a(cut2_a[9]), .b(cut2_a[10]), .ci(cut2_a[11]), .s(a3_s2), .co(a3_c2));
wire a3_s3, a3_c3;
csa_fa u_a3_fa3 (.a(cut2_a[12]), .b(cut2_a[13]), .ci(cut2_a[14]), .s(a3_s3), .co(a3_c3));
wire a3_s4, a3_c4;
csa_fa u_a3_fa4 (.a(cut2_a[16]), .b(cut2_a[17]), .ci(cut2_a[18]), .s(a3_s4), .co(a3_c4));
wire a3_s5, a3_c5;
csa_fa u_a3_fa5 (.a(cut2_a[19]), .b(cut2_a[20]), .ci(cut2_a[21]), .s(a3_s5), .co(a3_c5));
wire a3_s6, a3_c6;
csa_fa u_a3_fa6 (.a(cut2_a[24]), .b(cut2_a[25]), .ci(cut2_a[26]), .s(a3_s6), .co(a3_c6));
wire a3_s7, a3_c7;
csa_fa u_a3_fa7 (.a(cut2_a[27]), .b(cut2_a[28]), .ci(cut2_a[29]), .s(a3_s7), .co(a3_c7));
wire a3_s8, a3_c8;
csa_fa u_a3_fa8 (.a(cut2_a[32]), .b(cut2_a[33]), .ci(cut2_a[34]), .s(a3_s8), .co(a3_c8));
wire a3_s9, a3_c9;
csa_fa u_a3_fa9 (.a(cut2_a[35]), .b(cut2_a[36]), .ci(cut2_a[37]), .s(a3_s9), .co(a3_c9));
wire a3_s10, a3_c10;
csa_fa u_a3_fa10 (.a(cut2_a[40]), .b(cut2_a[41]), .ci(cut2_a[42]), .s(a3_s10), .co(a3_c10));
wire a3_s11, a3_c11;
csa_fa u_a3_fa11 (.a(cut2_a[43]), .b(cut2_a[44]), .ci(cut2_a[45]), .s(a3_s11), .co(a3_c11));
wire a3_s12, a3_c12;
csa_fa u_a3_fa12 (.a(cut2_a[48]), .b(cut2_a[49]), .ci(cut2_a[50]), .s(a3_s12), .co(a3_c12));
wire a3_s13, a3_c13;
csa_fa u_a3_fa13 (.a(cut2_a[51]), .b(cut2_a[52]), .ci(cut2_a[53]), .s(a3_s13), .co(a3_c13));
wire a3_s14, a3_c14;
csa_fa u_a3_fa14 (.a(cut2_a[56]), .b(cut2_a[57]), .ci(cut2_a[58]), .s(a3_s14), .co(a3_c14));
wire a3_s15, a3_c15;
csa_fa u_a3_fa15 (.a(cut2_a[59]), .b(cut2_a[60]), .ci(cut2_a[61]), .s(a3_s15), .co(a3_c15));
wire a3_s16, a3_c16;
csa_fa u_a3_fa16 (.a(cut2_a[63]), .b(cut2_a[64]), .ci(cut2_a[65]), .s(a3_s16), .co(a3_c16));
wire a3_s17, a3_c17;
csa_fa u_a3_fa17 (.a(cut2_a[68]), .b(cut2_a[69]), .ci(cut2_a[70]), .s(a3_s17), .co(a3_c17));
// a3: 18 full adders; 54 live bits; column heights 1,1,4,4,6,6,6,6,6,5,5,2,2,0,0,0,0,0,0,0,0
wire b3_s0, b3_c0;
csa_fa u_b3_fa0 (.a(cut2_b[2]), .b(cut2_b[3]), .ci(cut2_b[4]), .s(b3_s0), .co(b3_c0));
wire b3_s1, b3_c1;
csa_fa u_b3_fa1 (.a(cut2_b[5]), .b(cut2_b[6]), .ci(cut2_b[7]), .s(b3_s1), .co(b3_c1));
wire b3_s2, b3_c2;
csa_fa u_b3_fa2 (.a(cut2_b[9]), .b(cut2_b[10]), .ci(cut2_b[11]), .s(b3_s2), .co(b3_c2));
wire b3_s3, b3_c3;
csa_fa u_b3_fa3 (.a(cut2_b[12]), .b(cut2_b[13]), .ci(cut2_b[14]), .s(b3_s3), .co(b3_c3));
wire b3_s4, b3_c4;
csa_fa u_b3_fa4 (.a(cut2_b[15]), .b(cut2_b[16]), .ci(cut2_b[17]), .s(b3_s4), .co(b3_c4));
wire b3_s5, b3_c5;
csa_fa u_b3_fa5 (.a(cut2_b[19]), .b(cut2_b[20]), .ci(cut2_b[21]), .s(b3_s5), .co(b3_c5));
wire b3_s6, b3_c6;
csa_fa u_b3_fa6 (.a(cut2_b[22]), .b(cut2_b[23]), .ci(cut2_b[24]), .s(b3_s6), .co(b3_c6));
wire b3_s7, b3_c7;
csa_fa u_b3_fa7 (.a(cut2_b[25]), .b(cut2_b[26]), .ci(cut2_b[27]), .s(b3_s7), .co(b3_c7));
wire b3_s8, b3_c8;
csa_fa u_b3_fa8 (.a(cut2_b[28]), .b(cut2_b[29]), .ci(cut2_b[30]), .s(b3_s8), .co(b3_c8));
wire b3_s9, b3_c9;
csa_fa u_b3_fa9 (.a(cut2_b[32]), .b(cut2_b[33]), .ci(cut2_b[34]), .s(b3_s9), .co(b3_c9));
wire b3_s10, b3_c10;
csa_fa u_b3_fa10 (.a(cut2_b[35]), .b(cut2_b[36]), .ci(cut2_b[37]), .s(b3_s10), .co(b3_c10));
wire b3_s11, b3_c11;
csa_fa u_b3_fa11 (.a(cut2_b[38]), .b(cut2_b[39]), .ci(cut2_b[40]), .s(b3_s11), .co(b3_c11));
wire b3_s12, b3_c12;
csa_fa u_b3_fa12 (.a(cut2_b[41]), .b(cut2_b[42]), .ci(cut2_b[43]), .s(b3_s12), .co(b3_c12));
wire b3_s13, b3_c13;
csa_fa u_b3_fa13 (.a(cut2_b[44]), .b(cut2_b[45]), .ci(cut2_b[46]), .s(b3_s13), .co(b3_c13));
wire b3_s14, b3_c14;
csa_fa u_b3_fa14 (.a(cut2_b[47]), .b(cut2_b[48]), .ci(cut2_b[49]), .s(b3_s14), .co(b3_c14));
wire b3_s15, b3_c15;
csa_fa u_b3_fa15 (.a(cut2_b[50]), .b(cut2_b[51]), .ci(cut2_b[52]), .s(b3_s15), .co(b3_c15));
wire b3_s16, b3_c16;
csa_fa u_b3_fa16 (.a(cut2_b[53]), .b(cut2_b[54]), .ci(cut2_b[55]), .s(b3_s16), .co(b3_c16));
wire b3_s17, b3_c17;
csa_fa u_b3_fa17 (.a(cut2_b[56]), .b(cut2_b[57]), .ci(cut2_b[58]), .s(b3_s17), .co(b3_c17));
wire b3_s18, b3_c18;
csa_fa u_b3_fa18 (.a(cut2_b[59]), .b(cut2_b[60]), .ci(cut2_b[61]), .s(b3_s18), .co(b3_c18));
wire b3_s19, b3_c19;
csa_fa u_b3_fa19 (.a(cut2_b[62]), .b(cut2_b[63]), .ci(cut2_b[64]), .s(b3_s19), .co(b3_c19));
wire b3_s20, b3_c20;
csa_fa u_b3_fa20 (.a(cut2_b[65]), .b(cut2_b[66]), .ci(cut2_b[67]), .s(b3_s20), .co(b3_c20));
wire b3_s21, b3_c21;
csa_fa u_b3_fa21 (.a(cut2_b[68]), .b(cut2_b[69]), .ci(cut2_b[70]), .s(b3_s21), .co(b3_c21));
wire b3_s22, b3_c22;
csa_fa u_b3_fa22 (.a(cut2_b[71]), .b(cut2_b[72]), .ci(cut2_b[73]), .s(b3_s22), .co(b3_c22));
wire b3_s23, b3_c23;
csa_fa u_b3_fa23 (.a(cut2_b[74]), .b(cut2_b[75]), .ci(cut2_b[76]), .s(b3_s23), .co(b3_c23));
wire b3_s24, b3_c24;
csa_fa u_b3_fa24 (.a(cut2_b[77]), .b(cut2_b[78]), .ci(cut2_b[79]), .s(b3_s24), .co(b3_c24));
wire b3_s25, b3_c25;
csa_fa u_b3_fa25 (.a(cut2_b[80]), .b(cut2_b[81]), .ci(cut2_b[82]), .s(b3_s25), .co(b3_c25));
wire b3_s26, b3_c26;
csa_fa u_b3_fa26 (.a(cut2_b[83]), .b(cut2_b[84]), .ci(cut2_b[85]), .s(b3_s26), .co(b3_c26));
wire b3_s27, b3_c27;
csa_fa u_b3_fa27 (.a(cut2_b[86]), .b(cut2_b[87]), .ci(cut2_b[88]), .s(b3_s27), .co(b3_c27));
wire b3_s28, b3_c28;
csa_fa u_b3_fa28 (.a(cut2_b[89]), .b(cut2_b[90]), .ci(cut2_b[91]), .s(b3_s28), .co(b3_c28));
wire b3_s29, b3_c29;
csa_fa u_b3_fa29 (.a(cut2_b[92]), .b(cut2_b[93]), .ci(cut2_b[94]), .s(b3_s29), .co(b3_c29));
wire b3_s30, b3_c30;
csa_fa u_b3_fa30 (.a(cut2_b[95]), .b(cut2_b[96]), .ci(cut2_b[97]), .s(b3_s30), .co(b3_c30));
wire b3_s31, b3_c31;
csa_fa u_b3_fa31 (.a(cut2_b[98]), .b(cut2_b[99]), .ci(cut2_b[100]), .s(b3_s31), .co(b3_c31));
wire b3_s32, b3_c32;
csa_fa u_b3_fa32 (.a(cut2_b[101]), .b(cut2_b[102]), .ci(cut2_b[103]), .s(b3_s32), .co(b3_c32));
wire b3_s33, b3_c33;
csa_fa u_b3_fa33 (.a(cut2_b[104]), .b(cut2_b[105]), .ci(cut2_b[106]), .s(b3_s33), .co(b3_c33));
wire b3_s34, b3_c34;
csa_fa u_b3_fa34 (.a(cut2_b[107]), .b(cut2_b[108]), .ci(cut2_b[109]), .s(b3_s34), .co(b3_c34));
wire b3_s35, b3_c35;
csa_fa u_b3_fa35 (.a(cut2_b[110]), .b(cut2_b[111]), .ci(cut2_b[112]), .s(b3_s35), .co(b3_c35));
wire b3_s36, b3_c36;
csa_fa u_b3_fa36 (.a(cut2_b[113]), .b(cut2_b[114]), .ci(cut2_b[115]), .s(b3_s36), .co(b3_c36));
wire b3_s37, b3_c37;
csa_fa u_b3_fa37 (.a(cut2_b[116]), .b(cut2_b[117]), .ci(cut2_b[118]), .s(b3_s37), .co(b3_c37));
wire b3_s38, b3_c38;
csa_fa u_b3_fa38 (.a(cut2_b[120]), .b(cut2_b[121]), .ci(cut2_b[122]), .s(b3_s38), .co(b3_c38));
wire b3_s39, b3_c39;
csa_fa u_b3_fa39 (.a(cut2_b[123]), .b(cut2_b[124]), .ci(cut2_b[125]), .s(b3_s39), .co(b3_c39));
wire b3_s40, b3_c40;
csa_fa u_b3_fa40 (.a(cut2_b[126]), .b(cut2_b[127]), .ci(cut2_b[128]), .s(b3_s40), .co(b3_c40));
wire b3_s41, b3_c41;
csa_fa u_b3_fa41 (.a(cut2_b[130]), .b(cut2_b[131]), .ci(cut2_b[132]), .s(b3_s41), .co(b3_c41));
wire b3_s42, b3_c42;
csa_fa u_b3_fa42 (.a(cut2_b[133]), .b(cut2_b[134]), .ci(cut2_b[135]), .s(b3_s42), .co(b3_c42));
// b3: 43 full adders; 94 live bits; column heights 2,3,6,8,9,10,10,10,10,10,8,5,3,0,0,0,0,0,0,0,0
wire route0_0;
assign route0_0 = cut2_mode ? 1'b0 : cut2_a[0];
wire route1_0;
assign route1_0 = cut2_mode ? 1'b0 : a3_s0;
wire route2_0;
assign route2_0 = cut2_mode ? 1'b0 : a3_c0;
wire route2_1;
assign route2_1 = cut2_mode ? 1'b0 : a3_s1;
wire route2_2;
assign route2_2 = cut2_mode ? 1'b0 : cut2_a[7];
wire route2_3;
assign route2_3 = cut2_mode ? 1'b0 : cut2_a[8];
wire route3_0;
assign route3_0 = cut2_mode ? 1'b0 : a3_c1;
wire route3_1;
assign route3_1 = cut2_mode ? 1'b0 : a3_s2;
wire route3_2;
assign route3_2 = cut2_mode ? 1'b0 : a3_s3;
wire route3_3;
assign route3_3 = cut2_mode ? 1'b0 : cut2_a[15];
wire route4_0;
assign route4_0 = cut2_mode ? cut2_a[0] : a3_c2;
wire route4_1;
assign route4_1 = cut2_mode ? 1'b0 : a3_c3;
wire route4_2;
assign route4_2 = cut2_mode ? 1'b0 : a3_s4;
wire route4_3;
assign route4_3 = cut2_mode ? 1'b0 : a3_s5;
wire route4_4;
assign route4_4 = cut2_mode ? 1'b0 : cut2_a[22];
wire route4_5;
assign route4_5 = cut2_mode ? 1'b0 : cut2_a[23];
wire route5_0;
assign route5_0 = cut2_mode ? a3_s0 : a3_c4;
wire route5_1;
assign route5_1 = cut2_mode ? 1'b0 : a3_c5;
wire route5_2;
assign route5_2 = cut2_mode ? 1'b0 : a3_s6;
wire route5_3;
assign route5_3 = cut2_mode ? 1'b0 : a3_s7;
wire route5_4;
assign route5_4 = cut2_mode ? 1'b0 : cut2_a[30];
wire route5_5;
assign route5_5 = cut2_mode ? 1'b0 : cut2_a[31];
wire route6_0;
assign route6_0 = cut2_mode ? a3_c0 : a3_c6;
wire route6_1;
assign route6_1 = cut2_mode ? a3_s1 : a3_c7;
wire route6_2;
assign route6_2 = cut2_mode ? cut2_a[7] : a3_s8;
wire route6_3;
assign route6_3 = cut2_mode ? cut2_a[8] : a3_s9;
wire route6_4;
assign route6_4 = cut2_mode ? 1'b0 : cut2_a[38];
wire route6_5;
assign route6_5 = cut2_mode ? 1'b0 : cut2_a[39];
wire route7_0;
assign route7_0 = cut2_mode ? a3_c1 : a3_c8;
wire route7_1;
assign route7_1 = cut2_mode ? a3_s2 : a3_c9;
wire route7_2;
assign route7_2 = cut2_mode ? a3_s3 : a3_s10;
wire route7_3;
assign route7_3 = cut2_mode ? cut2_a[15] : a3_s11;
wire route7_4;
assign route7_4 = cut2_mode ? 1'b0 : cut2_a[46];
wire route7_5;
assign route7_5 = cut2_mode ? 1'b0 : cut2_a[47];
wire route8_0;
assign route8_0 = cut2_mode ? a3_c2 : a3_c10;
wire route8_1;
assign route8_1 = cut2_mode ? a3_c3 : a3_c11;
wire route8_2;
assign route8_2 = cut2_mode ? a3_s4 : a3_s12;
wire route8_3;
assign route8_3 = cut2_mode ? a3_s5 : a3_s13;
wire route8_4;
assign route8_4 = cut2_mode ? cut2_a[22] : cut2_a[54];
wire route8_5;
assign route8_5 = cut2_mode ? cut2_a[23] : cut2_a[55];
wire route9_0;
assign route9_0 = cut2_mode ? a3_c4 : a3_c12;
wire route9_1;
assign route9_1 = cut2_mode ? a3_c5 : a3_c13;
wire route9_2;
assign route9_2 = cut2_mode ? a3_s6 : a3_s14;
wire route9_3;
assign route9_3 = cut2_mode ? a3_s7 : a3_s15;
wire route9_4;
assign route9_4 = cut2_mode ? cut2_a[30] : cut2_a[62];
wire route9_5;
assign route9_5 = cut2_mode ? cut2_a[31] : 1'b0;
wire route10_0;
assign route10_0 = cut2_mode ? a3_c6 : a3_c14;
wire route10_1;
assign route10_1 = cut2_mode ? a3_c7 : a3_c15;
wire route10_2;
assign route10_2 = cut2_mode ? a3_s8 : a3_s16;
wire route10_3;
assign route10_3 = cut2_mode ? a3_s9 : cut2_a[66];
wire route10_4;
assign route10_4 = cut2_mode ? cut2_a[38] : cut2_a[67];
wire route10_5;
assign route10_5 = cut2_mode ? cut2_a[39] : 1'b0;
wire route11_0;
assign route11_0 = cut2_mode ? a3_c8 : a3_c16;
wire route11_1;
assign route11_1 = cut2_mode ? a3_c9 : a3_s17;
wire route11_2;
assign route11_2 = cut2_mode ? a3_s10 : 1'b0;
wire route11_3;
assign route11_3 = cut2_mode ? a3_s11 : 1'b0;
wire route11_4;
assign route11_4 = cut2_mode ? cut2_a[46] : 1'b0;
wire route11_5;
assign route11_5 = cut2_mode ? cut2_a[47] : 1'b0;
wire route12_0;
assign route12_0 = cut2_mode ? a3_c10 : a3_c17;
wire route12_1;
assign route12_1 = cut2_mode ? a3_c11 : cut2_a[71];
wire route12_2;
assign route12_2 = cut2_mode ? a3_s12 : 1'b0;
wire route12_3;
assign route12_3 = cut2_mode ? a3_s13 : 1'b0;
wire route12_4;
assign route12_4 = cut2_mode ? cut2_a[54] : 1'b0;
wire route12_5;
assign route12_5 = cut2_mode ? cut2_a[55] : 1'b0;
wire route13_0;
assign route13_0 = cut2_mode ? a3_c12 : 1'b0;
wire route13_1;
assign route13_1 = cut2_mode ? a3_c13 : 1'b0;
wire route13_2;
assign route13_2 = cut2_mode ? a3_s14 : 1'b0;
wire route13_3;
assign route13_3 = cut2_mode ? a3_s15 : 1'b0;
wire route13_4;
assign route13_4 = cut2_mode ? cut2_a[62] : 1'b0;
wire route14_0;
assign route14_0 = cut2_mode ? a3_c14 : 1'b0;
wire route14_1;
assign route14_1 = cut2_mode ? a3_c15 : 1'b0;
wire route14_2;
assign route14_2 = cut2_mode ? a3_s16 : 1'b0;
wire route14_3;
assign route14_3 = cut2_mode ? cut2_a[66] : 1'b0;
wire route14_4;
assign route14_4 = cut2_mode ? cut2_a[67] : 1'b0;
wire route15_0;
assign route15_0 = cut2_mode ? a3_c16 : 1'b0;
wire route15_1;
assign route15_1 = cut2_mode ? a3_s17 : 1'b0;
wire route16_0;
assign route16_0 = cut2_mode ? a3_c17 : 1'b0;
wire route16_1;
assign route16_1 = cut2_mode ? cut2_a[71] : 1'b0;
wire l4_s0, l4_c0;
csa_fa u_l4_fa0 (.a(route0_0), .b(cut2_b[0]), .ci(cut2_b[1]), .s(l4_s0), .co(l4_c0));
wire l4_s1, l4_c1;
csa_fa u_l4_fa1 (.a(route1_0), .b(b3_s0), .ci(b3_s1), .s(l4_s1), .co(l4_c1));
wire l4_s2, l4_c2;
csa_fa u_l4_fa2 (.a(route2_0), .b(route2_1), .ci(route2_2), .s(l4_s2), .co(l4_c2));
wire l4_s3, l4_c3;
csa_fa u_l4_fa3 (.a(route2_3), .b(b3_c0), .ci(b3_c1), .s(l4_s3), .co(l4_c3));
wire l4_s4, l4_c4;
csa_fa u_l4_fa4 (.a(b3_s2), .b(b3_s3), .ci(b3_s4), .s(l4_s4), .co(l4_c4));
wire l4_s5, l4_c5;
csa_fa u_l4_fa5 (.a(route3_0), .b(route3_1), .ci(route3_2), .s(l4_s5), .co(l4_c5));
wire l4_s6, l4_c6;
csa_fa u_l4_fa6 (.a(route3_3), .b(b3_c2), .ci(b3_c3), .s(l4_s6), .co(l4_c6));
wire l4_s7, l4_c7;
csa_fa u_l4_fa7 (.a(b3_c4), .b(b3_s5), .ci(b3_s6), .s(l4_s7), .co(l4_c7));
wire l4_s8, l4_c8;
csa_fa u_l4_fa8 (.a(b3_s7), .b(b3_s8), .ci(cut2_b[31]), .s(l4_s8), .co(l4_c8));
wire l4_s9, l4_c9;
csa_fa u_l4_fa9 (.a(route4_0), .b(route4_1), .ci(route4_2), .s(l4_s9), .co(l4_c9));
wire l4_s10, l4_c10;
csa_fa u_l4_fa10 (.a(route4_3), .b(route4_4), .ci(route4_5), .s(l4_s10), .co(l4_c10));
wire l4_s11, l4_c11;
csa_fa u_l4_fa11 (.a(b3_c5), .b(b3_c6), .ci(b3_c7), .s(l4_s11), .co(l4_c11));
wire l4_s12, l4_c12;
csa_fa u_l4_fa12 (.a(b3_c8), .b(b3_s9), .ci(b3_s10), .s(l4_s12), .co(l4_c12));
wire l4_s13, l4_c13;
csa_fa u_l4_fa13 (.a(b3_s11), .b(b3_s12), .ci(b3_s13), .s(l4_s13), .co(l4_c13));
wire l4_s14, l4_c14;
csa_fa u_l4_fa14 (.a(route5_0), .b(route5_1), .ci(route5_2), .s(l4_s14), .co(l4_c14));
wire l4_s15, l4_c15;
csa_fa u_l4_fa15 (.a(route5_3), .b(route5_4), .ci(route5_5), .s(l4_s15), .co(l4_c15));
wire l4_s16, l4_c16;
csa_fa u_l4_fa16 (.a(b3_c9), .b(b3_c10), .ci(b3_c11), .s(l4_s16), .co(l4_c16));
wire l4_s17, l4_c17;
csa_fa u_l4_fa17 (.a(b3_c12), .b(b3_c13), .ci(b3_s14), .s(l4_s17), .co(l4_c17));
wire l4_s18, l4_c18;
csa_fa u_l4_fa18 (.a(b3_s15), .b(b3_s16), .ci(b3_s17), .s(l4_s18), .co(l4_c18));
wire l4_s19, l4_c19;
csa_fa u_l4_fa19 (.a(route6_0), .b(route6_1), .ci(route6_2), .s(l4_s19), .co(l4_c19));
wire l4_s20, l4_c20;
csa_fa u_l4_fa20 (.a(route6_3), .b(route6_4), .ci(route6_5), .s(l4_s20), .co(l4_c20));
wire l4_s21, l4_c21;
csa_fa u_l4_fa21 (.a(b3_c14), .b(b3_c15), .ci(b3_c16), .s(l4_s21), .co(l4_c21));
wire l4_s22, l4_c22;
csa_fa u_l4_fa22 (.a(b3_c17), .b(b3_c18), .ci(b3_s19), .s(l4_s22), .co(l4_c22));
wire l4_s23, l4_c23;
csa_fa u_l4_fa23 (.a(b3_s20), .b(b3_s21), .ci(b3_s22), .s(l4_s23), .co(l4_c23));
wire l4_s24, l4_c24;
csa_fa u_l4_fa24 (.a(route7_0), .b(route7_1), .ci(route7_2), .s(l4_s24), .co(l4_c24));
wire l4_s25, l4_c25;
csa_fa u_l4_fa25 (.a(route7_3), .b(route7_4), .ci(route7_5), .s(l4_s25), .co(l4_c25));
wire l4_s26, l4_c26;
csa_fa u_l4_fa26 (.a(b3_c19), .b(b3_c20), .ci(b3_c21), .s(l4_s26), .co(l4_c26));
wire l4_s27, l4_c27;
csa_fa u_l4_fa27 (.a(b3_c22), .b(b3_c23), .ci(b3_s24), .s(l4_s27), .co(l4_c27));
wire l4_s28, l4_c28;
csa_fa u_l4_fa28 (.a(b3_s25), .b(b3_s26), .ci(b3_s27), .s(l4_s28), .co(l4_c28));
wire l4_s29, l4_c29;
csa_fa u_l4_fa29 (.a(route8_0), .b(route8_1), .ci(route8_2), .s(l4_s29), .co(l4_c29));
wire l4_s30, l4_c30;
csa_fa u_l4_fa30 (.a(route8_3), .b(route8_4), .ci(route8_5), .s(l4_s30), .co(l4_c30));
wire l4_s31, l4_c31;
csa_fa u_l4_fa31 (.a(b3_c24), .b(b3_c25), .ci(b3_c26), .s(l4_s31), .co(l4_c31));
wire l4_s32, l4_c32;
csa_fa u_l4_fa32 (.a(b3_c27), .b(b3_c28), .ci(b3_s29), .s(l4_s32), .co(l4_c32));
wire l4_s33, l4_c33;
csa_fa u_l4_fa33 (.a(b3_s30), .b(b3_s31), .ci(b3_s32), .s(l4_s33), .co(l4_c33));
wire l4_s34, l4_c34;
csa_fa u_l4_fa34 (.a(route9_0), .b(route9_1), .ci(route9_2), .s(l4_s34), .co(l4_c34));
wire l4_s35, l4_c35;
csa_fa u_l4_fa35 (.a(route9_3), .b(route9_4), .ci(route9_5), .s(l4_s35), .co(l4_c35));
wire l4_s36, l4_c36;
csa_fa u_l4_fa36 (.a(b3_c29), .b(b3_c30), .ci(b3_c31), .s(l4_s36), .co(l4_c36));
wire l4_s37, l4_c37;
csa_fa u_l4_fa37 (.a(b3_c32), .b(b3_c33), .ci(b3_s34), .s(l4_s37), .co(l4_c37));
wire l4_s38, l4_c38;
csa_fa u_l4_fa38 (.a(b3_s35), .b(b3_s36), .ci(b3_s37), .s(l4_s38), .co(l4_c38));
wire l4_s39, l4_c39;
csa_fa u_l4_fa39 (.a(route10_0), .b(route10_1), .ci(route10_2), .s(l4_s39), .co(l4_c39));
wire l4_s40, l4_c40;
csa_fa u_l4_fa40 (.a(route10_3), .b(route10_4), .ci(route10_5), .s(l4_s40), .co(l4_c40));
wire l4_s41, l4_c41;
csa_fa u_l4_fa41 (.a(b3_c34), .b(b3_c35), .ci(b3_c36), .s(l4_s41), .co(l4_c41));
wire l4_s42, l4_c42;
csa_fa u_l4_fa42 (.a(b3_c37), .b(b3_s38), .ci(b3_s39), .s(l4_s42), .co(l4_c42));
wire l4_s43, l4_c43;
csa_fa u_l4_fa43 (.a(route11_0), .b(route11_1), .ci(route11_2), .s(l4_s43), .co(l4_c43));
wire l4_s44, l4_c44;
csa_fa u_l4_fa44 (.a(route11_3), .b(route11_4), .ci(route11_5), .s(l4_s44), .co(l4_c44));
wire l4_s45, l4_c45;
csa_fa u_l4_fa45 (.a(b3_c38), .b(b3_c39), .ci(b3_c40), .s(l4_s45), .co(l4_c45));
wire l4_s46, l4_c46;
csa_fa u_l4_fa46 (.a(route12_0), .b(route12_1), .ci(route12_2), .s(l4_s46), .co(l4_c46));
wire l4_s47, l4_c47;
csa_fa u_l4_fa47 (.a(route12_3), .b(route12_4), .ci(route12_5), .s(l4_s47), .co(l4_c47));
wire l4_s48, l4_c48;
csa_fa u_l4_fa48 (.a(b3_c41), .b(b3_c42), .ci(cut2_b[136]), .s(l4_s48), .co(l4_c48));
wire l4_s49, l4_c49;
csa_fa u_l4_fa49 (.a(route13_0), .b(route13_1), .ci(route13_2), .s(l4_s49), .co(l4_c49));
wire l4_s50, l4_c50;
csa_fa u_l4_fa50 (.a(route14_0), .b(route14_1), .ci(route14_2), .s(l4_s50), .co(l4_c50));
// l4: 51 full adders; 121 live bits; column heights 1,3,5,7,9,11,11,11,11,11,11,9,6,6,4,3,2,0,0,0,0
reg [120:0] cut4;
always @(posedge i_clk) cut4 <= {route16_1,route16_0,route15_1,route15_0,l4_c50,route14_4,route14_3,l4_s50,l4_c49,route13_4,route13_3,l4_s49,l4_c48,l4_c47,l4_c46,l4_s48,l4_s47,l4_s46,l4_c45,l4_c44,l4_c43,b3_s42,b3_s41,l4_s45,l4_s44,l4_s43,l4_c42,l4_c41,l4_c40,l4_c39,cut2_b[129],b3_s40,l4_s42,l4_s41,l4_s40,l4_s39,l4_c38,l4_c37,l4_c36,l4_c35,l4_c34,cut2_b[119],l4_s38,l4_s37,l4_s36,l4_s35,l4_s34,l4_c33,l4_c32,l4_c31,l4_c30,l4_c29,b3_s33,l4_s33,l4_s32,l4_s31,l4_s30,l4_s29,l4_c28,l4_c27,l4_c26,l4_c25,l4_c24,b3_s28,l4_s28,l4_s27,l4_s26,l4_s25,l4_s24,l4_c23,l4_c22,l4_c21,l4_c20,l4_c19,b3_s23,l4_s23,l4_s22,l4_s21,l4_s20,l4_s19,l4_c18,l4_c17,l4_c16,l4_c15,l4_c14,b3_s18,l4_s18,l4_s17,l4_s16,l4_s15,l4_s14,l4_c13,l4_c12,l4_c11,l4_c10,l4_c9,l4_s13,l4_s12,l4_s11,l4_s10,l4_s9,l4_c8,l4_c7,l4_c6,l4_c5,l4_s8,l4_s7,l4_s6,l4_s5,l4_c4,l4_c3,l4_c2,cut2_b[18],l4_s4,l4_s3,l4_s2,l4_c1,cut2_b[8],l4_s1,l4_c0,l4_s0};
wire l5_s0, l5_c0;
csa_fa u_l5_fa0 (.a(cut4[1]), .b(cut4[2]), .ci(cut4[3]), .s(l5_s0), .co(l5_c0));
wire l5_s1, l5_c1;
csa_fa u_l5_fa1 (.a(cut4[4]), .b(cut4[5]), .ci(cut4[6]), .s(l5_s1), .co(l5_c1));
wire l5_s2, l5_c2;
csa_fa u_l5_fa2 (.a(cut4[9]), .b(cut4[10]), .ci(cut4[11]), .s(l5_s2), .co(l5_c2));
wire l5_s3, l5_c3;
csa_fa u_l5_fa3 (.a(cut4[12]), .b(cut4[13]), .ci(cut4[14]), .s(l5_s3), .co(l5_c3));
wire l5_s4, l5_c4;
csa_fa u_l5_fa4 (.a(cut4[16]), .b(cut4[17]), .ci(cut4[18]), .s(l5_s4), .co(l5_c4));
wire l5_s5, l5_c5;
csa_fa u_l5_fa5 (.a(cut4[19]), .b(cut4[20]), .ci(cut4[21]), .s(l5_s5), .co(l5_c5));
wire l5_s6, l5_c6;
csa_fa u_l5_fa6 (.a(cut4[22]), .b(cut4[23]), .ci(cut4[24]), .s(l5_s6), .co(l5_c6));
wire l5_s7, l5_c7;
csa_fa u_l5_fa7 (.a(cut4[25]), .b(cut4[26]), .ci(cut4[27]), .s(l5_s7), .co(l5_c7));
wire l5_s8, l5_c8;
csa_fa u_l5_fa8 (.a(cut4[28]), .b(cut4[29]), .ci(cut4[30]), .s(l5_s8), .co(l5_c8));
wire l5_s9, l5_c9;
csa_fa u_l5_fa9 (.a(cut4[31]), .b(cut4[32]), .ci(cut4[33]), .s(l5_s9), .co(l5_c9));
wire l5_s10, l5_c10;
csa_fa u_l5_fa10 (.a(cut4[36]), .b(cut4[37]), .ci(cut4[38]), .s(l5_s10), .co(l5_c10));
wire l5_s11, l5_c11;
csa_fa u_l5_fa11 (.a(cut4[39]), .b(cut4[40]), .ci(cut4[41]), .s(l5_s11), .co(l5_c11));
wire l5_s12, l5_c12;
csa_fa u_l5_fa12 (.a(cut4[42]), .b(cut4[43]), .ci(cut4[44]), .s(l5_s12), .co(l5_c12));
wire l5_s13, l5_c13;
csa_fa u_l5_fa13 (.a(cut4[47]), .b(cut4[48]), .ci(cut4[49]), .s(l5_s13), .co(l5_c13));
wire l5_s14, l5_c14;
csa_fa u_l5_fa14 (.a(cut4[50]), .b(cut4[51]), .ci(cut4[52]), .s(l5_s14), .co(l5_c14));
wire l5_s15, l5_c15;
csa_fa u_l5_fa15 (.a(cut4[53]), .b(cut4[54]), .ci(cut4[55]), .s(l5_s15), .co(l5_c15));
wire l5_s16, l5_c16;
csa_fa u_l5_fa16 (.a(cut4[58]), .b(cut4[59]), .ci(cut4[60]), .s(l5_s16), .co(l5_c16));
wire l5_s17, l5_c17;
csa_fa u_l5_fa17 (.a(cut4[61]), .b(cut4[62]), .ci(cut4[63]), .s(l5_s17), .co(l5_c17));
wire l5_s18, l5_c18;
csa_fa u_l5_fa18 (.a(cut4[64]), .b(cut4[65]), .ci(cut4[66]), .s(l5_s18), .co(l5_c18));
wire l5_s19, l5_c19;
csa_fa u_l5_fa19 (.a(cut4[69]), .b(cut4[70]), .ci(cut4[71]), .s(l5_s19), .co(l5_c19));
wire l5_s20, l5_c20;
csa_fa u_l5_fa20 (.a(cut4[72]), .b(cut4[73]), .ci(cut4[74]), .s(l5_s20), .co(l5_c20));
wire l5_s21, l5_c21;
csa_fa u_l5_fa21 (.a(cut4[75]), .b(cut4[76]), .ci(cut4[77]), .s(l5_s21), .co(l5_c21));
wire l5_s22, l5_c22;
csa_fa u_l5_fa22 (.a(cut4[80]), .b(cut4[81]), .ci(cut4[82]), .s(l5_s22), .co(l5_c22));
wire l5_s23, l5_c23;
csa_fa u_l5_fa23 (.a(cut4[83]), .b(cut4[84]), .ci(cut4[85]), .s(l5_s23), .co(l5_c23));
wire l5_s24, l5_c24;
csa_fa u_l5_fa24 (.a(cut4[86]), .b(cut4[87]), .ci(cut4[88]), .s(l5_s24), .co(l5_c24));
wire l5_s25, l5_c25;
csa_fa u_l5_fa25 (.a(cut4[91]), .b(cut4[92]), .ci(cut4[93]), .s(l5_s25), .co(l5_c25));
wire l5_s26, l5_c26;
csa_fa u_l5_fa26 (.a(cut4[94]), .b(cut4[95]), .ci(cut4[96]), .s(l5_s26), .co(l5_c26));
wire l5_s27, l5_c27;
csa_fa u_l5_fa27 (.a(cut4[97]), .b(cut4[98]), .ci(cut4[99]), .s(l5_s27), .co(l5_c27));
wire l5_s28, l5_c28;
csa_fa u_l5_fa28 (.a(cut4[100]), .b(cut4[101]), .ci(cut4[102]), .s(l5_s28), .co(l5_c28));
wire l5_s29, l5_c29;
csa_fa u_l5_fa29 (.a(cut4[103]), .b(cut4[104]), .ci(cut4[105]), .s(l5_s29), .co(l5_c29));
wire l5_s30, l5_c30;
csa_fa u_l5_fa30 (.a(cut4[106]), .b(cut4[107]), .ci(cut4[108]), .s(l5_s30), .co(l5_c30));
wire l5_s31, l5_c31;
csa_fa u_l5_fa31 (.a(cut4[109]), .b(cut4[110]), .ci(cut4[111]), .s(l5_s31), .co(l5_c31));
wire l5_s32, l5_c32;
csa_fa u_l5_fa32 (.a(cut4[112]), .b(cut4[113]), .ci(cut4[114]), .s(l5_s32), .co(l5_c32));
wire l5_s33, l5_c33;
csa_fa u_l5_fa33 (.a(cut4[116]), .b(cut4[117]), .ci(cut4[118]), .s(l5_s33), .co(l5_c33));
// l5: 34 full adders; 87 live bits; column heights 1,1,4,4,5,8,8,8,8,8,8,6,5,4,4,2,3,0,0,0,0
wire l6_s0, l6_c0;
csa_fa u_l6_fa0 (.a(l5_c0), .b(l5_s1), .ci(cut4[7]), .s(l6_s0), .co(l6_c0));
wire l6_s1, l6_c1;
csa_fa u_l6_fa1 (.a(l5_c1), .b(l5_s2), .ci(l5_s3), .s(l6_s1), .co(l6_c1));
wire l6_s2, l6_c2;
csa_fa u_l6_fa2 (.a(l5_c2), .b(l5_c3), .ci(l5_s4), .s(l6_s2), .co(l6_c2));
wire l6_s3, l6_c3;
csa_fa u_l6_fa3 (.a(l5_c4), .b(l5_c5), .ci(l5_c6), .s(l6_s3), .co(l6_c3));
wire l6_s4, l6_c4;
csa_fa u_l6_fa4 (.a(l5_s7), .b(l5_s8), .ci(l5_s9), .s(l6_s4), .co(l6_c4));
wire l6_s5, l6_c5;
csa_fa u_l6_fa5 (.a(l5_c7), .b(l5_c8), .ci(l5_c9), .s(l6_s5), .co(l6_c5));
wire l6_s6, l6_c6;
csa_fa u_l6_fa6 (.a(l5_s10), .b(l5_s11), .ci(l5_s12), .s(l6_s6), .co(l6_c6));
wire l6_s7, l6_c7;
csa_fa u_l6_fa7 (.a(l5_c10), .b(l5_c11), .ci(l5_c12), .s(l6_s7), .co(l6_c7));
wire l6_s8, l6_c8;
csa_fa u_l6_fa8 (.a(l5_s13), .b(l5_s14), .ci(l5_s15), .s(l6_s8), .co(l6_c8));
wire l6_s9, l6_c9;
csa_fa u_l6_fa9 (.a(l5_c13), .b(l5_c14), .ci(l5_c15), .s(l6_s9), .co(l6_c9));
wire l6_s10, l6_c10;
csa_fa u_l6_fa10 (.a(l5_s16), .b(l5_s17), .ci(l5_s18), .s(l6_s10), .co(l6_c10));
wire l6_s11, l6_c11;
csa_fa u_l6_fa11 (.a(l5_c16), .b(l5_c17), .ci(l5_c18), .s(l6_s11), .co(l6_c11));
wire l6_s12, l6_c12;
csa_fa u_l6_fa12 (.a(l5_s19), .b(l5_s20), .ci(l5_s21), .s(l6_s12), .co(l6_c12));
wire l6_s13, l6_c13;
csa_fa u_l6_fa13 (.a(l5_c19), .b(l5_c20), .ci(l5_c21), .s(l6_s13), .co(l6_c13));
wire l6_s14, l6_c14;
csa_fa u_l6_fa14 (.a(l5_s22), .b(l5_s23), .ci(l5_s24), .s(l6_s14), .co(l6_c14));
wire l6_s15, l6_c15;
csa_fa u_l6_fa15 (.a(l5_c22), .b(l5_c23), .ci(l5_c24), .s(l6_s15), .co(l6_c15));
wire l6_s16, l6_c16;
csa_fa u_l6_fa16 (.a(l5_s25), .b(l5_s26), .ci(l5_s27), .s(l6_s16), .co(l6_c16));
wire l6_s17, l6_c17;
csa_fa u_l6_fa17 (.a(l5_c25), .b(l5_c26), .ci(l5_c27), .s(l6_s17), .co(l6_c17));
wire l6_s18, l6_c18;
csa_fa u_l6_fa18 (.a(l5_c28), .b(l5_c29), .ci(l5_s30), .s(l6_s18), .co(l6_c18));
wire l6_s19, l6_c19;
csa_fa u_l6_fa19 (.a(l5_c30), .b(l5_c31), .ci(l5_s32), .s(l6_s19), .co(l6_c19));
wire l6_s20, l6_c20;
csa_fa u_l6_fa20 (.a(l5_c33), .b(cut4[119]), .ci(cut4[120]), .s(l6_s20), .co(l6_c20));
// l6: 21 full adders; 66 live bits; column heights 1,1,2,3,4,5,6,6,6,6,6,4,5,3,3,3,1,1,0,0,0
wire l7_s0, l7_c0;
csa_fa u_l7_fa0 (.a(l6_c0), .b(l6_s1), .ci(cut4[15]), .s(l7_s0), .co(l7_c0));
wire l7_s1, l7_c1;
csa_fa u_l7_fa1 (.a(l6_c1), .b(l6_s2), .ci(l5_s5), .s(l7_s1), .co(l7_c1));
wire l7_s2, l7_c2;
csa_fa u_l7_fa2 (.a(l6_c2), .b(l6_s3), .ci(l6_s4), .s(l7_s2), .co(l7_c2));
wire l7_s3, l7_c3;
csa_fa u_l7_fa3 (.a(l6_c3), .b(l6_c4), .ci(l6_s5), .s(l7_s3), .co(l7_c3));
wire l7_s4, l7_c4;
csa_fa u_l7_fa4 (.a(l6_s6), .b(cut4[45]), .ci(cut4[46]), .s(l7_s4), .co(l7_c4));
wire l7_s5, l7_c5;
csa_fa u_l7_fa5 (.a(l6_c5), .b(l6_c6), .ci(l6_s7), .s(l7_s5), .co(l7_c5));
wire l7_s6, l7_c6;
csa_fa u_l7_fa6 (.a(l6_s8), .b(cut4[56]), .ci(cut4[57]), .s(l7_s6), .co(l7_c6));
wire l7_s7, l7_c7;
csa_fa u_l7_fa7 (.a(l6_c7), .b(l6_c8), .ci(l6_s9), .s(l7_s7), .co(l7_c7));
wire l7_s8, l7_c8;
csa_fa u_l7_fa8 (.a(l6_s10), .b(cut4[67]), .ci(cut4[68]), .s(l7_s8), .co(l7_c8));
wire l7_s9, l7_c9;
csa_fa u_l7_fa9 (.a(l6_c9), .b(l6_c10), .ci(l6_s11), .s(l7_s9), .co(l7_c9));
wire l7_s10, l7_c10;
csa_fa u_l7_fa10 (.a(l6_s12), .b(cut4[78]), .ci(cut4[79]), .s(l7_s10), .co(l7_c10));
wire l7_s11, l7_c11;
csa_fa u_l7_fa11 (.a(l6_c11), .b(l6_c12), .ci(l6_s13), .s(l7_s11), .co(l7_c11));
wire l7_s12, l7_c12;
csa_fa u_l7_fa12 (.a(l6_s14), .b(cut4[89]), .ci(cut4[90]), .s(l7_s12), .co(l7_c12));
wire l7_s13, l7_c13;
csa_fa u_l7_fa13 (.a(l6_c13), .b(l6_c14), .ci(l6_s15), .s(l7_s13), .co(l7_c13));
wire l7_s14, l7_c14;
csa_fa u_l7_fa14 (.a(l6_c15), .b(l6_c16), .ci(l6_s17), .s(l7_s14), .co(l7_c14));
wire l7_s15, l7_c15;
csa_fa u_l7_fa15 (.a(l6_c17), .b(l6_s18), .ci(l5_s31), .s(l7_s15), .co(l7_c15));
wire l7_s16, l7_c16;
csa_fa u_l7_fa16 (.a(l6_c18), .b(l6_s19), .ci(cut4[115]), .s(l7_s16), .co(l7_c16));
wire l7_s17, l7_c17;
csa_fa u_l7_fa17 (.a(l6_c19), .b(l5_c32), .ci(l5_s33), .s(l7_s17), .co(l7_c17));
// l7: 18 full adders; 48 live bits; column heights 1,1,2,1,3,4,3,4,4,4,4,4,4,2,2,2,2,1,0,0,0
reg [47:0] cut7;
always @(posedge i_clk) cut7 <= {l6_c20,l6_s20,l7_c17,l7_s17,l7_c16,l7_s16,l7_c15,l7_s15,l7_c14,l5_s29,l5_s28,l7_s14,l7_c13,l6_s16,l7_s13,l7_c12,l7_c11,l7_s12,l7_s11,l7_c10,l7_c9,l7_s10,l7_s9,l7_c8,l7_c7,l7_s8,l7_s7,l7_c6,l7_c5,l7_s6,l7_s5,l7_c4,l7_c3,l7_s4,l7_s3,l7_c2,cut4[35],cut4[34],l7_s2,l7_c1,l5_s6,l7_s1,l7_c0,l7_s0,cut4[8],l6_s0,l5_s0,cut4[0]};
wire l8_s0, l8_c0;
csa_fa u_l8_fa0 (.a(cut7[5]), .b(cut7[6]), .ci(cut7[7]), .s(l8_s0), .co(l8_c0));
wire l8_s1, l8_c1;
csa_fa u_l8_fa1 (.a(cut7[8]), .b(cut7[9]), .ci(cut7[10]), .s(l8_s1), .co(l8_c1));
wire l8_s2, l8_c2;
csa_fa u_l8_fa2 (.a(cut7[12]), .b(cut7[13]), .ci(cut7[14]), .s(l8_s2), .co(l8_c2));
wire l8_s3, l8_c3;
csa_fa u_l8_fa3 (.a(cut7[15]), .b(cut7[16]), .ci(cut7[17]), .s(l8_s3), .co(l8_c3));
wire l8_s4, l8_c4;
csa_fa u_l8_fa4 (.a(cut7[19]), .b(cut7[20]), .ci(cut7[21]), .s(l8_s4), .co(l8_c4));
wire l8_s5, l8_c5;
csa_fa u_l8_fa5 (.a(cut7[23]), .b(cut7[24]), .ci(cut7[25]), .s(l8_s5), .co(l8_c5));
wire l8_s6, l8_c6;
csa_fa u_l8_fa6 (.a(cut7[27]), .b(cut7[28]), .ci(cut7[29]), .s(l8_s6), .co(l8_c6));
wire l8_s7, l8_c7;
csa_fa u_l8_fa7 (.a(cut7[31]), .b(cut7[32]), .ci(cut7[33]), .s(l8_s7), .co(l8_c7));
wire l8_s8, l8_c8;
csa_fa u_l8_fa8 (.a(cut7[35]), .b(cut7[36]), .ci(cut7[37]), .s(l8_s8), .co(l8_c8));
// l8: 9 full adders; 39 live bits; column heights 1,1,2,1,1,3,2,3,3,3,3,3,3,3,2,2,2,1,0,0,0
wire l9_s0, l9_c0;
csa_fa u_l9_fa0 (.a(l8_c0), .b(l8_s1), .ci(cut7[11]), .s(l9_s0), .co(l9_c0));
wire l9_s1, l9_c1;
csa_fa u_l9_fa1 (.a(l8_c2), .b(l8_s3), .ci(cut7[18]), .s(l9_s1), .co(l9_c1));
wire l9_s2, l9_c2;
csa_fa u_l9_fa2 (.a(l8_c3), .b(l8_s4), .ci(cut7[22]), .s(l9_s2), .co(l9_c2));
wire l9_s3, l9_c3;
csa_fa u_l9_fa3 (.a(l8_c4), .b(l8_s5), .ci(cut7[26]), .s(l9_s3), .co(l9_c3));
wire l9_s4, l9_c4;
csa_fa u_l9_fa4 (.a(l8_c5), .b(l8_s6), .ci(cut7[30]), .s(l9_s4), .co(l9_c4));
wire l9_s5, l9_c5;
csa_fa u_l9_fa5 (.a(l8_c6), .b(l8_s7), .ci(cut7[34]), .s(l9_s5), .co(l9_c5));
wire l9_s6, l9_c6;
csa_fa u_l9_fa6 (.a(l8_c7), .b(l8_s8), .ci(cut7[38]), .s(l9_s6), .co(l9_c6));
wire l9_s7, l9_c7;
csa_fa u_l9_fa7 (.a(l8_c8), .b(cut7[39]), .ci(cut7[40]), .s(l9_s7), .co(l9_c7));
// l9: 8 full adders; 31 live bits; column heights 1,1,2,1,1,1,3,1,2,2,2,2,2,2,3,2,2,1,0,0,0
wire l10_s0, l10_c0;
csa_fa u_l10_fa0 (.a(l9_c0), .b(l8_c1), .ci(l8_s2), .s(l10_s0), .co(l10_c0));
wire l10_s1, l10_c1;
csa_fa u_l10_fa1 (.a(l9_c7), .b(cut7[41]), .ci(cut7[42]), .s(l10_s1), .co(l10_c1));
// l10: 2 full adders; 29 live bits; column heights 1,1,2,1,1,1,1,2,2,2,2,2,2,2,1,3,2,1,0,0,0
reg [28:0] cut10;
always @(posedge i_clk) cut10 <= {cut7[47],cut7[46],cut7[45],cut7[44],cut7[43],l10_c1,l10_s1,l9_s7,l9_c6,l9_s6,l9_c5,l9_s5,l9_c4,l9_s4,l9_c3,l9_s3,l9_c2,l9_s2,l9_c1,l9_s1,l10_c0,l10_s0,l9_s0,l8_s0,cut7[4],cut7[3],cut7[2],cut7[1],cut7[0]};
wire l11_s0, l11_c0;
csa_fa u_l11_fa0 (.a(cut10[23]), .b(cut10[24]), .ci(cut10[25]), .s(l11_s0), .co(l11_c0));
// l11: 1 full adders; 28 live bits; column heights 1,1,2,1,1,1,1,2,2,2,2,2,2,2,1,1,3,1,0,0,0
wire l12_s0, l12_c0;
csa_fa u_l12_fa0 (.a(l11_c0), .b(cut10[26]), .ci(cut10[27]), .s(l12_s0), .co(l12_c0));
// l12: 1 full adders; 27 live bits; column heights 1,1,2,1,1,1,1,2,2,2,2,2,2,2,1,1,1,2,0,0,0
reg [26:0] cut12;
always @(posedge i_clk) cut12 <= {cut10[28],l12_c0,l12_s0,l11_s0,cut10[22],cut10[21],cut10[20],cut10[19],cut10[18],cut10[17],cut10[16],cut10[15],cut10[14],cut10[13],cut10[12],cut10[11],cut10[10],cut10[9],cut10[8],cut10[7],cut10[6],cut10[5],cut10[4],cut10[3],cut10[2],cut10[1],cut10[0]};
assign sum[0] = cut12[0];
assign carry[0] = 1'b0;
assign sum[1] = cut12[1];
assign carry[1] = 1'b0;
assign sum[2] = cut12[2];
assign carry[2] = cut12[3];
assign sum[3] = cut12[4];
assign carry[3] = 1'b0;
assign sum[4] = cut12[5];
assign carry[4] = 1'b0;
assign sum[5] = cut12[6];
assign carry[5] = 1'b0;
assign sum[6] = cut12[7];
assign carry[6] = 1'b0;
assign sum[7] = cut12[8];
assign carry[7] = cut12[9];
assign sum[8] = cut12[10];
assign carry[8] = cut12[11];
assign sum[9] = cut12[12];
assign carry[9] = cut12[13];
assign sum[10] = cut12[14];
assign carry[10] = cut12[15];
assign sum[11] = cut12[16];
assign carry[11] = cut12[17];
assign sum[12] = cut12[18];
assign carry[12] = cut12[19];
assign sum[13] = cut12[20];
assign carry[13] = cut12[21];
assign sum[14] = cut12[22];
assign carry[14] = 1'b0;
assign sum[15] = cut12[23];
assign carry[15] = 1'b0;
assign sum[16] = cut12[24];
assign carry[16] = 1'b0;
assign sum[17] = cut12[25];
assign carry[17] = cut12[26];
assign sum[18] = 1'b0;
assign carry[18] = 1'b0;
assign sum[19] = 1'b0;
assign carry[19] = 1'b0;
assign sum[20] = 1'b0;
assign carry[20] = 1'b0;
endmodule

// Full-adder cell wrapper: library ADDFX1 for DC, behavioral for RTL simulation.
module csa_fa (input a, b, ci, output s, co);
`ifdef SYNTHESIS
ADDFX1 u_cell (.A(a), .B(b), .CI(ci), .S(s), .CO(co));
`else
assign s  = a ^ b ^ ci;
assign co = (a & b) | (a & ci) | (b & ci);
`endif
endmodule
