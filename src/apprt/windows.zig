const std = @import("std");

const win32 = @import("win32.zig");

const apprt = @import("../apprt.zig");
const terminal = @import("../terminal/main.zig");
const CoreApp = @import("../App.zig");
const CoreSurface = @import("../Surface.zig");
const Config = @import("../config.zig").Config;

const c = @cImport({
    @cInclude("GhosttyResourceNames.h");
});

const log = std.log.scoped(.windows);

const L = win32.L;
const HWND = win32.HWND;
const HICON = win32.HICON;

const Icons = struct {
    small: ?HICON,
    large: ?HICON,
};
fn getIcons() Icons {
    const small_x = win32.GetSystemMetrics(.CXSMICON);
    const small_y = win32.GetSystemMetrics(.CYSMICON);
    const large_x = win32.GetSystemMetrics(.CXICON);
    const large_y = win32.GetSystemMetrics(.CYICON);
    const small = win32.LoadImageW(
        win32.GetModuleHandleW(null),
        @ptrFromInt(c.ID_ICON_GHOSTTY),
        .ICON,
        small_x,
        small_y,
        win32.LR_SHARED,
    );
    if (small == null) {
        log.err("LoadImage for small icon failed, error={}", .{win32.GetLastError()});
        // not a critical error
    }
    const large = win32.LoadImageW(
        win32.GetModuleHandleW(null),
        @ptrFromInt(c.ID_ICON_GHOSTTY),
        .ICON,
        large_x,
        large_y,
        win32.LR_SHARED,
    );
    if (large == null) {
        log.err("LoadImage for large icon failed, error={}", .{win32.GetLastError()});
        // not a critical error
    }
    return .{ .small = @ptrCast(small), .large = @ptrCast(large) };
}

pub const App = struct {
    pub const Options = struct {};
    core_app: *CoreApp,

    pub fn init(core_app: *CoreApp, _: Options) !App {
        // Queue a single new window that starts on launch
        _ = core_app.mailbox.push(.{
            .new_window = .{},
        }, .{ .forever = {} });

        return .{ .core_app = core_app };
    }

    pub fn terminate(self: *App) void {
        _ = self;
        win32.PostQuitMessage(0);
    }

    pub fn run(self: *App) !void {
        const icons = getIcons();
        const CLASS_NAME = L("Ghostty");
        {
            const wc = win32.WNDCLASSEXW{
                .cbSize = @sizeOf(win32.WNDCLASSEXW),
                .style = 0,
                .lpfnWndProc = WndProc,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = win32.GetModuleHandleW(null),
                .hIcon = icons.large,
                .hIconSm = icons.small,
                .hCursor = null,
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = CLASS_NAME,
            };
            const class_id = win32.RegisterClassExW(&wc);
            if (class_id == 0)
                std.debug.panic("RegisterClass failed, error={}", .{win32.GetLastError()});
        }

        const hwnd = win32.CreateWindowExW(
            0,
            CLASS_NAME,
            L("Ghostty"),
            win32.WS_OVERLAPPEDWINDOW,
            win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, // position
            win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, // size
            null, // Parent window
            null, // Menu
            win32.GetModuleHandleW(null),
            null,
        ) orelse {
            log.err("CreateWindow failed with {}", .{win32.GetLastError()});
            std.os.exit(0xff);
        };
        _ = win32.ShowWindow(hwnd, .NORMAL);

        while (true) {
            const should_quit = try self.core_app.tick(self);
            if (should_quit) break;

            var msg: win32.MSG = undefined;
            while (win32.GetMessageW(&msg, null, 0, 0) != 0) {
                _ = win32.TranslateMessage(&msg);
                _ = win32.DispatchMessageW(&msg);
            }
        }

    }

    /// Open the configuration in the system editor.
    pub fn openConfig(self: *App) !void {
        _ = self;
        @panic("todo: openConfig");
    }

    /// Reload the configuration. This should return the new configuration.
    /// The old value can be freed immediately at this point assuming a
    /// successful return.
    ///
    /// The returned pointer value is only valid for a stable self pointer.
    pub fn reloadConfig(self: *App) !?*const Config {
        _ = self;
        //var config = try Config.load(self.app.alloc);
        //errdefer config.deinit();

        // Update the existing config, be sure to clean up the old one.
        //self.config.deinit();
        //self.config = config;

        //return &self.config;
        @panic("todo");
    }

    pub fn redrawSurface(self: *App, surface: *Surface) void {
        _ = self;
        _ = surface;
        @panic("todo: redrawSurface");
    }
    pub fn redrawInspector(self: *App, surface: *Surface) void {
        _ = self;
        _ = surface;
        @panic("todo: redrawInspector");
    }
};

fn WndProc(
    hwnd: HWND,
    uMsg: u32,
    wParam: win32.WPARAM,
    lParam: win32.LPARAM,
) callconv(win32.WINAPI) win32.LRESULT {
    switch (uMsg) {
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
}

pub const Surface = struct {
    core_surface: CoreSurface,

    /// Initialize the surface into the given self pointer. This gives a
    /// stable pointer to the destination that can be used for callbacks.
    pub fn init(self: *Surface, app: *App) !void {
        const config = Config{ };

        try self.core_surface.init(
            app.app.alloc,
            &config,
            app.app,
            app,
            self,
        );
        errdefer self.core_surface.deinit();
    }
    pub fn deinit(self: *Surface) void {
        self.core_surface.deinit();
    }

    /// Close this surface.
    pub fn close(self: *Surface, processActive: bool) void {
        _ = processActive;
        //self.setShouldClose();
        self.deinit();
        self.app.app.alloc.destroy(self);
    }

    /// Returns true if the window is flagged to close.
    pub fn shouldClose(self: *const Surface) bool {
        // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        // TODO
        _ = self;
        return false;
    }

    pub fn setTitle(self: *Surface, slice: [:0]const u8) !void {
        _ = self;
        _ = slice;
        @panic("todo: setTitle");
    }

    pub fn setMouseShape(self: *Surface, shape: terminal.MouseShape) !void {
        _ = self;
        _ = shape;
        @panic("todo: setMouseShape");
    }

    pub fn setCellSize(self: *const Surface, width: u32, height: u32) !void {
        _ = self;
        _ = width;
        _ = height;
        @panic("todo: setCellSize");
    }

    /// Start an async clipboard request.
    pub fn clipboardRequest(
        self: *Surface,
        clipboard_type: apprt.Clipboard,
        state: apprt.ClipboardRequest,
    ) !void {
        _ = self;
        _ = clipboard_type;
        _ = state;
        @panic("todo: clipboardRequest");
    }

    pub fn setClipboardString(
        self: *const Surface,
        val: [:0]const u8,
        clipboard_type: apprt.Clipboard,
        confirm: bool,
    ) !void {
        _ = self;
        _ = val;
        _ = clipboard_type;
        _ = confirm;
        @panic("todo: setClipboardString");
    }

};
