const std = @import("std");
const c = @import("c.zig");
const vk = @import("vulkan");
const shaders = @import("shaders");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const Allocator = std.mem.Allocator;

/// Wraps ImGui setup. Only initialize one `ImGuiContext` at a time.
pub const ImGuiContext = struct {
    gc: *const GraphicsContext,
    allocator: Allocator,
    render_pass: vk.RenderPass,
    framebuffers: []const vk.Framebuffer,
    extent: vk.Extent2D,
    descriptor_pool: vk.DescriptorPool,

    pub fn init(
        gc: *const GraphicsContext,
        swapchain: *const Swapchain,
        allocator: Allocator,
        window: *c.GLFWwindow,
        ini_path: [*:0]const u8,
    ) !ImGuiContext {
        _ = c.igCreateContext(null);
        errdefer c.igDestroyContext(null);

        const io: *c.ImGuiIO = c.igGetIO();
        io.IniFilename = ini_path;
        io.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard;
        io.ConfigFlags |= c.ImGuiConfigFlags_NavEnableGamepad;
        io.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
        // io.ConfigFlags |= c.ImGuiConfigFlags_ViewportsEnable;

        // When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
        const style: *c.ImGuiStyle = c.igGetStyle();
        if ((io.ConfigFlags & c.ImGuiConfigFlags_ViewportsEnable) != 0) {
            style.WindowRounding = 0.0;
            style.Colors[c.ImGuiCol_WindowBg].w = 1.0;
        }

        c.igStyleColorsDark(null);

        if (!c.ImGui_ImplGlfw_InitForVulkan(window, true)) return error.ImGuiGlfwInit;
        errdefer c.ImGui_ImplGlfw_Shutdown();

        const render_pass = try createRenderPass(gc, swapchain.surface_unorm_format);
        errdefer gc.vkd.destroyRenderPass(gc.dev, render_pass, null);

        const pool_sizes = [_]vk.DescriptorPoolSize{
            .{ .type = .sampler, .descriptor_count = 1000 },
            .{ .type = .combined_image_sampler, .descriptor_count = 1000 },
            .{ .type = .sampled_image, .descriptor_count = 1000 },
            .{ .type = .storage_image, .descriptor_count = 1000 },
            .{ .type = .uniform_texel_buffer, .descriptor_count = 1000 },
            .{ .type = .storage_texel_buffer, .descriptor_count = 1000 },
            .{ .type = .uniform_buffer, .descriptor_count = 1000 },
            .{ .type = .storage_buffer, .descriptor_count = 1000 },
            .{ .type = .uniform_buffer_dynamic, .descriptor_count = 1000 },
            .{ .type = .storage_buffer_dynamic, .descriptor_count = 1000 },
            .{ .type = .input_attachment, .descriptor_count = 1000 },
        };

        const descriptor_pool = try gc.vkd.createDescriptorPool(gc.dev, &.{
            .flags = .{ .free_descriptor_set_bit = true },
            .max_sets = 1000 * pool_sizes.len,
            .pool_size_count = @intCast(pool_sizes.len),
            .p_pool_sizes = &pool_sizes,
        }, null);
        errdefer gc.vkd.destroyDescriptorPool(gc.dev, descriptor_pool, null);

        var init_info = c.ImGui_ImplVulkan_InitInfo{
            .instance = gc.instance,
            .physical_device = gc.pdev,
            .device = gc.dev,
            .queue_family = gc.graphics_queue.family,
            .queue = gc.graphics_queue.handle,
            .pipeline_cache = .null_handle,
            .descriptor_pool = descriptor_pool,
            .subpass = 0,
            .min_image_count = 2,
            .image_count = @intCast(swapchain.swap_images.len),
            .msaa_samples = .{ .@"1_bit" = true },
            .use_dynamic_rendering = false,
            .color_attachment_format = swapchain.surface_unorm_format,
            .min_allocation_size = 0,
        };
        if (!c.ImGui_ImplVulkan_Init(&init_info, render_pass)) return error.ImGuiVulkanInit;
        errdefer c.ImGui_ImplVulkan_Shutdown();

        const framebuffers = try createFramebuffers(gc, allocator, render_pass, swapchain);
        errdefer destroyFramebuffers(gc, allocator, framebuffers);

        return .{
            .gc = gc,
            .allocator = allocator,
            .render_pass = render_pass,
            .framebuffers = framebuffers,
            .extent = swapchain.extent,
            .descriptor_pool = descriptor_pool,
        };
    }

    pub fn deinit(self: *const ImGuiContext) void {
        destroyFramebuffers(self.gc, self.allocator, self.framebuffers);
        self.gc.vkd.destroyRenderPass(self.gc.dev, self.render_pass, null);

        c.ImGui_ImplVulkan_Shutdown();
        self.gc.vkd.destroyDescriptorPool(self.gc.dev, self.descriptor_pool, null);
        c.ImGui_ImplGlfw_Shutdown();
        c.igDestroyContext(null);
    }

    pub fn newFrame(self: *const ImGuiContext) void {
        _ = self;
        c.ImGui_ImplVulkan_NewFrame();
        c.ImGui_ImplGlfw_NewFrame();
        c.igNewFrame();
    }

    pub fn render(self: *const ImGuiContext) void {
        _ = self;
        c.igRender();
    }

    pub fn renderPass(self: *const ImGuiContext, framebuffer: vk.Framebuffer, cmdbuf: vk.CommandBuffer) !void {
        const clear = vk.ClearValue{
            .color = .{ .float_32 = .{ 0, 0, 0, 0 } },
        };

        // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
        const render_area = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.extent,
        };

        self.gc.vkd.cmdBeginRenderPass(cmdbuf, &.{
            .render_pass = self.render_pass,
            .framebuffer = framebuffer,
            .render_area = render_area,
            .clear_value_count = 1,
            .p_clear_values = @as([*]const vk.ClearValue, @ptrCast(&clear)),
        }, .@"inline");

        c.ImGui_ImplVulkan_RenderDrawData(c.igGetDrawData(), cmdbuf, .null_handle);

        self.gc.vkd.cmdEndRenderPass(cmdbuf);
    }

    pub fn postPresent(self: *const ImGuiContext) void {
        _ = self;
        // Update and Render additional Platform Windows
        const io: *c.ImGuiIO = c.igGetIO();
        if ((io.ConfigFlags & c.ImGuiConfigFlags_ViewportsEnable) != 0) {
            c.igUpdatePlatformWindows();
            c.igRenderPlatformWindowsDefault(null, null);
        }
    }

    pub fn resize(self: *ImGuiContext, swapchain: *const Swapchain) !void {
        destroyFramebuffers(self.gc, self.allocator, self.framebuffers);
        self.framebuffers = try createFramebuffers(self.gc, self.allocator, self.render_pass, swapchain);
        self.extent = swapchain.extent;
    }
};

fn createFramebuffers(gc: *const GraphicsContext, allocator: Allocator, render_pass: vk.RenderPass, swapchain: *const Swapchain) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.vkd.destroyFramebuffer(gc.dev, fb, null);

    for (framebuffers) |*fb| {
        fb.* = try gc.vkd.createFramebuffer(gc.dev, &.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @as([*]const vk.ImageView, @ptrCast(&swapchain.swap_images[i].unorm_view)),
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn destroyFramebuffers(gc: *const GraphicsContext, allocator: Allocator, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |fb| gc.vkd.destroyFramebuffer(gc.dev, fb, null);
    allocator.free(framebuffers);
}

fn createRenderPass(gc: *const GraphicsContext, format: vk.Format) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .load,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .present_src_khr,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
    };

    return try gc.vkd.createRenderPass(gc.dev, &.{
        .attachment_count = 1,
        .p_attachments = @as([*]const vk.AttachmentDescription, @ptrCast(&color_attachment)),
        .subpass_count = 1,
        .p_subpasses = @as([*]const vk.SubpassDescription, @ptrCast(&subpass)),
    }, null);
}
