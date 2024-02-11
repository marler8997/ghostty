/// Types, constants and functions to interact with the win32 api copied
/// from zigwin32 (https://github.com/marlersoft/zigwin32).
const std = @import("std");
pub const WINAPI = std.os.windows.WINAPI;

pub const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const BOOL = i32;
pub const HANDLE = std.os.windows.HANDLE;
pub const HINSTANCE = std.os.windows.HINSTANCE;
pub const HWND = *opaque{};
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;

pub const HMENU = *opaque{};
pub const HICON = *opaque{};
pub const HCURSOR = HICON;

pub const HGDIOBJ = *opaque{};
pub const HBRUSH = HGDIOBJ;

pub const POINT = extern struct {
    x: i32,
    y: i32,
};
pub const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
};

pub const WNDPROC = *const fn(
    param0: HWND,
    param1: u32,
    param2: WPARAM,
    param3: LPARAM,
) callconv(WINAPI) LRESULT;

pub const WNDCLASSEXW = extern struct {
    cbSize: u32,
    style: u32,
    lpfnWndProc: ?WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: ?HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: ?[*:0]const u16,
    hIconSm: ?HICON,
};

pub const GDI_IMAGE_TYPE = enum(u32) {
    BITMAP = 0,
    CURSOR = 2,
    ICON = 1,
};
pub const LR_SHARED = 0x8000;


pub const WM_DESTROY: u32 = 2;

pub const WS_MAXIMIZEBOX = 0x010000;
pub const WS_MINIMIZEBOX = 0x020000;
pub const WS_THICKFRAME  = 0x040000;
pub const WS_SYSMENU     = 0x080000;
pub const WS_CAPTION     = 0xC00000;
pub const WS_OVERLAPPEDWINDOW = 0
    | WS_MAXIMIZEBOX
    | WS_MINIMIZEBOX
    | WS_THICKFRAME
    | WS_SYSMENU
    | WS_CAPTION
    ;

pub const WIN32_ERROR = enum(u32) {
    NO_ERROR = 0,
    _,
};

pub const CW_USEDEFAULT = @as(i32, -2147483648);

pub extern "kernel32" fn GetLastError() callconv(WINAPI) WIN32_ERROR;

pub extern "kernel32" fn GetModuleHandleW(
    lpModuleName: ?[*:0]const u16,
) callconv(WINAPI) ?HINSTANCE;

pub const SYSTEM_METRICS_INDEX = enum(u32) {
    CXICON = 11,
    CXSMICON = 49,
    CYICON = 12,
    CYSMICON = 50,
};
pub extern "user32" fn GetSystemMetrics(
    nIndex: SYSTEM_METRICS_INDEX,
) callconv(WINAPI) i32;

pub extern "user32" fn LoadImageW(
    hInst: ?HINSTANCE,
    name: ?[*:0]const align(1) u16,
    type: GDI_IMAGE_TYPE,
    cx: i32,
    cy: i32,
    flags: u32,
) callconv(WINAPI) ?HANDLE;

pub extern "user32" fn RegisterClassExW(
    param0: ?*const WNDCLASSEXW,
) callconv(WINAPI) u16;

pub extern "user32" fn GetMessageW(
    lpMsg: ?*MSG,
    hWnd: ?HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
) callconv(WINAPI) BOOL;
pub extern "user32" fn TranslateMessage(
    lpMsg: ?*const MSG,
) callconv(WINAPI) BOOL;
pub extern "user32" fn DispatchMessageW(
    lpMsg: ?*const MSG,
) callconv(WINAPI) LRESULT;
pub extern "user32" fn PostQuitMessage(
    nExitCode: i32,
) callconv(WINAPI) void;

pub const SHOW_WINDOW_CMD = enum(u32) {
    NORMAL = 1,
};

pub extern "user32" fn CreateWindowExW(
    dwExStyle: u32,
    lpClassName: ?[*:0]const u16,
    lpWindowName: ?[*:0]const u16,
    dwStyle: u32,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: ?HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(WINAPI) ?HWND;

pub extern "user32" fn ShowWindow(
    hWnd: ?HWND,
    nCmdShow: SHOW_WINDOW_CMD,
) callconv(WINAPI) BOOL;

pub extern "user32" fn DefWindowProcW(
    hWnd: ?HWND,
    Msg: u32,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(WINAPI) LRESULT;
