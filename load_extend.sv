// Selects the addressed byte/halfword out of the word the memory returned,
// then sign- or zero-extends it according to funct3.
//
//   funct3[1:0] = width   (00 byte, 01 half, 10 word)
//   funct3[2]   = 1 -> unsigned (LBU/LHU), 0 -> signed (LB/LH)
//
// Lives on the CPU side of the memory: extension is instruction semantics,
// not storage behaviour, so it stays correct for every device on a bus.
module load_extend(
    input  logic [31:0] mem_dat,    // raw word from memory
    input  logic [1:0]  addr_lo,    // address bits [1:0] -- which lane
    input  logic [2:0]  funct3,
    output logic [31:0] load_data
);

    logic [7:0]  b;
    logic [15:0] h;

    assign b = mem_dat[8  * addr_lo    +: 8];
    assign h = mem_dat[16 * addr_lo[1] +: 16];

    always_comb begin
        case (funct3)
            3'b000:  load_data = {{24{b[7]}},  b};   // LB   signed
            3'b001:  load_data = {{16{h[15]}}, h};   // LH   signed
            3'b010:  load_data = mem_dat;            // LW
            3'b100:  load_data = {24'b0, b};         // LBU  unsigned
            3'b101:  load_data = {16'b0, h};         // LHU  unsigned
            default: load_data = 32'b0;
        endcase
    end

endmodule
