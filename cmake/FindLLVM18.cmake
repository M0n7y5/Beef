function(find_and_configure_llvm18)
    if(UNIX AND NOT APPLE)
            find_program(LLVM_CONFIG_18_EXECUTABLE NAMES llvm-config-18)

            if(NOT LLVM_CONFIG_18_EXECUTABLE)
                find_program(LLVM_CONFIG_EXECUTABLE
                    NAMES llvm-config
                    HINTS /usr/lib/llvm*/bin
                )

                if(LLVM_CONFIG_EXECUTABLE)
                    execute_process(
                        COMMAND ${LLVM_CONFIG_EXECUTABLE} --version
                        OUTPUT_VARIABLE LLVM_VERSION_OUTPUT
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                    )
                    string(REGEX MATCH "^([0-9]+)\\.([0-9]+)" LLVM_VERSION_MATCH "${LLVM_VERSION_OUTPUT}")

                    if(LLVM_VERSION_MATCH)
                        set(LLVM_MAJOR_VERSION ${CMAKE_MATCH_1})
                        set(LLVM_MINOR_VERSION ${CMAKE_MATCH_2})

                        if(LLVM_MAJOR_VERSION EQUAL 18 AND LLVM_MINOR_VERSION GREATER 0)
                            set(LLVM_CONFIG_18_EXECUTABLE "llvm-config-${LLVM_MAJOR_VERSION}")
                            message(STATUS "Detected LLVM ${LLVM_MAJOR_VERSION}.${LLVM_MINOR_VERSION} using llvm-config-${LLVM_MAJOR_VERSION}")
                        else()
                            message(WARNING "Found LLVM version ${LLVM_MAJOR_VERSION}.${LLVM_MINOR_VERSION}, but it's not 18.1 or later.")
                        endif()
                    endif()
                endif()
            endif()

        endif()

    if (LLVM_CONFIG_18_EXECUTABLE)
        set(LLVM_CONFIG_EXECUTABLE ${LLVM_CONFIG_18_EXECUTABLE} PARENT_SCOPE) # Set early

        execute_process(
            COMMAND ${LLVM_CONFIG_18_EXECUTABLE} --cmakedir
            OUTPUT_VARIABLE LLVM_CMAKE_DIR
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(LLVM_DIR ${LLVM_CMAKE_DIR} PARENT_SCOPE)
        set(LLVM_PACKAGE_VERSION ${LLVM_PACKAGE_VERSION} PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Could not find llvm-config-18, exiting..")
        return()
    endif()

endfunction()
