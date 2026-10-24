# Заглушка (AO Bible, только проверочная сборка под Windows): пустая библиотека вместо кода с ATL
cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "flutter_local_notifications_windows")
project(${PROJECT_NAME} LANGUAGES CXX)
add_library(flutter_local_notifications_windows SHARED "${CMAKE_CURRENT_SOURCE_DIR}/stub.cpp")
set(flutter_local_notifications_windows_bundled_libraries $<TARGET_FILE:flutter_local_notifications_windows> PARENT_SCOPE)
