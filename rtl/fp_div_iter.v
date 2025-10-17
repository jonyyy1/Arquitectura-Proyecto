// fp_div_iter.v  (Verilog-2001, Vivado OK)
// División IEEE-754 parametrizable (E,F) con algoritmo iterativo shift/subtract.
// FSM: IDLE -> INIT -> ITER -> NORM -> ROUND -> PACK -> DONE
// Flags de salida = {NV, DZ, OF, UF, NX}

`timescale 1ns/1ps
module fp_div_iter
#(parameter E=8, parameter F=23)
(
  input              clk,
  input              rst,
  input              start,
  input      [E+F:0] a,       // {sign, exp[E-1:0], frac[F-1:0]}
  input      [E+F:0] b,
  output reg [E+F:0] y,
  output reg [4:0]   flags,   // {NV, DZ, OF, UF, NX}
  output reg         done
);

  // Constantes
  localparam [E-1:0] EXP_MAX = {E{1'b1}};
  localparam [E-1:0] EXP_ZERO= {E{1'b0}};
  localparam integer BIAS    = (1<<(E-1)) - 1;

  // Desempaquetado
  wire sa = a[E+F];
  wire sb = b[E+F];
  wire [E-1:0] ea = a[F +: E];
  wire [E-1:0] eb = b[F +: E];
  wire [F-1:0] fa = a[0 +: F];
  wire [F-1:0] fb = b[0 +: F];

  // Clasificación
  wire a_nan  = (ea==EXP_MAX) && (fa!=0);
  wire b_nan  = (eb==EXP_MAX) && (fb!=0);
  wire a_inf  = (ea==EXP_MAX) && (fa==0);
  wire b_inf  = (eb==EXP_MAX) && (fb==0);
  wire a_zero = (ea==0)       && (fa==0);
  wire b_zero = (eb==0)       && (fb==0);

  wire s = sa ^ sb;

  // FSM
  localparam S_IDLE = 3'd0,
             S_INIT = 3'd1,
             S_ITER = 3'd2,
             S_NORM = 3'd3,
             S_ROUND= 3'd4,
             S_PACK = 3'd5,
             S_DONE = 3'd6;

  reg [2:0]  st, st_n;

  // ---------- Registros de trabajo (declarar aquí: Verilog-2001) ----------
  reg [F:0]  num_w;           // significando del numerador (1.frac o 0.frac)
  reg [F:0]  den_w;           // significando del denominador
  reg [F:0]  rem_w;           // resto (F+1 bits)
  reg [F+3:0] q_w;            // F+4 bits: [MSB..LSB] = ... G R S
  reg [7:0]  cnt;             // iteraciones (0..F+3)
  reg signed [E+1:0] ex_eff;  // exponente efectivo inicial
  reg signed [E+1:0] ex_n;    // exponente normalizado/redondeado
  reg [F:0]  mant_norm;       // 1.frac (F+1) tras ROUND
  reg        NV, DZ, OF, UF, NX;

  // Auxiliares para ROUND/PACK
  reg        inc_round;
  reg [F:0]  mant_sum;
  reg        carry_round;
  reg [F:0]  subm;            // para subnormal en PACK
  integer    sh_amt;          // desplazamiento a la derecha

  // Efectivos (subnormal => 1)
  wire [E:0] ea_eff = (ea==0) ? 1 : ea;
  wire [E:0] eb_eff = (eb==0) ? 1 : eb;

  // ---------- Estado ----------
  always @(posedge clk) begin
    if (rst) st <= S_IDLE;
    else     st <= st_n;
  end

  // ---------- Próximo estado ----------
  always @* begin
    case (st)
      S_IDLE : st_n = start ? S_INIT : S_IDLE;
      S_INIT : st_n = (a_nan || b_nan || (a_inf && b_inf) || b_zero || a_zero || a_inf || b_inf)
                      ? S_DONE : S_ITER;
      S_ITER : st_n = (cnt==(F+3)) ? S_NORM : S_ITER;
      S_NORM : st_n = S_ROUND;
      S_ROUND: st_n = S_PACK;
      S_PACK : st_n = S_DONE;
      S_DONE : st_n = S_IDLE;
      default: st_n = S_IDLE;
    endcase
  end

  // ---------- Señal done ----------
  always @(posedge clk) begin
    if (rst) done <= 1'b0;
    else if (st==S_DONE) done <= 1'b1;
    else if (start)      done <= 1'b0;
  end

  // ---------- Datapath / acciones ----------
  always @(posedge clk) begin
    if (rst) begin
      y<=0; flags<=0; NV<=0; DZ<=0; OF<=0; UF<=0; NX<=0;
      num_w<=0; den_w<=0; rem_w<=0; q_w<=0; cnt<=0; ex_eff<=0; ex_n<=0; mant_norm<=0;
      inc_round<=0; mant_sum<=0; carry_round<=0; subm<=0; sh_amt=0;
    end else begin
      case (st)

        // ---------- INIT ----------
        S_INIT: begin
          NV<=1'b0; DZ<=1'b0; OF<=1'b0; UF<=1'b0; NX<=1'b0;
          if (a_nan || b_nan) begin
            y  <= {1'b0, EXP_MAX, {1'b1,{(F-1){1'b0}}}}; NV <= 1'b1;
          end else if (a_inf && b_inf) begin
            y  <= {1'b0, EXP_MAX, {1'b1,{(F-1){1'b0}}}}; NV <= 1'b1;
          end else if (a_inf) begin
            y  <= {s, EXP_MAX, {F{1'b0}}};
          end else if (b_inf) begin
            y  <= {s, EXP_ZERO, {F{1'b0}}};
          end else if (b_zero && a_zero) begin
            y  <= {1'b0, EXP_MAX, {1'b1,{(F-1){1'b0}}}}; NV <= 1'b1;
          end else if (b_zero) begin
            y  <= {s, EXP_MAX, {F{1'b0}}}; DZ <= 1'b1;
          end else if (a_zero) begin
            y  <= {s, EXP_ZERO, {F{1'b0}}};
          end else begin
            num_w  <= (ea==0) ? {1'b0, fa} : {1'b1, fa};
            den_w  <= (eb==0) ? {1'b0, fb} : {1'b1, fb};
            rem_w  <= { (F+1){1'b0} };
            q_w    <= { (F+4){1'b0} };
            cnt    <= 8'd0;
            ex_eff <= $signed(ea_eff) - $signed(eb_eff) + $signed(BIAS);
          end
        end

        // ---------- ITER: genera F+4 bits (incl. G,R,S) ----------
        S_ITER: begin
          // formar "dividend" = {resto, siguiente bit de num_w}
          if ( {rem_w[F-1:0], num_w[F]} >= den_w ) begin
            rem_w <= {rem_w[F-1:0], num_w[F]} - den_w;
            q_w   <= {q_w[F+2:0], 1'b1};
          end else begin
            rem_w <= {rem_w[F-1:0], num_w[F]};
            q_w   <= {q_w[F+2:0], 1'b0};
          end
          num_w <= {num_w[F-1:0], 1'b0}; // seguir alimentando (ceros luego)
          cnt   <= cnt + 1'b1;
        end

        // ---------- NORM ----------
        S_NORM: begin
          ex_n <= ex_eff;
          if (!q_w[F+3]) begin
            q_w  <= {q_w[F+2:0], 1'b0}; // <1 -> shift-left 1
            ex_n <= ex_eff - 1;
          end
        end

        // ---------- ROUND: nearest-even con GRS = q_w[2:0] ----------
        S_ROUND: begin
          NX        <= (q_w[2:0] != 3'b000) || (rem_w != 0);
          mant_norm <= q_w[F+3:3];                  // F+1 bits
          inc_round <= q_w[2] & (q_w[1] | q_w[0] | q_w[3]); // LSB actual = mant_norm[0] = q_w[3]
          // suma con acarreo explícito
          {carry_round, mant_sum} = {1'b0, q_w[F+3:3]} + { {F{1'b0}}, inc_round };
          mant_norm <= mant_sum;
          if (carry_round) ex_n <= ex_n + 1;
        end

        // ---------- PACK ----------
        S_PACK: begin
          OF <= 1'b0; UF <= 1'b0;
          if (ex_n < 1) begin
            // subnormal/underflow
            sh_amt = 1 - ex_n;         // entero
            if (sh_amt > (F+1)) begin
              y  <= {s, EXP_ZERO, {F{1'b0}}};
              UF <= 1'b1;
            end else begin
              subm = mant_norm >> sh_amt;
              y    <= {s, EXP_ZERO, subm[F-1:0]};
              UF   <= 1'b1;
            end
          end else if (ex_n >= $signed((1<<E)-1)) begin
            y  <= {s, EXP_MAX, {F{1'b0}}};
            OF <= 1'b1;
          end else begin
            y  <= {s, ex_n[E-1:0], mant_norm[F-1:0]};
          end
        end

        // ---------- DONE ----------
        S_DONE: begin
          flags <= {NV, DZ, OF, UF, NX};
        end

        default: ;
      endcase
    end
  end
endmodule
