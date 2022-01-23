const std = @import("std");

fn convertLevel(step: *std.build.LibExeObjStep, in: []const u8, id: usize, options: *std.build.OptionsStep) !void {
    const allocator = step.builder.allocator;
    // parse the level file and convert it to a slice
    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();

    const json = try std.fs.cwd().readFileAlloc(allocator, in, std.math.maxInt(usize));
    defer allocator.free(json);

    var tree = try parser.parse(json);
    defer tree.deinit();

    const root = tree.root.Object;
    const width = @intCast(usize, root.get("width").?.Integer);
    const height = @intCast(usize, root.get("height").?.Integer);

    const b64 = root.get("layers").?.Array.items[0].Object.get("data").?.String;
    const decodedLen = try std.base64.standard.Decoder.calcSizeForSlice(b64);

    const decoded = try allocator.alloc(u8, decodedLen);
    defer allocator.free(decoded);
    try std.base64.standard.Decoder.decode(decoded, b64);

    const tiles = try allocator.alloc(u4, width * height);
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const pos = y * width + x;
            const tileId = std.mem.readIntSliceLittle(u32, decoded[pos*4..(pos+1)*4]) -| 1;
            tiles[pos] = @intCast(u4, tileId);
        }
    }

    const dataName = try std.fmt.allocPrint(allocator, "level_{d}_data", .{ id });
    const widthName = try std.fmt.allocPrint(allocator, "level_{d}_width", .{ id });
    const heightName = try std.fmt.allocPrint(allocator, "level_{d}_height", .{ id });

    options.addOption([]const u4, dataName, tiles);
    options.addOption(usize, widthName, width);
    options.addOption(usize, heightName, height);
}

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("cart", "src/main.zig", .unversioned);
    @import("deps.zig").addAllTo(lib);
    lib.setBuildMode(mode);
    //lib.setBuildMode(.ReleaseSmall);
    lib.single_threaded = true;
    lib.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    lib.import_memory = true;
    lib.initial_memory = 65536;
    lib.max_memory = 65536;
    lib.global_base = 6560;
    lib.stack_size = 8192;

    const builder = lib.builder;
    const options = builder.addOptions();
    lib.addOptions("levels", options);
    try convertLevel(lib, "assets/levels/level1.json", 0, options);
    try convertLevel(lib, "assets/levels/level2.json", 1, options);
    try convertLevel(lib, "assets/levels/level3.json", 2, options);

    lib.install();
}
