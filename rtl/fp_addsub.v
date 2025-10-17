// fp_addsub.v
// Suma/resta IEEE-754 parametrizable: E bits exponente, F bits fracción.
// Flags: {NV, DZ, OF, UF, NX}  (DZ no aplica aquí; se mantiene 0)
// Modo suma/resta con 'sub' (0 = ADD, 1 = SUB). Redondeo: nearest-even.

`timescale 1ns/1ps
module fp_addsub
#(parameter E=8, parameter F=23)
(
  input      [E+F:0] a,     // {sign, exp[E-1:0], frac[F-1:0]}
  input      [E+F:0] b,
  input              sub,   // 0: A+B, 1: A-B
  output reg [E+F:0] y,
  output reg [4:0]   flags  // {NV, DZ, OF, UF, NX}
);

  // Constantes
  localparam W = 1+E+F;
  localparam [E-1:0] EXP_MAX  = {E{1'b1}};
  localparam [E-1:0] EXP_ZERO = {E{1'b0}};
  localparam [E:0]   BIAS     = (1 << (E-1)) - 1; // 2^(E-1)-1 (no usado, pero correcto)

  // Desempaquetar
  wire sa = a[E+F];
  wire sb = b[E+F];
  wire [E-1:0] ea = a[F +: E];
  wire [E-1:0] eb = b[F +: E];
  wire [F-1:0] fa = a[0 +: F];
  wire [F-1:0] fb = b[0 +: F];

  // Clasificación
  wire a_is_nan = (ea==EXP_MAX) && (fa!=0);
  wire b_is_nan = (eb==EXP_MAX) && (fb!=0);
  wire a_is_inf = (ea==EXP_MAX) && (fa==0);
  wire b_is_inf = (eb==EXP_MAX) && (fb==0);
  wire a_is_zero= (ea==0) && (fa==0);
  wire b_is_zero= (eb==0) && (fb==0);

  // ÚNICO bloque combinacional
  integer shamt;
  always @* begin : MAIN
    // --- Declaraciones permitidas en Verilog-2001: TODAS al inicio del bloque ---
    reg [W-1:0]   y_n;
    reg [4:0]     f_n;

    // Camino normal
    reg [F:0]     ma, mb;          // 1.frac
    reg [E:0]     expa, expb;
    reg           sb_eff;
    reg           sgna, sgnb;
    reg [E:0]     exph;
    reg [F+3:0]   ah, bh;          // extendido con GRS
    reg           sh;

    reg [F+4:0]   sum;             // 1 bit extra
    reg           sign_res;

    reg [E:0]     expn;
    reg [F+3:0]   manx;            // con GRS
    reg           zero_mag;

    // temporales reutilizables para shifts/normalización
    integer       d, k, lz;
    reg [F+3:0]   tmp;
    reg           sticky, sticky2;

    // redondeo
    reg [F:0]     mant_round;      // 1.frac (F+1 bits)
    reg           inexact;
    reg           carry_rnd;

    // control de flujo sin 'disable'
    reg           done;

    // defaults
    y_n   = {W{1'b0}};
    f_n   = 5'b0;
    done  = 1'b0;

    // ---- Casos especiales temparanos (en el mismo always) ----
    if (a_is_nan || b_is_nan) begin
      // Propaga QNaN
      y_n   = {1'b0, EXP_MAX, {1'b1, {(F-1){1'b0}}}}; // quiet NaN
      f_n   = 5'b10000; // NV=1 (marcamos para reportar NaN)
      done  = 1'b1;
    end
    else if (a_is_inf || b_is_inf) begin
      if (a_is_inf && b_is_inf) begin
        // A ± B con ambos inf
        sb_eff = sub ? ~sb : sb;
        if (sa == sb_eff) begin
          y_n = {sa, EXP_MAX, {F{1'b0}}}; // mismo signo => ±Inf
          f_n = 5'b0;
        end else begin
          // +Inf + (-Inf) -> NaN inválido
          y_n = {1'b0, EXP_MAX, {1'b1, {(F-1){1'b0}}}};
          f_n = 5'b10000; // NV
        end
      end else begin
        // uno es inf, el otro finito
        sb_eff = sub ? ~sb : sb;
        y_n = { (a_is_inf ? sa : sb_eff), EXP_MAX, {F{1'b0}} };
        f_n = 5'b0;
      end
      done = 1'b1;
    end
    else if (a_is_zero && b_is_zero) begin
      // ±0 (+/-) ±0 -> tomamos 0 con una regla simple de signo
      y_n = { (sub ? (sa ^ sb) : (sa & sb)), {E{1'b0}}, {F{1'b0}} };
      f_n = 5'b0;
      done= 1'b1;
    end

    // ---- Camino normal si no se resolvió arriba ----
    if (!done) begin
      // Construir mantisas con bit implícito
      ma   = (ea==0) ? {1'b0, fa} : {1'b1, fa};
      mb   = (eb==0) ? {1'b0, fb} : {1'b1, fb};
      expa = (ea==0) ? 1 : {1'b0, ea}; // exp efectivo (subnormal = 1)
      expb = (eb==0) ? 1 : {1'b0, eb};

      sb_eff = sub ? ~sb : sb;     // signo efectivo de B
      sgna   = sa;
      sgnb   = sb_eff;

      // Alinear por exponente
      exph = 0; ah = 0; bh = 0; sh = 1'b0;
      d = 0; tmp = 0; sticky = 1'b0;

      if (expa >= expb) begin
        exph = expa;
        ah   = {ma, 3'b000};
        // shift mb right by (expa-expb), con sticky
        tmp = {mb, 3'b000};
        d   = expa - expb;
        if (d > 0) begin
          if (d >= F+4) begin
            tmp = {1'b0, {(F+2){1'b0}}, 1'b1}; // sólo sticky
          end else begin
            sticky = 1'b0;
            for (k = 0; k < d; k = k + 1)
              sticky = sticky | tmp[k];
            tmp    = tmp >> d;
            tmp[0] = tmp[0] | sticky;
          end
        end
        bh = tmp;
        sh = sgna;
      end else begin
        exph = expb;
        bh   = {mb, 3'b000};
        // shift ma
        tmp = {ma, 3'b000};
        d   = expb - expa;
        if (d >= F+4) begin
          tmp = {1'b0, {(F+2){1'b0}}, 1'b1};
        end else begin
          sticky = 1'b0;
            for (k = 0; k < d; k = k + 1)
              sticky = sticky | tmp[k];
            tmp    = tmp >> d;
            tmp[0] = tmp[0] | sticky;
        end
        ah = tmp;
        sh = sgnb;
        // intercambiar signos para operación posterior
        sgna = sgnb;
        sgnb = sa;
      end

      // Operación sobre mantisas alineadas
      if (sgna == sgnb) begin
        sum      = {1'b0, ah} + {1'b0, bh};
        sign_res = sh;
      end else begin
        sum      = {1'b0, ah} - {1'b0, bh}; // ah >= bh por construcción
        sign_res = sh;
      end

      // Normalización
      expn = exph;
      manx = sum[F+3:0];    // quitar bit extra superior

      if (sum[F+4]) begin
        sticky2 = manx[0];
        manx    = manx >> 1;
        manx[0] = manx[0] | sticky2;
        expn    = expn + 1;
      end else begin
        if (manx[F+3:3] == 0) begin
          zero_mag = (manx == 0);
          if (zero_mag) begin
            y_n   = {1'b0, {E{1'b0}}, {F{1'b0}}};
            f_n   = 5'b0;
            done  = 1'b1;
          end else begin
            // contar ceros líderes en [F+3:3]
            lz = 0;
            for (k=F+3; k>=3; k=k-1) begin
              if (manx[k]==1'b0) lz = lz + 1;
              else k = -1; // break
            end
            if (lz > 0) begin
              if (expn > lz) begin
                expn = expn - lz;
                manx = manx << lz;
              end else begin
               
                shamt = expn - 1; // pasar a subnormal
                if (shamt > 0) manx = manx << shamt;
                expn = 0;
              end
            end
          end
        end
      end

      // Si no terminamos por cero exacto, seguimos
      if (!done) begin
        // Redondeo a nearest-even usando G,R,S = manx[2], manx[1], manx[0]
        inexact    = (manx[2:0] != 3'b000);
        mant_round = manx[F+3:3]; // F+1 bits

        if (manx[2] && (manx[1] || manx[0] || mant_round[0])) begin
          {carry_rnd, mant_round} = {1'b0, mant_round} + 1'b1;
        end else begin
          carry_rnd = 1'b0;
        end

        if (carry_rnd) begin
          mant_round = mant_round >> 1;
          expn       = expn + 1;
        end

        // Empaquetar con manejo de over/underflow y subnormales
        begin : PACK
          reg of, uf;
          of = 1'b0; uf = 1'b0;

          if (expn[E]) begin
            // overflow de exponente (más de E bits)
            of = 1'b1;
            y_n = {sign_res, EXP_MAX, {F{1'b0}}}; // ±Inf
          end else if (expn == 0) begin
            // subnormal o cero
            if (mant_round[F]) begin
              // convertir a subnormal (quitar implícito)
              y_n = {sign_res, {E{1'b0}}, mant_round[F-1:0]};
              uf  = 1'b1;
            end else begin
              y_n = {sign_res, {E{1'b0}}, mant_round[F-1:0]};
              uf  = inexact; // pérdida por corrimientos
            end
          end else if (expn == {1'b0, EXP_MAX}) begin
            // max exp representable (un paso antes de all-ones)
            y_n = {sign_res, EXP_MAX-1, mant_round[F-1:0]};
          end else begin
            // normal
            y_n = {sign_res, expn[E-1:0], mant_round[F-1:0]};
          end

          f_n      = 5'b0;
          f_n[2]   = of;       // OF
          f_n[1]   = uf;       // UF
          f_n[0]   = inexact;  // NX
        end
      end
    end

    // Salida final
    y     = y_n;
    flags = f_n;
  end

endmodule
