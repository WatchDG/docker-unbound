// Zig v0.15.2
const std = @import("std");

const c = @cImport({
    @cInclude("sys/types.h");
    @cInclude("sys/socket.h");
    @cInclude("netdb.h");
    @cInclude("arpa/inet.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
});

fn getEnv(allocator: std.mem.Allocator, env_map: *const std.process.EnvMap, key: []const u8, default_value: []const u8) ![]const u8 {
    if (env_map.get(key)) |val| {
        if (val.len > 0) {
            return try allocator.dupe(u8, val);
        }
    }
    return try allocator.dupe(u8, default_value);
}

fn escapeReplacement(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    for (s) |ch| {
        if (ch == '\\') {
            try result.appendSlice(allocator, "\\\\");
        } else if (ch == '&') {
            try result.appendSlice(allocator, "\\&");
        } else {
            try result.append(allocator, ch);
        }
    }
    return try result.toOwnedSlice(allocator);
}

fn replaceAll(allocator: std.mem.Allocator, content: []const u8, placeholder: []const u8, replacement: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < content.len) {
        if (std.mem.indexOf(u8, content[i..], placeholder)) |pos| {
            try result.appendSlice(allocator, content[i..][0..pos]);
            try result.appendSlice(allocator, replacement);
            i += pos + placeholder.len;
        } else {
            try result.appendSlice(allocator, content[i..]);
            break;
        }
    }
    return try result.toOwnedSlice(allocator);
}

fn resolveHost(allocator: std.mem.Allocator, host: []const u8) ![]const u8 {
    const host_z = try allocator.dupeZ(u8, host);
    defer allocator.free(host_z);

    var hints: c.struct_addrinfo = .{
        .ai_flags = 0,
        .ai_family = c.AF_UNSPEC,
        .ai_socktype = c.SOCK_STREAM,
        .ai_protocol = 0,
        .ai_addrlen = 0,
        .ai_addr = null,
        .ai_canonname = null,
        .ai_next = null,
    };

    var res: ?*c.struct_addrinfo = null;
    const ret = c.getaddrinfo(host_z.ptr, null, &hints, &res);
    defer if (res) |r| c.freeaddrinfo(r);

    if (ret != 0) {
        const msg = "unable to resolve forward-addr host: ";
        _ = std.posix.write(2, msg) catch {};
        _ = std.posix.write(2, host) catch {};
        _ = std.posix.write(2, "\n") catch {};
        return error.ResolveFailed;
    }

    const info = res orelse return error.NoAddress;
    const addr = info.*.ai_addr;

    var buf: [64]u8 = undefined;
    const ptr: ?[*:0]const u8 = if (info.*.ai_family == c.AF_INET) blk: {
        const sockaddr_in = @as(*const c.struct_sockaddr_in, @alignCast(@ptrCast(addr)));
        break :blk c.inet_ntop(c.AF_INET, @ptrCast(&sockaddr_in.sin_addr), &buf, buf.len);
    } else if (info.*.ai_family == c.AF_INET6) blk: {
        const sockaddr_in6 = @as(*const c.struct_sockaddr_in6, @alignCast(@ptrCast(addr)));
        break :blk c.inet_ntop(c.AF_INET6, @ptrCast(&sockaddr_in6.sin6_addr), &buf, buf.len);
    } else
        null;

    if (ptr == null) return error.UnsupportedAddressFamily;
    const len = std.mem.len(ptr.?);
    const ip_str = ptr.?[0..len];
    if (info.*.ai_family == c.AF_INET6 and (ip_str.len == 0 or ip_str[0] != '[')) {
        return std.fmt.allocPrint(allocator, "[{s}]", .{ip_str});
    }
    return allocator.dupe(u8, ip_str);
}

