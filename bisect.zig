const std = @import("std");
const mem = std.mem;
const sort = std.sort;
const Order = std.math.Order;
const assert = std.debug.assert;

extern fn memcmp(?[*]const u8, ?[*]const u8, usize) c_int;
extern fn strlen(?[*]const u8) usize;

fn port_strlen(str: [*]allowzero const u8) usize {
    var res: usize = 0;
    // this is bounded by the sanity check that the last byte is null in bisectSearch
    while (true) : (res += 1) {
        if (str[res] == '\x00') break;
    }
    return res;
    //return strlen(str);
}

fn getFofs(file: []const u8, _off: usize) usize {
    var off = _off;
    if (off == 0) return 0;
    if (off > file.len) return file.len;
    off -= 1;
    off += port_strlen(file[off..].ptr);
    return off + 1;
}

fn compareLine(valueLn: fn ([]const u8) usize, file: []const u8, _off: usize, search: []const u8) c_int {
    var off = _off + valueLn(file[_off..]);
    if (file.len <= off) return 1; // EOF
    const compareLen = if (search.len < file.len - off) search.len else file.len - off;
//std.debug.warn("{} {} {} {c} {} {} {}\n", .{search.len, file.ptr[off..off+compareLen], search[2], file.ptr[off+2], off, compareLen, memcmp(file.ptr + off, search.ptr, compareLen)});
    return memcmp(file.ptr + off, search.ptr, compareLen);
}

fn bisectWay(valueLn: fn ([]const u8) usize, file: []const u8, _lo: usize, _hi: usize, search: []const u8) ?[]const u8 {
    var lo = _lo;
    var hi = _hi;
    var mid: usize = undefined;
    if (hi > file.len) hi = file.len;
    if (lo >= hi) {
        var off = getFofs(file, lo);
        return file[off..off + search.len];
    }
    while (true) {
        mid = (lo + hi) >> 1;
        const midf = getFofs(file, mid);
        const cmp = compareLine(valueLn, file, midf, search); // EOF is GreaterThan
//std.debug.warn("cmp {} {} {}\n", .{cmp, mid, midf});
        if (cmp > 0) {
            hi = mid;
        } else if (cmp < 0) {
            lo = mid + 1;
        } else { // equal
            var off = midf + valueLn(file[midf..]);
            return file[off..off + search.len];
        }
        if (lo < hi) continue;
        break;
    }
    return null;
}

fn valueLnFn(where: []const u8) usize {
    return 1;
}

pub fn bisectSearch(file: []const u8, search: []const u8) !?[]const u8 {
    if (file[file.len - 1] != '\x00') return error.EINVAL;
    return bisectWay(valueLnFn, file, 0, file.len, search);
}

const Entry = struct {
    key: []const u8,
    value: usize,
};

fn numberEntries(allocator: *mem.Allocator, entries: []const []const u8) ![]Entry {
    var ret = try allocator.alloc(Entry, entries.len);
    for (entries) |entry, i| {
        ret[i].key = entry;
        ret[i].value = i;
    }
    return ret;
}

fn lessThanEntry(l: Entry, r: Entry) bool {
    return mem.lessThan(u8, l.key, r.key);
}

fn sortEntries(entries: []Entry) void {
    return sort.sort(Entry, entries, lessThanEntry);
}

pub fn generateBisect(out: []u8, entries: []Entry) []const u8 {
    sortEntries(entries);
    var off: usize = 0;
    for (entries) |entry| {
        out[off] = @intCast(u7, entry.value);
        mem.copy(u8, out[off + 1..], entry.key);
//std.debug.warn("key {} {}\n", .{entry.key, entry.key.len});
        off += 1 + entry.key.len;
        out[off] = '\x00';
        off += 1;
    }
    assert(off == out.len);
    return out;
}

pub fn generateSimple(allocator: *mem.Allocator, entriesOrderedUnsorted: []const []const u8) ![]const u8 {
    if (entriesOrderedUnsorted.len > 128) {
        return error.E2BIG;
    }
    var allocSize: usize = 0;
    for (entriesOrderedUnsorted) |entry, i| {
        //           key         sep value
        allocSize += entry.len + 1 + 1;
    }
    const ret = try allocator.alloc(u8, allocSize);
    var entriesStillUnsorted = try numberEntries(allocator, entriesOrderedUnsorted);
    return generateBisect(ret, entriesStillUnsorted);
}

const expect = std.testing.expect;

test "corner cases" {
    var buf: [4096]u8 = undefined;
    var allocator = &std.heap.FixedBufferAllocator.init(buf[0..]).allocator;
    const first = [_][]const u8{
        "hi"[0..],
        "hittite"[0..],
        "high-five"[0..],
        "highten"[0..],
        "high"[0..],
        "hightening"[0..],
        };
    const file = try generateSimple(allocator, first[0..]);
    var search = "hi\x00"[0..];
    var res = try bisectSearch(file, search);
    if (res) |r| {
        expect(mem.eql(u8, r[0..search.len], search));
    } else {
        return error.NotFound;
    }
}

// -------------------------------


