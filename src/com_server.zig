const std = @import("std");
const builtin = @import("builtin");

const context_menu = @import("context_menu.zig");
const extension_shared = @import("context_extension_shared.zig");
const hash = @import("hash/core.zig");
const single_instance = @import("single_instance.zig");

const HResult = i32;
const Guid = extension_shared.clsid;

const iid_iunknown = Guid{
    .data1 = 0,
    .data2 = 0,
    .data3 = 0,
    .data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 },
};
const iid_class_factory = Guid{
    .data1 = 1,
    .data2 = 0,
    .data3 = 0,
    .data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 },
};
const iid_execute_command = Guid{
    .data1 = 0x7F9185B0,
    .data2 = 0xCB92,
    .data3 = 0x43C5,
    .data4 = .{ 0x80, 0xA9, 0x92, 0x27, 0x7A, 0x4F, 0x7B, 0x54 },
};
const iid_object_with_selection = Guid{
    .data1 = 0x1C9CD5BB,
    .data2 = 0x98E9,
    .data3 = 0x4491,
    .data4 = .{ 0xA6, 0x0F, 0x31, 0xAA, 0xCC, 0x72, 0xB8, 0x3C },
};
const iid_initialize_command = Guid{
    .data1 = 0x85075ACF,
    .data2 = 0x231F,
    .data3 = 0x40EA,
    .data4 = .{ 0x96, 0x10, 0xD2, 0x6B, 0x7B, 0x58, 0xF6, 0x38 },
};

const s_ok: HResult = 0;
const s_false: HResult = 1;
const e_fail: HResult = @bitCast(@as(u32, 0x80004005));
const e_no_interface: HResult = @bitCast(@as(u32, 0x80004002));
const e_invalid_arg: HResult = @bitCast(@as(u32, 0x80070057));
const e_no_aggregation: HResult = @bitCast(@as(u32, 0x80040110));
const e_out_of_memory: HResult = @bitCast(@as(u32, 0x8007000E));

const clsctx_local_server: u32 = 0x4;
const regcls_multiple_use: u32 = 0x1;
const coinit_apartment_threaded: u32 = 0x2;
const sigdn_file_sys_path: u32 = 0x8005_8000;

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, coinit: u32) callconv(.winapi) HResult;
extern "ole32" fn CoUninitialize() callconv(.winapi) void;
extern "ole32" fn CoRegisterClassObject(class_id: *const Guid, class_factory: *anyopaque, context: u32, flags: u32, registration: *u32) callconv(.winapi) HResult;
extern "ole32" fn CoRevokeClassObject(registration: u32) callconv(.winapi) HResult;
extern "ole32" fn CoTaskMemFree(memory: ?*anyopaque) callconv(.winapi) void;

const UnknownVTable = extern struct {
    query_interface: *const fn (*anyopaque, *const Guid, *?*anyopaque) callconv(.winapi) HResult,
    add_ref: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
};

const ClassFactoryVTable = extern struct {
    query_interface: *const fn (*anyopaque, *const Guid, *?*anyopaque) callconv(.winapi) HResult,
    add_ref: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    create_instance: *const fn (*anyopaque, ?*anyopaque, *const Guid, *?*anyopaque) callconv(.winapi) HResult,
    lock_server: *const fn (*anyopaque, i32) callconv(.winapi) HResult,
};

const ExecuteCommandVTable = extern struct {
    query_interface: *const fn (*anyopaque, *const Guid, *?*anyopaque) callconv(.winapi) HResult,
    add_ref: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    set_key_state: *const fn (*anyopaque, u32) callconv(.winapi) HResult,
    set_parameters: *const fn (*anyopaque, ?[*:0]const u16) callconv(.winapi) HResult,
    set_position: *const fn (*anyopaque, Point) callconv(.winapi) HResult,
    set_show_window: *const fn (*anyopaque, i32) callconv(.winapi) HResult,
    set_no_show_ui: *const fn (*anyopaque, i32) callconv(.winapi) HResult,
    set_directory: *const fn (*anyopaque, ?[*:0]const u16) callconv(.winapi) HResult,
    execute: *const fn (*anyopaque) callconv(.winapi) HResult,
};

