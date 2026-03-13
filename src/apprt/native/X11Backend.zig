const X11Backend = @This();

const std = @import("std");
const posix = std.posix;
const x11 = @import("x11");
const Pty = @import("Pty.zig");

const log = std.log.scoped(.x11);

const default_bg: u24 = 0x282c34;
const default_fg: u24 = 0xabb2bf;

const Io = struct {
    read_buf: [4096]u8,
    write_buf: [4096]u8,
    stream_reader: x11.Stream15.Reader,
    stream_writer: x11.Stream15.Writer,
    source: x11.Source,
    sink: x11.RequestSink,
};

const Ids = struct {
    base: x11.ResourceBase,

    fn window(self: Ids) x11.Window {
        return self.base.add(0).window();
    }
    fn gc(self: Ids) x11.GraphicsContext {
        return self.base.add(1).graphicsContext();
    }
    fn font(self: Ids) x11.Font {
        return self.base.add(2).font();
    }
    fn offscreenPixmap(self: Ids) x11.Pixmap {
        return self.base.add(3).pixmap();
    }
};

const Screen = struct {
    root: x11.Window,
    visual: x11.Visual,
    depth: x11.Depth,
};

const FontDims = struct {
    width: u8,
    height: u8,
    ascent: i16,
};

fd: posix.fd_t,
ids: Ids,
screen: Screen,
io: Io,
keymap: x11.keymap.Full,
gc_fg: u24,
gc_bg: u24,
font_dims: FontDims,
win_width: u16,
win_height: u16,

pub fn init(self: *X11Backend) !void {
    self.io.stream_reader, const used_auth = try x11.draft.connect(&self.io.read_buf);
    _ = used_auth;
    const stream = self.io.stream_reader.getStream();
    errdefer x11.disconnect(stream);

    const setup = try x11.readSetupSuccess(self.io.stream_reader.interface());
    log.info("connected to X11 server: {f}", .{setup});

    var source: x11.Source = .initFinishSetup(self.io.stream_reader.interface(), &setup);
    const screen_info = try x11.draft.readSetupDynamic(&source, &setup, .{}) orelse {
        return error.NoScreen;
    };

    const screen: Screen = .{
        .root = screen_info.root,
        .visual = screen_info.root_visual,
        .depth = x11.Depth.init(screen_info.root_depth) orelse {
            return error.UnsupportedDepth;
        },
    };

    self.io.stream_writer = x11.socketWriter(stream, &self.io.write_buf);
    var sink: x11.RequestSink = .{ .writer = &self.io.stream_writer.interface };
    const ids: Ids = .{ .base = setup.resource_id_base };

    // Initialize keymap
    const keyrange: x11.KeycodeRange = try .init(setup.min_keycode, setup.max_keycode);
    const keymap: x11.keymap.Full = try .initSynchronous(&sink, &source, keyrange);

    const win_width: u16 = 800;
    const win_height: u16 = 600;

    // Open a fixed-width font
    try sink.OpenFont(ids.font(), .{ .ptr = "fixed", .len = 5 });
    try sink.QueryTextExtents(ids.font().fontable(), .initComptime(&[_]u16{'m'}));
    try sink.writer.flush();

    const extents, _ = try source.readSynchronousReplyFull(sink.sequence, .QueryTextExtents);
    const font_dims: FontDims = .{
        .width = @intCast(extents.overall_width),
        .height = @intCast(extents.font_ascent + extents.font_descent),
        .ascent = extents.font_ascent,
    };
    log.info("font: {}x{} ascent={}", .{ font_dims.width, font_dims.height, font_dims.ascent });

    // Create window
    try sink.CreateWindow(
        .{
            .window_id = ids.window(),
            .parent_window_id = screen.root,
            .depth = 0,
            .x = 0,
            .y = 0,
            .width = win_width,
            .height = win_height,
            .border_width = 0,
            .class = .input_output,
            .visual_id = screen.visual,
        },
        .{
            .bg_pixel = screen.depth.rgbFrom24(default_bg),
            .bit_gravity = .north_west,
            .event_mask = .{
                .Exposure = 1,
                .KeyPress = 1,
                .KeyRelease = 1,
                .StructureNotify = 1,
            },
        },
    );

    // Create GC with the font
    try sink.CreateGc(ids.gc(), ids.window().drawable(), .{
        .foreground = screen.depth.rgbFrom24(default_fg),
        .background = screen.depth.rgbFrom24(default_bg),
        .font = ids.font(),
        .graphics_exposures = false,
    });

    // Create offscreen pixmap for double buffering
    try sink.CreatePixmap(ids.offscreenPixmap(), ids.window().drawable(), .{
        .depth = screen.depth,
        .width = win_width,
        .height = win_height,
    });

    try sink.MapWindow(ids.window());
    try sink.writer.flush();

    self.fd = stream.handle;
    self.ids = ids;
    self.screen = screen;
    self.io.source = .initAfterSetup(self.io.stream_reader.interface());
    self.io.sink = sink;
    self.keymap = keymap;
    self.gc_fg = default_fg;
    self.gc_bg = default_bg;
    self.font_dims = font_dims;
    self.win_width = win_width;
    self.win_height = win_height;
}

