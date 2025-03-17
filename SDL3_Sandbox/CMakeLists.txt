cmake_minimum_required(VERSION 3.16)

project(SDL3_Sandbox LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Create an option to switch between a system sdl library and a vendored SDL library
option(SDL_VENDORED "Use vendored libraries" OFF)

if(SDL_VENDORED)
    # This assumes you have added SDL as a submodule in vendored/SDL
    add_subdirectory(vendored/SDL EXCLUDE_FROM_ALL)
else()
    # 1. Look for a SDL3 package,
    # 2. look for the SDL3-shared component, and
    # 3. fail if the shared component cannot be found.
    find_package(SDL3 REQUIRED CONFIG REQUIRED COMPONENTS SDL3-shared)
endif()

add_executable(SDL3_Sandbox main.cpp
    TheApp.h)

# Link to the actual SDL3 library.
target_link_libraries(SDL3_Sandbox PRIVATE SDL3::SDL3)

# include(GNUInstallDirs)
# install(TARGETS SDL3_Sandbox
#     LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
#     RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
# )
