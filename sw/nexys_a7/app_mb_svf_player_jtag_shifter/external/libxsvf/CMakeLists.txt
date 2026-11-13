add_library(xsvf STATIC
    svf.c
    tap.c
    play.c
    statename.c
    memname.c
)

target_include_directories(xsvf PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_definitions(xsvf PUBLIC
    LIBXSVF_WITHOUT_XSVF
    LIBXSVF_WITHOUT_SCAN
)

target_compile_options(xsvf PRIVATE
    -Wall
    -O2
)