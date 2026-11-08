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

    assign uio_oe = 8'b1111_0000;

    reg        gpu_mode_q;
    reg  [1:0] active_wave_q;
    reg  [7:0] reg_a_q;
    reg  [7:0] reg_b_q;
    reg  [7:0] z_buffer_q;
    reg        z_pass_flag_q;
    reg  [7:0] result_q;

    // 0-Cycle Wavefront ID Switcher on L1 Cache Miss
    wire [1:0] next_wave = (gpu_mode_q && l1_miss_swap) ? (active_wave_q + 2'd1) : active_wave_q;

    // Hardware 2D Morton Z-Order Address Interleaver (X[3:0] = reg_a_q, Y[3:0] = reg_b_q)
    wire [7:0] morton_2d_addr = {
        reg_b_q[3], reg_a_q[3],
        reg_b_q[2], reg_a_q[2],
        reg_b_q[1], reg_a_q[1],
        reg_b_q[0], reg_a_q[0]
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpu_mode_q    <= 1'b0;
            active_wave_q <= 2'd0;
            reg_a_q       <= 8'h00;
            reg_b_q       <= 8'h00;
            z_buffer_q    <= 8'hFF;
            z_pass_flag_q <= 1'b0;
            result_q      <= 8'h00;
        end else if (ena) begin
            gpu_mode_q    <= morph_wave_en;
            active_wave_q <= next_wave;

            if (exec_strobe) begin
                case (opcode)
                    3'b000: begin // MOVI into R0 (reg_sel=0) or R1 (reg_sel=1)
                        if (reg_sel[0] == 1'b0) reg_a_q <= {4'h0, imm_data};
                        else                    reg_b_q <= {4'h0, imm_data};
                        result_q <= {4'h0, imm_data};
                    end
                    3'b001: begin // ADD
                        result_q <= reg_a_q + reg_b_q;
                    end
                    3'b010: begin // SUB
                        result_q <= reg_a_q - reg_b_q;
                    end
                    3'b011: begin // VFMA (reg_a * imm + reg_b)
                        result_q <= (reg_a_q[3:0] * imm_data) + reg_b_q;
                    end
                    3'b100: begin // WAVE BANK READ
                        result_q <= reg_a_q + {6'h0, next_wave};
                    end
                    3'b101: begin // TEX2D / 2D MORTON SWIZZLE
                        result_q <= morton_2d_addr;
                    end
                    3'b110: begin // ROP.ZWRITE (Hardware Depth Test)
                        if (reg_a_q < z_buffer_q) begin
                            z_buffer_q    <= reg_a_q;
                            z_pass_flag_q <= 1'b1;
                            result_q      <= reg_b_q;
                        end else begin
                            z_pass_flag_q <= 1'b0;
                        end
                    end
                    3'b111: begin // SOLO.JOIN / CLEAR_Z
                        z_buffer_q    <= 8'hFF;
                        z_pass_flag_q <= 1'b0;
                        gpu_mode_q    <= 1'b0;
                        result_q      <= 8'h00;
                    end
                endcase
            end
        end
    end

    assign uo_out  = result_q;
    assign uio_out = {z_pass_flag_q, gpu_mode_q, active_wave_q, 4'b0000};
    wire _unused = &{reg_sel[1], uio_in[7:4], 1'b0};

endmodule
