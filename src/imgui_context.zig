const std = @import("std");
const c = @import("c.zig");
const vk = @import("vulkan");
const shaders = @import("shaders");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;

/// Wraps ImGui setup. Only initialize one `ImGuiContext` at a time.
pub const ImGuiContext = struct {
    gc: *const GraphicsContext,
    render_pass: vk.RenderPass,
    imgui_render_pass: vk.RenderPass,
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,
    xfb: ExternalFramebuffer,
    descriptor_layout: vk.DescriptorSetLayout,
    descriptor_set: vk.DescriptorSet,
    descriptor_pool: vk.DescriptorPool,
    pool: vk.CommandPool,
    cmdbuf: vk.CommandBuffer,

    const format: vk.Format = .b8g8r8a8_srgb;

    pub fn init(
        gc: *const GraphicsContext,
        render_pass: vk.RenderPass,
        extent: vk.Extent2D,
        pool: vk.CommandPool,
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

        const imgui_render_pass = try createRenderPass(gc, format);
        errdefer gc.vkd.destroyRenderPass(gc.dev, imgui_render_pass, null);

        var cmdbuf: vk.CommandBuffer = undefined;
        try gc.vkd.allocateCommandBuffers(gc.dev, &.{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&cmdbuf));
        errdefer gc.vkd.freeCommandBuffers(gc.dev, pool, 1, @ptrCast(&cmdbuf));

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
            .image_count = 2,
            .msaa_samples = .{ .@"1_bit" = true },
            .use_dynamic_rendering = false,
            .color_attachment_format = format,
            .min_allocation_size = 0,
        };
        if (!c.ImGui_ImplVulkan_Init(&init_info, imgui_render_pass)) return error.ImGuiVulkanInit;
        errdefer c.ImGui_ImplVulkan_Shutdown();

        const descriptor_binding = vk.DescriptorSetLayoutBinding{
            .stage_flags = .{ .fragment_bit = true },
            .descriptor_type = .combined_image_sampler,
            .binding = 0,
            .descriptor_count = 1,
        };

        const descriptor_layout = try gc.vkd.createDescriptorSetLayout(gc.dev, &.{
            .binding_count = 1,
            .p_bindings = @ptrCast(&descriptor_binding),
        }, null);
        errdefer gc.vkd.destroyDescriptorSetLayout(gc.dev, descriptor_layout, null);

        var descriptor_set: vk.DescriptorSet = undefined;
        try gc.vkd.allocateDescriptorSets(gc.dev, &vk.DescriptorSetAllocateInfo{
            .descriptor_pool = descriptor_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = @ptrCast(&descriptor_layout),
        }, @ptrCast(&descriptor_set));
        errdefer gc.vkd.freeDescriptorSets(gc.dev, descriptor_pool, 1, @ptrCast(&descriptor_set)) catch {};

        const pipeline_layout = try gc.vkd.createPipelineLayout(gc.dev, &.{
            .flags = .{},
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast(&descriptor_layout),
            .push_constant_range_count = 0,
            .p_push_constant_ranges = undefined,
        }, null);
        errdefer gc.vkd.destroyPipelineLayout(gc.dev, pipeline_layout, null);

        const pipeline = try createPipeline(gc, pipeline_layout, render_pass);
        errdefer gc.vkd.destroyPipeline(gc.dev, pipeline, null);

        const xfb = try ExternalFramebuffer.init(gc, imgui_render_pass, format, extent, pool, descriptor_set);
        errdefer xfb.deinit(gc);

        return .{
            .gc = gc,
            .render_pass = render_pass,
            .imgui_render_pass = imgui_render_pass,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .xfb = xfb,
            .descriptor_layout = descriptor_layout,
            .descriptor_set = descriptor_set,
            .descriptor_pool = descriptor_pool,
            .pool = pool,
            .cmdbuf = cmdbuf,
        };
    }

    pub fn deinit(self: *const ImGuiContext) void {
        self.gc.vkd.freeDescriptorSets(self.gc.dev, self.descriptor_pool, 1, @ptrCast(&self.descriptor_set)) catch {};
        self.gc.vkd.destroyDescriptorSetLayout(self.gc.dev, self.descriptor_layout, null);
        self.xfb.deinit(self.gc);
        self.gc.vkd.destroyPipeline(self.gc.dev, self.pipeline, null);
        self.gc.vkd.destroyPipelineLayout(self.gc.dev, self.pipeline_layout, null);
        self.gc.vkd.destroyRenderPass(self.gc.dev, self.imgui_render_pass, null);

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

    pub fn renderDrawDataToTexture(self: *const ImGuiContext) !void {
        const clear = vk.ClearValue{
            .color = .{ .float_32 = .{ 0, 0, 0, 0 } },
        };

        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @as(f32, @floatFromInt(self.xfb.extent.width)),
            .height = @as(f32, @floatFromInt(self.xfb.extent.height)),
            .min_depth = 0,
            .max_depth = 1,
        };

        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.xfb.extent,
        };

        try self.gc.vkd.resetCommandBuffer(self.cmdbuf, .{});
        try self.gc.vkd.beginCommandBuffer(self.cmdbuf, &.{});

        self.gc.vkd.cmdSetViewport(self.cmdbuf, 0, 1, @ptrCast(&viewport));
        self.gc.vkd.cmdSetScissor(self.cmdbuf, 0, 1, @ptrCast(&scissor));

        // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
        const render_area = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.xfb.extent,
        };

        self.gc.vkd.cmdBeginRenderPass(self.cmdbuf, &.{
            .render_pass = self.imgui_render_pass,
            .framebuffer = self.xfb.framebuffer,
            .render_area = render_area,
            .clear_value_count = 1,
            .p_clear_values = @as([*]const vk.ClearValue, @ptrCast(&clear)),
        }, .@"inline");

        c.ImGui_ImplVulkan_RenderDrawData(c.igGetDrawData(), self.cmdbuf, .null_handle);

        self.gc.vkd.cmdEndRenderPass(self.cmdbuf);
        try self.gc.vkd.endCommandBuffer(self.cmdbuf);

        const si = vk.SubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.cmdbuf),
            .p_wait_dst_stage_mask = undefined,
        };
        try self.gc.vkd.queueSubmit(self.gc.graphics_queue.handle, 1, @ptrCast(&si), .null_handle);
        try self.gc.vkd.queueWaitIdle(self.gc.graphics_queue.handle);
    }

    pub fn drawTexture(self: *const ImGuiContext, cmdbuf: vk.CommandBuffer) void {
        self.gc.vkd.cmdBindDescriptorSets(cmdbuf, .graphics, self.pipeline_layout, 0, 1, @ptrCast(&self.descriptor_set), 0, null);
        self.gc.vkd.cmdBindPipeline(cmdbuf, .graphics, self.pipeline);
        self.gc.vkd.cmdDraw(cmdbuf, 6, 1, 0, 0);
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

    pub fn resize(self: *ImGuiContext, extent: vk.Extent2D) !void {
        self.xfb.deinit(self.gc);
        self.xfb = try ExternalFramebuffer.init(
            self.gc,
            self.imgui_render_pass,
            self.xfb.format,
            extent,
            self.pool,
            self.descriptor_set,
        );
    }
};

