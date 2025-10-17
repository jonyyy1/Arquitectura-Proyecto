// fp_mul.v
// Multiplicación IEEE-754 parametrizable (E,F).
// Redondeo: nearest-even con GRS. Maneja NaN/Inf/0/subnormales.
// Flags: {NV, DZ, OF, UF, NX}  (DZ=0 aquí)

`timescale 1ns/1ps
module fp_mul2
#(parameter E=8, parameter F=23)
(
  input      [E+F:0] a,    // {sign, exp[E-1:0], frac[F-1:0]}
  input      [E+F:0] b,
  output reg [E+F:0] y,
  output reg [4:0]   flags
);
  localparam [E-1:0] EXP_MAX  = {E{1'b1}};
  localparam [E-1:0] EXP_ZERO = {E{1'b0}};
  localparam integer BIAS     = (1<<(E-1)) - 1;

  // Desempaquetado
  wire sa = a[E+F];
  wire sb = b[E+F];
  wire [E-1:0] ea = a[F +: E];
  wire [E-1:0] eb = b[F +: E];
  wire [F-1:0] fa = a[0 +: F];
  wire [F-1:0] fb = b[0 +: F];

  // Clasificación
  wire a_nan = (ea==EXP_MAX) && (fa!=0);
  wire b_nan = (eb==EXP_MAX) && (fb!=0);
  wire a_inf = (ea==EXP_MAX) && (fa==0);
  wire b_inf = (eb==EXP_MAX) && (fb==0);
  wire a_zero= (ea==0)       && (fa==0);
  wire b_zero= (eb==0)       && (fb==0);

  wire s = sa ^ sb;

  // --- Registros temporales (declarados al inicio; nada dentro de if/else) ---
  reg NV, OF, UF, NX;
  reg [F:0]     ma, mb;
  reg [2*F+1:0] prod;
  reg signed [E+1:0] expa, expb, exn;
  reg [F+3:0]   mantx;         // significando extendido con GRS
  reg [F:0]     mant_round;    // 1.frac redondeada
  reg           carry_r;
  integer       sh;            // shift para subnormal
  reg [F:0]     subm;          // mantisa subnormal

  always @* begin
    // Defaults
    y     = {s, EXP_ZERO, {F{1'b0}}};
    NV=1'b0; OF=1'b0; UF=1'b0; NX=1'b0;
    flags = 5'b0;

    // Casos especiales
    if (a_nan || b_nan) begin
      y  = {1'b0, EXP_MAX, {1'b1,{(F-1){1'b0}}}}; // qNaN
      NV = 1'b1;
    end
    else if ((a_inf && b_zero) || (b_inf && a_zero)) begin
      // 0 * Inf -> NaN inválido
      y  = {1'b0, EXP_MAX, {1'b1,{(F-1){1'b0}}}};
      NV = 1'b1;
    end
    else if (a_inf || b_inf) begin
      y  = {s, EXP_MAX, {F{1'b0}}};                // ±Inf
    end
    else if (a_zero || b_zero) begin
      y  = {s, EXP_ZERO, {F{1'b0}}};               // ±0
    end
    else begin
      // Operandos normales/subnormales
      ma   = (ea==0) ? {1'b0, fa} : {1'b1, fa};
      mb   = (eb==0) ? {1'b0, fb} : {1'b1, fb};
      // exponentes efectivos (subnormal -> 1)
      expa = (ea==0) ? 1 : {1'b0,ea};
      expb = (eb==0) ? 1 : {1'b0,eb};

      // Producto de significandos: (F+1)x(F+1) -> 2F+2 bits
      prod = ma * mb;

      // Exponente intermedio: expa + expb - bias
      exn  = expa + expb - BIAS;

      // Normalización del producto: rango [1,4)
      if (prod[2*F+1]) begin
        // 11.x -> desplazar 1 a la derecha y exn++
        mantx = {prod[2*F+1:F+1], 3'b000};
        mantx = (mantx >> 1) | { {(F+2){1'b0}}, mantx[0] }; // conserva sticky
        exn   = exn + 1;
      end else begin
        // 1x.x -> ya normal
        mantx = {prod[2*F:F], 3'b000};
      end

      // Redondeo nearest-even con GRS
      NX         = (mantx[2:0] != 3'b000);
      mant_round = mantx[F+3:3];
      if (mantx[2] && (mantx[1] || mantx[0] || mant_round[0])) begin
        {carry_r, mant_round} = {1'b0, mant_round} + 1'b1;
      end else begin
        carry_r = 1'b0;
      end
      if (carry_r) begin
        mant_round = mant_round >> 1;
        exn        = exn + 1;
      end

      // Empaquetado (OF/UF/Subnormal)
      if (exn < 1) begin
        // subnormal / underflow
        sh = 1 - exn;
        if (sh > F+1) begin
          y  = {s, EXP_ZERO, {F{1'b0}}};
          UF = 1'b1;
        end else begin
          subm = mant_round >> sh;
          // si hubo bits perdidos, marcar sticky en LSB
          if (NX) subm[0] = 1'b1;
          y  = {s, EXP_ZERO, subm[F-1:0]};
          UF = 1'b1;
        end
      end
      else if (exn >= (1<<E)-1) begin
        y  = {s, EXP_MAX, {F{1'b0}}};
        OF = 1'b1;
      end
      else begin
        y  = {s, exn[E-1:0], mant_round[F-1:0]};
      end
    end

    flags = {NV, 1'b0 /*DZ*/, OF, UF, NX};
  end
endmodule
