cmake_minimum_required(VERSION 3.16)
project(wetype-dictate LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(GNUInstallDirs)
include(CTest)
find_package(Fcitx5Core REQUIRED)

# The helper's path is compiled in, so the test builds its own copy of the
# addon around a fake helper.
function(dictate_addon target dir helper)
  add_library(${target} MODULE wetypedictate.cpp)
  set_target_properties(${target} PROPERTIES
    OUTPUT_NAME wetypedictate
    PREFIX lib
    LIBRARY_OUTPUT_DIRECTORY ${dir})
  target_compile_definitions(${target} PRIVATE WETYPE_DICTATE_HELPER="${helper}")
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(${target} PRIVATE Fcitx5::Core)
endfunction()

dictate_addon(wetypedictate ${CMAKE_BINARY_DIR}
  "${CMAKE_INSTALL_FULL_LIBEXECDIR}/wetype-dictate")
install(TARGETS wetypedictate DESTINATION ${CMAKE_INSTALL_LIBDIR}/fcitx5)
install(FILES wetypedictate.conf DESTINATION ${CMAKE_INSTALL_DATADIR}/fcitx5/addon)

if(BUILD_TESTING)
  find_package(Fcitx5ModuleTestFrontend REQUIRED)
  set(testdir ${CMAKE_BINARY_DIR}/test)
  dictate_addon(wetypedictate-test ${testdir}/addons
    "${CMAKE_SOURCE_DIR}/test/fake-helper.sh")
  # fcitx5 installs its testing addons but not their descriptions.
  configure_file(wetypedictate.conf ${testdir}/data/addon/wetypedictate.conf COPYONLY)
  foreach(addon testfrontend testim testui)
    file(WRITE ${testdir}/data/addon/${addon}.conf
      "[Addon]\nName=${addon}\nType=SharedLibrary\nLibrary=lib${addon}\n")
  endforeach()
  file(APPEND ${testdir}/data/addon/testfrontend.conf "Category=Frontend\n")
  file(APPEND ${testdir}/data/addon/testim.conf "Category=InputMethod\n")
  file(APPEND ${testdir}/data/addon/testui.conf "Category=UI\n")

  add_executable(testdictate test/testdictate.cpp)
  target_compile_definitions(testdictate PRIVATE
    TEST_DIR="${testdir}"
    FCITX_ADDON_DIR="${FCITX_INSTALL_LIBDIR}/fcitx5")
  target_link_libraries(testdictate PRIVATE Fcitx5::Core Fcitx5::Module::TestFrontend)
  add_dependencies(testdictate wetypedictate-test)
  add_test(NAME testdictate COMMAND testdictate)
endif()
