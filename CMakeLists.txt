cmake_minimum_required(VERSION 3.20)
project("Beef")

# Resolve LLVM 18.1 Instalation
include(cmake/FindLLVM18.cmake)
find_and_configure_llvm18()
find_package(LLVM "18.1" CONFIG REQUIRED)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Debug")
  message(STATUS "Build type not specified: Use Debug by default.")
endif(NOT CMAKE_BUILD_TYPE)

if(LINUX)
    set(BF_ENABLE_SDL "")
endif()

add_subdirectory(SDL3_Sandbox)

if (DEFINED BF_ONLY_RUNTIME)
    add_subdirectory(BeefRT)
    add_subdirectory(BeefySysLib)
else()
    add_subdirectory(BeefRT)
    add_subdirectory(BeefySysLib)
    add_subdirectory(extern/hunspell)
    add_subdirectory(IDEHelper)
    add_subdirectory(BeefBoot)
endif()

if(LLVM_DIR)
    message(STATUS "Found LLVM Version: ${LLVM_PACKAGE_VERSION}")
    message(STATUS "LLVM Config Directory: ${LLVM_DIR}")
else()
    message(FATAL_ERROR "LLVM 18 not found.  Compilation cannot proceed.")
endif()

