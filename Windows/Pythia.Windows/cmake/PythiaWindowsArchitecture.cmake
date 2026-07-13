function(require_pythia_windows_x64)
  if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "Pythia Windows requires a 64-bit x64 toolchain.")
  endif()

  string(TOLOWER
    "${CMAKE_GENERATOR_PLATFORM};${CMAKE_VS_PLATFORM_NAME};${CMAKE_SYSTEM_PROCESSOR}"
    pythia_windows_architectures
  )
  if(NOT pythia_windows_architectures MATCHES "(^|;)(x64|amd64|x86_64)(;|$)")
    message(FATAL_ERROR
      "Pythia Windows supports x64 only. Detected: ${pythia_windows_architectures}"
    )
  endif()
endfunction()
