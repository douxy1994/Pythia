cmake_minimum_required(VERSION 3.14)
project(pythia_windows LANGUAGES CXX)

set(BINARY_NAME "Pythia")

cmake_policy(VERSION 3.14...3.25)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_subdirectory(windows)
