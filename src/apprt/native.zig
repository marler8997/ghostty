/// Native application runtime with X11 and Wayland backends.
/// No GTK or other toolkit dependency required.
pub const App = @import("native/App.zig");
pub const Surface = @import("native/Surface.zig");
pub const resourcesDir = @import("../os/main.zig").resourcesDir;
