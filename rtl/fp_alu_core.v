// fp_alu_core.v
// ALU IEEE-754 parametrizable para ADD, SUB, MUL, DIV.
// op_code: 3'b000=ADD, 001=SUB, 010=MUL, 011=DIV (otros reservados)
// Handshake: start/valid_out (DIV multi-ciclo; las otras 1 ciclo).

`timescale 1ns/1ps
module fp_alu_core
#(parameter E=8, parameter F=23)
(
  input              clk,
  input              rst,
  input              start,
  input      [2:0]   op_code,
  input      [E+F:0] op_a,
  input      [E+F:0] op_b,
  output reg [E+F:0] result,
  output reg [4:0]   flags,
  output reg         valid_out
);

  wire [E+F:0] add_y, sub_y, mul_y, div_y;
  wire [4:0]   add_f, sub_f, mul_f, div_f;
  wire         div_done;

  // ADD / SUB / MUL son combinacionales (registramos 1 ciclo)
  fp_addsub #(E,F) U_ADD (.a(op_a), .b(op_b), .sub(1'b0), .y(add_y), .flags(add_f));
  fp_addsub #(E,F) U_SUB (.a(op_a), .b(op_b), .sub(1'b1), .y(sub_y), .flags(sub_f));
  fp_mul2    #(E,F) U_MUL (.a(op_a), .b(op_b), .y(mul_y), .flags(mul_f));

  // DIV es secuencial
  fp_div_iter #(E,F) U_DIV (
    .clk(clk), .rst(rst), .start(start & (op_code==3'b011)),
    .a(op_a), .b(op_b),
    .y(div_y), .flags(div_f), .done(div_done)
  );

  // Selección y registro de salida
  always @(posedge clk) begin
    if (rst) begin
      result    <= {1'b0,{E{1'b0}},{F{1'b0}}};
      flags     <= 5'b0;
      valid_out <= 1'b0;
    end else begin
      case (op_code)
        3'b000: begin // ADD
          result    <= add_y;
          flags     <= add_f;
          valid_out <= start; // disponible al ciclo siguiente de start
        end
        3'b001: begin // SUB
          result    <= sub_y;
          flags     <= sub_f;
          valid_out <= start;
        end
        3'b010: begin // MUL
          result    <= mul_y;
          flags     <= mul_f;
          valid_out <= start;
        end
        3'b011: begin // DIV (espera done)
          if (div_done) begin
            result    <= div_y;
            flags     <= div_f;
            valid_out <= 1'b1;
          end else begin
            valid_out <= 1'b0;
          end
        end
        default: begin
          result    <= {1'b0,{E{1'b0}},{F{1'b0}}};
          flags     <= 5'b0;
          valid_out <= 1'b0;
        end
      endcase
    end
  end

endmodule