pub fn cellWidth(self: *const X11Backend) u16 {
    return self.win_width / self.font_dims.width;
}

pub fn cellHeight(self: *const X11Backend) u16 {
    return self.win_height / self.font_dims.height;
}

pub const DrainResult = enum { ok, damaged, quit };

/// Drain and process X11 events.
/// Writes key input to pty_fd.
pub fn drain(self: *X11Backend, pty: *Pty) !DrainResult {
    var damaged = false;
    while (true) {
        const msg_kind = self.io.source.readKind() catch |err| switch (err) {
            error.EndOfStream => {
                log.info("X11 connection closed", .{});
                return .quit;
            },
            else => return err,
        };

        switch (msg_kind) {
            .Expose => {
                _ = try self.io.source.read2(.Expose);
                damaged = true;
            },
            .KeyPress => {
                const event = try self.io.source.read2(.KeyPress);
                const keysym = self.keymap.getKeysym(event.keycode, event.state.mod()) catch |err| switch (err) {
                    error.KeycodeTooSmall => {
                        log.warn("keycode {} too small", .{event.keycode});
                        continue;
                    },
                };

                const bytes = if (event.state.control)
                    keysymToCtrlBytes(keysym)
                else
                    keysymToBytes(keysym);
                if (bytes.len > 0) {
                    // Write key input to PTY
                    _ = posix.write(pty.master, bytes) catch |err| {
                        log.err("pty write failed: {}", .{err});
                    };
                }
            },
            .KeyRelease => {
                _ = try self.io.source.read2(.KeyRelease);
            },
            .ConfigureNotify => {
                const notify = try self.io.source.read2(.ConfigureNotify);
                if (notify.width != self.win_width or notify.height != self.win_height) {
                    self.win_width = notify.width;
                    self.win_height = notify.height;
                    // Recreate offscreen pixmap for new size
                    try self.io.sink.FreePixmap(self.ids.offscreenPixmap());
                    try self.io.sink.CreatePixmap(self.ids.offscreenPixmap(), self.ids.window().drawable(), .{
                        .depth = self.screen.depth,
                        .width = self.win_width,
                        .height = self.win_height,
                    });
                    // Update PTY window size
                    pty.updateWinsz(self.cellWidth(), self.cellHeight());
                    damaged = true;
                }
            },
            .MappingNotify,
            .ReparentNotify,
            .MapNotify,
            => try self.io.source.discardRemaining(),
            else => {
                log.debug("unhandled X11 event: {}", .{msg_kind});
                try self.io.source.discardRemaining();
            },
        }

        // Stop draining when no more buffered data
        if (self.io.source.reader.seek >= self.io.source.reader.end) break;
    }
    return if (damaged) .damaged else .ok;
}

