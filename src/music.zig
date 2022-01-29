//! Play music encoded in my self-made audio format (https://globalempire.github.io/OpenStandards/Audio/AAF)
const std = @import("std");
const w4 = @import("wasm4.zig");

pub const Music = struct {
    channels: u8,
    data: []const []const Command,
    currentNotes: [3]usize = [_]usize { 0, 0, 0 },
    currentNotesStart: [3]f32 = [_]f32 { -1, -1, -1 },

    const Command = union(enum) {
        Note: struct { frequency: u16, duration: f32, start: f32 },
        SetVolume: struct { volume: u8 },
        SetAdsr: struct { attack: u8, delay: u8, sustain: u8, release: u8 }
    };

    pub fn readMusicCommands(comptime aaf: []const u8) !Music {
        @setEvalBranchQuota(10000);

        var fba = std.io.fixedBufferStream(aaf);
        const reader = fba.reader();
        if (!try reader.isBytes("\x13AAF\x03")) {
            @compileError("Not an AAF file.");
        }

        const waveTypes = try reader.readByte();
        if (waveTypes & ~@as(u8, 0b0101) != 0) {
            @compileError("AAF file requests more than available wave types");
        }

        const flags = try reader.readByte();
        if (flags & ~@as(u8, 0b11) != 0) {
            @compileError("AAf file uses unsupported flags");
        }

        const numChannels = try reader.readByte();
        if (numChannels > 3) {
            @compileError("AAF file uses too much channels.");
        }

        var channelData: [numChannels][]const Command = @as([1][]const Command, .{ &[0]Command {} }) ** numChannels;
        var channelTimes = [3]f32 { 0, 0, 0 };

        mainLoop: while (true) {
            var channel = 0;
            while (channel < numChannels) : (channel += 1) {
                const frequency = reader.readIntLittle(u16) catch |err| {
                    if (err == error.EndOfStream) break :mainLoop;
                };

                switch (frequency) {
                    1 => {
                        const attack = try reader.readIntLittle(u16);
                        const delay = try reader.readIntLittle(u16);
                        const sustain = try reader.readIntLittle(u16);
                        const release = try reader.readIntLittle(u16);
                        channelData[channel] = channelData[channel] ++ @as([]const Command, &[_]Command {
                            .{ .SetAdsr = .{ .attack = attack, .delay = delay, .sustain = sustain, .release = release }}
                        });
                    },
                    2 => {
                        const volume = try reader.readIntLittle(u8);
                        // Convert AAF volume (0-255) to WASM-4 volume (0-100)
                        const w4Volume = @floatToInt(u8, @intToFloat(f32, volume) / 255.0 * 100.0);
                        channelData[channel] = channelData[channel] ++ @as([]const Command, &[_]Command {
                            .{ .SetVolume = .{ .volume = w4Volume }}
                        });
                    },
                    3 => @compileError("TODO: wave type body"),
                    else => {
                        const duration = try reader.readIntLittle(u16);
                        const adjustedDur = @intToFloat(f32, duration) / 1000.0;
                        channelData[channel] = channelData[channel] ++ @as([]const Command, &[_]Command {
                            .{ .Note = .{
                                .frequency = @intCast(u16, frequency),
                                .duration = adjustedDur,
                                .start = channelTimes[channel]
                            }}
                        });
                        channelTimes[channel] += adjustedDur;
                    }
                }
            }
        }

        return Music {
            .channels = numChannels,
            .data = &channelData
        };
    }

    pub fn play(self: *Music, time: f32) void {
        var channel: usize = 0;
        while (channel < 3) : (channel += 1) {
            const curNote = self.data[channel][self.currentNotes[channel]];
            const curNoteStart = self.currentNotesStart[channel];
            switch (curNote) {
                .Note => |note| {
                    if (curNoteStart == -1) {
                        if (time < note.start) continue;
                        const flags = switch (channel) {
                            0 => w4.TONE_TRIANGLE,
                            1 => w4.TONE_TRIANGLE | w4.TONE_MODE1,
                            2 => w4.TONE_TRIANGLE | w4.TONE_MODE1,
                            else => unreachable
                        };
                        var frameDuration = @floatToInt(u32, note.duration * 1000 / 30);
                        if (frameDuration > 255) {
                            w4.trace("music: DURATION OVERFLOW");
                            frameDuration = 255;
                        }
                        if (note.frequency > 0) {
                            w4.tone(note.frequency, frameDuration, 63, flags);
                        }
                        self.currentNotesStart[channel] = note.start;
                    } else if (time >= curNoteStart + note.duration) {
                        self.currentNotes[channel] += 1;
                        self.currentNotesStart[channel] = -1;
                    }
                },
                .SetVolume => |volume| {
                    _ = volume;
                    // TODO: set volume
                    self.currentNotes[channel] += 1;
                },
                .SetAdsr => |adsr| {
                    _ = adsr;
                    // TODO: set adsr
                    self.currentNotes[channel] += 1;
                }
            }
        }
    }

};