const ExternalFramebuffer = struct {
    image: vk.Image,
    memory: vk.DeviceMemory,
    view: vk.ImageView,
    sampler: vk.Sampler,
    extent: vk.Extent2D,
    format: vk.Format,
    framebuffer: vk.Framebuffer,

    pub fn init(
        gc: *const GraphicsContext,
        render_pass: vk.RenderPass,
        format: vk.Format,
        extent: vk.Extent2D,
        pool: vk.CommandPool,
        descriptor_set: vk.DescriptorSet,
    ) !ExternalFramebuffer {
        const image = try gc.vkd.createImage(gc.dev, &vk.ImageCreateInfo{
            .image_type = .@"2d",
            .format = format,
            .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true, .sampled_bit = true },
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        }, null);
        errdefer gc.vkd.destroyImage(gc.dev, image, null);

        const mem_reqs = gc.vkd.getImageMemoryRequirements(gc.dev, image);
        const memory = try gc.allocate(mem_reqs, .{ .device_local_bit = true });
        errdefer gc.vkd.freeMemory(gc.dev, memory, null);

        try gc.vkd.bindImageMemory(gc.dev, image, memory, 0);

        const barrier = vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{},
            .image = image,
            .old_layout = .undefined,
            .new_layout = .shader_read_only_optimal,
            .src_queue_family_index = 0,
            .dst_queue_family_index = 0,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        const cmdbuf = try createSingleUseCommandBuffer(gc, pool);

        const src_stage = vk.PipelineStageFlags{ .top_of_pipe_bit = true };
        const dst_stage = vk.PipelineStageFlags{ .fragment_shader_bit = true };
        gc.vkd.cmdPipelineBarrier(cmdbuf, src_stage, dst_stage, .{}, 0, null, 0, null, 1, @ptrCast(&barrier));

        try finalizeSingleUseCommandBuffer(gc, cmdbuf, pool);

        const view = try gc.vkd.createImageView(gc.dev, &.{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer gc.vkd.destroyImageView(gc.dev, view, null);

        const sampler = try gc.vkd.createSampler(gc.dev, &vk.SamplerCreateInfo{
            .mag_filter = .linear,
            .min_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .anisotropy_enable = vk.FALSE,
            .max_anisotropy = undefined,
            .border_color = .float_opaque_white,
            .unnormalized_coordinates = vk.FALSE,
            .compare_enable = vk.FALSE,
            .compare_op = .always,
            .mipmap_mode = .linear,
            .mip_lod_bias = 0,
            .min_lod = 0,
            .max_lod = 0,
        }, null);
        errdefer gc.vkd.destroySampler(gc.dev, sampler, null);

        const image_info = vk.DescriptorImageInfo{
            .image_layout = .shader_read_only_optimal,
            .image_view = view,
            .sampler = sampler,
        };
        const descriptor_write = vk.WriteDescriptorSet{
            .dst_set = descriptor_set,
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
            .p_image_info = @ptrCast(&image_info),
        };
        gc.vkd.updateDescriptorSets(gc.dev, 1, @ptrCast(&descriptor_write), 0, null);

        const framebuffer = try gc.vkd.createFramebuffer(gc.dev, &.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @as([*]const vk.ImageView, @ptrCast(&view)),
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        }, null);
        errdefer gc.vkd.destroyFramebuffer(gc.dev, framebuffer, null);

        return .{
            .image = image,
            .memory = memory,
            .view = view,
            .sampler = sampler,
            .extent = extent,
            .format = format,
            .framebuffer = framebuffer,
        };
    }

    pub fn deinit(self: ExternalFramebuffer, gc: *const GraphicsContext) void {
        gc.vkd.destroyFramebuffer(gc.dev, self.framebuffer, null);
        gc.vkd.destroySampler(gc.dev, self.sampler, null);
        gc.vkd.destroyImageView(gc.dev, self.view, null);
        gc.vkd.destroyImage(gc.dev, self.image, null);
        gc.vkd.freeMemory(gc.dev, self.memory, null);
    }
};

