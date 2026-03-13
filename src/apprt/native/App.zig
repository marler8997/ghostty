const App = @This();

const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const xev = @import("xev").Dynamic;
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");

const X11Backend = @import("X11Backend.zig");
const WaylandBackend = @import("WaylandBackend.zig");
const Pty = @import("Pty.zig");
const Surface = @import("Surface.zig");

const log = std.log.scoped(.native);

backend: union(enum) {
    x11: X11Backend,
    wayland: WaylandBackend,
},

loop: xev.Loop,
stop: xev.Async,
stop_c: xev.Completion = .{},

/// Completions for polling X11 and PTY fds.
x11_poll_c: xev.Completion = .{},
pty_poll_c: xev.Completion = .{},

x11_stream: xev.Stream,
pty_stream: xev.Stream,

core_app: *CoreApp,
pty: Pty,

/// Terminal data buffer (mmap'd, growable like mite)
term_data: []u8,
term_used: usize,
cursor_pos: usize,

/// Whether the screen needs to be redrawn
damaged: bool,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    // Initialize xev backend detection
    if (comptime xev.dynamic) xev.detect() catch |err| {
        log.warn("failed to detect xev backend err={}", .{err});
    };

    // Runtime backend detection
    const xdg_session_type = std.posix.getenv("XDG_SESSION_TYPE");
    log.info("XDG_SESSION_TYPE={?s}", .{xdg_session_type});

    if (std.mem.eql(u8, xdg_session_type orelse "", "wayland")) {
        self.backend = .{ .wayland = undefined };
        try self.backend.wayland.init();
    } else {
        self.backend = .{ .x11 = undefined };
        try self.backend.x11.init();
    }

    const x11_fd = switch (self.backend) {
        inline else => |*b| b.fd,
    };

    // Spawn PTY with shell
    const cols, const rows = switch (self.backend) {
        .x11 => |*b| .{ b.cellWidth(), b.cellHeight() },
        .wayland => .{ @as(u16, 80), @as(u16, 24) },
    };
    self.pty = try Pty.openAndSpawn(cols, rows);
    log.info("spawned shell pid={}", .{self.pty.pid});

    // Allocate terminal data buffer
    self.term_data = try posix.mmap(
        null,
        std.heap.pageSize(),
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .NORESERVE = true },
        -1,
        0,
    );
    self.term_used = 0;
    self.cursor_pos = 0;
    self.damaged = false;

    self.loop = try xev.Loop.init(.{});
    self.stop = try xev.Async.init();
    self.x11_stream = xev.Stream.initFd(x11_fd);
    self.pty_stream = xev.Stream.initFd(self.pty.master);
    self.x11_poll_c = .{};
    self.pty_poll_c = .{};
    self.stop_c = .{};
    self.core_app = core_app;
}

pub fn run(self: *App) !void {
    // Register the stop async handle
    self.stop.wait(&self.loop, &self.stop_c, App, self, stopCallback);

    // Poll both X11 and PTY fds
    self.x11_stream.poll(&self.loop, &self.x11_poll_c, .read, App, self, x11PollCallback);
    self.pty_stream.poll(&self.loop, &self.pty_poll_c, .read, App, self, ptyPollCallback);

    // Run the event loop
    try self.loop.run(.until_done);
}

fn x11PollCallback(
    self_: ?*App,
    loop: *xev.Loop,
    _: *xev.Completion,
    _: xev.Stream,
    result: xev.PollError!xev.PollEvent,
) xev.CallbackAction {
    const self = self_.?;
    _ = result catch |err| {
        log.err("x11 poll error: {}", .{err});
        loop.stop();
        return .disarm;
    };

    const drain_result = switch (self.backend) {
        .x11 => |*b| b.drain(&self.pty) catch |err| {
            log.err("x11 drain error: {}", .{err});
            loop.stop();
            return .disarm;
        },
        .wayland => |*b| blk: {
            _ = b.drain() catch {};
            break :blk X11Backend.DrainResult.ok;
        },
    };

    switch (drain_result) {
        .quit => {
            loop.stop();
            return .disarm;
        },
        .damaged => {
            self.damaged = true;
            self.doRender();
        },
        .ok => {},
    }

    return .rearm;
}

fn ptyPollCallback(
    self_: ?*App,
    loop: *xev.Loop,
    _: *xev.Completion,
    _: xev.Stream,
    result: xev.PollError!xev.PollEvent,
) xev.CallbackAction {
    const self = self_.?;
    _ = result catch |err| {
        log.err("pty poll error: {}", .{err});
        loop.stop();
        return .disarm;
    };

    // Read PTY data
    self.readPty() catch |err| switch (err) {
        error.EndOfStream => {
            log.info("shell closed", .{});
            loop.stop();
            return .disarm;
        },
        else => {
            log.err("pty read error: {}", .{err});
            loop.stop();
            return .disarm;
        },
    };

    self.damaged = true;
    self.doRender();

    return .rearm;
}

