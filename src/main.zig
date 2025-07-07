const std = @import("std");
const BloomFilter = @import("root.zig").BloomFilter;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const num_items: usize = 10_000;
    const fp_rate = 0.01;

    var bf = try BloomFilter.init(allocator, fp_rate, num_items);
    defer bf.deinit();

    var timer = try std.time.Timer.start();

    // Benchmark insert
    var total_insert_time: u64 = 0;
    for (0..num_items) |i| {
        const item = std.fmt.allocPrint(allocator, "item-{d}", .{i}) catch continue;
        defer allocator.free(item);

        const start = timer.read();
        try bf.insert(item);
        const end = timer.read();
        total_insert_time += (end - start);
    }

    std.debug.print("Average insert time: {d} ns\n", .{total_insert_time / num_items});

    // Benchmark contains
    var total_lookup_time: u64 = 0;
    for (0..num_items) |i| {
        const item = std.fmt.allocPrint(allocator, "item-{d}", .{i}) catch continue;
        defer allocator.free(item);

        const start = timer.read();
        _ = bf.contains(item);
        const end = timer.read();
        total_lookup_time += (end - start);
    }

    std.debug.print("Average lookup time: {d} ns\n", .{total_lookup_time / num_items});
}
