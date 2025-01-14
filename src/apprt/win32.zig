const std = @import("std");
const win32 = @import("win32").everything;
const c = @cImport({
    @cInclude("GhosttyResourceNames.h");
});

const Config = @import("../config.zig").Config;
const CoreApp = @import("../App.zig");
const CoreSurface = @import("../Surface.zig");
const apprt = @import("../apprt.zig");

pub const Options = struct {};

const msg_wnd_class_name = win32.L("GhosttyApp");
const surface_wnd_class_name = win32.L("GhosttyWindow");

const WM_APP_MSG_GHOSTTY_WAKEUP = win32.WM_APP + 0;

pub const App = struct {
    msg_hwnd: win32.HWND,

    pub fn init(core: *CoreApp, opts: Options) !App {
        _ = opts;
        {
            var wc = win32.WNDCLASSEXW{
                .cbSize = @sizeOf(win32.WNDCLASSEXW),
                .style = .{},
                .lpfnWndProc = appWndProc,
                .cbClsExtra = 0,
                .cbWndExtra = @sizeOf(usize), // enough bytes to store the CoreApp pointer
                .hInstance = win32.GetModuleHandleW(null),
                .hIcon = null,
                .hCursor = null,
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = msg_wnd_class_name,
                .hIconSm = null,
            };
            if (0 == win32.RegisterClassExW(&wc)) fatalWin32(
                "RegisterClass",
                win32.GetLastError(),
            );
        }

        const msg_hwnd = win32.CreateWindowExW(
            .{},
            msg_wnd_class_name,
            null,
            .{},
            0,
            0,
            0,
            0,
            null, // parent window
            null, // menu
            win32.GetModuleHandleW(null),
            core, // WM_CREATE arg
        ) orelse fatalWin32("CreateWindow", win32.GetLastError());
        errdefer destroyWindow(msg_hwnd);

        // var config = try Config.load(core.alloc);
        // errdefer config.deinit();
        _ = core.mailbox.push(.{ .new_window = .{} }, .{ .forever = {} });

        return .{ .msg_hwnd = msg_hwnd };
    }
    pub fn terminate(self: App) void {
        _ = self;
        @panic("todo");
    }
    pub fn run(self: App) !void {
        _ = self;
        const maybe_monitor: ?win32.HMONITOR = blk: {
            break :blk win32.MonitorFromPoint(
                .{ .x = 0, .y = 0 },
                win32.MONITOR_DEFAULTTOPRIMARY,
            ) orelse {
                std.log.warn("MonitorFromPoint failed with {}", .{win32.GetLastError().fmt()});
                break :blk null;
            };
        };

        const dpi: XY(u32) = blk: {
            const monitor = maybe_monitor orelse break :blk .{ .x = 96, .y = 96 };
            var dpi: XY(u32) = undefined;
            const hr = win32.GetDpiForMonitor(
                monitor,
                win32.MDT_EFFECTIVE_DPI,
                &dpi.x,
                &dpi.y,
            );
            if (hr < 0) {
                std.log.warn("GetDpiForMonitor failed, hresult=0x{x}", .{@as(u32, @bitCast(hr))});
                break :blk .{ .x = 96, .y = 96 };
            }
            std.log.debug("primary monitor dpi {}x{}", .{ dpi.x, dpi.y });
            break :blk dpi;
        };

        const icons = getIcons(dpi);

        {
            var wc = win32.WNDCLASSEXW{
                .cbSize = @sizeOf(win32.WNDCLASSEXW),
                //.style = .{ .VREDRAW = 1, .HREDRAW = 1 },
                .style = .{},
                .lpfnWndProc = surfaceWndProc,
                .cbClsExtra = 0,
                .cbWndExtra = @sizeOf(usize),
                .hInstance = win32.GetModuleHandleW(null),
                .hIcon = icons.large,
                .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = surface_wnd_class_name,
                .hIconSm = icons.small,
            };
            if (0 == win32.RegisterClassExW(&wc)) fatalWin32(
                "RegisterClass",
                win32.GetLastError(),
            );
        }

        // WARNING:
        // Be careful about modifying this loop because it can be circumvented
        // by modal APIs that won't have modifications made here.
        // You can use the message-only app window for app-level customizations.
        while (true) {
            var msg: win32.MSG = undefined;
            if (0 == win32.GetMessageW(&msg, null, 0, 0))
                break;
            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
        }
    }
    pub fn performAction(
        self: *App,
        target: apprt.Target,
        comptime action: apprt.Action.Key,
        value: apprt.Action.Value(action),
    ) !void {
        _ = self;
        _ = target;
        _ = value;
        switch (action) {
            .quit => @panic("todo"),
            .new_window => @panic("todo"),
            .open_config => @panic("todo"),
            .reload_config => @panic("todo"),
            .close_all_windows => @panic("todo"),
            .toggle_quick_terminal => @panic("todo"),
            .toggle_visibility => @panic("todo"),
            .cell_size => @panic("todo"),
            .set_title => @panic("todo"),
            .config_change => @panic("todo"),
            .color_change => @panic("todo"),
            .mouse_shape => @panic("todo"),
            else => @compileError("todo perform action: " ++ @tagName(action)),
        }
    }

    pub fn newWindow(self: App, parent: ?*CoreSurface) !void {
        if (parent != null) @panic("todo");

        const hwnd = win32.CreateWindowExW(
            .{},
            surface_wnd_class_name,
            win32.L("Ghostty"),
            win32.WS_OVERLAPPEDWINDOW,
            win32.CW_USEDEFAULT, // x
            win32.CW_USEDEFAULT, // y
            win32.CW_USEDEFAULT, // width
            win32.CW_USEDEFAULT, // height
            null, // parent window
            null, // menu
            win32.GetModuleHandleW(null),
            null, // WM_CREATE arg
        ) orelse fatalWin32("CreateWindow", win32.GetLastError());
        //errdefer destroyWindowif (0 == win32.DestroyWindow(hwnd)) ("DestroyWindow failed");

        _ = win32.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });

        try self.core.addSurface(surfaceFromHwnd(hwnd));
        // _ = hwnd;
        // _ = self;
        // @panic("todo");
        // Grab a surface allocation because we're going to need it.
        // const surface = try self.core.alloc.create(Surface);
        // errdefer self.app.alloc.destroy(surface);
        // surface.* = .{};
        //try surface.init(app);
        //errdefer surface.deinit();
        //return surface;
    }
};

