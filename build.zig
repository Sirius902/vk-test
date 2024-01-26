const std = @import("std");
const vkgen = @import("vulkan_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vk-test",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    linkGlfw(b, exe, target);
    linkVulkan(b, exe, target);
    linkShaders(b, exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn linkGlfw(b: *std.Build, compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    // Try to link libs using vcpkg on Windows
    if (target.result.os.tag == .windows) {
        const vcpkg_root = std.process.getEnvVarOwned(b.allocator, "VCPKG_ROOT") catch |err|
            std.debug.panic("Expected VCPKG_ROOT env to be found: {}", .{err});

        const arch_str = switch (target.result.cpu.arch) {
            .x86 => "x86",
            .x86_64 => "x64",
            else => std.debug.panic("Unsupported CPU architecture: {}", .{target.result.cpu.arch}),
        };

        const vcpkg_installed_arch_path = b.pathJoin(&[_][]const u8{
            vcpkg_root,
            "installed",
            std.mem.concat(b.allocator, u8, &[_][]const u8{ arch_str, "-windows" }) catch unreachable,
        });

        const vcpkg_lib_path = b.pathJoin(&[_][]const u8{
            vcpkg_installed_arch_path,
            "lib",
        });

        const vcpkg_include_path = b.pathJoin(&[_][]const u8{
            vcpkg_installed_arch_path,
            "include",
        });

        const glfw_name = "glfw3";

        compile.addIncludePath(.{ .path = vcpkg_include_path });
        compile.addLibraryPath(.{ .path = vcpkg_lib_path });
        compile.linkSystemLibrary(glfw_name ++ "dll");

        const vcpkg_bin_path = b.pathJoin(&[_][]const u8{
            vcpkg_installed_arch_path,
            "bin",
        });

        inline for (.{ ".dll", ".pdb" }) |prefix| {
            b.installBinFile(
                b.pathJoin(&[_][]const u8{ vcpkg_bin_path, glfw_name ++ prefix }),
                glfw_name ++ prefix,
            );
        }
    } else {
        compile.linkSystemLibrary("glfw");
    }
}

fn linkVulkan(b: *std.Build, compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    const registry_path = if (target.result.os.tag == .windows) blk: {
        const vulkan_sdk_root = std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK") catch |err|
            std.debug.panic("Expected VULKAN_SDK env to be found: {}", .{err});

        break :blk b.pathJoin(&[_][]const u8{
            vulkan_sdk_root,
            "share",
            "vulkan",
            "registry",
            "vk.xml",
        });
    } else "/usr/share/vulkan/registry/vk.xml";

    const vkzig = b.dependency("vulkan_zig", .{ .registry = @as([]const u8, registry_path) });
    const vkzig_bindings = vkzig.module("vulkan-zig");
    compile.root_module.addImport("vulkan", vkzig_bindings);
}

fn linkShaders(b: *std.Build, compile: *std.Build.Step.Compile) void {
    const shaders = vkgen.ShaderCompileStep.create(
        b,
        &[_][]const u8{ "glslc", "--target-env=vulkan1.3" },
        "-o",
    );

    shaders.add("triangle_vert", "src/shaders/triangle.vert", .{});
    shaders.add("triangle_frag", "src/shaders/triangle.frag", .{});
    compile.root_module.addImport("shaders", shaders.getModule());
}
