const std = @import("std");
const w4 = @import("wasm4.zig");
const Gamepad = w4.Gamepad;

const Player = @import("player.zig").Player;
const Level = @import("level.zig").Level;
const Direction = @import("entity.zig").Direction;
const Resources = @import("resources.zig");

pub const Minion = struct {
    x: f32,
    y: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    direction: Direction = .Right,
    bricks: u32 = 5,

    pub usingnamespace @import("entity.zig").Mixin(Minion);
};

pub const MinionArray = std.BoundedArray(Minion, 32);
pub const Game = struct {
    time: f32 = 8,
    allocator: std.mem.Allocator,
    state: union(enum) {
        Intro: void,
        Playing: PlayingState
    },

    pub fn resetLevelAllocator(self: *Game) void {
        _ = self;
        fba.reset();
    }
};

pub const PlayingState = struct {
    level: Level,
    minions: MinionArray,
    camX: f32 = 0,
    /// You get this from mining minable tiles from the level
    /// You can either spend them in making new (expensive) tiles
    /// or by spawning minions.
    bricks: u32 = 0,
};

var player: Player = .{};
var game: Game = .{ .state = .{ .Intro = {} }, .allocator = allocator };

var oldGamepadState: u8 = undefined;

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    _ = trace;
    w4.trace(@ptrCast([*:0]const u8, msg.ptr));
    @breakpoint();
    unreachable;
}

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
    game.time += 1.0 / 60.0; // roughly
    w4.PALETTE.* = .{
        0x7c3f58,
        0xeb6b6f,
        0xf9a875,
        0xfff6d3
    };

    if (gameError) {
        w4.DRAW_COLORS.* = 2;
        w4.text("Game Error", 0, 0);
    }

    switch (game.state) {
        .Intro => {
            w4.DRAW_COLORS.* = 4;
            w4.rect(0, 0, 160, 160);
            w4.DRAW_COLORS.* = 3;

            const y = @floatToInt(i32, lerp(0, 160 / 2, std.math.min(game.time, 1))) - 20 / 2;
            if (game.time > 2 and game.time < 3) {
                const blink = @floatToInt(u16, @mod(game.time, 1.0) / 0.1);
                w4.DRAW_COLORS.* = (blink % 3) + 1;
            }
            w4.text("Zen1th", 60, y);
            w4.text("Presents", 52, y + 10);

            if (game.time > 4) {
                w4.DRAW_COLORS.* = 2;
                const name = "Don Carlos";
                const nameY = @floatToInt(i32, lerp(-10, 160 / 2, std.math.min(easeOutBounce((game.time - 4) / 2), 1)));
                w4.text(name, 80 - name.len * 4, nameY + 10);
            }
            if (game.time > 7) {
                const level = Level.loadFromText(allocator, @embedFile("../assets/levels/level2.json")) catch |err| {
                    if (std.debug.runtime_safety) {
                        const name: [:0]const u8 = @errorName(err);
                        var buf: [1000]u8 = undefined;
                        w4.trace(std.fmt.bufPrintZ(&buf, "{s}", .{ name }) catch unreachable);
                    }
                    gameError = true;
                    return;
                };
                game.state = .{ .Playing = .{
                    .minions = MinionArray.init(0) catch unreachable,
                    .level = level
                }};
            }
        },
        .Playing => {
            const play = &game.state.Playing;

            const gamepad = Gamepad { .state = w4.GAMEPAD1.* };
            const deltaGamepad = Gamepad { .state = gamepad.state ^ (oldGamepadState & gamepad.state) };
            oldGamepadState = gamepad.state;
            player.update(&game, gamepad, deltaGamepad);

            const level = play.level;

            if (player.x - play.camX > 90)
                play.camX = player.x - 90;
            if (play.camX > 0 and player.x - play.camX < 10)
                play.camX = std.math.max(player.x - 10, 0);

            if (deltaGamepad.isPressed(.X)) {
                if (play.bricks >= 5) {
                    play.bricks -= 5;
                    play.minions.append(Minion {
                        .x = player.x,
                        .y = player.y
                    }) catch {};
                }
            }

            w4.DRAW_COLORS.* = 4;
            w4.rect(0, 0, 160, 160);

            player.render(game);
            w4.DRAW_COLORS.* = 0x4321;
            for (play.minions.slice()) |*minion| {
                _ = minion.applyGravity(level, 1);
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
                w4.blit(&Resources.Minion, @floatToInt(i32, minion.x - play.camX), @floatToInt(i32, minion.y), 16, 16, w4.BLIT_2BPP);
            }

            w4.DRAW_COLORS.* = 0x4321;
            var ty: u16 = 0;
            while (ty < level.height) : (ty += 1) {
                var tx: u16 = 0;
                while (tx < level.width) : (tx += 1) {
                    const t = level.getTile(tx, ty);
                    const dx = @floatToInt(i32, @intToFloat(f32, tx * 16) - play.camX);
                    if (t != .Air) {
                        const resource = switch (t) {
                            .Air => unreachable,
                            .Tile => &Resources.Tile1,
                            .Brick => &Resources.TileBrick,
                            .DoorTop => &Resources.DoorTop,
                            .DoorBottom => &Resources.DoorBottom,
                            .StickyBall => &Resources.StickyBall,
                        };
                        w4.blit(resource, dx, ty * 16, 16, 16, w4.BLIT_2BPP);
                    }
                }
            }

            w4.DRAW_COLORS.* = 2;
            var i: u32 = 0;
            w4.DRAW_COLORS.* = 0x4321;
            while (i < play.bricks) : (i += 1) {
                const x = @intCast(i32, 55 + (i/2) * 7);
                const y = @intCast(i32, 1 + (i%2) * 3);
                w4.blit(&Resources.Brick, x, y, 8, 2, w4.BLIT_2BPP);
            }

            if (player.heldItem) |held| {
                switch (held) {
                    .StickyBall => w4.blit(&Resources.StickyBall, 140, 5, 16, 16, w4.BLIT_2BPP)
                }
            }
        }
    }
}
