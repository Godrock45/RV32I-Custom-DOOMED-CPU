// Load-use interlock.
//
// Forwarding cannot rescue a load whose result is needed by the very next
// instruction: the data does not exist until MEM completes. One stall cycle
// buys enough time for it to reach MEM/WB, where the distance-2 forwarding
// path can supply it.
//
// Compares the load already in EX (ID/EX) against the consumer still in ID (IF/ID).
// Purely combinational -- re-evaluated every cycle, no counter, no state.
module hazard(
    input  logic       ex_MemRead,
    input  logic [4:0] ex_rd,
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    output logic       stall
);

    assign stall = ex_MemRead && (ex_rd != 5'd0) &&
                   ((ex_rd == id_rs1) || (ex_rd == id_rs2));

endmodule
