# Injected with -DCMAKE_PROJECT_INCLUDE (no upstream file is edited). Runs right after the top-level
# project() call; the DEFERred block runs once every upstream target exists.
# (CMAKE_PROJECT_INCLUDE also fires for the project() call of every subproject, e.g. mcl: act on the top level only)
if(CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
	cmake_language(DEFER CALL _mayhem_add_targets)
endif()

function(_mayhem_add_targets)
	# the two translation units that take >10 min each under ASan+UBSan+libFuzzer instrumentation
	# (sorter/grouper template explosion); they are not on the query-parser path
	foreach(f sortergroup.cpp columnarsort.cpp)
		set_property(SOURCE "${MANTICORE_SOURCE_DIR}/src/${f}" TARGET_DIRECTORY lmanticore
			APPEND PROPERTY COMPILE_OPTIONS -O0 -fno-sanitize=all)
	endforeach()

	if(MAYHEM_FUZZ_HARNESS)
		add_executable(mayhem_qfuzzer EXCLUDE_FROM_ALL "${MAYHEM_FUZZ_HARNESS}" "${MAYHEM_LSAN_OFF}")
		target_include_directories(mayhem_qfuzzer PRIVATE "${MANTICORE_SOURCE_DIR}/src")
		target_link_libraries(mayhem_qfuzzer PRIVATE lextra lmanticore sphinxquery -fsanitize=address,fuzzer)

		# run-once reproducer: no libFuzzer engine; the sancov callbacks the libraries were
		# instrumented with come from the ASan runtime
		add_executable(mayhem_qfuzzer_standalone EXCLUDE_FROM_ALL "${MAYHEM_FUZZ_HARNESS}"
			"${MAYHEM_LSAN_OFF}" "${MAYHEM_STANDALONE_MAIN}")
		target_include_directories(mayhem_qfuzzer_standalone PRIVATE "${MANTICORE_SOURCE_DIR}/src")
		target_link_libraries(mayhem_qfuzzer_standalone PRIVATE lextra lmanticore sphinxquery -fsanitize=address,undefined)
	endif()

	if(MAYHEM_GTESTS)
		include(GetGoogletest)  # imported targets are directory-scoped; src/gtests found it in its own scope
		set(_g "${MANTICORE_SOURCE_DIR}/src/gtests")
		add_executable(mayhem_gtests EXCLUDE_FROM_ALL
			"${_g}/gtests_hugetokenizer.cpp" "${MANTICORE_SOURCE_DIR}/mayhem/gtests_globalstate.cpp"
			"${_g}/gtests_strfmt.cpp")
		target_include_directories(mayhem_gtests PRIVATE "${MANTICORE_SOURCE_DIR}/src")
		target_link_libraries(mayhem_gtests PRIVATE GTest::gmock_main lmanticore)
	endif()
endfunction()
