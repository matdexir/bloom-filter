//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const math = std.math;
const testing = std.testing;

pub const BloomFilter = struct {
    const Self = @This();
    bitset: std.bit_set.DynamicBitSet,
    fp_rate: f64,
    bitset_width: u64,
    num_hash_fn: u8,
    item_count: u64,
    max_items: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, fp_rate: f64, max_items: u64) !BloomFilter {
        const idealBitsetWidth = calculateBitWidth(max_items, fp_rate);
        const hashFnCount = calculateHashFnNum(max_items, idealBitsetWidth);

        if (hashFnCount > std.math.maxInt(u8)) {
            return error.YouAreDoingTooMuch;
        }
        if (idealBitsetWidth > std.math.maxInt(u64)) {
            return error.YouAreAlsoDoingTooMuch;
        }

        const bitset = try std.bit_set.DynamicBitSet.initEmpty(allocator, idealBitsetWidth);

        return BloomFilter{ .allocator = allocator, .fp_rate = fp_rate, .bitset = bitset, .bitset_width = idealBitsetWidth, .num_hash_fn = @truncate(hashFnCount), .item_count = 0, .max_items = max_items };
    }

    pub fn deinit(self: *Self) void {
        self.bitset.deinit();
        self.* = undefined;
    }

    pub fn insert(self: *Self, item: []const u8) !void {
        for (0..self.num_hash_fn) |i| {
            const hashed = self.hash_(item, @truncate(i));
            self.bitset.set(hashed);
        }

        self.item_count += 1;
    }

    pub fn contains(self: *Self, item: []const u8) bool {
        for (0..self.num_hash_fn) |i| {
            const hashed_idx = self.hash_(item, @truncate(i));
            if (!self.bitset.isSet(hashed_idx)) {
                return false;
            }
        }
        return true;
    }

    fn hash_(self: *Self, item: []const u8, seed: u32) u64 {
        const hash = std.hash.Murmur3_32.hashWithSeed(item, seed);
        return hash % self.bitset_width; // NOTE: I'm not sure if this is ideal
    }
};

// (-nln(f))/ln(2)^2
fn calculateBitWidth(n: u64, f: f64) u64 {
    const numerator = @as(f64, @floatFromInt(n)) * -math.log(f64, math.e, f);
    const denominator = math.pow(f64, math.log(f64, math.e, 2), 2);

    const result = math.divTrunc(f64, numerator, denominator) catch unreachable;

    return if (result > 0) @as(u64, @intFromFloat(result)) else 1;
}

// mln(2)/n
fn calculateHashFnNum(n: u64, m: u64) u64 {
    const numerator = @as(f64, @floatFromInt(m)) * math.log(f64, math.e, 2);
    const denominator = @as(f64, @floatFromInt(n));

    const result = math.divTrunc(f64, numerator, denominator) catch unreachable;
    return if (result > 0) @as(u64, @intFromFloat(result)) else 1;
}

test "BloomFilter: init and deinit" {
    var bf = try BloomFilter.init(testing.allocator, 0.01, 100);
    defer bf.deinit();

    try testing.expect(bf.bitset_width > 0);
    try testing.expect(bf.num_hash_fn > 0);
    try testing.expectEqual(bf.item_count, 0);
    try testing.expectEqual(bf.max_items, 100);
    try testing.expectEqual(bf.fp_rate, 0.01);
}

test "BloomFilter: insert and contains" {
    var bf = try BloomFilter.init(testing.allocator, 0.01, 100);
    defer bf.deinit();

    const item1 = "hello";
    const item2 = "world";
    const item3 = "zig";
    const item_not_in_filter = "not here";

    try bf.insert(item1);
    try bf.insert(item2);

    try testing.expect(bf.contains(item1));
    try testing.expect(bf.contains(item2));
    try testing.expect(!bf.contains(item3)); // Should not contain yet
    try testing.expect(!bf.contains(item_not_in_filter));

    try bf.insert(item3);
    try testing.expect(bf.contains(item3));
    try testing.expectEqual(bf.item_count, 3);
}

test "BloomFilter: edge case - max_items = 1" {
    var bf = try BloomFilter.init(testing.allocator, 0.01, 1);
    defer bf.deinit();

    try testing.expect(bf.bitset_width > 0);
    try testing.expect(bf.num_hash_fn > 0);

    const item = "single_item";
    try bf.insert(item);
    try testing.expect(bf.contains(item));
    try testing.expect(!bf.contains("another_item"));
}

test "BloomFilter: edge case - high false positive rate (e.g., 0.5)" {
    var bf = try BloomFilter.init(testing.allocator, 0.5, 100);
    defer bf.deinit();

    // m and h should be smaller with a higher acceptable FP rate
    std.debug.print("High FP rate: m = {d}, h = {d}\n", .{ bf.bitset_width, bf.num_hash_fn });
    try testing.expect(bf.bitset_width > 0);
    try testing.expect(bf.num_hash_fn > 0);
}

test "BloomFilter: edge case - low false positive rate (e.g., 0.00001)" {
    var bf = try BloomFilter.init(testing.allocator, 0.00001, 100);
    defer bf.deinit();

    // m and h should be larger with a lower acceptable FP rate
    std.debug.print("Low FP rate: m = {d}, h = {d}\n", .{ bf.bitset_width, bf.num_hash_fn });
    try testing.expect(bf.bitset_width > 0);
    try testing.expect(bf.num_hash_fn > 0);
    // You could add assertions here that m and h are significantly larger than for the 0.5 FP rate case.
}

test "calculateBitWidth: basic check" {
    // These values are approximate, actual results may vary slightly due to float precision
    // Using an online Bloom filter calculator for comparison:
    // n=1000, f=0.01 => m ≈ 9585 bits
    try testing.expect(calculateBitWidth(1000, 0.01) >= 9500);
    try testing.expect(calculateBitWidth(1000, 0.01) <= 9600);

    // n=100, f=0.1 => m ≈ 479 bits
    try testing.expect(calculateBitWidth(100, 0.1) >= 470);
    try testing.expect(calculateBitWidth(100, 0.1) <= 485);
}

test "calculateHashFnNum: basic check" {
    // Using an online Bloom filter calculator for comparison:
    // n=1000, m=9585 => k ≈ 6.6 => should truncate to 6
    try testing.expectEqual(calculateHashFnNum(1000, 9585), 6);

    // n=100, m=479 => k ≈ 3.3 => should truncate to 3
    try testing.expectEqual(calculateHashFnNum(100, 479), 3);
}

test "calculateBitWidth: returns at least 1" {
    // Even if calculation yields 0, m should be at least 1
    try testing.expectEqual(calculateBitWidth(1, 0.999), 1);
}

test "calculateHashFnNum: returns at least 1" {
    // Even if calculation yields 0, h should be at least 1
    try testing.expectEqual(calculateHashFnNum(100, 1), 1);
}
