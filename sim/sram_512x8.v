`timescale 1ns/1ps
// Independent functional model for portable RTL simulation.
// No macro timing, notifiers, physical implementation or library data.
module sram_512x8 (
    output reg [7:0] Q,
    input CLK,
    input CEN,
    input WEN,
    input [8:0] A,
    input [7:0] D
);
    reg [7:0] mem [0:511];
    // No reset or initialization: enabled writes also update Q.
    always @(posedge CLK) begin
        if (CEN === 1'b0) begin
            if (WEN === 1'b0) begin
                mem[A] <= D;
                Q <= D;
            end else if (WEN === 1'b1) begin
                Q <= mem[A];
            end else begin
                Q <= 8'hxx;
            end
        end else if (CEN !== 1'b1) begin
            Q <= 8'hxx;
        end
    end
endmodule
