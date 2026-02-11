module telemetry_rx (
    input  wire        clk,
    input  wire        rst,

    input  wire [7:0]  rx_byte,
    input  wire        rx_valid,

    output reg         packet_valid,
    output reg [15:0]  packet_id,
    output reg [31:0]  line_number,
    output reg [15:0]  payload_size,

    output reg [7:0]   payload_byte,
    output reg         payload_valid
);

    //-----------------------------------------
    // Parameters
    //-----------------------------------------
    localparam SYNC_WORD = 16'hABCD;

    localparam S_SYNC1   = 0,
               S_SYNC2   = 1,
               S_HEADER  = 2,
               S_PAYLOAD = 3,
               S_DONE    = 4;

    reg [2:0] state;

    //-----------------------------------------
    // Internal Registers
    //-----------------------------------------
    reg [15:0] sync_shift;

    reg [3:0]  header_count;
    reg [31:0] crc_received;
    reg [31:0] crc_calc;

    reg [15:0] payload_count;

    //-----------------------------------------
    // CRC32 function (same polynomial)
    //-----------------------------------------
    function [31:0] crc32;
        input [31:0] crc;
        input [7:0]  data;
        integer i;
        begin
            crc32 = crc ^ (data << 24);
            for (i = 0; i < 8; i = i + 1) begin
                if (crc32[31])
                    crc32 = (crc32 << 1) ^ 32'h04C11DB7;
                else
                    crc32 = crc32 << 1;
            end
        end
    endfunction

    //-----------------------------------------
    // FSM
    //-----------------------------------------
    always @(posedge clk) begin

        if (rst) begin
            state <= S_SYNC1;
            packet_valid <= 0;
            payload_valid <= 0;
        end
        else if (rx_valid) begin

            packet_valid <= 0;
            payload_valid <= 0;

            case (state)

            //---------------------------------
            // SEARCH SYNC (2 bytes)
            //---------------------------------
            S_SYNC1: begin
                sync_shift[15:8] <= rx_byte;
                state <= S_SYNC2;
            end

            S_SYNC2: begin
                sync_shift[7:0] <= rx_byte;

                if (sync_shift == SYNC_WORD) begin
                    header_count <= 0;
                    crc_calc <= 32'hFFFFFFFF;
                    state <= S_HEADER;
                end
                else begin
                    state <= S_SYNC1;
                end
            end

            //---------------------------------
            // READ HEADER
            //---------------------------------
            S_HEADER: begin

                case (header_count)

                    0: packet_id[15:8] <= rx_byte;
                    1: packet_id[7:0]  <= rx_byte;

                    2: line_number[31:24] <= rx_byte;
                    3: line_number[23:16] <= rx_byte;
                    4: line_number[15:8]  <= rx_byte;
                    5: line_number[7:0]   <= rx_byte;

                    6: payload_size[15:8] <= rx_byte;
                    7: payload_size[7:0]  <= rx_byte;

                    8: crc_received[31:24] <= rx_byte;
                    9: crc_received[23:16] <= rx_byte;
                    10: crc_received[15:8] <= rx_byte;
                    11: crc_received[7:0]  <= rx_byte;

                endcase

                header_count <= header_count + 1;

                if (header_count == 11) begin
                    payload_count <= 0;
                    state <= S_PAYLOAD;
                end

            end

            //---------------------------------
            // READ PAYLOAD + COMPUTE CRC
            //---------------------------------
            S_PAYLOAD: begin

                payload_byte <= rx_byte;
                payload_valid <= 1;

                crc_calc <= crc32(crc_calc, rx_byte);

                payload_count <= payload_count + 1;

                if (payload_count == payload_size - 1) begin
                    state <= S_DONE;
                end

            end

            //---------------------------------
            // CHECK CRC
            //---------------------------------
            S_DONE: begin

                if (~crc_calc == crc_received)
                    packet_valid <= 1;

                state <= S_SYNC1;

            end

            endcase

        end
    end

endmodule