const ObjectWithSelectionVTable = extern struct {
    query_interface: *const fn (*anyopaque, *const Guid, *?*anyopaque) callconv(.winapi) HResult,
    add_ref: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    set_selection: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HResult,
    get_selection: *const fn (*anyopaque, *const Guid, *?*anyopaque) callconv(.winapi) HResult,
};

const InitializeCommandVTable = extern struct {
    query_interface: *const fn (*anyopaque, *const Guid, *?*anyopaque) callconv(.winapi) HResult,
    add_ref: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    initialize: *const fn (*anyopaque, ?[*:0]const u16, ?*anyopaque) callconv(.winapi) HResult,
};

const ClassFactoryInterface = extern struct { vtable: *const ClassFactoryVTable };
const ExecuteCommandInterface = extern struct { vtable: *const ExecuteCommandVTable };
const ObjectWithSelectionInterface = extern struct { vtable: *const ObjectWithSelectionVTable };
const InitializeCommandInterface = extern struct { vtable: *const InitializeCommandVTable };

const Point = extern struct { x: i32, y: i32 };

const ShellItemArrayVTable = extern struct {
    query_interface: *const anyopaque,
    add_ref: *const anyopaque,
    release: *const anyopaque,
    bind_to_handler: *const anyopaque,
    get_property_store: *const anyopaque,
    get_property_description_list: *const anyopaque,
    get_attributes: *const anyopaque,
    get_count: *const fn (*anyopaque, *u32) callconv(.winapi) HResult,
    get_item_at: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) HResult,
};

const ShellItemVTable = extern struct {
    query_interface: *const anyopaque,
    add_ref: *const anyopaque,
    release: *const anyopaque,
    bind_to_handler: *const anyopaque,
    get_parent: *const anyopaque,
    get_display_name: *const fn (*anyopaque, u32, *?[*:0]const u16) callconv(.winapi) HResult,
};

const ClassFactory = struct {
    interface: ClassFactoryInterface,
    ref_count: std.atomic.Value(i32),
    queue: *single_instance.RequestQueue,
};

const CommandObject = struct {
    execute_interface: ExecuteCommandInterface,
    selection_interface: ObjectWithSelectionInterface,
    initialize_interface: InitializeCommandInterface,
    ref_count: std.atomic.Value(i32),
    queue: *single_instance.RequestQueue,
    options: hash.HashOptions,
    selection: ?*anyopaque,
};

var server_lock_count = std.atomic.Value(i32).init(0);

const class_factory_vtable = ClassFactoryVTable{
    .query_interface = classFactoryQueryInterface,
    .add_ref = classFactoryAddRef,
    .release = classFactoryRelease,
    .create_instance = classFactoryCreateInstance,
    .lock_server = classFactoryLockServer,
};

const execute_command_vtable = ExecuteCommandVTable{
    .query_interface = commandQueryInterface,
    .add_ref = commandAddRef,
    .release = commandRelease,
    .set_key_state = commandSetKeyState,
    .set_parameters = commandSetParameters,
    .set_position = commandSetPosition,
    .set_show_window = commandSetShowWindow,
    .set_no_show_ui = commandSetNoShowUi,
    .set_directory = commandSetDirectory,
    .execute = commandExecute,
};

const selection_vtable = ObjectWithSelectionVTable{
    .query_interface = commandQueryInterface,
    .add_ref = commandAddRef,
    .release = commandRelease,
    .set_selection = commandSetSelection,
    .get_selection = commandGetSelection,
};

const initialize_vtable = InitializeCommandVTable{
    .query_interface = commandQueryInterface,
    .add_ref = commandAddRef,
    .release = commandRelease,
    .initialize = commandInitialize,
};

