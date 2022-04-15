const std = @import("std");
const w4 = @import("wasm4.zig");
const Allocator = std.mem.Allocator;

pub const Tile = enum(u4) {
    Air,
    SandN,
    Brick,
    DoorBottom,
    DoorTop,
    StickyBall,
    SandC,
    Coin,
    // sticky brick is actually a bouncing break so don't mind the name
    BrickSticky,
    BrickStack,
    SandNWS,
    SandNES,

    pub fn isSolid(self: Tile) bool {
        return self == .SandN or self == .SandC or self == .SandNWS or self == .SandNES or self == .Brick or self == .BrickSticky;
    }
};

pub const Level = struct {
    tiles: []Tile,
    width: usize,
    height: usize,
    allocator: Allocator,

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
