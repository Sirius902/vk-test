const std = @import("std");
const c = @cImport(@cInclude("GLFW/glfw3.h"));

pub fn main() !void {
    _ = c.glfwSetErrorCallback(glfwErrorCallback);

    if (c.glfwInit() == c.GLFW_FALSE) return error.GlfwInit;
    defer c.glfwTerminate();

    const window = if (c.glfwCreateWindow(640, 480, "Vulkan Test", null, null)) |w| w else return error.GlfwCreateWindow;
    defer c.glfwDestroyWindow(window);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
    }
}

fn glfwErrorCallback(error_code: c_int, description: [*c]const u8) callconv(.C) void {
    std.log.err("GLFW error {}: {s}", .{ error_code, description });
}
