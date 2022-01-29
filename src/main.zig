const std = @import("std");
const w4 = @import("wasm4.zig");
const Gamepad = w4.Gamepad;

const Item = @import("player.zig").Item;
const Player = @import("player.zig").Player;
const Level = @import("level.zig").Level;
const Direction = @import("entity.zig").Direction;
const Music = @import("music.zig").Music;
const Resources = @import("resources.zig");

pub const Minion = struct {
    x: f32,
    y: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    direction: Direction = .Right,
    bricks: u32 = 5,

    pub usingnamespace @import("entity.zig").Mixin(Minion);

    pub fn update(self: *Minion, g: *Game) void {
        const level = g.state.Playing.level;
        
        const mtx = @floatToInt(usize, @round(self.x / 16));
        const mty = @floatToInt(usize, @round(self.y / 16));
        if (level.getTile(mtx, mty+1) == .BrickSticky) {
            self.vy = -4;
        }
        _ = self.applyGravity(level, 1);
    }
};

pub const MinionArray = std.BoundedArray(Minion, 32);
pub const Game = struct {
    time: f32 = 6,
    /// Frames since the start of the game
    frames: u32 = 0,
    allocator: std.mem.Allocator,
    state: union(enum) {
        Intro: void,
        Playing: PlayingState,
        Menu: MenuState,
    },
    changedLevel: bool = false,
    music: Music = Music.readMusicCommands(@embedFile("../assets/music/menu.aaf")) catch unreachable,
    musicStart: f32 = 0,

    pub fn resetLevelAllocator(self: *Game) void {
        _ = self;
        fba.reset();
    }

    // As of now, there is a bug in WASM-4 that makes it so every game shares
    // the same save data. As a weak mitigation for that, I use a magic number
    // where if it doesn't correspond, the save data won't be loaded.
    const MAGIC_SAVEKEY: u32 = 0xD011C357;

    pub fn loadData(self: *Game) void {
        const state = &self.state.Playing;

        var buffer: [32]u8 = undefined;
        if (w4.diskr(&buffer, buffer.len) != buffer.len) {
            w4.trace("Could not load the game save.");
            return;
        }
        var stream = std.io.fixedBufferStream(&buffer);
        const reader = stream.reader();

        // check the magic number before loading
        if (reader.readIntNative(u32) catch unreachable == MAGIC_SAVEKEY) {
            player.x = @bitCast(f32, reader.readIntNative(u32) catch unreachable);
            player.y = @bitCast(f32, reader.readIntNative(u32) catch unreachable);
            const heldItem = reader.readIntNative(u8) catch unreachable;
            if (heldItem > 0) {
                player.heldItem = @intToEnum(Item, heldItem - 1);
            } else {
                player.heldItem = null;
            }
            state.bricks = reader.readIntNative(u32) catch unreachable;
            self.loadLevel(reader.readIntNative(u32) catch unreachable);
        } else {
            w4.trace("Invalid magic key");
        }
    }

    pub fn saveData(self: Game) void {
        const state = self.state.Playing;

        var buffer: [32]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        const writer = stream.writer();

        writer.writeIntNative(u32, MAGIC_SAVEKEY) catch unreachable;
        writer.writeIntNative(u32, @bitCast(u32, player.x)) catch unreachable;
        writer.writeIntNative(u32, @bitCast(u32, player.y)) catch unreachable;
        if (player.heldItem) |held| {
            writer.writeIntBig(u8, @enumToInt(held) + 1) catch unreachable;
        } else {
            writer.writeIntBig(u8, 0) catch unreachable;
        }
        writer.writeIntNative(u32, state.bricks) catch unreachable;
        writer.writeIntNative(u32, state.levelId) catch unreachable;

        if (w4.diskw(&buffer, buffer.len) != buffer.len) {
            w4.trace("Could not save the game.");
        }
    }

    pub fn loadLevel(self: *Game, id: usize) void {
        self.changedLevel = true;
        self.musicStart = self.time;
        self.music = comptime Music.readMusicCommands(@embedFile("../assets/music/game.aaf")) catch unreachable;
        if (id == 3) {
            gameFinished = true;
            return;
        }

        self.resetLevelAllocator();
        var level: Level = undefined;
        gameError = true;

        comptime var i: usize = 0;
        inline while (i < 3) : (i += 1) {
            if (i == id) {
                level = Level.loadLevelId(self.allocator, i) catch |err| {
                    if (std.debug.runtime_safety) {
                        const name: [:0]const u8 = @errorName(err);
                        var buf: [1000]u8 = undefined;
                        w4.trace(std.fmt.bufPrintZ(&buf, "{s}", .{ name }) catch unreachable);
                    }
                    gameError = true;
                    return;
                };
                gameError = false;
            }
        }
        self.state = .{ .Playing = .{
            .minions = MinionArray.init(0) catch unreachable,
            .level = level,
            .levelId = id,
        }};
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
    levelId: u32,
};

pub const MenuState = struct {
    selectedButton: u1 = 0,
};

var player: Player = .{};
var game: Game = .{ .state = .{ .Intro = {} }, .allocator = allocator };
var oldGamepadState: u8 = undefined;
var gameFinished: bool = false;

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
    game.frames += 1;

    w4.PALETTE.* = .{
        0x7c3f58,
        0xeb6b6f,
        0xf9a875,
        0xfff6d3
    };

    if (gameError) {
        w4.DRAW_COLORS.* = 2;
        w4.text("Game Error", 0, 0);
        return;
    }
    if (gameFinished) {
        w4.DRAW_COLORS.* = 2;
        w4.text("You finished the", 0, 60);
        w4.text("game as sadly I", 0, 70);
        w4.text("couldn't add more", 0, 80);
        w4.text(":'(", 0, 90);
        return;
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
            if (game.time >= 7) {
                game.state = .{ .Menu = .{} };
            }
        },
        .Menu => {
            const menu = &game.state.Menu;
            const gamepad = Gamepad { .state = w4.GAMEPAD1.* };
            const deltaGamepad = Gamepad { .state = gamepad.state ^ (oldGamepadState & gamepad.state) };
            oldGamepadState = gamepad.state;
            game.music.play(game.time - 7);

            w4.DRAW_COLORS.* = 4;
            w4.rect(0, 0, 160, 160);
            w4.DRAW_COLORS.* = 0x4321;

            const logoX = @floatToInt(i32, lerp(-100, 160 / 2 - 96 / 2, std.math.min(easeOutBounce((game.time - 7) / 2), 1)));
            w4.blit(&Resources.Logo, logoX, 20, 96, 32, w4.BLIT_2BPP);

            var playerSprite = &Resources.Player.Standing;
            if (@mod(game.time, 0.5) >= 0 and @mod(game.time, 0.5) < (0.5 / 3.0)) {
                playerSprite = &Resources.Player.Walking;
            } else if (@mod(game.time, 0.5) < (0.5 / 3.0) * 2.0) {
                playerSprite = &Resources.Player.Standing;
            } else {
                playerSprite = &Resources.Player.Walking2;
            }

            const playerX = @floatToInt(i32, lerp(-16, 160, std.math.max(0, @mod((game.time - 10), 2) / 2)));
            w4.blit(playerSprite, playerX, 120, 16, 16, w4.BLIT_2BPP);

            w4.DRAW_COLORS.* = 2;
            w4.text("Continue", 50, 70);
            w4.text("New Game", 50, 80);
            w4.text(">", 40, 70 + @as(i32, menu.selectedButton) * 10);

            if (deltaGamepad.isPressed(.Up)) {
                menu.selectedButton -|= 1;
            }
            if (deltaGamepad.isPressed(.Down)) {
                menu.selectedButton +|= 1;
            }

            if (deltaGamepad.isPressed(.X)) {
                switch (menu.selectedButton) {
                    0 => { // continue
                        game.loadLevel(0);
                        game.loadData();
                    },
                    1 => { // new game
                        game.loadLevel(0);
                    }
                }
            }
        },
        .Playing => {
            const play = &game.state.Playing;
            game.music.play(game.time - game.musicStart);

            const gamepad = Gamepad { .state = w4.GAMEPAD1.* };
            const deltaGamepad = Gamepad { .state = gamepad.state ^ (oldGamepadState & gamepad.state) };
            oldGamepadState = gamepad.state;
            player.update(&game, gamepad, deltaGamepad);
            if (game.changedLevel) {
                game.changedLevel = false;
                return;
            }

            if (game.frames % 120 == 0) { // save every ~2 seconds
                game.saveData();
            }

            const level = play.level;

            if (player.x - play.camX > 90)
                play.camX = player.x - 90;
            if (play.camX > 0 and player.x - play.camX < 10)
                play.camX = std.math.max(player.x - 10, 0);

            w4.DRAW_COLORS.* = 4;
            w4.rect(0, 0, 160, 160);

            player.render(game);
            w4.DRAW_COLORS.* = 0x4321;
            for (play.minions.slice()) |*minion| {
                minion.update(&game);
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
                            .Sand2 => &Resources.Sand2,
                            .Brick => &Resources.TileBrick,
                            .DoorTop => &Resources.DoorTop,
                            .DoorBottom => &Resources.DoorBottom,
                            .StickyBall => &Resources.StickyBall,
                            .Coin => &Resources.Coin,
                            .BrickSticky => &Resources.TileBrickSticky,
                            .BrickStack => &Resources.BrickStack,
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