fn readPty(self: *App) !void {
    // Grow buffer if full
    if (self.term_used == self.term_data.len) {
        const new_len = self.term_data.len * 2;
        self.term_data = try posix.mremap(
            @alignCast(self.term_data.ptr),
            self.term_data.len,
            new_len,
            .{ .MAYMOVE = true },
            null,
        );
    }

    const buf = self.term_data[self.term_used..];
    const n = posix.read(self.pty.master, buf) catch |err| switch (err) {
        error.InputOutput => {
            log.info("pty read EIO", .{});
            return error.EndOfStream;
        },
        else => return err,
    };
    if (n == 0) return error.EndOfStream;

    // Simple terminal processing: track cursor position
    // Process escape sequences minimally
    processPtyData(self.term_data, self.term_used, self.term_used + n, &self.cursor_pos);
    self.term_used = @max(self.term_used + n, self.cursor_pos);
}

fn processPtyData(data: []u8, start: usize, end: usize, cursor: *usize) void {
    var write_idx = cursor.*;
    var i = start;
    while (i < end) : (i += 1) {
        switch (data[i]) {
            '\r' => {
                // Carriage return: move cursor to start of line
                while (write_idx > 0 and data[write_idx - 1] != '\n') {
                    write_idx -= 1;
                }
            },
            '\n' => {
                // Newline
                data[write_idx] = '\n';
                write_idx += 1;
            },
            '\x08' => {
                // Backspace
                if (write_idx > 0 and data[write_idx - 1] != '\n') {
                    write_idx -= 1;
                }
            },
            '\x1b' => {
                // Escape sequence
                if (i + 1 < end and data[i + 1] == '[') {
                    i += 2;
                    const param_start = i;
                    while (i < end and data[i] < 0x40) : (i += 1) {}
                    if (i < end) {
                        const final = data[i];
                        const params = data[param_start..i];
                        switch (final) {
                            'm' => {
                                // SGR: preserve in buffer for renderer
                                data[write_idx] = '\x1b';
                                write_idx += 1;
                                data[write_idx] = '[';
                                write_idx += 1;
                                @memcpy(data[write_idx..][0..params.len], params);
                                write_idx += params.len;
                                data[write_idx] = 'm';
                                write_idx += 1;
                            },
                            'K' => {
                                // Erase in line (param 0 = cursor to end)
                                const param = if (params.len == 0) @as(u16, 0) else std.fmt.parseUnsigned(u16, params, 10) catch 0;
                                if (param == 0) {
                                    // Find end of current line, clear it
                                    var le = write_idx;
                                    while (le < data.len and data[le] != '\n') : (le += 1) {}
                                    if (le > write_idx) {
                                        @memset(data[write_idx..le], ' ');
                                    }
                                }
                            },
                            'J' => {
                                // Erase in display
                            },
                            else => {},
                        }
                    }
                } else if (i + 1 < end and data[i + 1] == ']') {
                    // OSC: skip until ST (\x1b\\ or \x07)
                    i += 2;
                    while (i < end) : (i += 1) {
                        if (data[i] == '\x07') break;
                        if (data[i] == '\x1b' and i + 1 < end and data[i + 1] == '\\') {
                            i += 1;
                            break;
                        }
                    }
                }
            },
            '\x07' => {}, // bell - ignore
            else => {
                data[write_idx] = data[i];
                write_idx += 1;
            },
        }
    }
    cursor.* = write_idx;
}

fn doRender(self: *App) void {
    if (!self.damaged) return;
    self.damaged = false;

    switch (self.backend) {
        .x11 => |*b| {
            b.render(self.term_data[0..self.term_used], self.cursor_pos) catch |err| {
                log.err("render error: {}", .{err});
            };
        },
        .wayland => {},
    }
}

fn stopCallback(
    _: ?*App,
    _: *xev.Loop,
    _: *xev.Completion,
    _: xev.Async.WaitError!void,
) xev.CallbackAction {
    return .disarm;
}

pub fn terminate(self: *App) void {
    // Kill the child shell process and close the PTY
    posix.kill(self.pty.pid, posix.SIG.HUP) catch {};
    posix.close(self.pty.master);
    _ = posix.waitpid(self.pty.pid, 0);
    switch (self.backend) {
        inline else => |*b| b.deinit(),
    }
    self.stop.deinit();
    self.loop.deinit();
}

pub fn wakeup(self: *App) void {
    self.stop.notify() catch {};
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    _ = self;
    _ = target;
    _ = value;
    return false;
}

pub fn performIpc(
    alloc: Allocator,
    target: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    value: apprt.ipc.Action.Value(action),
) !bool {
    _ = alloc;
    _ = target;
    _ = value;
    return false;
}

pub fn redrawInspector(self: *App, surface: *Surface) void {
    _ = self;
    _ = surface;
}
