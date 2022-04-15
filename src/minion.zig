const Game = @import("main.zig").Game;
const Direction = @import("entity.zig").Direction;

pub const Minion = struct {
    x: f32,
    y: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    direction: Direction = .Right,
    bricks: u32 = 5,
    mode: Mode,

    pub const Mode = enum(u8) {
        Build,
        Attack,
    };

    pub usingnamespace @import("entity.zig").Mixin(Minion);

    pub fn update(self: *Minion, g: *Game) void {
        const level = g.state.Playing.level;
        
        const mtx = @floatToInt(usize, @round(self.x / 16));
        const mty = @floatToInt(usize, @round(self.y / 16));

        if (level.getTile(mtx, mty+1) == .BrickSticky) {
            self.vy = -4;
        }
        _ = self.applyGravity(level, 1);

        switch (self.mode) {
            .Build => {
                if (self.bricks > 0) {
                    const tx = @floatToInt(usize, self.x / 16);
                    const ty = @floatToInt(usize, self.y / 16);
                    if (level.getTile(tx, ty+1) == .Air) {
                        level.setTile(tx, ty+1, .Brick);
                        self.bricks -= 1;
                    }
                } else {
                    // TODO: remove
                }
            },
            .Attack => {
                // TODO
            }
        }
    }
};
