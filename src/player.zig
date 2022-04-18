const std = @import("std");
const w4 = @import("wasm4.zig");
const entity = @import("entity.zig");
const Game = @import("main.zig").Game;
const Resources = @import("resources.zig");
const Level = @import("level.zig").Level;
const MinionArray = @import("main.zig").MinionArray;
const Minion = @import("minion.zig").Minion;

pub const Item = enum(u8) {
    StickyBall
};

pub const Player = struct {
    x: f32 = 0,
    y: f32 = 0,
    vx: f32 = 0,
    vy: f32 = 0,
    direction: entity.Direction = .Right,
    heldItem: ?Item = null,
    nextMinionMode: Minion.Mode = .Build,

    pub usingnamespace entity.Mixin(Player);

    pub fn update(self: *Player, game: *Game, gamepad: w4.Gamepad, deltaGamepad: w4.Gamepad) void {
        const state = &game.state.Playing;
        const level = state.level;

        if (deltaGamepad.isPressed(.Down) and self.y >= 0) {
            const vx: f32 = if (self.direction == .Left) -16 else 16;
            const tx = @floatToInt(usize, @round((self.x + vx) / 16));
            const ty = @floatToInt(usize, (self.y) / 16);
            if (level.getTile(tx, ty) == .Brick) {
                level.setTile(tx, ty, .Air);
                state.bricks += 1;
                w4.tone(370, (14 << 8) | (40 << 8), 30, w4.TONE_NOISE);
            }
        }

        if (deltaGamepad.isPressed(.Y) and self.heldItem == null) {
            self.nextMinionMode = @intToEnum(Minion.Mode, 
                (@enumToInt(self.nextMinionMode) + 1) % std.meta.fields(Minion.Mode).len);
        }

        if (self.y > 0) {
            const tx = @floatToInt(usize, self.x / 16);
            const ty = @floatToInt(usize, self.y / 16);
            const mtx = @floatToInt(usize, @round(self.x / 16));
            const mty = @floatToInt(usize, @round(self.y / 16));

            if (level.getTile(tx, ty) == .DoorBottom or level.getTile(tx, ty) == .DoorTop) {
                level.deinit();
                game.resetLevelAllocator();
                game.endLevel();
                self.* = .{};
                return;
            }

            if (level.getTile(mtx, mty) == .StickyBall) {
                level.setTile(mtx, mty, .Air);
                self.heldItem = .StickyBall;
            }

            if (level.getTile(mtx, mty) == .Coin) {
                level.setTile(mtx, mty, .Air);
            }

            if (level.getTile(mtx, mty) == .BrickStack) {
                level.setTile(mtx, mty, .Air);
                state.bricks += 5;
            }

            if (self.heldItem) |held| {
                switch (held) {
                    .StickyBall => {
                        if (deltaGamepad.isPressed(.Y)) {
                            if (level.getTile(mtx, mty+1) == .Brick) {
                                level.setTile(mtx, mty+1, .BrickSticky);
                                self.heldItem = null;
                            }
                        }
                    }
                }
            }
        }

        var speed: f32 = 0;
        if (gamepad.isPressed(.Left))
            speed = -2;
        if (gamepad.isPressed(.Right))
            speed = 2;

        const collideInfo = self.applyGravity(level, speed);
        if (deltaGamepad.isPressed(.X) and collideInfo.collidesDown) {
            if (state.bricks >= 5) {
                state.bricks -= 5;
                state.minions.append(Minion {
                    .x = self.x,
                    .y = self.y,
                    .mode = self.nextMinionMode,
                }) catch {};
            }
        }

        if (collideInfo.collidesDown and gamepad.isPressed(.Up)) {
            w4.tone(250 | (880 << 16), (10 << 8) | (18 << 16), 50, w4.TONE_TRIANGLE);
            self.vy = -4;
        }

        if (self.y > 300) {
            // Respawn
            level.deinit();
            game.resetLevelAllocator();
            game.reloadLevel();
            self.* = .{};
            return;
        }
    }

    pub fn render(self: Player, game: Game) void {
        w4.DRAW_COLORS.* = 0x4321;
        var playerSprite = &Resources.Player.Standing;
        if (!std.math.approxEqAbs(f32, self.vx, 0, 0.01)) {
            if (@mod(game.time, 0.5) >= 0 and @mod(game.time, 0.5) < (0.5 / 3.0)) {
                playerSprite = &Resources.Player.Walking;
            } else if (@mod(game.time, 0.5) < (0.5 / 3.0) * 2.0) {
                playerSprite = &Resources.Player.Standing;
            } else {
                playerSprite = &Resources.Player.Walking2;
            }
        }
        w4.blit(playerSprite, @floatToInt(i32, self.x - game.state.Playing.camX), @floatToInt(i32, self.y), 16, 16, w4.BLIT_2BPP |
            if (self.direction == .Right) 0 else w4.BLIT_FLIP_X);
    }
};