fn surfaceFromHwnd(hwnd: win32.HWND) *Surface {
    const addr: usize = @bitCast(win32.GetWindowLongPtrW(hwnd, @enumFromInt(0)));
    if (addr == 0) @panic("hwnd missing its surface");
    return @ptrFromInt(addr);
}

pub const Surface = struct {
    // pub fn init(surface: *Surface, app: *App) !void {
    //     // surface.* = .{
    //     //     .maybe_hwnd = hwnd,
    //     //     .hdc = hdc,
    //     //     .hglrc = hglrc,
    //     //     .app = app,
    //     //     .core_surface = undefined,
    //     // };

    //     // Add ourselves to the list of surfaces on the app.
    //     try app.app.addSurface(surface);
    //     errdefer app.app.deleteSurface(surface);

    //     // Get our new surface config
    //     var config = try apprt.surface.newConfig(app.app, &app.config);
    //     defer config.deinit();

    //     // Initialize our surface now that we have the stable pointer.
    //     try surface.core_surface.init(
    //         app.app.alloc,
    //         &config,
    //         app.app,
    //         app,
    //         surface,
    //     );
    //     errdefer surface.core_surface.deinit();

    //     _ = win32.UpdateWindow(hwnd);
    //     _ = win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT);
    //     _ = win32.SetForegroundWindow(hwnd);
    //     _ = win32.SetFocus(hwnd);
    // }
    pub fn deinit(self: *Surface) void {
        _ = self;
        @panic("todo");
    }
    pub fn shouldClose(surface: *Surface) bool {
        _ = surface;
        @panic("todo");
    }
    pub fn close(self: *Surface, processActive: bool) void {
        _ = self;
        _ = processActive;
        @panic("todo");
    }
    pub fn getTitle(self: *Surface) ?[:0]const u8 {
        _ = self;
        @panic("todo");
    }
};

