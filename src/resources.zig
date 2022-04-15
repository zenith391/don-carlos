const std = @import("std");
const bmp = @import("bmp.zig");

// Menu
pub const Logo = makeImageArray(@embedFile("../assets/logo.bmp"));

// Modes
pub const MinionBuild = makeImageArray(@embedFile("../assets/overlay/builder-minion.bmp"));
pub const MinionAttack = makeImageArray(@embedFile("../assets/overlay/attack-minion.bmp"));

// Items
pub const Brick = makeImageArray(@embedFile("../assets/brick.bmp"));
pub const StickyBall = makeImageArray(@embedFile("../assets/sticky-ball.bmp"));

// Tiles
pub const SandN = makeImageArray(@embedFile("../assets/tiles/sand_n.bmp"));
pub const SandC = makeImageArray(@embedFile("../assets/tiles/sand_c.bmp"));
pub const SandNWS = makeImageArray(@embedFile("../assets/tiles/sand_nws.bmp"));
pub const SandNES = makeImageArray(@embedFile("../assets/tiles/sand_nes.bmp"));

pub const TileBrick = makeImageArray(@embedFile("../assets/tiles/brick.bmp"));
pub const TileBrickSticky = makeImageArray(@embedFile("../assets/tiles/brick-sticky.bmp"));
pub const DoorBottom = makeImageArray(@embedFile("../assets/tiles/door-bottom.bmp"));
pub const DoorTop = makeImageArray(@embedFile("../assets/tiles/door-top.bmp"));
pub const Coin = makeImageArray(@embedFile("../assets/tiles/coin.bmp"));
pub const BrickStack = makeImageArray(@embedFile("../assets/tiles/brick-stack.bmp"));

// Entities
pub const Minion = makeImageArray(@embedFile("../assets/minion.bmp"));
pub const Player = struct {
    pub const Walking = makeImageArray(@embedFile("../assets/player-walkingr.bmp"));
    pub const Walking2 = makeImageArray(@embedFile("../assets/player-walkingr2.bmp"));
    pub const Standing = makeImageArray(@embedFile("../assets/player-standing.bmp"));
};

fn MakeImageArrayReturn(comptime bmpFile: []const u8) type {
    @setEvalBranchQuota(100000);
    const image = bmp.comptimeRead(bmpFile) catch unreachable;
    return [(image.width * image.height) / 4]u8;
}

fn makeImageArray(comptime bmpFile: []const u8) MakeImageArrayReturn(bmpFile) {
    @setEvalBranchQuota(100000);
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
