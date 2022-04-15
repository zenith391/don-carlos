const std = @import("std");
const Level = @import("level.zig").Level;

pub const Direction = enum { Left, Right };
pub const CollisionInfo = struct {
    collidesH: bool,
    collidesUp: bool,
    collidesDown: bool,

    pub fn collidesV(self: CollisionInfo) void {
        return self.collidesUp or self.collidesDown;
    }
};

pub fn Mixin(comptime T: type) type {
    return struct {
        pub fn applyGravity(self: *T, level: Level, speed: f32) CollisionInfo {
            const gravity = 0.2;
            const friction = 1.5;
            var bounciness: f32 = 0.25;
            const noClip = false;

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
            var collidesH = false;
            var collidesDown = false;
            var collidesUp = false;

            if (self.y > 0) {
                const tx = @floatToInt(usize, (self.x + self.vx) / 16);
                const ty = @floatToInt(usize, (self.y) / 16);

                if (self.vy > 0) {
                    // Going down
                    if (level.getTile(tx, ty+1).isSolid() or level.getTile(tx+1, ty+1).isSolid() and !noClip) {
                        collidesDown = true;
                    }
                } else if (self.vy < 0) {
                    // Going up
                    if (level.getTile(tx, ty).isSolid() or level.getTile(tx+1, ty).isSolid() and !noClip) {
                        collidesUp = true;
                    }
                }
                if (self.vx > 0 and level.getTile(tx+1, ty).isSolid() and !noClip) {
                    collidesH = true;
                } else if (self.vx < 0 and level.getTile(tx, ty).isSolid() and !noClip) {
                    collidesH = true;
                }


                const mtx = @floatToInt(usize, @round(self.x / 16));
                const mty = @floatToInt(usize, @round(self.y / 16));
                if (level.getTile(mtx, mty+1) == .BrickSticky) {
                    bounciness = 1.1;
                }
            }


            if (collidesDown or collidesUp) {
                _ = bounciness;
                self.vy = -self.vy * bounciness;
            } else {
                self.y = targetY;
            }
            if (collidesH) self.vx = 0;

            if (self.x < 0) self.x = 0;

            return CollisionInfo { .collidesH = collidesH, .collidesUp = collidesUp or noClip, .collidesDown = collidesDown or noClip };
        }
    };
}
