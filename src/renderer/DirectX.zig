const std = @import("std");
const Config = @import("../config.zig").Config;

pub const DerivedConfig = struct {
    pub fn init(allocator: std.mem.Allocator, config: *const Config) !DerivedConfig {
        _ = allocator;
        _ = config;
        @panic("todo");
    }
};
