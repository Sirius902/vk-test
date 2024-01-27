const c = @import("c.zig");
const vk = @import("vulkan");

pub const ImGui_ImplVulkanH_Frame = extern struct {
    CommandPool: vk.CommandPool = @import("std").mem.zeroes(vk.CommandPool),
    CommandBuffer: vk.CommandBuffer = @import("std").mem.zeroes(vk.CommandBuffer),
    Fence: vk.Fence = @import("std").mem.zeroes(vk.Fence),
    Backbuffer: vk.Image = @import("std").mem.zeroes(vk.Image),
    BackbufferView: vk.ImageView = @import("std").mem.zeroes(vk.ImageView),
    Framebuffer: vk.Framebuffer = @import("std").mem.zeroes(vk.Framebuffer),
};

pub const ImGui_ImplVulkanH_FrameSemaphores = extern struct {
    ImageAcquiredSemaphore: vk.Semaphore = @import("std").mem.zeroes(vk.Semaphore),
    RenderCompleteSemaphore: vk.Semaphore = @import("std").mem.zeroes(vk.Semaphore),
};

pub const ImGui_ImplVulkanH_Window = extern struct {
    Width: c_int = @import("std").mem.zeroes(c_int),
    Height: c_int = @import("std").mem.zeroes(c_int),
    Swapchain: vk.SwapchainKHR = @import("std").mem.zeroes(vk.SwapchainKHR),
    Surface: vk.SurfaceKHR = @import("std").mem.zeroes(vk.SurfaceKHR),
    SurfaceFormat: vk.SurfaceFormatKHR = @import("std").mem.zeroes(vk.SurfaceFormatKHR),
    PresentMode: vk.PresentModeKHR = @import("std").mem.zeroes(vk.PresentModeKHR),
    RenderPass: vk.RenderPass = @import("std").mem.zeroes(vk.RenderPass),
    Pipeline: vk.Pipeline = @import("std").mem.zeroes(vk.Pipeline),
    UseDynamicRendering: bool = @import("std").mem.zeroes(bool),
    ClearEnable: bool = @import("std").mem.zeroes(bool),
    ClearValue: vk.ClearValue = @import("std").mem.zeroes(vk.ClearValue),
    FrameIndex: u32 = @import("std").mem.zeroes(u32),
    ImageCount: u32 = @import("std").mem.zeroes(u32),
    SemaphoreIndex: u32 = @import("std").mem.zeroes(u32),
    Frames: [*c]ImGui_ImplVulkanH_Frame = @import("std").mem.zeroes([*c]ImGui_ImplVulkanH_Frame),
    FrameSemaphores: [*c]ImGui_ImplVulkanH_FrameSemaphores = @import("std").mem.zeroes([*c]ImGui_ImplVulkanH_FrameSemaphores),
};

pub const ImGui_ImplVulkan_InitInfo = extern struct {
    Instance: vk.Instance = @import("std").mem.zeroes(vk.Instance),
    PhysicalDevice: vk.PhysicalDevice = @import("std").mem.zeroes(vk.PhysicalDevice),
    Device: vk.Device = @import("std").mem.zeroes(vk.Device),
    QueueFamily: u32 = @import("std").mem.zeroes(u32),
    Queue: vk.Queue = @import("std").mem.zeroes(vk.Queue),
    PipelineCache: vk.PipelineCache = @import("std").mem.zeroes(vk.PipelineCache),
    DescriptorPool: vk.DescriptorPool = @import("std").mem.zeroes(vk.DescriptorPool),
    Subpass: u32 = @import("std").mem.zeroes(u32),
    MinImageCount: u32 = @import("std").mem.zeroes(u32),
    ImageCount: u32 = @import("std").mem.zeroes(u32),
    MSAASamples: vk.SampleCountFlags = .{},
    UseDynamicRendering: bool = @import("std").mem.zeroes(bool),
    ColorAttachmentFormat: vk.Format = @import("std").mem.zeroes(vk.Format),
    Allocator: [*c]const vk.AllocationCallbacks = @import("std").mem.zeroes([*c]const vk.AllocationCallbacks),
    CheckVkResultFn: ?*const fn (vk.Result) callconv(.C) void = @import("std").mem.zeroes(?*const fn (vk.Result) callconv(.C) void),
    MinAllocationSize: vk.DeviceSize = @import("std").mem.zeroes(vk.DeviceSize),
};

pub extern fn ImGui_ImplVulkan_Init(info: [*c]ImGui_ImplVulkan_InitInfo, render_pass: vk.RenderPass) bool;
pub extern fn ImGui_ImplVulkan_Shutdown() void;
pub extern fn ImGui_ImplVulkan_NewFrame() void;
pub extern fn ImGui_ImplVulkan_RenderDrawData(draw_data: [*c]c.ImDrawData, command_buffer: vk.CommandBuffer, pipeline: vk.Pipeline) void;
pub extern fn ImGui_ImplVulkan_CreateFontsTexture() bool;
pub extern fn ImGui_ImplVulkan_DestroyFontsTexture() void;
pub extern fn ImGui_ImplVulkan_SetMinImageCount(min_image_count: u32) void;
pub extern fn ImGui_ImplVulkan_AddTexture(sampler: vk.Sampler, image_view: vk.ImageView, image_layout: vk.ImageLayout) vk.DescriptorSet;
pub extern fn ImGui_ImplVulkan_RemoveTexture(descriptor_set: vk.DescriptorSet) void;
pub extern fn ImGui_ImplVulkan_LoadFunctions(loader_func: ?*const fn ([*c]const u8, ?*anyopaque) callconv(vk.vulkan_call_conv) void, user_data: ?*anyopaque) bool;
pub extern fn ImGui_ImplVulkanH_CreateOrResizeWindow(instance: vk.Instance, physical_device: vk.PhysicalDevice, device: vk.Device, wnd: [*c]ImGui_ImplVulkanH_Window, queue_family: u32, allocator: [*c]const vk.AllocationCallbacks, w: c_int, h: c_int, min_image_count: u32) void;
pub extern fn ImGui_ImplVulkanH_DestroyWindow(instance: vk.Instance, device: vk.Device, wnd: [*c]ImGui_ImplVulkanH_Window, allocator: [*c]const vk.AllocationCallbacks) void;
pub extern fn ImGui_ImplVulkanH_SelectSurfaceFormat(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR, request_formats: [*c]const vk.Format, request_formats_count: c_int, request_color_space: vk.ColorSpaceKHR) vk.SurfaceFormatKHR;
pub extern fn ImGui_ImplVulkanH_SelectPresentMode(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR, request_modes: [*c]const vk.PresentModeKHR, request_modes_count: c_int) vk.PresentModeKHR;
pub extern fn ImGui_ImplVulkanH_GetMinImageCountFromPresentMode(present_mode: vk.PresentModeKHR) c_int;
