const std = @import("std");
const builtin = @import("builtin");

/// Minimum supported version of Zig
const min_ver = "0.16.0";

comptime {
    const order = std.SemanticVersion.order;
    const parse = std.SemanticVersion.parse;
    if (order(builtin.zig_version, parse(min_ver) catch unreachable) == .lt)
        @compileError("Raylib requires zig version " ++ min_ver);
}

const interfaces = &.{
    // Level 1
    "asum",
    "axpby",
    "axpy",
    "copy",
    "dot",
    "nrm2",
    "rot",
    "rotg",
    "rotm",
    "rotmg",
    "scal",
    "swap",
    "max",
    "sum",
    "imax",

    // Level 2
    "gbmv",
    "gemv",
    "ger",
    "sbmv",
    "spmv",
    "spr",
    "spr2",
    "symv",
    "syr",
    "syr2",
    "tbmv",
    "tbsv",
    "tpmv",
    "tpsv",
    "trmv",
    "trsv",

    // Level 3
    "gemm",
    "symm",
    "syrk",
    "syr2k",
    "trsm",

    // Extensions
    "geadd",
    "gemm_batch",
    "gemm_batch_strided",
    "gemmt",
    "imatcopy",
    "omatcopy",

    // Error handler
    "xerbla",
};

fn compileInterface(b: *std.Build, mod: *std.Build.Module, comptime name: []const u8, comptime variant: []const u8, use_openmp: bool) !void {
    var flags: std.ArrayList([]const u8) = .empty;
    try flags.append(b.allocator, "-DASMNAME=" ++ variant ++ name ++ "_");
    try flags.append(b.allocator, "-DASMFNAME=" ++ variant ++ name ++ "_");
    try flags.append(b.allocator, "-DNAME=" ++ variant ++ name ++ "_");
    try flags.append(b.allocator, "-DCNAME=" ++ variant ++ name);
    try flags.append(b.allocator, "-DCHAR_NAME=\"" ++ variant ++ name ++ "_\"");
    try flags.append(b.allocator, "-DCHAR_CNAME=\"" ++ variant ++ name ++ "\"");
    try flags.append(b.allocator, "-std=c11");
    if (use_openmp) {
        try flags.append(b.allocator, "-fopenmp");
    }
    switch (variant[0]) {
        'd' => {
            try flags.append(b.allocator, "-DDOUBLE");
        },

        'c' => {
            try flags.append(b.allocator, "-DCOMPLEX");
        },

        'z' => {
            try flags.append(b.allocator, "-DDOUBLE");
            try flags.append(b.allocator, "-DCOMPLEX");
        },
        else => {},
    }

    mod.addCSourceFiles(.{
        .files = &.{
            "interface/" ++ name ++ ".c",
        },
        .flags = flags.items,
    });
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "shared", "Build shared library") orelse true;
    const dynamic_arch = b.option(bool, "dynamic-arch", "Enable dynamic arch dispatch") orelse false;
    const use_threads = b.option(bool, "threads", "Enable threading") orelse false;
    const use_openmp = b.option(bool, "openmp", "Enable OpenMP") orelse true;

    if (use_openmp and use_threads) {
        std.debug.print("use_threads and use_openmp can't both be true at the same time", .{});
    }

    const mod = b.addModule("openblas", .{
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "openblas",
        .linkage = if (shared) .dynamic else .static,
        .root_module = mod,
    });

    mod.addCMacro("MAX_PARALLEL_NUMBER", "1");

    // inline for (interfaces) |interface| {
    //     inline for (&.{ "s", "d", "h", "i", "u" }) |variant| {
    //         try compileInterface(b, mod, interface, variant, use_openmp);
    //     }
    // }
    // drivers
    mod.addCSourceFiles(.{
        .files = &.{
            "driver/others/init.c",
            "driver/others/memory.c",
            "driver/others/parameter.c",
        },
        .flags = &.{
            "-std=c11",
        },
    });

    //
    // Include directories
    //
    mod.addIncludePath(b.path(""));
    mod.addIncludePath(b.path("driver/level2"));
    mod.addIncludePath(b.path("driver/level3"));
    mod.addIncludePath(b.path("kernel"));
    mod.addIncludePath(b.path("interface"));

    if (use_threads) {
        mod.single_threaded = false;
        mod.addCMacro("SMP_SERVER", "1");
        mod.addCSourceFiles(.{
            .root = b.path(""),
            .files = &.{
                "driver/others/blas_server.c",
            },
            .flags = &.{
                "-std=c11",
            },
        });

        mod.linkSystemLibrary("pthread", .{});
    }
    const arch = target.result.cpu.arch;

    if (dynamic_arch) {
        mod.addCMacro("DYNAMIC_ARCH", "1");
    }

    if (use_openmp) {
        mod.linkSystemLibrary("omp", .{});
        mod.addCMacro("USE_OPENMP", "1");
        mod.addCMacro("_Atomic", "_Atomic");
    }

    switch (arch) {
        .x86_64 => mod.addCMacro("X86_64", "1"),
        .aarch64 => mod.addCMacro("ARMV8", "1"),
        else => {},
    }

    const step = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&step.step);
}
