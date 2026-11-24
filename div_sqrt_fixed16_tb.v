//=============================================================================
// div_sqrt_fixed16_tb - тестбенч для div_sqrt_fixed16 (iverilog)
// Проверка:
//   1. КВАДРАТНЫЙ КОРЕНЬ - перебор всех 32768 неотрицательных Q1.15 аргументов
//      (эталон: isqrt(X*2^15), усечение к нулю, rmode=00).
//   2. ДЕЛЕНИЕ - граничные случаи + случайная выборка; эталон считается
//      точной целочисленной моделью (Q17 + guard/sticky + режимы округления).
//=============================================================================
`timescale 1ns/1ps

module div_sqrt_fixed16_tb;

    reg         clk = 0;
    reg         reset = 1;
    reg         start = 0;
    reg         div = 0;
    reg  [15:0] op1 = 0;
    reg  [15:0] op2 = 0;
    reg  [1:0]  rmode = 0;
    wire [15:0] result;
    wire        ready;
    wire        busy;

    integer errors = 0;
    integer checks = 0;

    div_sqrt_fixed16 dut (
        .clk(clk), .reset(reset), .start(start), .div(div),
        .op1(op1), .op2(op2), .rmode(rmode),
        .result(result), .ready(ready), .busy(busy));

    always #5 clk = ~clk;

    task run_op;                       // запустить и дождаться ready
        begin
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
            @(posedge ready);
        end
    endtask

    // -------- эталонные функции (точная целочисленная арифметика) ----------
    function integer isqrt;            // floor(sqrt(n))
        input integer n;
        integer lo, hi, mid;
        begin
            lo = 0; hi = 65535;
            while (lo < hi) begin
                mid = (lo + hi + 1) / 2;
                if (mid * mid <= n) lo = mid; else hi = mid - 1;
            end
            isqrt = lo;
        end
    endfunction

    function [15:0] ref_sqrt;          // sqrt(x), x >= 0 (Q1.15), trunc
        input [15:0] x;
        begin
            ref_sqrt = isqrt(x * 32768);   // X * 2^15
        end
    endfunction

    // |частное| в Q17 (32 бита): floor(a * 2^17 / b), a,b - модули, b>0
    function [31:0] ref_div_q17;
        input [15:0] a;
        input [15:0] b;
        integer i;
        reg [16:0] rem;
        reg [31:0] q;
        begin
            q = 0;
            rem = {1'b0, a};
            for (i = 0; i < 32; i = i + 1) begin
                q = q << 1;
                if ({rem[15:0], 1'b0} >= {1'b0, b}) begin
                    rem = {rem[15:0], 1'b0} - {1'b0, b};
                    q = q | 1;
                end else begin
                    rem = {rem[15:0], 1'b0};
                end
            end
            ref_div_q17 = q;
        end
    endfunction

    // ------------------------------------------------------------------------
    integer k;
    reg [15:0] exp;

    initial begin
        $dumpfile("div_sqrt_fixed16_tb.vcd");
        $dumpvars(0, div_sqrt_fixed16_tb);

        repeat (3) @(negedge clk);
        reset = 0;
        repeat (2) @(negedge clk);

        //=================== 1. КВАДРАТНЫЙ КОРЕНЬ: перебор ==================
        div = 0;
        for (k = 0; k < 32768; k = k + 1) begin
            op2   = k[15:0];
            rmode = 2'b00;
            run_op();
            exp = ref_sqrt(k[15:0]);
            checks = checks + 1;
            if (result !== exp) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("SQRT ERR op2=%h got=%h exp=%h", k, result, exp);
            end
        end
        $display("sqrt exhaustive done (%0d checks, %0d errors)", checks, errors);

        // корень из отрицательного -> насыщение MAXPOS
        op2 = 16'hFFFF; rmode = 2'b01; run_op();
        checks = checks + 1;
        if (result !== 16'h7FFF) begin errors = errors + 1;
            $display("SQRT NEG ERR got=%h", result); end

        //=================== 2. ДЕЛЕНИЕ: граничные случаи ====================
        div = 1; rmode = 2'b00;

        // 0.5 / 0.5 = +1.0 не представимо -> насыщение 0x7FFF
        op1 = 16'h4000; op2 = 16'h4000; run_op();
        checks = checks + 1;
        if (result !== 16'h7FFF) begin errors = errors + 1;
            $display("DIV OVF+ ERR got=%h", result); end

        // -0.5 / 0.5 = -1.0 представимо -> 0x8000
        op1 = 16'hC000; op2 = 16'h4000; run_op();
        checks = checks + 1;
        if (result !== 16'h8000) begin errors = errors + 1;
            $display("DIV OVF- ERR got=%h", result); end

        // 0.25 / 0.75 = 1/3 -> trunc: 0x2AAA
        op1 = 16'h2000; op2 = 16'h6000; run_op();
        checks = checks + 1;
        if (result !== 16'h2AAA) begin errors = errors + 1;
            $display("DIV 1/3 ERR got=%h exp=2AAA", result); end

        // -0.25 / 0.75 = -1/3 -> trunc(к нулю): 0xD556
        op1 = 16'hE000; op2 = 16'h6000; run_op();
        checks = checks + 1;
        if (result !== 16'hD556) begin errors = errors + 1;
            $display("DIV -1/3 ERR got=%h exp=D556", result); end

        // 0.75 / 0.25 = 3 -> переполнение -> 0x7FFF
        op1 = 16'h6000; op2 = 16'h2000; run_op();
        checks = checks + 1;
        if (result !== 16'h7FFF) begin errors = errors + 1;
            $display("DIV OVF3 ERR got=%h", result); end

        // деление на ноль: 0.5 / 0 -> 0x7FFF
        op1 = 16'h4000; op2 = 16'h0000; run_op();
        checks = checks + 1;
        if (result !== 16'h7FFF) begin errors = errors + 1;
            $display("DIV ZERO ERR got=%h", result); end

        // 0 / 0.5 = 0
        op1 = 16'h0000; op2 = 16'h4000; run_op();
        checks = checks + 1;
        if (result !== 16'h0000) begin errors = errors + 1;
            $display("DIV ZNUM ERR got=%h", result); end

        // -1 / 1 (0x8000 / 0x4000) = -2 -> насыщение отриц. 0x8000
        op1 = 16'h8000; op2 = 16'h4000; run_op();
        checks = checks + 1;
        if (result !== 16'h8000) begin errors = errors + 1;
            $display("DIV -2 ERR got=%h", result); end

        // 0.5 / -0.25 = -2 -> насыщение 0x8000
        op1 = 16'h4000; op2 = 16'he000; run_op();
        checks = checks + 1;
        if (result !== 16'h8000) begin errors = errors + 1;
            $display("DIV -2b ERR got=%h", result); end

        //=================== 3. ДЕЛЕНИЕ: случайная выборка ===================
        begin : rnd_blk
            integer t, aa, bb;
            reg [15:0] am, bm;
            reg [31:0] qq;
            reg [16:0] mm;
            reg        gg, ss, ii, oo, nn;
            reg [15:0] ea;
            for (t = 0; t < 3000; t = t + 1) begin
                aa = $random; bb = $random;
                op1 = {aa[15], aa[14:0]};
                op2 = {bb[15], bb[14:0] & 16'h3FFF};  // исключит. 0x8000 у делителя
                if (op2 == 16'b0) op2 = 16'h0001;
                rmode = $random & 2'b11;

                // ---- эталон ----
                nn = op1[15] ^ op2[15];
                am = op1[15] ? (~op1 + 16'b1) : op1;
                bm = op2[15] ? (~op2 + 16'b1) : op2;
                oo = (bm == 16'b0);
                qq = ref_div_q17(am, bm);
                mm = qq[31:15];              // 17 бит: бит16 - целая часть
                gg = qq[14];                 // guard
                ss = |qq[13:0];              // sticky
                if (!oo && mm[16]) oo = 1'b1;             // |частное| >= 1
                if (nn && !oo && mm == 17'd32768 && !gg && !ss) oo = 1'b0; // -1 ok? нет: =1 -> ovf
                ii = 1'b0;
                if (!oo && (gg | ss)) begin
                    case (rmode)
                        2'b01:   ii = 1'b1;
                        2'b10:   ii = ss;
                        2'b11:   ii = ss | ~mm[0];
                        default: ii = 1'b0;
                    endcase
                end
                if (!oo && ii) mm = mm + 17'd1;
                if (oo || mm[16])
                    ea = nn ? 16'h8000 : 16'h7FFF;
                else if (nn && mm[15:0] != 16'b0)
                    ea = ~mm[15:0] + 16'b1 - 16'b1;       // = -mm (two's comp)
                else
                    ea = mm[15:0];

                run_op();
                checks = checks + 1;
                if (result !== ea) begin
                    errors = errors + 1;
                    if (errors < 20)
                        $display("DIV ERR op1=%h op2=%h rm=%b got=%h exp=%h",
                                 op1, op2, rmode, result, ea);
                end
            end
        end

        //=================== 4. ПРОТОКОЛ: busy/ready ========================
        // запуск во время busy игнорируется
        @(negedge clk);
        div = 1; op1 = 16'h4000; op2 = 16'h2000; rmode = 2'b00; start = 1;
        @(negedge clk); start = 0;
        checks = checks + 1;
        if (!busy) begin errors = errors + 1; $display("BUSY not set"); end
        @(negedge clk);
        checks = checks + 1;
        if (!dut.d_quo[31] && dut.cnt > 2) begin // уже считаем
        end
        @(posedge ready);
        checks = checks + 1;
        if (busy) begin errors = errors + 1; $display("BUSY still set"); end
        if (result !== 16'h7FFF) begin errors = errors + 1;
            $display("PROTO ERR got=%h", result); end

        if (errors == 0)
            $display("ALL %0d CHECKS PASSED", checks);
        else
            $display("FAILED: %0d errors out of %0d checks", errors, checks);
        $finish;
    end

    // страховка от зависания
    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