pub const Server = struct {
    queue: *single_instance.RequestQueue,
    class_factory: ?*ClassFactory = null,
    registration: ?u32 = null,
    initialized: bool = false,

    pub fn init(queue: *single_instance.RequestQueue) Server {
        return .{ .queue = queue };
    }

    pub fn start(self: *Server) !void {
        if (builtin.os.tag != .windows) return;
        const initialize_result = CoInitializeEx(null, coinit_apartment_threaded);
        if (initialize_result != s_ok and initialize_result != s_false) return error.ComInitializationFailed;
        self.initialized = true;

        const factory = std.heap.page_allocator.create(ClassFactory) catch return error.OutOfMemory;
        factory.* = .{
            .interface = .{ .vtable = &class_factory_vtable },
            .ref_count = std.atomic.Value(i32).init(1),
            .queue = self.queue,
        };
        _ = server_lock_count.fetchAdd(1, .seq_cst);
        self.class_factory = factory;

        var registration: u32 = 0;
        const result = CoRegisterClassObject(
            &extension_shared.extension_clsid,
            &factory.interface,
            clsctx_local_server,
            regcls_multiple_use,
            &registration,
        );
        if (result != s_ok) {
            _ = classFactoryRelease(&factory.interface);
            self.class_factory = null;
            CoUninitialize();
            self.initialized = false;
            return error.ComRegistrationFailed;
        }
        self.registration = registration;
    }

    pub fn deinit(self: *Server) void {
        if (builtin.os.tag != .windows or !self.initialized) return;
        if (self.registration) |registration| _ = CoRevokeClassObject(registration);
        self.registration = null;
        if (self.class_factory) |factory| _ = classFactoryRelease(&factory.interface);
        self.class_factory = null;
        CoUninitialize();
        self.initialized = false;
    }
};

fn classFactoryQueryInterface(self_ptr: *anyopaque, iid: *const Guid, result: *?*anyopaque) callconv(.winapi) HResult {
    const factory = fromClassFactory(self_ptr);
    result.* = null;
    if (!guidEqual(iid, &iid_iunknown) and !guidEqual(iid, &iid_class_factory)) return e_no_interface;
    result.* = &factory.interface;
    _ = classFactoryAddRef(&factory.interface);
    return s_ok;
}

fn classFactoryAddRef(self_ptr: *anyopaque) callconv(.winapi) u32 {
    const factory = fromClassFactory(self_ptr);
    return @intCast(factory.ref_count.fetchAdd(1, .seq_cst) + 1);
}

fn classFactoryRelease(self_ptr: *anyopaque) callconv(.winapi) u32 {
    const factory = fromClassFactory(self_ptr);
    const count = factory.ref_count.fetchSub(1, .seq_cst) - 1;
    if (count == 0) {
        _ = server_lock_count.fetchSub(1, .seq_cst);
        std.heap.page_allocator.destroy(factory);
    }
    return @intCast(@max(count, 0));
}

fn classFactoryCreateInstance(self_ptr: *anyopaque, outer: ?*anyopaque, iid: *const Guid, result: *?*anyopaque) callconv(.winapi) HResult {
    const factory = fromClassFactory(self_ptr);
    result.* = null;
    if (outer != null) return e_no_aggregation;

    const object = std.heap.page_allocator.create(CommandObject) catch return e_out_of_memory;
    object.* = .{
        .execute_interface = .{ .vtable = &execute_command_vtable },
        .selection_interface = .{ .vtable = &selection_vtable },
        .initialize_interface = .{ .vtable = &initialize_vtable },
        .ref_count = std.atomic.Value(i32).init(1),
        .queue = factory.queue,
        .options = hash.HashOptions.only(.sha256),
        .selection = null,
    };
    _ = server_lock_count.fetchAdd(1, .seq_cst);
    const query_result = commandQueryInterface(&object.execute_interface, iid, result);
    _ = commandRelease(&object.execute_interface);
    return query_result;
}

