const std = @import("std");

const Base64 = struct {
    /// lookup table
    _encode_table: *const [64]u8,
    _decode_table: *const [256]u8,

    pub fn init() Base64 {
        const first26 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const second26 = "abcdefghijklmnopqrstuvwxyz";
        const last12 = "0123456789+/";
        const encode_table = first26 ++ second26 ++ last12;

        const decode_table = comptime block: {
            var table = [_]u8{255} ** 256;
            for (encode_table, 0..) |ch, i| {
                table[ch] = i;
            }
            break :block table;
        };

        return Base64{
            ._encode_table = encode_table,
            ._decode_table = &decode_table,
        };
    }

    pub fn _char_at(self: Base64, index: usize) u8 {
        return self._encode_table[index];
    }

    pub fn _value_at(self: Base64, ch: u8) u8 {
        return self._decode_table[ch];
    }
};

pub fn _calc_encode_length(input: []const u8) !usize {
    return if (input.len < 3) 4 else try std.math.divCeil(usize, input.len, 3) * 4;
}

pub fn _calc_decode_length(input: []const u8) !usize {
    var decode_len: usize = if (input.len < 3) 4 else try std.math.divFloor(usize, input.len, 4) * 3;
    var i: usize = input.len - 1;
    while (i > 0) : (i -= 1) {
        if (input[i] == '=') {
            decode_len -= 1;
        } else {
            break;
        }
    }
    return decode_len;
}

pub fn encode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    if (input.len == 0) {
        return "";
    }
    const size: usize = try _calc_encode_length(input);
    var bf = [_]u8{0} ** 3;
    var bf_idx: u8 = 0;
    var code: []u8 = try allocator.alloc(u8, size);
    var code_idx: usize = 0;

    for (input, 0..) |_, i| {
        bf[bf_idx] = input[i]; // load the buffer
        bf_idx += 1;

        if (bf_idx == 3) { // once the buffer is full
            var bits: u8 = undefined; // holds the 6 bit codes

            // first chunk - first 6 bits of bf[0]
            bits = bf[0] >> 2;
            code[code_idx + 0] = self._char_at(bits);

            // second chunk
            // concatenate(last 2 of bf[0], first 4 of bf[1])
            bits = ((bf[0] & 0x03) << 4) + (bf[1] >> 4);
            code[code_idx + 1] = self._char_at(bits);

            // third chunk
            // concatenate(last 4 of bf[1], first 2 of bf[2])
            bits = ((bf[1] & 0x0F) << 2) + (bf[2] >> 6);
            code[code_idx + 2] = self._char_at(bits);

            // fourth 6 bits
            // last 6 of bf[2]
            bits = bf[2] & 0x3F;
            code[code_idx + 3] = self._char_at(bits);

            code_idx += 4; // move on to the next section of the output
            bf_idx = 0; // "clear" the buffer
        }
    }

    // if input.len % 3 != 0, there will be bytes left in the buffer

    if (bf_idx == 2) {
        var bits: u8 = undefined;

        // first chunk - first 6 bits of bf[0]
        bits = bf[0] >> 2;
        code[code_idx + 0] = self._char_at(bits);

        //  second chunk
        //  concatenate(last 2 of bf[0], first 4 of bf[1])
        bits = ((bf[0] & 0x03) << 4) + (bf[1] >> 4);
        code[code_idx + 1] = self._char_at(bits);

        // third chunk
        // concatenate(last 4 of bf[1], 0)
        bits = (bf[1] & 0x0F) << 2;
        code[code_idx + 2] = self._char_at(bits);

        code[code_idx + 3] = '=';
    }

    if (bf_idx == 1) {
        var bits: u8 = undefined;

        // first chunk - first 6 bits of bf[0]
        bits = bf[0] >> 2;
        code[code_idx + 0] = self._char_at(bits);

        //  second chunk
        //  concatenate(last 2 of bf[0], 0)
        bits = (bf[0] & 0x03) << 4;
        code[code_idx + 1] = self._char_at(bits);

        code[code_idx + 2] = '=';
        code[code_idx + 3] = '=';
    }
    return code;
}

