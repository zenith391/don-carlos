const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tile = enum(u2) {
    Air,
    Tile,
    // minable tile
    Brick,

    pub fn isSolid(self: Tile) bool {
        return self == .Tile or self == .Brick;
    }
};

pub const Level = struct {
    tiles: []Tile,
    width: usize,
    height: usize,

    // Zig (currently) can't parse JSON at comptime
    // TODO: convert the JSON to level data in a separate build step
    pub fn loadFromText(allocator: Allocator, json: []const u8) !Level {
        var parser = std.json.Parser.init(allocator, false);
        defer parser.deinit();
        var tree = try parser.parse(json);
        defer tree.deinit();
        const root = tree.root.Object;

        const width = @intCast(usize, root.get("width").?.Integer);
        const height = @intCast(usize, root.get("height").?.Integer);

        const b64 = root.get("layers").?.Array.items[0].Object.get("data").?.String;
        const decodedLen = std.base64.standard.Decoder.calcSizeForSlice(b64) catch unreachable;
        const decoded = try allocator.alloc(u8, decodedLen);
        std.base64.standard.Decoder.decode(decoded, b64) catch unreachable;

        const tiles = try allocator.alloc(Tile, width * height);
        var y: usize = 0;
        while (y < height) : (y += 1) {
            var x: usize = 0;
            while (x < width) : (x += 1) {
                const pos = y * width + x;
                const int = std.mem.readIntSliceLittle(u32, decoded[pos*4..(pos+1)*4]) -| 1;
                tiles[pos] = @intToEnum(Tile, int);
            }
        }
 
        return Level {
            .tiles = tiles,
            .width = width,
            .height = height,
        };
    }

    pub fn getTile(self: Level, x: usize, y: usize) Tile {
        if (x < 0 or x >= self.width or y < 0 or y >= self.height) return .Air;
        return self.tiles[y * self.width + x];
    }

    pub fn setTile(self: Level, x: usize, y: usize, t: Tile) void {
        self.tiles[y * self.width + x] = t;
    }
};
