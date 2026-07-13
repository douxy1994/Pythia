set(CMAKE_SIZEOF_VOID_P 4)
set(CMAKE_GENERATOR_PLATFORM Win32)
set(CMAKE_VS_PLATFORM_NAME Win32)
set(CMAKE_SYSTEM_PROCESSOR x86)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/PythiaWindowsArchitecture.cmake")
require_pythia_windows_x64()
