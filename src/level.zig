const std = @import("std");
const w4 = @import("wasm4.zig");
const Allocator = std.mem.Allocator;

pub const Tile = enum(u4) {
    Air,
    Tile,
    Brick,
    DoorBottom,
    DoorTop,
    StickyBall,
    Sand2,
    Coin,
    // sticky brick is actually a bouncing break so don't mind the name
    BrickSticky,

    pub fn isSolid(self: Tile) bool {
        return self == .Tile or self == .Brick or self == .BrickSticky or
            self == .Sand2;
    }
};

pub const Level = struct {
    tiles: []Tile,
    width: usize,
    height: usize,
    allocator: Allocator,

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
        const decodedLen = try std.base64.standard.Decoder.calcSizeForSlice(b64);

        const decoded = try allocator.alloc(u8, decodedLen);
        defer allocator.free(decoded);
        try std.base64.standard.Decoder.decode(decoded, b64);

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
            .allocator = allocator,
        };
    }

    pub fn loadLevelId(allocator: Allocator, comptime id: usize) !Level {
        const levelsModule = @import("levels");
        const data = comptime @field(levelsModule, std.fmt.comptimePrint("level_{d}_data", .{ id }));
        const width = comptime @field(levelsModule, std.fmt.comptimePrint("level_{d}_width", .{ id }));
        const height = comptime @field(levelsModule, std.fmt.comptimePrint("level_{d}_height", .{ id }));

        const tiles = try allocator.alloc(Tile, data.len);
        for (data) |tid, i| {
            tiles[i] = @intToEnum(Tile, tid);
        }

        return Level {
            .tiles = tiles,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    pub fn getTile(self: Level, x: usize, y: usize) Tile {
        if (x < 0 or x >= self.width or y < 0 or y >= self.height) return .Air;
        return self.tiles[y * self.width + x];
    }

    pub fn setTile(self: Level, x: usize, y: usize, t: Tile) void {
        self.tiles[y * self.width + x] = t;
    }

    pub fn deinit(self: Level) void {
        self.allocator.free(self.tiles);
    }
};
