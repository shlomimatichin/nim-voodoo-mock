all: test_nim

NIM_VOODOO_MOCK_DIR ?= $(PWD)/../nim-voodoo-mock
UNITTEST_BUILD_DIR ?= $(PWD)/build
NIM_TEST_PATHS ?=
NIMTEST_OUTPUT_FORMAT ?= PRINT_SUITE_TEST

.PHONY: FORCE
test_nim: $(UNITTEST_BUILD_DIR)/nimunittest FORCE
	NIMTEST_OUTPUT_FORMAT=$(NIMTEST_OUTPUT_FORMAT) $<

$(UNITTEST_BUILD_DIR)/nimunittest: $(NIM_VOODOO_MOCK_DIR)/runall.nim FORCE
	@mkdir -p $(@D)
	TESTS_DIR="$(NIM_TEST_DIRS)" ~/nim/bin/nim compile --nimcache=$(UNITTEST_BUILD_DIR)/nimcache.unittest $(addprefix  --path=,$(NIM_TEST_PATHS)) --path=$(NIM_VOODOO_MOCK_DIR) --parallelBuild=1 --out=$@ $<