fn isIpAddress(host: []const u8) bool {
    if (std.net.Address.parseIp4(host, 0)) |_| return true else |_| {}
    if (std.net.Address.parseIp6(host, 0)) |_| return true else |_| {}
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();

    const template_path = try getEnv(allocator, &env, "TEMPLATE", "/etc/unbound/unbound.conf.template");
    defer allocator.free(template_path);

    const conf_path = try getEnv(allocator, &env, "CONF", "/etc/unbound/unbound.conf");
    defer allocator.free(conf_path);

    const template_content = blk: {
        if (template_path.len > 0 and template_path[0] == '/') {
            var file = try std.fs.openFileAbsolute(template_path, .{});
            defer file.close();
            break :blk try file.readToEndAlloc(allocator, 1024 * 1024);
        } else {
            break :blk try std.fs.cwd().readFileAlloc(allocator, template_path, 1024 * 1024);
        }
    };
    defer allocator.free(template_content);

    var content: []u8 = try allocator.dupe(u8, template_content);
    defer allocator.free(content);

    const replacements = [_]struct { []const u8, []const u8, []const u8 }{
        .{ "__SERVER__USERNAME__", "UNBOUND__SERVER__USERNAME", "" },
        .{ "__SERVER__PORT__", "UNBOUND__SERVER__PORT", "5353" },
        .{ "__SERVER__NUM_THREADS__", "UNBOUND__SERVER__NUM_THREADS", "2" },
        .{ "__SERVER__SO_RCVBUF__", "UNBOUND__SERVER__SO_RCVBUF", "0" },
        .{ "__SERVER__SO_SNDBUF__", "UNBOUND__SERVER__SO_SNDBUF", "0" },
        .{ "__SERVER__DO_NOT_QUERY_LOCALHOST__", "UNBOUND__SERVER__DO_NOT_QUERY_LOCALHOST", "yes" },
        .{ "__SERVER__VERBOSITY__", "UNBOUND__SERVER__VERBOSITY", "1" },
        .{ "__SERVER__LOG_QUERIES__", "UNBOUND__SERVER__LOG_QUERIES", "yes" },
        .{ "__SERVER__USE_SYSLOG__", "UNBOUND__SERVER__USE_SYSLOG", "no" },
        .{ "__SERVER__LOGFILE__", "UNBOUND__SERVER__LOGFILE", "\"\"" },
        .{ "__SERVER__DIRECTORY__", "UNBOUND__SERVER__DIRECTORY", "/var/unbound" },
        .{ "__SERVER__CHROOT__", "UNBOUND__SERVER__CHROOT", "" },
        .{ "__SERVER__INTERFACE__", "UNBOUND__SERVER__INTERFACE", "0.0.0.0" },
        .{ "__SERVER__DO_IP4__", "UNBOUND__SERVER__DO_IP4", "yes" },
        .{ "__SERVER__DO_IP6__", "UNBOUND__SERVER__DO_IP6", "no" },
        .{ "__SERVER__DO_UDP__", "UNBOUND__SERVER__DO_UDP", "yes" },
        .{ "__SERVER__DO_TCP__", "UNBOUND__SERVER__DO_TCP", "yes" },
        .{ "__SERVER__USE_CAPS_FOR_ID__", "UNBOUND__SERVER__USE_CAPS_FOR_ID", "yes" },
        .{ "__SERVER__PREFETCH__", "UNBOUND__SERVER__PREFETCH", "yes" },
        .{ "__SERVER__QNAME_MINIMISATION__", "UNBOUND__SERVER__QNAME_MINIMISATION", "yes" },
        .{ "__SERVER__MINIMAL_RESPONSES__", "UNBOUND__SERVER__MINIMAL_RESPONSES", "yes" },
        .{ "__SERVER__HIDE_IDENTITY__", "UNBOUND__SERVER__HIDE_IDENTITY", "yes" },
        .{ "__SERVER__HIDE_VERSION__", "UNBOUND__SERVER__HIDE_VERSION", "yes" },
        .{ "__SERVER__HARDEN_GLUE__", "UNBOUND__SERVER__HARDEN_GLUE", "yes" },
        .{ "__SERVER__HARDEN_REFERRAL_PATH__", "UNBOUND__SERVER__HARDEN_REFERRAL_PATH", "yes" },
        .{ "__SERVER__CACHE_MIN_TTL__", "UNBOUND__SERVER__CACHE_MIN_TTL", "60" },
        .{ "__SERVER__CACHE_MAX_TTL__", "UNBOUND__SERVER__CACHE_MAX_TTL", "86400" },
        .{ "__SERVER__MSG_CACHE_SIZE__", "UNBOUND__SERVER__MSG_CACHE_SIZE", "64m" },
        .{ "__SERVER__RRSET_CACHE_SIZE__", "UNBOUND__SERVER__RRSET_CACHE_SIZE", "64m" },
        .{ "__SERVER__UNWANTED_REPLY_THRESHOLD__", "UNBOUND__SERVER__UNWANTED_REPLY_THRESHOLD", "10000" },
    };

    for (replacements) |r| {
        const val = try getEnv(allocator, &env, r.@"1", r.@"2");
        defer allocator.free(val);
        const escaped = try escapeReplacement(allocator, val);
        defer allocator.free(escaped);
        const new_content = try replaceAll(allocator, content, r.@"0", escaped);
        allocator.free(content);
        content = new_content;
    }

    const forward_addr = try getEnv(allocator, &env, "UNBOUND__FORWARD_ZONE__FORWARD_ADDR", "");
    defer allocator.free(forward_addr);

    if (forward_addr.len > 0) {
        const forward_name = try getEnv(allocator, &env, "UNBOUND__FORWARD_ZONE__NAME", ".");
        defer allocator.free(forward_name);
        const forward_tls = try getEnv(allocator, &env, "UNBOUND__FORWARD_ZONE__FORWARD_TLS_UPSTREAM", "no");
        defer allocator.free(forward_tls);

        var forward_host = forward_addr;
        var forward_port: ?[]const u8 = null;
        if (std.mem.indexOf(u8, forward_addr, "@")) |at_pos| {
            forward_host = forward_addr[0..at_pos];
            forward_port = forward_addr[at_pos + 1 ..];
        }

        const resolved_host = if (isIpAddress(forward_host))
            try allocator.dupe(u8, forward_host)
        else
            try resolveHost(allocator, forward_host);
        defer allocator.free(resolved_host);

        var forward_addr_resolved: []const u8 = resolved_host;
        if (forward_port) |port| {
            forward_addr_resolved = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ resolved_host, port });
            defer allocator.free(forward_addr_resolved);
        }

        const forward_zone = try std.fmt.allocPrint(allocator,
            "\nforward-zone:\n    name: \"{s}\"\n    forward-addr: {s}\n    forward-tls-upstream: {s}\n",
            .{ forward_name, forward_addr_resolved, forward_tls },
        );
        defer allocator.free(forward_zone);

        const new_content = try std.mem.concat(allocator, u8, &.{ content, forward_zone });
        allocator.free(content);
        content = new_content;
    }

    const conf_dir = std.fs.path.dirname(conf_path) orelse "/etc/unbound";
    if (conf_path.len > 0 and conf_path[0] == '/') {
        try std.fs.cwd().makePath(conf_dir);
        var file = try std.fs.createFileAbsolute(conf_path, .{});
        defer file.close();
        try file.writeAll(content);
    } else {
        try std.fs.cwd().makePath(conf_dir);
        try std.fs.cwd().writeFile(.{ .sub_path = conf_path, .data = content });
    }

    const server_directory = try getEnv(allocator, &env, "UNBOUND__SERVER__DIRECTORY", "/var/unbound");
    defer allocator.free(server_directory);
    try std.fs.cwd().makePath(server_directory);

    const unbound_path = "/usr/sbin/unbound";
    const args = [_][]const u8{ unbound_path, "-d", "-c", conf_path };

    var env_strings: std.ArrayList(?[*:0]u8) = .empty;
    var env_slices: std.ArrayList([]u8) = .empty;
    defer {
        for (env_slices.items) |slice| allocator.free(slice);
        env_slices.deinit(allocator);
        env_strings.deinit(allocator);
    }

    var env_iterator = env.iterator();
    while (env_iterator.next()) |entry| {
        const env_str_slice = try std.fmt.allocPrint(allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* });
        const env_str = try allocator.alloc(u8, env_str_slice.len + 1);
        @memcpy(env_str[0..env_str_slice.len], env_str_slice);
        env_str[env_str_slice.len] = 0;
        allocator.free(env_str_slice);
        try env_strings.append(allocator, @ptrCast(env_str.ptr));
        try env_slices.append(allocator, env_str);
    }
    try env_strings.append(allocator, null);

    var args_z: std.ArrayList(?[*:0]const u8) = .empty;
    var args_slices: std.ArrayList([]u8) = .empty;
    defer {
        for (args_slices.items) |slice| allocator.free(slice);
        args_slices.deinit(allocator);
        args_z.deinit(allocator);
    }

    for (args) |arg| {
        const arg_slice = try allocator.alloc(u8, arg.len + 1);
        @memcpy(arg_slice[0..arg.len], arg);
        arg_slice[arg.len] = 0;
        try args_z.append(allocator, @ptrCast(arg_slice.ptr));
        try args_slices.append(allocator, arg_slice);
    }
    try args_z.append(allocator, null);

    const path_slice = try allocator.alloc(u8, unbound_path.len + 1);
    @memcpy(path_slice[0..unbound_path.len], unbound_path);
    path_slice[unbound_path.len] = 0;
    defer allocator.free(path_slice);

    const path_ptr: [*:0]const u8 = @ptrCast(path_slice.ptr);
    const args_ptr = @as([*c]const [*c]u8, @ptrCast(args_z.items.ptr));
    const env_ptr = @as([*c]const [*c]u8, @ptrCast(env_strings.items.ptr));

    _ = c.execve(path_ptr, args_ptr, env_ptr);
    return error.ExecveFailed;
}
