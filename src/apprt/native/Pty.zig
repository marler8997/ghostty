const Pty = @This();

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const log = std.log.scoped(.native);

master: posix.fd_t,
pid: posix.pid_t,
cols: u16,
rows: u16,

pub fn openAndSpawn(cols: u16, rows: u16) !Pty {
    const dev_ptmx = "/dev/ptmx";
    const master = try posix.open(dev_ptmx, .{ .ACCMODE = .RDWR, .NOCTTY = true, .CLOEXEC = true }, 0);
    errdefer posix.close(master);

    // Unlock the slave side
    var unlock: c_int = 0;
    if (posix.errno(linux.ioctl(master, linux.T.IOCSPTLCK, @intFromPtr(&unlock))) != .SUCCESS) {
        return error.UnlockPtyFailed;
    }

    // Get the slave PTY number
    var pty_num: c_uint = 0;
    if (posix.errno(linux.ioctl(master, linux.T.IOCGPTN, @intFromPtr(&pty_num))) != .SUCCESS) {
        return error.GetPtyNumFailed;
    }

    // Build slave path: /dev/pts/N
    var pts_path_buf: [32]u8 = undefined;
    const pts_path = std.fmt.bufPrint(&pts_path_buf, "/dev/pts/{}\x00", .{pty_num}) catch unreachable;
    const pts_path_z: [:0]const u8 = pts_path[0 .. pts_path.len - 1 :0];

    setWinsz(master, cols, rows);

    const pid = try posix.fork();
    if (pid == 0) {
        // Child process
        posix.close(master);
        _ = linux.setsid();

        const slave = posix.open(pts_path_z, .{ .ACCMODE = .RDWR }, 0) catch {
            std.process.exit(0xff);
        };

        posix.dup2(slave, 0) catch std.process.exit(0xff);
        posix.dup2(slave, 1) catch std.process.exit(0xff);
        posix.dup2(slave, 2) catch std.process.exit(0xff);
        if (slave > 2) posix.close(slave);

        const shell = posix.getenv("SHELL") orelse "/bin/sh";
        const envp = setTermEnv();
        posix.execvpeZ(
            @ptrCast(shell.ptr),
            &[_:null]?[*:0]const u8{ @ptrCast(shell.ptr), null },
            envp,
        ) catch std.process.exit(0xff);
        std.process.exit(0xff);
    }

    return .{ .master = master, .pid = pid, .cols = cols, .rows = rows };
}

pub fn updateWinsz(self: *Pty, cols: u16, rows: u16) void {
    if (cols != self.cols or rows != self.rows) {
        log.info("updating winsz from {}x{} to {}x{}", .{ self.cols, self.rows, cols, rows });
        self.cols = cols;
        self.rows = rows;
        setWinsz(self.master, cols, rows);
    }
}

fn setWinsz(fd: posix.fd_t, cols: u16, rows: u16) void {
    var ws: posix.winsize = .{ .col = cols, .row = rows, .xpixel = 0, .ypixel = 0 };
    _ = linux.ioctl(fd, linux.T.IOCSWINSZ, @intFromPtr(&ws));
}

fn setTermEnv() [*:null]?[*:0]const u8 {
    for (std.os.environ) |*entry| {
        if (std.mem.startsWith(u8, std.mem.span(entry.*), "TERM=")) {
            entry.* = @ptrCast(@constCast("TERM=xterm-256color"));
            return @ptrCast(std.os.environ.ptr);
        }
    }
    const old_len = std.os.environ.len;
    const new_envp = std.heap.page_allocator.alloc(?[*:0]const u8, old_len + 2) catch
        std.process.exit(0xff);
    @memcpy(new_envp[0..old_len], std.os.environ);
    new_envp[old_len] = "TERM=xterm-256color";
    new_envp[old_len + 1] = null;
    return @ptrCast(new_envp.ptr);
}