fn classFactoryLockServer(_: *anyopaque, lock: i32) callconv(.winapi) HResult {
    if (lock != 0) {
        _ = server_lock_count.fetchAdd(1, .seq_cst);
    } else {
        _ = server_lock_count.fetchSub(1, .seq_cst);
    }
    return s_ok;
}

fn commandQueryInterface(self_ptr: *anyopaque, iid: *const Guid, result: *?*anyopaque) callconv(.winapi) HResult {
    const object = fromCommandInterface(self_ptr);
    result.* = null;

    if (guidEqual(iid, &iid_iunknown) or guidEqual(iid, &iid_execute_command)) {
        result.* = &object.execute_interface;
    } else if (guidEqual(iid, &iid_object_with_selection)) {
        result.* = &object.selection_interface;
    } else if (guidEqual(iid, &iid_initialize_command)) {
        result.* = &object.initialize_interface;
    } else {
        return e_no_interface;
    }
    _ = commandAddRef(&object.execute_interface);
    return s_ok;
}

fn commandAddRef(self_ptr: *anyopaque) callconv(.winapi) u32 {
    const object = fromCommandInterface(self_ptr);
    return @intCast(object.ref_count.fetchAdd(1, .seq_cst) + 1);
}

fn commandRelease(self_ptr: *anyopaque) callconv(.winapi) u32 {
    const object = fromCommandInterface(self_ptr);
    const count = object.ref_count.fetchSub(1, .seq_cst) - 1;
    if (count == 0) {
        if (object.selection) |selection| releaseUnknown(selection);
        _ = server_lock_count.fetchSub(1, .seq_cst);
        std.heap.page_allocator.destroy(object);
    }
    return @intCast(@max(count, 0));
}

fn commandSetKeyState(_: *anyopaque, _: u32) callconv(.winapi) HResult {
    return s_ok;
}

fn commandSetParameters(_: *anyopaque, _: ?[*:0]const u16) callconv(.winapi) HResult {
    return s_ok;
}

fn commandSetPosition(_: *anyopaque, _: Point) callconv(.winapi) HResult {
    return s_ok;
}

fn commandSetShowWindow(_: *anyopaque, _: i32) callconv(.winapi) HResult {
    return s_ok;
}

fn commandSetNoShowUi(_: *anyopaque, _: i32) callconv(.winapi) HResult {
    return s_ok;
}

fn commandSetDirectory(_: *anyopaque, _: ?[*:0]const u16) callconv(.winapi) HResult {
    return s_ok;
}

fn commandSetSelection(self_ptr: *anyopaque, selection: ?*anyopaque) callconv(.winapi) HResult {
    const object = fromCommandInterface(self_ptr);
    if (selection == null) return e_invalid_arg;
    if (object.selection) |previous| releaseUnknown(previous);
    object.selection = selection;
    addRefUnknown(selection.?);
    return s_ok;
}

fn commandGetSelection(self_ptr: *anyopaque, iid: *const Guid, result: *?*anyopaque) callconv(.winapi) HResult {
    const object = fromCommandInterface(self_ptr);
    const selection = object.selection orelse return e_fail;
    return unknownVTable(selection).query_interface(selection, iid, result);
}

fn commandInitialize(self_ptr: *anyopaque, command_name: ?[*:0]const u16, _: ?*anyopaque) callconv(.winapi) HResult {
    const object = fromCommandInterface(self_ptr);
    object.options = hash.HashOptions.only(.sha256);
    const name = command_name orelse return s_ok;
    inline for (extension_shared.menu_algorithms) |algorithm| {
        if (wideEqualsAscii(name, extension_shared.commandKey(algorithm))) {
            object.options = hash.HashOptions.only(algorithm);
            return s_ok;
        }
    }
    if (wideEqualsAscii(name, "all")) object.options = hash.HashOptions.all();
    return s_ok;
}

