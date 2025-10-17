// tb_top_fp_alu.v  (Verilog-2001, Vivado OK)
`timescale 1ns/1ps

module tb_top_fp_alu;

  // Señales
  reg         clk = 1'b0;
  reg         rst = 1'b1;
  reg         start = 1'b0;
  reg         mode_fp = 1'b1;      // 1=single(32), 0=half(16)
  reg  [2:0]  op_code = 3'b000;
  reg  [31:0] op_a = 32'h00000000;
  reg  [31:0] op_b = 32'h00000000;
  wire [31:0] result;
  wire [4:0]  flags;               // {NV,DZ,OF,UF,NX}
  wire        valid_out;

  // DUT
  top_fp_alu DUT (
    .clk(clk), .rst(rst), .start(start), .op_code(op_code),
    .mode_fp(mode_fp), .op_a(op_a), .op_b(op_b),
    .result(result), .flags(flags), .valid_out(valid_out)
  );

  // Clock 100 MHz
  always #5 clk = ~clk;

  // Tareas auxiliares (sin 'automatic', Verilog-2001)
  task run32;
    input [2:0]   opc;
    input [31:0]  a;
    input [31:0]  b;
    input [255:0] name;  // "string" como bus de 256 bits
    integer cycles;
    begin
      @(negedge clk);
      mode_fp = 1'b1; op_code = opc; op_a = a; op_b = b;
      start = 1'b1; @(negedge clk); start = 1'b0;

      cycles = 0;
      while (!valid_out && cycles < 600) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      $display("[32] %0s  A=%h  B=%h  ->  R=%h  flags(NV DZ OF UF NX)=%b  (cycles=%0d)",
                name, a, b, result, flags, cycles);
      #1;
    end
  endtask

  task run16;
    input [2:0]   opc;
    input [15:0]  a;
    input [15:0]  b;
    input [255:0] name;
    integer cycles;
    begin
      @(negedge clk);
      mode_fp = 1'b0; op_code = opc; op_a = {16'h0000, a}; op_b = {16'h0000, b};
      start = 1'b1; @(negedge clk); start = 1'b0;

      cycles = 0;
      while (!valid_out && cycles < 600) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      $display("[16] %0s  A=%h  B=%h  ->  R=%h (res16=%h)  flags=%b  (cycles=%0d)",
                name, a, b, result, result[15:0], flags, cycles);
      #1;
    end
  endtask

  // Estímulos
  initial begin
    // Reset
    repeat (4) @(posedge clk);
    rst = 1'b0;

    // -------- Single (32 bits): 9.8 (~0x411CCCCD) y 4.3 (~0x4089999A)
    run32(3'b000, 32'h411CCCCD, 32'h4089999A, "ADD 9.8 + 4.3");
    run32(3'b001, 32'h411CCCCD, 32'h4089999A, "SUB 9.8 - 4.3");
    run32(3'b010, 32'h411CCCCD, 32'h4089999A, "MUL 9.8 * 4.3");
    run32(3'b011, 32'h411CCCCD, 32'h4089999A, "DIV 9.8 / 4.3");

    // Especiales 32
    run32(3'b000, 32'h7F800000, 32'h3F800000, "INF + 1");
    run32(3'b000, 32'h7F800000, 32'hFF800000, "INF + (-INF) -> NaN");
    run32(3'b010, 32'h00000000, 32'h7F800000, "0 * INF -> NaN");
    run32(3'b011, 32'h3F800000, 32'h00000000, "1 / 0 -> INF (DZ)");
    run32(3'b010, 32'h7F7FFFFF, 32'h7F7FFFFF, "MAX*MAX -> OF");

    // -------- Half (16 bits): 1.0=0x3C00, 2.0=0x4000, 3.0=0x4200
    run16(3'b000, 16'h3C00, 16'h4000, "ADD 1 + 2 (half)");
    run16(3'b001, 16'h3C00, 16'h4000, "SUB 1 - 2 (half)");
    run16(3'b010, 16'h3C00, 16'h4000, "MUL 1 * 2 (half)");
    run16(3'b011, 16'h3C00, 16'h4000, "DIV 1 / 2 (half)");

    // Especiales half: Inf=0x7C00, NaN=0x7E00, Max=0x7BFF
    run16(3'b011, 16'h3C00, 16'h0000, "1 / 0 -> INF (DZ) half");
    run16(3'b000, 16'h7C00, 16'hFC00, "INF + (-INF) -> NaN half");

    $display("== FIN ==");
    #50 $finish;
  end

endmodule
