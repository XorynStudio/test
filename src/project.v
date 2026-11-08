`default_nettype none

module tt_um_xorynstudios_chimera (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // Always 1 when the design is powered
    input  wire       clk,      // 50 MHz Silicon Clock
    input  wire       rst_n     // Active-low reset
);

    wire [2:0] opcode        = ui_in[2:0];
    wire       morph_wave_en = ui_in[3];
    wire       l1_miss_swap  = ui_in[4];
    wire [1:0] reg_sel       = ui_in[6:5];
    wire       exec_strobe   = ui_in[7];
    wire [3:0] imm_data      = uio_in[3:0];

    // uio[3:0] = Inputs (0), uio[7:4] = Live Silicon Telemetry Outputs (1)
    assign uio_oe = 8'b1111_0000;

    reg        gpu_mode_q;
    reg  [1:0] active_wave_q;
    reg  [7:0] sram_bank [0:3][0:3];
    reg  [7:0] z_buffer_q;
    reg        z_pass_flag_q;
    reg  [7:0] result_q;

    // 0-Cycle Wavefront Switcher on L1 Cache Miss
    wire [1:0] next_wave = (gpu_mode_q && l1_miss_swap) ? (active_wave_q + 2'd1) : active_wave_q;

    wire [7:0] op_a = sram_bank[next_wave][reg_sel];
    wire [7:0] op_b = sram_bank[next_wave][(reg_sel + 2'd1) & 2'd3];
    wire [7:0] op_c = sram_bank[next_wave][(reg_sel + 2'd2) & 2'd3];

    // 2D Morton Z-Order Address Interleaver
    wire [7:0] morton_2d_addr = {
        op_b[3], op_a[3], op_b[2], op_a[2],
        op_b[1], op_a[1], op_b[0], op_a[0]
    };

    integer w, r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpu_mode_q    <= 1'b0;
            active_wave_q <= 2'd0;
            z_buffer_q    <= 8'hFF;
            z_pass_flag_q <= 1'b0;
            result_q      <= 8'h00;
            for (w = 0; w < 4; w = w + 1) begin
                for (r = 0; r < 4; r = r + 1) begin
                    sram_bank[w][r] <= 8'h00;
                end
            end
        end else if (ena) begin
            gpu_mode_q    <= morph_wave_en;
            active_wave_q <= next_wave;

            if (exec_strobe) begin
                case (opcode)
                    3'b000: begin // MOVI
                        sram_bank[next_wave][reg_sel] <= {4'h0, imm_data} + {6'h0, next_wave};
                        result_q <= {4'h0, imm_data} + {6'h0, next_wave};
                    end
                    3'b001: begin // ADD / VADD
                        sram_bank[next_wave][reg_sel] <= op_a + op_b;
                        result_q <= op_a + op_b;
                    end
                    3'b010: begin // SUB / VSUB
                        sram_bank[next_wave][reg_sel] <= op_a - op_b;
                        result_q <= op_a - op_b;
                    end
                    3'b011: begin // VFMA
                        sram_bank[next_wave][reg_sel] <= (op_a[3:0] * imm_data) + op_c;
                        result_q <= (op_a[3:0] * imm_data) + op_c;
                    end
                    3'b100: begin // VDOT2
                        result_q <= (op_a[3:0] * op_b[3:0]) + (op_c[3:0] * imm_data);
                    end
                    3'b101: begin // TEX2D / MORTON 2D
                        result_q <= morton_2d_addr;
                    end
                    3'b110: begin // ROP.ZWRITE
                        if (op_a < z_buffer_q) begin
                            z_buffer_q    <= op_a;
                            z_pass_flag_q <= 1'b1;
                            result_q      <= op_b;
                        end else begin
                            z_pass_flag_q <= 1'b0;
                        end
                    end
                    3'b111: begin // SOLO.JOIN / CLEAR_Z
                        z_buffer_q    <= 8'hFF;
                        z_pass_flag_q <= 1'b0;
                        gpu_mode_q    <= 1'b0;
                        result_q      <= op_a;
                    end
                endcase
            end
        end
    end

    assign uo_out  = result_q;
    assign uio_out = {z_pass_flag_q, gpu_mode_q, active_wave_q, 4'b0000};
    wire _unused = &{uio_in[7:4], 1'b0};

endmodule
