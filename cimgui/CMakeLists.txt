cmake_minimum_required(VERSION 3.7...3.27)

if(${CMAKE_VERSION} VERSION_LESS 3.12)
    cmake_policy(VERSION ${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION})
endif()

project(cimgui LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(glfw3 CONFIG REQUIRED)
find_package(Vulkan REQUIRED)

set(CIMGUI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../external/cimgui")
set(SOURCE
    "${CIMGUI_DIR}/cimgui.cpp"
    "${CIMGUI_DIR}/imgui/imgui.cpp"
    "${CIMGUI_DIR}/imgui/imgui_demo.cpp"
    "${CIMGUI_DIR}/imgui/imgui_draw.cpp"
    "${CIMGUI_DIR}/imgui/imgui_tables.cpp"
    "${CIMGUI_DIR}/imgui/imgui_widgets.cpp"
    "${CIMGUI_DIR}/imgui/backends/imgui_impl_glfw.cpp"
    "${CIMGUI_DIR}/imgui/backends/imgui_impl_vulkan.cpp"
)

add_library(cimgui SHARED "${SOURCE}")

if(WIN32)
    target_compile_definitions(cimgui PRIVATE "-DIMGUI_IMPL_API=extern \"C\" __declspec\(dllexport\)")
else()
    target_compile_definitions(cimgui PRIVATE "-DIMGUI_IMPL_API=extern \"C\"")
endif()

target_include_directories(cimgui PRIVATE "${CIMGUI_DIR}/imgui")
target_link_libraries(cimgui PRIVATE glfw Vulkan::Vulkan)