pub fn render(self: *X11Backend, data: []const u8, cursor_pos: usize) !void {
    const sink = &self.io.sink;
    const drawable = self.ids.offscreenPixmap().drawable();
    const fw = self.font_dims.width;
    const fh = self.font_dims.height;
    const fa = self.font_dims.ascent;
    const num_cols: u16 = if (fw > 0) self.win_width / fw else 80;
    const visible_rows: u16 = if (fh > 0) self.win_height / fh else 24;

    // Clear with background color
    try self.updateGcFg(default_bg);
    try sink.PolyFillRectangle(drawable, self.ids.gc(), .initAssume(&.{
        .{ .x = 0, .y = 0, .width = self.win_width, .height = self.win_height },
    }));

    // Render characters
    try self.updateGcFg(default_fg);
    var col: u16 = 0;
    var row: i16 = 0;
    var fg: u24 = default_fg;
    var bg: u24 = default_bg;
    var bold = false;
    var reverse = false;

    // Compute total rows for auto-scroll
    var total_rows: i16 = 0;
    {
        var tc: u16 = 0;
        for (data) |ch| {
            if (ch == '\n') {
                total_rows += 1;
                tc = 0;
            } else if (ch >= 0x20 and ch != '\x1b') {
                tc += 1;
                if (num_cols > 0 and tc >= num_cols) {
                    total_rows += 1;
                    tc = 0;
                }
            }
        }
        total_rows += 1; // current line
    }
    const scroll_offset: i16 = if (total_rows > visible_rows)
        total_rows - @as(i16, @intCast(visible_rows))
    else
        0;

    var i: usize = 0;
    while (i < data.len) {
        const byte = data[i];
        switch (byte) {
            '\n' => {
                row += 1;
                col = 0;
                i += 1;
            },
            '\t' => {
                col = (col + 8) & ~@as(u16, 7);
                if (num_cols > 0 and col >= num_cols) {
                    row += 1;
                    col = 0;
                }
                i += 1;
            },
            '\x1b' => {
                // Parse SGR sequence
                if (i + 2 < data.len and data[i + 1] == '[') {
                    const param_start = i + 2;
                    var end = param_start;
                    while (end < data.len and data[end] < 0x40) : (end += 1) {}
                    if (end < data.len and data[end] == 'm') {
                        applySgr(data[param_start..end], &fg, &bg, &bold, &reverse);
                        i = end + 1;
                        continue;
                    }
                }
                i += 1;
            },
            else => {
                if (byte >= 0x80 and byte < 0xC0) {
                    i += 1;
                    continue;
                }
                if (num_cols > 0 and col >= num_cols) {
                    row += 1;
                    col = 0;
                }
                const screen_row = row - scroll_offset;
                if (screen_row >= 0 and screen_row < visible_rows) {
                    const is_cursor = (i == cursor_pos);
                    const render_fg = if (reverse) bg else fg;
                    const render_bg = if (reverse) fg else bg;
                    const char_fg: u24 = if (is_cursor) render_bg else render_fg;
                    const char_bg: u24 = if (is_cursor) render_fg else render_bg;

                    const px: i16 = @intCast(@as(u16, col) * fw);
                    const py: i16 = screen_row * @as(i16, @intCast(fh));

                    // Draw background if not default
                    if (char_bg != default_bg) {
                        try self.updateGcFg(char_bg);
                        try sink.PolyFillRectangle(drawable, self.ids.gc(), .initAssume(&.{
                            .{ .x = px, .y = py, .width = fw, .height = fh },
                        }));
                    }

                    // Draw character
                    if (byte >= 0x20 and byte < 0x7f) {
                        try self.updateGcFg(char_fg);
                        try sink.ImageText8(
                            drawable,
                            self.ids.gc(),
                            .{ .x = px, .y = py + fa },
                            .{ .ptr = @ptrCast(&byte), .len = 1 },
                        );
                    }
                }
                col += 1;
                i += 1;
            },
        }
    }

    // Draw cursor if not already drawn inline
    {
        // Compute cursor screen position
        var cc: u16 = 0;
        var cr: i16 = 0;
        for (data[0..@min(cursor_pos, data.len)]) |ch| {
            if (ch == '\n') {
                cr += 1;
                cc = 0;
            } else if (ch >= 0x20) {
                cc += 1;
                if (num_cols > 0 and cc >= num_cols) {
                    cr += 1;
                    cc = 0;
                }
            }
        }
        const cursor_screen_row = cr - scroll_offset;
        if (cursor_screen_row >= 0 and cursor_screen_row < visible_rows) {
            const cpx: i16 = @intCast(@as(u16, cc) * fw);
            const cpy: i16 = cursor_screen_row * @as(i16, @intCast(fh));
            try self.updateGcFg(default_fg);
            try sink.PolyFillRectangle(drawable, self.ids.gc(), .initAssume(&.{
                .{ .x = cpx, .y = cpy, .width = fw, .height = fh },
            }));
        }
    }

    // Swap
    try sink.CopyArea(.{
        .src_drawable = drawable,
        .dst_drawable = self.ids.window().drawable(),
        .gc = self.ids.gc(),
        .src_x = 0,
        .src_y = 0,
        .dst_x = 0,
        .dst_y = 0,
        .width = self.win_width,
        .height = self.win_height,
    });
    try sink.writer.flush();
}