fn coreAppFromMsgHwnd(hwnd: win32.HWND) *CoreApp {
    const core: ?*CoreApp = @ptrFromInt(win32.getWindowLongPtrW(hwnd, 0));
    return core.?;
}

fn appWndProc(
    hwnd: win32.HWND,
    msg: u32,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(std.os.windows.WINAPI) win32.LRESULT {
    switch (msg) {
        win32.WM_CREATE => {
            const data: *win32.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const app: *CoreApp = @alignCast(@ptrCast(data.lpCreateParams));
            if (0 != win32.setWindowLongPtrW(hwnd, 0, @intFromPtr(app))) unreachable;
            std.debug.assert(app == coreAppFromMsgHwnd(hwnd));
            return 0;
        },
        WM_APP_MSG_GHOSTTY_WAKEUP => {
            const core_app = coreAppFromMsgHwnd(hwnd);
            var rt_app: App = .{ .msg_hwnd = hwnd };
            const should_quit = core_app.tick(&rt_app) catch |err|
                std.debug.panic("app tick failed with {s}", .{@errorName(err)});
            if (should_quit or core_app.surfaces.items.len == 0) {
                win32.PostQuitMessage(0);
            }
        },
        else => return win32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn surfaceWndProc(
    hwnd: win32.HWND,
    msg: u32,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(std.os.windows.WINAPI) win32.LRESULT {
    switch (msg) {
        win32.WM_CREATE => {

            // std.debug.assert(global.state == null);
            // global.state = .{
            //     .hwnd = hwnd,
            //     .render_state = render.WindowState.init(hwnd),
            // };
            // std.debug.assert(&(global.state.?) == stateFromHwnd(hwnd));
            //return 0;
            @panic("todo");
        },
        win32.WM_CLOSE, win32.WM_DESTROY => {
            @panic("todo");
            // win32.PostQuitMessage(0);
            // return 0;
        },
        // win32.WM_MOUSEMOVE => {
        //     const point = win32ext.pointFromLparam(lparam);
        //     const state = &global.state;
        //     if (state.mouse.updateTarget(targetFromPoint(&state.layout, point))) {
        //         win32.invalidateHwnd(hwnd);
        //     }
        // },
        // win32.WM_LBUTTONDOWN => {
        //     const point = ddui.pointFromLparam(lparam);
        //     const state = &global.state;
        //     if (state.mouse.updateTarget(targetFromPoint(&state.layout, point))) {
        //         win32.invalidateHwnd(hwnd);
        //     }
        //     state.mouse.setLeftDown();
        // },
        // win32.WM_LBUTTONUP => {
        //     const point = ddui.pointFromLparam(lparam);
        //     const state = &global.state;
        //     if (state.mouse.updateTarget(targetFromPoint(&state.layout, point))) {
        //         win32.invalidateHwnd(hwnd);
        //     }
        //     // if (state.mouse.setLeftUp()) |target| switch (target) {
        //     //     .new_window_button => newWindow(),
        //     // };
        // },
        // win32.WM_DISPLAYCHANGE => {
        //     win32.invalidateHwnd(hwnd);
        //     return 0;
        // },
        // win32.WM_SIZING => {
        //     const rect: *win32.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
        //     const dpi = win32.dpiFromHwnd(hwnd);
        //     const font = getFont(dpi, global.font_size, &global.font_face);
        //     const cell_size = font.getCellSize(i32);
        //     const new_rect = calcWindowRect(dpi, rect.*, wparam, cell_size);
        //     const state = stateFromHwnd(hwnd);
        //     state.bounds = .{
        //         .token = new_rect,
        //         .rect = rect.*,
        //     };
        //     rect.* = new_rect;
        //     return 0;
        // },
        // win32.WM_SIZE => {
        //     const client_size: XY(u16) = .{
        //         .x = win32.loword(lparam),
        //         .y = win32.hiword(lparam),
        //     };

        //     const do_sanity_check = true;
        //     if (do_sanity_check) {
        //         const client_size2 = getClientSize(u16, hwnd);
        //         std.debug.assert(client_size.x == client_size2.x);
        //         std.debug.assert(client_size.y == client_size2.y);
        //     }

        //     const dpi = win32.dpiFromHwnd(hwnd);
        //     const font = getFont(dpi, global.font_size, &global.font_face);
        //     const cell_size = font.getCellSize(u16);
        //     const col_count: u16 = @intCast(@divTrunc(client_size.x + cell_size.x - 1, cell_size.x));
        //     const row_count: u16 = @intCast(@divTrunc(client_size.y + cell_size.y - 1, cell_size.y));
        //     const cell_count: usize = @as(usize, col_count) * @as(usize, row_count);
        //     global.screen.cells.ensureTotalCapacity(global.screen_arena.allocator(), cell_count) catch |e| oom(e);
        //     global.screen.cells.items.len = cell_count;
        //     global.screen.col_count = col_count;
        //     global.screen.row_count = row_count;
        //     global.terminal.updateColRowCounts(col_count, row_count);
        //     // we wait until we have a size to start the terminal
        //     // because CreatePseudoConsole fails if the size is 0, which,
        //     // seem silly
        //     if (global.execute_shell_on_wm_size) {
        //         global.terminal.addInput("C:\\Windows\\System32\\cmd.exe");
        //         global.terminal.flushInput(hwnd, global.screen.col_count, global.screen.row_count);
        //         global.execute_shell_on_wm_size = false;
        //     }
        //     win32.invalidateHwnd(hwnd);
        //     return 0;
        // },
        // win32.WM_PAINT => {
        //     const state = stateFromHwnd(hwnd);
        //     const dpi = win32.dpiFromHwnd(hwnd);
        //     const font = getFont(dpi, global.font_size, &global.font_face);
        //     global.terminal.update(&global.screen);
        //     render.paint(hwnd, &state.render_state, font, &global.screen);
        //     return 0;
        // },
        // win32.WM_GETDPISCALEDSIZE => {
        //     const inout_size: *win32.SIZE = @ptrFromInt(@as(usize, @bitCast(lparam)));
        //     const new_dpi: u32 = @intCast(0xffffffff & wparam);
        //     // we don't want to update the font with the new dpi until after
        //     // the dpi change is effective, so, we get the cell size from the current font/dpi
        //     // and re-scale it based on the new dpi ourselves
        //     const current_dpi = win32.dpiFromHwnd(hwnd);
        //     const font = getFont(current_dpi, global.font_size, &global.font_face);
        //     const current_cell_size_i32 = font.getCellSize(i32);
        //     const current_cell_size: XY(f32) = .{
        //         .x = @floatFromInt(current_cell_size_i32.x),
        //         .y = @floatFromInt(current_cell_size_i32.y),
        //     };
        //     const scale: f32 = @as(f32, @floatFromInt(new_dpi)) / @as(f32, @floatFromInt(current_dpi));
        //     const rescaled_cell_size: XY(i32) = .{
        //         .x = @intFromFloat(@round(current_cell_size.x * scale)),
        //         .y = @intFromFloat(@round(current_cell_size.y * scale)),
        //     };
        //     const new_rect = calcWindowRect(
        //         new_dpi,
        //         .{
        //             .left = 0,
        //             .top = 0,
        //             .right = inout_size.cx,
        //             .bottom = inout_size.cy,
        //         },
        //         win32.WMSZ_BOTTOMRIGHT,
        //         rescaled_cell_size,
        //     );
        //     inout_size.* = .{
        //         .cx = new_rect.right,
        //         .cy = new_rect.bottom,
        //     };
        //     return 1;
        // },
        // win32.WM_DPICHANGED => {
        //     const state = stateFromHwnd(hwnd);
        //     const dpi = win32.dpiFromHwnd(hwnd);
        //     if (dpi != win32.hiword(wparam)) @panic("unexpected hiword dpi");
        //     if (dpi != win32.loword(wparam)) @panic("unexpected loword dpi");
        //     const rect: *win32.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
        //     setWindowPosRect(hwnd, rect.*);
        //     state.bounds = null;
        //     return 0;
        // },
        // win32.WM_KEYDOWN => {
        //     // NOTE: we only handle characters that we don't receive in WM_CHAR
        //     const key: Terminal.Key = switch (wparam) {
        //         @intFromEnum(win32.VK_LEFT) => .left,
        //         @intFromEnum(win32.VK_UP) => .up,
        //         @intFromEnum(win32.VK_RIGHT) => .right,
        //         @intFromEnum(win32.VK_DOWN) => .down,
        //         else => return 0,
        //     };
        //     const was_dirty = global.terminal.dirty;
        //     global.terminal.keyDown(key);
        //     if (!was_dirty and global.terminal.dirty) win32.invalidateHwnd(hwnd);
        //     return 0;
        // },
        // win32.WM_CHAR => switch (wparam) {
        //     @intFromEnum(win32.VK_RETURN) => {
        //         global.terminal.flushInput(hwnd, global.screen.col_count, global.screen.row_count);
        //         win32.invalidateHwnd(hwnd);
        //         return 0;
        //     },
        //     else => |char_wparam| {
        //         const char: u16 = std.math.cast(u16, char_wparam) orelse std.debug.panic(
        //             "unexpected WM_CHAR {}",
        //             .{char_wparam},
        //         );
        //         const input_log = std.log.scoped(.input);
        //         const maybe_high_surrogate = global.terminal.high_surrogate;
        //         global.terminal.high_surrogate = null;
        //         if (std.unicode.utf16IsHighSurrogate(char)) {
        //             if (maybe_high_surrogate) |high_surrogate| {
        //                 input_log.warn(
        //                     "high surrogate: {} discarded (followed by another high surrogate)",
        //                     .{high_surrogate},
        //                 );
        //             }
        //             input_log.info("high surrogate: {} set", .{char});
        //             global.terminal.high_surrogate = char;
        //             return 0;
        //         }

        //         const codepoint: u21 = blk: {
        //             if (maybe_high_surrogate) |high_surrogate| {
        //                 const pair = [2]u16{ high_surrogate, char };
        //                 if (std.unicode.utf16DecodeSurrogatePair(&pair)) |cp| {
        //                     input_log.info(
        //                         "surrogate pair: {} {} to codepoint {}",
        //                         .{ high_surrogate, char, cp },
        //                     );
        //                     break :blk cp;
        //                 } else |e| switch (e) {
        //                     error.ExpectedSecondSurrogateHalf => {
        //                         input_log.warn(
        //                             "high surrogate: {} discarded (followed by non-surrogate)",
        //                             .{high_surrogate},
        //                         );
        //                     },
        //                 }
        //             }
        //             break :blk char;
        //         };

        //         var utf8_buf: [7]u8 = undefined;
        //         const len: u3 = std.unicode.utf8Encode(codepoint, &utf8_buf) catch |e| switch (e) {
        //             error.Utf8CannotEncodeSurrogateHalf,
        //             error.CodepointTooLarge,
        //             => {
        //                 std.log.warn(
        //                     "failed to encode {} (0x{0x}) with {s}",
        //                     .{ codepoint, @errorName(e) },
        //                 );
        //                 return 0;
        //             },
        //         };
        //         var high_surrogate_str_buf: [50]u8 = undefined;
        //         const high_surrogate_str: []const u8 = if (maybe_high_surrogate) |h|
        //             (std.fmt.bufPrint(&high_surrogate_str_buf, "{} ", .{h}) catch unreachable)
        //         else
        //             "";
        //         const utf8 = utf8_buf[0..len];
        //         input_log.debug(
        //             "WM_CHAR {s}{} cp={} \"{}\"",
        //             .{ high_surrogate_str, char, codepoint, std.zig.fmtEscapes(utf8) },
        //         );
        //         global.terminal.addInput(utf8);
        //         win32.invalidateHwnd(hwnd);
        //         return 0;
        //     },
        // },
        // wmapp.CHILD_PROCESS_DATA => {
        //     const buffer: [*]const u8 = @ptrFromInt(wparam);
        //     const len: usize = @bitCast(lparam);
        //     std.debug.assert(len > 0);
        //     global.terminal.onChildProcessData(buffer[0..len]);
        //     if (global.terminal.dirty)
        //         win32.invalidateHwnd(hwnd);
        //     return wmapp.CHILD_PROCESS_DATA_RESULT;
        // },
        else => return win32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

const Icons = struct {
    small: win32.HICON,
    large: win32.HICON,
};
fn getIcons(dpi: XY(u32)) Icons {
    const small_x = win32.GetSystemMetricsForDpi(@intFromEnum(win32.SM_CXSMICON), dpi.x);
    const small_y = win32.GetSystemMetricsForDpi(@intFromEnum(win32.SM_CYSMICON), dpi.y);
    const large_x = win32.GetSystemMetricsForDpi(@intFromEnum(win32.SM_CXICON), dpi.x);
    const large_y = win32.GetSystemMetricsForDpi(@intFromEnum(win32.SM_CYICON), dpi.y);
    std.log.debug("icons small={}x{} large={}x{} at dpi {}x{}", .{
        small_x, small_y,
        large_x, large_y,
        dpi.x,   dpi.y,
    });
    const small = win32.LoadImageW(
        win32.GetModuleHandleW(null),
        @ptrFromInt(c.ID_ICON_GHOSTTY),
        .ICON,
        small_x,
        small_y,
        win32.LR_SHARED,
    ) orelse fatalWin32("LoadImage for small icon", win32.GetLastError());
    const large = win32.LoadImageW(
        win32.GetModuleHandleW(null),
        @ptrFromInt(c.ID_ICON_GHOSTTY),
        .ICON,
        large_x,
        large_y,
        win32.LR_SHARED,
    ) orelse fatalWin32("LoadImage for large icon", win32.GetLastError());
    return .{ .small = @ptrCast(small), .large = @ptrCast(large) };
}

fn XY(comptime T: type) type {
    return struct {
        x: T,
        y: T,
        pub fn init(x: T, y: T) @This() {
            return .{ .x = x, .y = y };
        }

        const Self = @This();
        pub fn eql(self: Self, other: Self) bool {
            return self.x == other.x and self.y == other.y;
        }
    };
}

fn destroyWindow(hwnd: win32.HWND) void {
    if (0 == win32.DestroyWindow(hwnd)) fatalWin32(
        "DestroyWindow",
        win32.GetLastError(),
    );
}

threadlocal var thread_is_panicing = false;

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    if (!thread_is_panicing) {
        thread_is_panicing = true;
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const msg_z: [:0]const u8 = if (std.fmt.allocPrintZ(
            arena.allocator(),
            "{s}",
            .{msg},
        )) |msg_z| msg_z else |_| "failed allocate error message";
        _ = win32.MessageBoxA(null, msg_z, "Ghostty Panic!", .{ .ICONASTERISK = 1 });
    }
    std.builtin.default_panic(msg, error_return_trace, ret_addr);
}

fn fatalWin32(what: []const u8, err: win32.WIN32_ERROR) noreturn {
    std.debug.panic("{s} failed with {}", .{ what, err.fmt() });
}
fn fatalHr(what: []const u8, hresult: win32.HRESULT) noreturn {
    std.debug.panic("{s} failed, hresult=0x{x}", .{ what, @as(u32, @bitCast(hresult)) });
}
fn oom(e: error{OutOfMemory}) noreturn {
    @panic(@errorName(e));
}
