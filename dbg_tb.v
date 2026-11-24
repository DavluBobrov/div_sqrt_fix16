`timescale 1ns/1ps
module dbg_tb;
reg clk=0, reset=1, start=0, div=0; reg [15:0] op1=0,op2=0; reg [1:0] rmode=0;
wire [15:0] result; wire ready,busy;
div_sqrt_fixed16 d(.clk(clk),.reset(reset),.start(start),.div(div),.op1(op1),.op2(op2),.rmode(rmode),.result(result),.ready(ready),.busy(busy));
always #5 clk=~clk;
task run; begin @(negedge clk); start=1; @(negedge clk); start=0; @(posedge ready); end endtask
initial begin
  repeat(3) @(negedge clk); reset=0; repeat(2) @(negedge clk);
  div=0; op2=16'h4000; rmode=0; run; $display("sqrt .25 = %h (exp 5a82)", result);
  div=0; op2=16'h0001; run; $display("sqrt 1LSB = %h (exp 00b5)", result);
  div=1; op1=16'h4000; op2=16'h4000; run; $display("div .5/.5 = %h (exp 7fff)", result);
  div=1; op1=16'h2000; op2=16'h6000; run; $display("div .25/.75 = %h (exp 2aaa)", result);
  $finish;
end
endmodule
