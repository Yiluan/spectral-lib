CMAKE_MINIMUM_REQUIRED(VERSION 2.6 FATAL_ERROR)
CMAKE_POLICY(VERSION 2.6)

SET(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" "${CMAKE_MODULE_PATH}")

IF(LUAROCKS_PREFIX)
    MESSAGE(STATUS "Installing Torch through Luarocks")
    STRING(REGEX REPLACE "(.*)lib/luarocks/rocks.*" "\\1" CMAKE_INSTALL_PREFIX  "${LUAROCKS_PREFIX}")
    MESSAGE(STATUS "Prefix inferred from Luarocks: ${CMAKE_INSTALL_PREFIX}")
    SET(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" "${CMAKE_MODULE_PATH}")
ENDIF()

FIND_PACKAGE(Torch REQUIRED)

FIND_PACKAGE(CUDA 6.5 REQUIRED)
LIST(APPEND CUDA_NVCC_FLAGS "-arch=sm_35;--use_fast_math;-O3")
MESSAGE("Compiling for CUDA architecture 3.5")

INCLUDE_DIRECTORIES("${Torch_INSTALL_INCLUDE}")
INCLUDE_DIRECTORIES("${Torch_INSTALL_INCLUDE}/TH")
INCLUDE_DIRECTORIES("${Torch_INSTALL_INCLUDE}/THC")
LINK_DIRECTORIES("${Torch_INSTALL_LIB}")

SET(src-cuda cuda/cufft.cpp cuda/init.cu)
SET(luasrc init.lua)
add_definitions( -DTORCH_BUILD )

CUDA_ADD_LIBRARY(spectralnet MODULE ${src-cuda})
TARGET_LINK_LIBRARIES(spectralnet THC TH cuda cufft)

### Torch packages supposes libraries prefix is "lib"
SET_TARGET_PROPERTIES(spectralnet PROPERTIES
  PREFIX "lib"
  IMPORT_PREFIX "lib")
    
SET(src)
FILE(GLOB luasrc *.lua)
ADD_TORCH_PACKAGE(spectralnet "${src}" "${luasrc}")

#TARGET_LINK_LIBRARIES(FFTconv luaT TH THC)

#INSTALL(DIRECTORY "doc" DESTINATION "${Torch_INSTALL_LUA_PATH_SUBDIR}/nn")

INSTALL(TARGETS spectralnet
  RUNTIME DESTINATION "${Torch_INSTALL_LUA_CPATH_SUBDIR}"
  LIBRARY DESTINATION "${Torch_INSTALL_LUA_CPATH_SUBDIR}")

# INSTALL(
#   FILES
#   ${luasrc}
#   DESTINATION "${Torch_INSTALL_LUA_PATH_SUBDIR}/FFTconv")
