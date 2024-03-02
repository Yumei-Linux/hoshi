const std = @import("std");
const clap = @import("clap");

const Setup = @import("./commands/setup.zig");
const Grab = @import("./commands/grab.zig");
const LocalBuilder = @import("./commands/build.zig");
const PackageImporter = @import("./commands/package_importer.zig");

const debug = std.debug;
const io = std.io;

const PrivilegesErrors = error{NotAdmin};

fn checkPrivileges() PrivilegesErrors!void {
    if (std.os.linux.geteuid() != 0) {
        return PrivilegesErrors.NotAdmin;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                        Displays this message and exit
        \\-s, --setup                       Perform a new scaffolding of the hoshi formulas repository
        \\-c, --clean                       Clean the last formulas repository archive before re cloning it
        \\-g, --grab <str>...               Build from source and install the desired packages
        \\-b, --build <str>...              Build the specified packages locally
        \\-I, --import <str>...             Import a given .hoshi file into the hoshi packages registry
        \\-r, --rootfs <str>                The root filesystem where the packages should get merged at
        \\
    );

    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        std.process.exit(1);
        return err;
    };

    defer res.deinit();

    var stdout = io.getStdOut().writer();
    var stderr = io.getStdErr().writer();

    if (res.args.help != 0) {
        try stdout.print("usage: ", .{});
        try clap.usage(stderr, clap.Help, &params);
        try stdout.print("\n\n", .{});
        return clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
    }

    // NOTE: one can call --help without root access though.
    checkPrivileges() catch |err| {
        switch (err) {
            PrivilegesErrors.NotAdmin => {
                try stderr.print("hoshi needs root rights to work properly!\n", .{});
                std.process.exit(1);
                return err;
            },
        }
    };

    if (res.args.setup != 0) {
        Setup.run(gpa.allocator(), res.args.clean != 0) catch |err| {
            std.debug.print("Cannot setup hoshi formulas: {s}\n", .{@errorName(err)});
        };
    }

    if (res.args.grab.len > 0) {
        var grab = try Grab.new(gpa.allocator(), &res.args.grab, &res.args.rootfs);
        defer grab.deinit();
        try grab.run();
    }

    if (res.args.build.len > 0) {
        var builder = try LocalBuilder.new(gpa.allocator(), &res.args.build);
        defer builder.deinit();
        try builder.run();
    }

    if (res.args.import.len > 0) {
        var package_importer = try PackageImporter.new(gpa.allocator(), &res.args.import, &res.args.rootfs);
        defer package_importer.deinit();
        try package_importer.run();
    }
}
