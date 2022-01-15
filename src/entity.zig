const std = @import("std");
const Level = @import("level.zig").Level;

pub const Direction = enum { Left, Right };
pub const CollisionInfo = struct {
    collidesH: bool,
    collidesV: bool,
};

pub fn Mixin(comptime T: type) type {
    return struct {
        pub fn applyGravity(self: *T, level: Level, speed: f32) CollisionInfo {
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
    };
}