pub fn decode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // todo notify of malformed input
    //  (a) length%4 != 0 == malformed

    if (input.len == 0) {
        return "";
    }

    const size: usize = try _calc_decode_length(input);
    var bf = [_]u8{0} ** 4;
    var bf_idx: u8 = 0;
    var code: []u8 = try allocator.alloc(u8, size);
    var code_idx: usize = 0;

    const chars = blk: {
        var len = input.len;
        var i = input.len - 1;
        while (i > 0) : (i -= 1) {
            if (input[i] == '=') {
                len -= 1;
            } else {
                break;
            }
        }
        break :blk len;
    };

    var byte: u8 = undefined;

    for (0..chars) |i| {
        bf[bf_idx] = self._value_at(input[i]);
        bf_idx += 1;

        if (bf_idx == 4) { // once the buffer is full
            // turn 4 bytes into 3

            // first byte
            // concatenate(last 6 of bf[0], first 2 of bf[1])
            byte = (bf[0] << 2) + (bf[1] >> 4);
            code[code_idx + 0] = byte;

            // second byte
            // concatenate(last 4 of bf[1], first 4 of bf[2])
            byte = (bf[1] << 4) + (bf[2] >> 2);
            code[code_idx + 1] = byte;

            // third byte
            // concatenate(last 2 of bf[2], first 6 of bf[3])
            byte = (bf[2] << 6) + bf[3];
            code[code_idx + 2] = byte;

            bf_idx = 0;
            code_idx += 3;
        }
    }

    if (bf_idx == 3) {
        // first byte
        // concatenate(last 6 of bf[0], first 2 of bf[1])
        byte = (bf[0] << 2) + (bf[1] >> 4);
        code[code_idx + 0] = byte;

        // second byte
        // concatenate(last 4 of bf[1], first 4 of bf[2])
        byte = (bf[1] << 4) + (bf[2] >> 2);
        code[code_idx + 1] = byte;
    }

    if (bf_idx == 2) {
        // first byte
        // concatenate(last 6 of bf[0], first 2 of bf[1])
        byte = (bf[0] << 2) + (bf[1] >> 4);
        code[code_idx + 0] = byte;
    }
    return code;
}

pub fn main() !void {
    // const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    if (std.os.argv.len == 2) {
        try print_usage(stdout);
    } else if (std.os.argv.len == 3) {
        if (std.mem.eql(u8, std.mem.span(std.os.argv[1]), "-es")) {
            try stdout.print("Sorry, so file/url safe mode yet.\n", .{});
        } else if (std.mem.eql(u8, std.mem.span(std.os.argv[1]), "-d")) {
            var memory_buffer: [4096]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&memory_buffer);
            const allocator = fba.allocator();
            const b64: Base64 = Base64.init();
            const input = std.mem.span(std.os.argv[2]);
            const code = try decode(b64, allocator, input);
            try stdout.print("{s}\n", .{code});
        } else if (std.mem.eql(u8, std.mem.span(std.os.argv[1]), "-e")) {
            var memory_buffer: [4096]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&memory_buffer);
            const allocator = fba.allocator();
            const b64: Base64 = Base64.init();
            const input = std.mem.span(std.os.argv[2]);
            const code = try encode(b64, allocator, input);
            try stdout.print("{s}\n", .{code});
        } else {
            try print_usage(stdout);
        }
    } else {
        try print_usage(stdout);
    }
}

pub fn print_usage(stdout: anytype) !void {
    try stdout.print(
        \\
        \\Usage:
        \\    base64 -e <string>
        \\        base-64 encoding of <string>
        \\
        \\    base64 -es <string>
        \\        url/file safe base-64 encoding of <string>
        \\
        \\    base64 -d <string>
        \\        decode string
        \\
        \\
    , .{});
}
