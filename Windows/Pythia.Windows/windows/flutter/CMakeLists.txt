cmake_minimum_required(VERSION 3.14)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")
set(WRAPPER_ROOT "${EPHEMERAL_DIR}/cpp_client_wrapper")
set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/flutter_windows.dll")
set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat")
set(PROJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(PROJECT_BUILD_DIR "${PROJECT_DIR}/build/")

include("${EPHEMERAL_DIR}/generated_config.cmake")

function(apply_standard_settings TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

set(FLUTTER_LIBRARY_HEADERS
  "flutter_export.h"
  "flutter_messenger.h"
  "flutter_plugin_registrar.h"
  "flutter_texture_registrar.h"
)
list(TRANSFORM FLUTTER_LIBRARY_HEADERS PREPEND "${EPHEMERAL_DIR}/")

add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE "${EPHEMERAL_DIR}")
target_link_libraries(flutter INTERFACE "${FLUTTER_LIBRARY}.lib")
add_dependencies(flutter flutter_assemble)

add_library(flutter_wrapper_plugin STATIC
  "${WRAPPER_ROOT}/core_implementations.cc"
  "${WRAPPER_ROOT}/standard_codec.cc"
)
apply_standard_settings(flutter_wrapper_plugin)
target_link_libraries(flutter_wrapper_plugin PUBLIC flutter)
target_include_directories(flutter_wrapper_plugin PUBLIC "${WRAPPER_ROOT}/include")
add_dependencies(flutter_wrapper_plugin flutter_assemble)

add_library(flutter_wrapper_app STATIC
  "${WRAPPER_ROOT}/flutter_engine.cc"
  "${WRAPPER_ROOT}/flutter_view_controller.cc"
)
apply_standard_settings(flutter_wrapper_app)
target_link_libraries(flutter_wrapper_app PUBLIC flutter)
target_include_directories(flutter_wrapper_app PUBLIC "${WRAPPER_ROOT}/include")
add_dependencies(flutter_wrapper_app flutter_assemble)

set(FLUTTER_TOOL_ENVIRONMENT
  "FLUTTER_ROOT=${FLUTTER_ROOT}"
  "PROJECT_DIR=${PROJECT_DIR}"
  "DART_DEFINES=${DART_DEFINES}"
  "DART_OBFUSCATION=${DART_OBFUSCATION}"
  "TRACK_WIDGET_CREATION=${TRACK_WIDGET_CREATION}"
  "TREE_SHAKE_ICONS=${TREE_SHAKE_ICONS}"
  "PACKAGE_CONFIG=${PACKAGE_CONFIG}"
)

add_custom_command(
  OUTPUT ${FLUTTER_LIBRARY} ${FLUTTER_LIBRARY_HEADERS}
    ${FLUTTER_ICU_DATA_FILE}
    "${PROJECT_BUILD_DIR}/flutter_assets"
    "${PROJECT_BUILD_DIR}/app.so"
  COMMAND ${CMAKE_COMMAND} -E env ${FLUTTER_TOOL_ENVIRONMENT}
    "${FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.bat"
      windows-x64 $<CONFIG>
  VERBATIM
)
add_custom_target(flutter_assemble DEPENDS
  "${FLUTTER_LIBRARY}"
  ${FLUTTER_LIBRARY_HEADERS}
  "${FLUTTER_ICU_DATA_FILE}"
  "${PROJECT_BUILD_DIR}/flutter_assets"
  "${PROJECT_BUILD_DIR}/app.so"
)
