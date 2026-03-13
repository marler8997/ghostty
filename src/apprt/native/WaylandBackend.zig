const WaylandBackend = @This();

const std = @import("std");
const posix = std.posix;

const log = std.log.scoped(.native);

fd: posix.fd_t,

pub fn init(_: *WaylandBackend) !void {
    log.err("Wayland backend is not yet supported", .{});
    return error.WaylandNotYetSupported;
}

/// Drain events from the Wayland socket. Returns true if the app should quit.
pub fn drain(_: *WaylandBackend) !bool {
    return false;
}

pub fn deinit(self: *WaylandBackend) void {
    posix.close(self.fd);
}