fn updateGcFg(self: *X11Backend, fg_color: u24) !void {
    if (self.gc_fg != fg_color) {
        self.gc_fg = fg_color;
        try self.io.sink.ChangeGc(self.ids.gc(), .{
            .foreground = self.screen.depth.rgbFrom24(fg_color),
        });
    }
}

fn applySgr(params: []const u8, fg: *u24, bg: *u24, bold_: *bool, reverse_: *bool) void {
    const ansi_colors = [8]u24{ 0x000000, 0xaa0000, 0x00aa00, 0xaa5500, 0x0000aa, 0xaa00aa, 0x00aaaa, 0xaaaaaa };
    const ansi_bright = [8]u24{ 0x555555, 0xff5555, 0x55ff55, 0xffff55, 0x5555ff, 0xff55ff, 0x55ffff, 0xffffff };
    if (params.len == 0) {
        fg.* = default_fg;
        bg.* = default_bg;
        bold_.* = false;
        reverse_.* = false;
        return;
    }
    var iter = std.mem.splitScalar(u8, params, ';');
    while (iter.next()) |param| {
        const code = std.fmt.parseUnsigned(u8, param, 10) catch continue;
        switch (code) {
            0 => { fg.* = default_fg; bg.* = default_bg; bold_.* = false; reverse_.* = false; },
            1 => bold_.* = true,
            7 => reverse_.* = true,
            22 => bold_.* = false,
            27 => reverse_.* = false,
            30...37 => fg.* = if (bold_.*) ansi_bright[code - 30] else ansi_colors[code - 30],
            39 => fg.* = default_fg,
            40...47 => bg.* = ansi_colors[code - 40],
            49 => bg.* = default_bg,
            90...97 => fg.* = ansi_bright[code - 90],
            else => {},
        }
    }
}

fn keysymToCtrlBytes(keysym: x11.charset.Combined) []const u8 {
    const S = struct { var buf: [1]u8 = undefined; };
    const charset = keysym.charset();
    const code = keysym.code();
    if (charset == .latin1) {
        if ((code >= 'a' and code <= 'z') or (code >= 'A' and code <= 'Z')) {
            S.buf[0] = code & 0x1f;
            return &S.buf;
        }
        if (code >= '@' and code <= '_') {
            S.buf[0] = code & 0x1f;
            return &S.buf;
        }
    }
    return keysymToBytes(keysym);
}

fn keysymToBytes(keysym: x11.charset.Combined) []const u8 {
    const S = struct { var buf: [1]u8 = undefined; };
    const charset = keysym.charset();
    const code = keysym.code();
    switch (charset) {
        .latin1 => {
            S.buf[0] = code;
            if (code <= 126 or code >= 128) return &S.buf;
            return "";
        },
        .keyboard => {
            return switch (keysym) {
                .kbd_return_enter, .kbd_keypad_enter => "\r",
                .kbd_backspace_back_space_back_char => "\x7f",
                .kbd_tab => "\t",
                .kbd_escape => "\x1b",
                .kbd_delete_rubout => "\x1b[3~",
                .kbd_up => "\x1b[A",
                .kbd_down => "\x1b[B",
                .kbd_right => "\x1b[C",
                .kbd_left => "\x1b[D",
                .kbd_home => "\x1b[H",
                .kbd_end_eol => "\x1b[F",
                .kbd_page_up => "\x1b[5~",
                .kbd_page_down => "\x1b[6~",
                .kbd_insert_insert_here => "\x1b[2~",
                else => "",
            };
        },
        else => return "",
    }
}

pub fn deinit(self: *X11Backend) void {
    posix.close(self.fd);
}
