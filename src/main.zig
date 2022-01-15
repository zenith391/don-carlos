const std = @import("std");
const w4 = @import("wasm4.zig");
const bmp = @import("bmp.zig");

const Gamepad = struct {
    state: u8,

    pub const Button = enum(u8) {
        Left = w4.BUTTON_LEFT,
        Right = w4.BUTTON_RIGHT,
        Down = w4.BUTTON_DOWN,
        Up = w4.BUTTON_UP,
        X = w4.BUTTON_1,
        Y = w4.BUTTON_2,
    };

    pub fn isPressed(self: Gamepad, button: Button) bool {
        return self.state & @enumToInt(button) != 0;
    }
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

const Resources = struct {
    pub const Brick = makeImageArray(@embedFile("../assets/brick.bmp"));
    pub const Tile1 = makeImageArray(@embedFile("../assets/tile1.bmp"));
    pub const TileBrick = makeImageArray(@embedFile("../assets/tile-brick.bmp"));
    pub const Minion = makeImageArray(@embedFile("../assets/minion.bmp"));
    pub const Player = struct {
        pub const Walking = makeImageArray(@embedFile("../assets/player-walkingr.bmp"));
        pub const Walking2 = makeImageArray(@embedFile("../assets/player-walkingr2.bmp"));
        pub const Standing = makeImageArray(@embedFile("../assets/player-standing.bmp"));
    };
};

const CollisionInfo = struct {
    collidesH: bool,
    collidesV: bool,
};

fn applyGravity(self: anytype, speed: f32) CollisionInfo {
    const gravity = 0.2;
    const friction = 1.5;
    const bounciness = 0.25;

    self.vy += gravity;
    self.x += self.vx;
    if (self.x < 0) self.x = 0;
    self.vx /= friction;

    if (speed != 0) {
        self.vx = speed;
    }

    if (self.vx > 0.01) self.direction = .Right;
    if (self.vx < -0.01) self.direction = .Left;

    const targetY = self.y + self.vy;
    const tx = @floatToInt(usize, (self.x + self.vx) / 16);
    const ty = @floatToInt(usize, (self.y) / 16);

    var collidesH = false;
    var collidesV = false;
    if (self.vy > 0) {
        if (level.getTile(tx, ty+1).isSolid() or level.getTile(tx+1, ty+1).isSolid()) {
            collidesV = true;
        }
    }
    if (self.vx > 0 and level.getTile(tx+1, ty).isSolid()) {
        collidesH = true;
    } else if (self.vx < 0 and level.getTile(tx, ty).isSolid()) {
        collidesH = true;
    }


    if (collidesV) {
        _ = bounciness;
        self.vy = -self.vy * bounciness;
    } else {
        self.y = targetY;
    }
    if (collidesH) self.vx = 0;

    return CollisionInfo { .collidesH = collidesH, .collidesV = collidesV };
}

const Direction = enum { Left, Right };
const Player = struct {
    x: f32 = 0,
    y: f32 = 0,
    vx: f32 = 0,
    vy: f32 = 0,
    direction: Direction = .Right,

    pub fn update(self: *Player, gamepad: Gamepad, deltaGamepad: Gamepad) void {
        if (deltaGamepad.isPressed(.Down)) {
            const vx: f32 = if (self.direction == .Left) -16 else 20;
            const tx = @floatToInt(usize, (self.x + vx) / 16);
            const ty = @floatToInt(usize, (self.y) / 16);
            if (level.getTile(tx, ty) == .Brick) {
                level.setTile(tx, ty, .Air);
                bricks += 1;
            }
        }

        var speed: f32 = 0;
        if (gamepad.isPressed(.Left))
            speed = -2;
        if (gamepad.isPressed(.Right))
            speed = 2;

        const collidesV = applyGravity(self, speed).collidesV;

        if (collidesV and gamepad.isPressed(.Up))
            self.vy = -4;
    }

    pub fn render(self: Player) void {
        w4.DRAW_COLORS.* = 0x4321;
        var playerSprite = &Resources.Player.Standing;
        if (!std.math.approxEqAbs(f32, self.vx, 0, 0.01)) {
            if (@mod(time, 0.5) >= 0 and @mod(time, 0.5) < (0.5 / 3.0)) {
                playerSprite = &Resources.Player.Walking;
            } else if (@mod(time, 0.5) < (0.5 / 3.0) * 2.0) {
                playerSprite = &Resources.Player.Standing;
            } else {
                playerSprite = &Resources.Player.Walking2;
            }
        }
        w4.blit(playerSprite, @floatToInt(i32, self.x - camX), @floatToInt(i32, self.y), 16, 16, w4.BLIT_2BPP |
            if (self.direction == .Right) 0 else w4.BLIT_FLIP_X);
    }
};

const Tile = enum(u2) {
    Air,
    Tile,
    // minable tile
    Brick,

    pub fn isSolid(self: Tile) bool {
        return self == .Tile or self == .Brick;
    }
};

const Level = struct {
    tiles: []Tile,
    width: usize,
    height: usize,

    pub fn loadFromText(json: []const u8) !Level {
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

    pub fn setTile(self: *Level, x: usize, y: usize, t: Tile) void {
        self.tiles[y * self.width + x] = t;
    }
};

const Minion = struct {
    x: f32,
    y: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    direction: Direction = .Right,
    bricks: u32 = 5,
};

const MinionArray = std.BoundedArray(Minion, 32);
const GameState = union(enum) {
    Intro: void,
    Playing: struct {
        minions: MinionArray
    },
};

var player: Player = .{};
var state: GameState = .{ .Intro = {} };
//var level: Level = Level.init();
var level: Level = undefined;
var camX: f32 = 0;
var time: f32 = 0;

/// You get this from mining minable tiles from the level
/// You can either spend them in making new (expensive) tiles
/// or by spawning minions.
var bricks: u32 = 5;

var oldGamepadState: u8 = undefined;

fn easeOutBounce(x: f32) f32 {
    const n1 = 7.5625;
    const d1 = 2.75;

    if (x < 1 / d1) {
        return n1 * x * x;
    } else if (x < 2 / d1) {
        return n1 * (x - 1.5 / d1) * (x - 1.5 / d1) + 0.75;
    } else if (x < 2.5 / d1) {
        return n1 * (x - 2.25 / d1) * (x - 2.25 / d1) + 0.9375;
    } else {
        return n1 * (x - 2.625 / d1) * (x - 2.625 / d1) + 0.984375;
    }
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a * (1 - t) + b * t;
}

var fbaBuf: [10000]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&fbaBuf);
const allocator = fba.allocator();

var gameError = false;
var levelLoaded = false;
export fn update() void {
    time += 1.0 / 60.0; // roughly
    w4.PALETTE.* = .{
        0x7c3f58,
        0xeb6b6f,
        0xf9a875,
        0xfff6d3
    };


    if (!levelLoaded) {
        levelLoaded = true;
        w4.trace("load level");
        level = Level.loadFromText(@embedFile("../assets/level1.json")) catch |err| {
            if (std.debug.runtime_safety) {
                const name: [:0]const u8 = @errorName(err);
                var buf: [1000]u8 = undefined;
                w4.trace(std.fmt.bufPrintZ(&buf, "{s}", .{ name }) catch unreachable);
            }
            gameError = true;
            return;
        };
    }

    if (gameError) {
        w4.DRAW_COLORS.* = 2;
        w4.text("Game Error", 0, 0);

    }

    switch (state) {
        .Intro => {
            w4.DRAW_COLORS.* = 4;
            w4.rect(0, 0, 160, 160);
            w4.DRAW_COLORS.* = 3;

            const y = @floatToInt(i32, lerp(0, 160 / 2, std.math.min(time, 1))) - 20 / 2;
            if (time > 2 and time < 3) {
                const blink = @floatToInt(u16, @mod(time, 1.0) / 0.1);
                w4.DRAW_COLORS.* = (blink % 3) + 1;
            }
            w4.text("Zen1th", 60, y);
            w4.text("Presents", 52, y + 10);

            if (time > 4) {
                w4.DRAW_COLORS.* = 2;
                const name = "Don Carlos";
                const nameY = @floatToInt(i32, lerp(-10, 160 / 2, std.math.min(easeOutBounce((time - 4) / 2), 1)));
                w4.text(name, 80 - name.len * 4, nameY + 10);
            }
            if (time > 7) {
                state = .{ .Playing = .{
                    .minions = MinionArray.init(0) catch unreachable
                }};
            }
        },
        .Playing => {
            const play = &state.Playing;

            const gamepad = Gamepad { .state = w4.GAMEPAD1.* };
            const deltaGamepad = Gamepad { .state = gamepad.state ^ (oldGamepadState & gamepad.state) };
            oldGamepadState = gamepad.state;
            player.update(gamepad, deltaGamepad);

            if (player.x - camX > 90)
                camX = player.x - 90;
            if (camX > 0 and player.x - camX < 10)
                camX = std.math.max(player.x - 10, 0);

            if (deltaGamepad.isPressed(.X)) {
                if (bricks >= 5) {
                    bricks -= 5;
                    play.minions.append(Minion {
                        .x = player.x,
                        .y = player.y
                    }) catch {};
                }
            }

            w4.DRAW_COLORS.* = 4;
            w4.rect(0, 0, 160, 160);

            player.render();
            w4.DRAW_COLORS.* = 0x4321;
            for (play.minions.slice()) |*minion| {
                _ = applyGravity(minion, 1);
                if (minion.bricks > 0) {
                    const tx = @floatToInt(usize, minion.x / 16);
                    const ty = @floatToInt(usize, minion.y / 16);
                    if (level.getTile(tx, ty+1) == .Air) {
                        level.setTile(tx, ty+1, .Brick);
                        minion.bricks -= 1;
                    }
                } else {
                    // TODO: remove
                }
                w4.blit(&Resources.Minion, @floatToInt(i32, minion.x - camX), @floatToInt(i32, minion.y), 16, 16, w4.BLIT_2BPP);
            }

            w4.DRAW_COLORS.* = 0x4321;
            var ty: u16 = 0;
            while (ty < level.height) : (ty += 1) {
                var tx: u16 = 0;
                while (tx < level.width) : (tx += 1) {
                    const t = level.getTile(tx, ty);
                    const dx = @floatToInt(i32, @intToFloat(f32, tx * 16) - camX);
                    if (t == .Tile) {
                        w4.blit(&Resources.Tile1, dx, @as(i32, ty * 16), 16, 16, w4.BLIT_2BPP);
                    } else if (t == .Brick) {
                        w4.blit(&Resources.TileBrick, dx, @as(i32, ty * 16), 16, 16, w4.BLIT_2BPP);
                    }
                }
            }


            w4.DRAW_COLORS.* = 2;
            w4.text("Bricks:", 0, 0);
            var i: u32 = 0;
            w4.DRAW_COLORS.* = 0x4321;
            while (i < bricks) : (i += 1) {
                const x = @intCast(i32, 55 + (i/2) * 7);
                const y = @intCast(i32, 1 + (i%2) * 3);
                w4.blit(&Resources.Brick, x, y, 8, 2, w4.BLIT_2BPP);
            }
            w4.DRAW_COLORS.* = 2;

            //const minionsText = std.fmt.bufPrintZ(&buf, "{d}", .{ play.minions.len }) catch unreachable;
            //w4.text("Minions:", 0, 8);
            //w4.text(minionsText.ptr, 160 - @intCast(i32, minionsText.len) * 8, 8);
        }
    }
}
