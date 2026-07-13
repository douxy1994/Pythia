set(CMAKE_SIZEOF_VOID_P 8)
set(CMAKE_GENERATOR_PLATFORM x64)
set(CMAKE_VS_PLATFORM_NAME x64)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/PythiaWindowsArchitecture.cmake")
require_pythia_windows_x64()
