const std = @import("std");
const bmp = @import("bmp.zig");

// Items
pub const Brick = makeImageArray(@embedFile("../assets/brick.bmp"));
pub const StickyBall = makeImageArray(@embedFile("../assets/sticky-ball.bmp"));

// Tiles
pub const Tile1 = makeImageArray(@embedFile("../assets/tiles/sand.bmp"));
pub const TileBrick = makeImageArray(@embedFile("../assets/tiles/brick.bmp"));
pub const DoorBottom = makeImageArray(@embedFile("../assets/tiles/door-bottom.bmp"));
pub const DoorTop = makeImageArray(@embedFile("../assets/tiles/door-top.bmp"));

// Entities
pub const Minion = makeImageArray(@embedFile("../assets/minion.bmp"));
pub const Player = struct {
    pub const Walking = makeImageArray(@embedFile("../assets/player-walkingr.bmp"));
    pub const Walking2 = makeImageArray(@embedFile("../assets/player-walkingr2.bmp"));
    pub const Standing = makeImageArray(@embedFile("../assets/player-standing.bmp"));
};

fn MakeImageArrayReturn(comptime bmpFile: []const u8) type {
    @setEvalBranchQuota(10000);
    const image = bmp.comptimeRead(bmpFile) catch unreachable;
    return [(image.width * image.height) / 4]u8;
}

fn makeImageArray(comptime bmpFile: []const u8) MakeImageArrayReturn(bmpFile) {
    @setEvalBranchQuota(10000);
    const image = bmp.comptimeRead(bmpFile) catch unreachable;
    var pixels: [image.width * image.height]u2 = undefined;
    var y: usize = 0;

    // assumes the BMP file uses indexed color and that it corresponds to the expected palette
    while (y < image.height) : (y += 1) {
        var x: usize = 0;
        while (x < image.width) : (x += 1) {
            const pos = y * image.width + x;
            const paletteIndex: u8 = image.data[pos];
            if (paletteIndex > 4) {
                @compileError(std.fmt.comptimePrint("Pixel {d}, {d} does not correspond to the palette, it has index {d}", .{ x, y, paletteIndex }));
            } else if (paletteIndex == 0) {
                // TODO transparency
                pixels[pos] = 3;
            } else {
                pixels[pos] = @intCast(u2, paletteIndex - 1);
            }
        }
    }

    var bytes: [(image.width * image.height) / 4]u8 = undefined;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const pos = i * 4;
        bytes[i] =
            (@as(u8, pixels[pos  ]) << 6) |
            (@as(u8, pixels[pos+1]) << 4) |
            (@as(u8, pixels[pos+2]) << 2) |
             @as(u8, pixels[pos+3]);
    }

    return bytes;
}