fn createSingleUseCommandBuffer(gc: *const GraphicsContext, pool: vk.CommandPool) !vk.CommandBuffer {
    var cmdbuf: vk.CommandBuffer = undefined;
    try gc.vkd.allocateCommandBuffers(gc.dev, &.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf));
    errdefer gc.vkd.freeCommandBuffers(gc.dev, pool, 1, @ptrCast(&cmdbuf));

    try gc.vkd.beginCommandBuffer(cmdbuf, &.{ .flags = .{ .one_time_submit_bit = true } });
    return cmdbuf;
}

fn finalizeSingleUseCommandBuffer(gc: *const GraphicsContext, cmdbuf: vk.CommandBuffer, pool: vk.CommandPool) !void {
    try gc.vkd.endCommandBuffer(cmdbuf);

    const submit_info = vk.SubmitInfo{ .command_buffer_count = 1, .p_command_buffers = @ptrCast(&cmdbuf) };
    try gc.vkd.queueSubmit(gc.graphics_queue.handle, 1, @ptrCast(&submit_info), .null_handle);
    try gc.vkd.queueWaitIdle(gc.graphics_queue.handle);
    gc.vkd.freeCommandBuffers(gc.dev, pool, 1, @ptrCast(&cmdbuf));
}

fn createRenderPass(gc: *const GraphicsContext, format: vk.Format) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .shader_read_only_optimal,
        .final_layout = .shader_read_only_optimal,
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

fn createPipeline(
    gc: *const GraphicsContext,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
) !vk.Pipeline {
    const vert = try gc.vkd.createShaderModule(gc.dev, &.{
        .code_size = shaders.imgui_vert.len,
        .p_code = @as([*]const u32, @ptrCast(&shaders.imgui_vert)),
    }, null);
    defer gc.vkd.destroyShaderModule(gc.dev, vert, null);

    const frag = try gc.vkd.createShaderModule(gc.dev, &.{
        .code_size = shaders.imgui_frag.len,
        .p_code = @as([*]const u32, @ptrCast(&shaders.imgui_frag)),
    }, null);
    defer gc.vkd.destroyShaderModule(gc.dev, frag, null);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
        },
    };

    // Vertex data is baked into the shader
    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 0,
        .p_vertex_binding_descriptions = undefined,
        .vertex_attribute_description_count = 0,
        .p_vertex_attribute_descriptions = undefined,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .counter_clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.TRUE,
        .src_color_blend_factor = .src_alpha,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .src_alpha,
        .dst_alpha_blend_factor = .one_minus_src_alpha,
        .alpha_blend_op = .subtract,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = @intCast(pssci.len),
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.vkd.createGraphicsPipelines(
        gc.dev,
        .null_handle,
        1,
        @ptrCast(&gpci),
        null,
        @ptrCast(&pipeline),
    );
    return pipeline;
}
