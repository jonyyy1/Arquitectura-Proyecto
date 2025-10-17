// top_fp_alu.v
// Interfaz común 32 bits en op_a/op_b/result. Si mode_fp=0 (half),
// se usan y producen los 16 LSBs (result[15:0] válido).
// Señales típicas para Basys3: clk, rst, start, op_code[2:0], mode_fp.

`timescale 1ns/1ps
module top_fp_alu (
  input              clk,
  input              rst,
  input              start,
  input      [2:0]   op_code,   // 000 ADD, 001 SUB, 010 MUL, 011 DIV
  input              mode_fp,   // 0=half(16), 1=single(32)
  input      [31:0]  op_a,
  input      [31:0]  op_b,
  output     [31:0]  result,    // en half usar [15:0]
  output     [4:0]   flags,
  output             valid_out
);

  // ALU 32-bit (E=8,F=23)
  wire [31:0] r32; wire [4:0] f32; wire v32;
  fp_alu_core #(8,23) ALU32 (
    .clk(clk), .rst(rst), .start(start & mode_fp), .op_code(op_code),
    .op_a(op_a), .op_b(op_b),
    .result(r32), .flags(f32), .valid_out(v32)
  );

  // ALU 16-bit (E=5,F=10)
  // Empaquetamos en 17 bits (1+5+10=16) pero usamos buses de 16 bits dentro de 32
  wire [15:0] a16 = op_a[15:0];
  wire [15:0] b16 = op_b[15:0];
  wire [16:0] r16_ext;
  wire [4:0]  f16; wire v16;

  fp_alu_core #(5,10) ALU16 (
    .clk(clk), .rst(rst), .start(start & ~mode_fp), .op_code(op_code),
    .op_a({a16[15], a16[14:10], a16[9:0]}),
    .op_b({b16[15], b16[14:10], b16[9:0]}),
    .result(r16_ext), .flags(f16), .valid_out(v16)
  );

  // Expandir r16_ext a 32 bits (mantener en LSBs)
  wire [31:0] r16_32 = {16'h0000, r16_ext[16], r16_ext[15:11], r16_ext[10:0]};

  assign result    = mode_fp ? r32 : r16_32;
  assign flags     = mode_fp ? f32 : f16;
  assign valid_out = mode_fp ? v32 : v16;

endmodule
