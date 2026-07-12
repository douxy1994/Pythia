cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/PythiaWindowsArchitecture.cmake")
require_pythia_windows_x64()

set(BINARY_NAME "Pythia")

cmake_policy(SET CMP0063 NEW)

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory("${FLUTTER_MANAGED_DIR}")

add_executable(${BINARY_NAME} WIN32
  "runner/flutter_window.cpp"
  "runner/main.cpp"
  "runner/pythia_credential_channel.cpp"
  "runner/pythia_platform_channel.cpp"
  "runner/screenshot_ocr.cpp"
  "runner/Runner.rc"
  "runner/utils.cpp"
  "runner/win32_window.cpp"
  "runner/runner.exe.manifest"
  "flutter/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app Advapi32 Shell32 Wintrust Crypt32 WindowsApp Uiautomationcore OleAut32)
add_dependencies(${BINARY_NAME} flutter_assemble)

include("${CMAKE_CURRENT_SOURCE_DIR}/flutter/generated_plugins.cmake")

set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${CMAKE_INSTALL_PREFIX}/data" COMPONENT Runtime)
install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/flutter_assets" DESTINATION "${CMAKE_INSTALL_PREFIX}/data" COMPONENT Runtime)
if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES ${PLUGIN_BUNDLED_LIBRARIES} DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
endif()
