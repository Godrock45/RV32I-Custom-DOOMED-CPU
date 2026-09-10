// Performance probe for the pipelined core. Read-only: observes via hierarchy.
//
// A shadow valid bit mirrors the ID/EX register (cleared on stall/flush, and an
// all-zero id_instr is a flushed bubble). Every valid instruction spends exactly
// one cycle in EX -- EX never stalls -- so counting valid EX cycles counts
// retired instructions.
//
// Window: from the instruction at +START reaching EX, up to (not including) the
// halt self-loop at +HALT reaching EX. With no hazards, cycles == instructions.
`timescale 1ns/1ps
module tb_perf;
    logic clk = 0, rst = 1;
    logic [31:0] dbg_pc, dbg_instr, dbg_wb_data; logic [4:0] dbg_rd; logic dbg_reg_we, halt;
    top_wire dut(.clk(clk),.rst(rst),.dbg_pc(dbg_pc),.dbg_instr(dbg_instr),.dbg_rd(dbg_rd),
                 .dbg_reg_we(dbg_reg_we),.dbg_wb_data(dbg_wb_data),.halt(halt));
    always #5 clk = ~clk;

    integer START, HALTPC, drain;
    reg active, done, v_ex;
    integer cyc, n, stalls, flushes, loads, stores, br, brt, jl, jr, other, k, dsum;

    initial begin
        if (!$value$plusargs("START=%d", START))  START  = 0;
        if (!$value$plusargs("HALT=%d",  HALTPC)) HALTPC = 0;
        active = 0; done = 0; v_ex = 0; drain = 0;
        cyc = 0; n = 0; stalls = 0; flushes = 0;
        loads = 0; stores = 0; br = 0; brt = 0; jl = 0; jr = 0; other = 0;
        #20 rst = 0;
        #5000000 $display("TIMEOUT"); $finish;
    end

    always @(posedge clk) begin
        if (rst) v_ex <= 1'b0;
        else     v_ex <= (!dut.stall && !dut.flush && dut.id_instr != 32'd0);
    end

    always @(posedge clk) if (!rst) begin
        if (!active && !done && v_ex && dut.ex_pc == START) active = 1;
        if (active && v_ex && dut.ex_pc == HALTPC) begin active = 0; done = 1; end
        if (active) begin
            cyc = cyc + 1;
            if (v_ex) begin
                n = n + 1;
                if      (dut.ex_MemRead)                begin loads  = loads + 1;  end
                else if (dut.ex_MemWrite)               begin stores = stores + 1; end
                else if (dut.ex_Branch && !dut.ex_Jump) begin br = br + 1; if (dut.ex_cmp) brt = brt + 1; end
                else if (dut.ex_Jump && !dut.ex_Branch) begin jl = jl + 1; end
                else if (dut.ex_Jump &&  dut.ex_Branch) begin jr = jr + 1; end
                else                                    begin other = other + 1; end
            end
            if (dut.stall) stalls  = stalls + 1;
            if (dut.flush) flushes = flushes + 1;
        end
        if (done) begin
            drain = drain + 1;          // let the last writebacks retire
            if (drain == 6) begin
                dsum = 0;
                for (k = 64; k < 128; k = k + 1) dsum = dsum + dut.meme.memistan[k];
                $display("RESULT n=%0d cyc=%0d stalls=%0d flushes=%0d loads=%0d stores=%0d br=%0d brt=%0d jal=%0d jalr=%0d other=%0d s0=%0d dsum=%0d",
                         n, cyc, stalls, flushes, loads, stores, br, brt, jl, jr, other,
                         dut.npn.registers[8], dsum);
                $finish;
            end
        end
    end
endmodule