fn commandExecute(self_ptr: *anyopaque) callconv(.winapi) HResult {
    const object = fromCommandInterface(self_ptr);
    const selection = object.selection orelse return e_fail;
    const array = shellItemArrayVTable(selection);
    var count: u32 = 0;
    if (array.get_count(selection, &count) != s_ok or count == 0) return e_fail;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var paths = std.ArrayList([]const u8).empty;
    defer paths.deinit(allocator);

    for (0..count) |index| {
        var item: ?*anyopaque = null;
        if (array.get_item_at(selection, @intCast(index), &item) != s_ok or item == null) continue;
        defer releaseUnknown(item.?);

        const item_vtable = shellItemVTable(item.?);
        var display_name: ?[*:0]const u16 = null;
        if (item_vtable.get_display_name(item.?, sigdn_file_sys_path, &display_name) != s_ok or display_name == null) continue;
        defer CoTaskMemFree(@constCast(@ptrCast(display_name.?)));

        const wide_path = std.mem.span(display_name.?);
        const path = std.unicode.utf16LeToUtf8Alloc(allocator, wide_path) catch continue;
        paths.append(allocator, path) catch return e_out_of_memory;
    }

    if (paths.items.len == 0) return e_fail;
    object.queue.enqueueRequest(.{ .options = object.options, .paths = paths.items });
    return s_ok;
}

fn fromClassFactory(self_ptr: *anyopaque) *ClassFactory {
    return @as(*ClassFactory, @ptrFromInt(@intFromPtr(self_ptr) - @offsetOf(ClassFactory, "interface")));
}

fn fromCommandInterface(self_ptr: *anyopaque) *CommandObject {
    const header: *const *const anyopaque = @ptrCast(@alignCast(self_ptr));
    const vtable_address = @intFromPtr(header.*);
    if (vtable_address == @intFromPtr(&selection_vtable)) {
        return @as(*CommandObject, @ptrFromInt(@intFromPtr(self_ptr) - @offsetOf(CommandObject, "selection_interface")));
    }
    if (vtable_address == @intFromPtr(&initialize_vtable)) {
        return @as(*CommandObject, @ptrFromInt(@intFromPtr(self_ptr) - @offsetOf(CommandObject, "initialize_interface")));
    }
    return @as(*CommandObject, @ptrFromInt(@intFromPtr(self_ptr) - @offsetOf(CommandObject, "execute_interface")));
}

fn shellItemArrayVTable(value: *anyopaque) *const ShellItemArrayVTable {
    const interface: *const *const ShellItemArrayVTable = @ptrCast(@alignCast(value));
    return interface.*;
}

fn shellItemVTable(value: *anyopaque) *const ShellItemVTable {
    const interface: *const *const ShellItemVTable = @ptrCast(@alignCast(value));
    return interface.*;
}

fn unknownVTable(value: *anyopaque) *const UnknownVTable {
    const interface: *const *const UnknownVTable = @ptrCast(@alignCast(value));
    return interface.*;
}

fn addRefUnknown(value: *anyopaque) void {
    _ = unknownVTable(value).add_ref(value);
}

fn releaseUnknown(value: *anyopaque) void {
    _ = unknownVTable(value).release(value);
}

fn guidEqual(left: *const Guid, right: *const Guid) bool {
    return std.mem.eql(u8, std.mem.asBytes(left), std.mem.asBytes(right));
}

fn wideEqualsAscii(value: [*:0]const u16, ascii: []const u8) bool {
    for (ascii, 0..) |character, index| {
        if (value[index] != character) return false;
    }
    return value[ascii.len] == 0;
}

pub fn isEmbeddingArg(args: []const []const u8) bool {
    if (builtin.os.tag != .windows) return false;
    for (args[1..]) |arg| {
        if (std.ascii.eqlIgnoreCase(arg, "-Embedding")) return true;
    }
    return false;
}

test "command names map to the registered menu order" {
    try std.testing.expectEqualStrings("crc64-iso", extension_shared.commandKey(.crc64_iso));
    try std.testing.expectEqualStrings("sha256", extension_shared.commandKey(.sha256));
}
