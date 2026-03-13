const Self = @This();

const std = @import("std");
const apprt = @import("../../apprt.zig");
const CoreSurface = @import("../../Surface.zig");
const configpkg = @import("../../config.zig");

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn close(self: *Self, process_active: bool) void {
    _ = self;
    _ = process_active;
}

pub fn getContentScale(self: *const Self) !apprt.ContentScale {
    _ = self;
    return .{ .x = 1, .y = 1 };
}

pub fn getSize(self: *const Self) !apprt.SurfaceSize {
    _ = self;
    return .{ .width = 800, .height = 600 };
}

pub fn getCursorPos(self: *const Self) !apprt.CursorPos {
    _ = self;
    return .{ .x = 0, .y = 0 };
}

pub fn supportsClipboard(self: *const Self, clipboard_type: apprt.Clipboard) bool {
    _ = self;
    _ = clipboard_type;
    return false;
}

pub fn clipboardRequest(
    self: *Self,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    _ = self;
    _ = clipboard_type;
    _ = state;
    return false;
}

pub fn setClipboard(
    self: *Self,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = self;
    _ = clipboard_type;
    _ = contents;
    _ = confirm;
}

pub fn defaultTermioEnv(self: *Self) !std.process.EnvMap {
    _ = self;
    return .init(std.heap.page_allocator);
}

pub fn redrawInspector(self: *Self) void {
    _ = self;
}
