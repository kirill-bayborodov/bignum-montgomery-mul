# Makefile for bignum library function

# --- Configurable Variables ---
CONFIG ?= debug
# values: auto | yes | no
USE_ASM ?= auto
REPORT_NAME ?= current
# Benchmark input mode: all_zero | all_nonzero | mixed
DATA_MODE ?= all_nonzero
# Benchmark executable environment (not Make variables):
# BIGNUM_BENCH_ITERATIONS=<positive integer> limits ST calls (default: 2000000000).
# BIGNUM_BENCH_MT_TOTAL_ITERATIONS=<positive integer> limits total MT calls;
# it must be divisible by MT_THREADS (default: 3200000000).
# BIGNUM_BENCH_SEED=<integer> makes pregenerated input data reproducible.
# Use these only for smoke tests; use the default workload for performance studies.
# Matrix benchmark settings. The matrix executes its declared profiles directly
# and writes raw samples plus a statistical JSON summary.
BENCH_MATRIX_PROFILE ?= $(BENCH_DIR)/profiles/$(LIB_NAME)_full.json
BENCH_MATRIX_REPETITIONS ?= 7
BENCH_MATRIX_ITERATIONS ?= 200000000
BENCH_MATRIX_MT_TOTAL_ITERATIONS ?= 320000000
BENCH_MATRIX_WARMUP ?= 10000
BENCH_MATRIX_DATA_COUNT ?= 4096
BENCH_MATRIX_SEED ?= 0x9E3779B97F4A7C15
BENCH_MATRIX_TIMEOUT_SECONDS ?= 1800
BENCH_REGRESSION_THRESHOLD_PCT ?= 5
# Set BENCH_BASELINE to a reviewed matrix or summary JSON to make bench_matrix
# fail on a confirmed regression or an incomplete profile set.
BENCH_BASELINE ?=
# values: no | address | undefined
SAN ?= no
# yes — прогнать *_mt тесты под valgrind --tool=helgrind
HELGRIND ?= no
VALGRIND ?= valgrind

# --- Calculated Variables ---
REPOSITORY_NAME := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
FAMILY_NAME := $(firstword $(subst -, ,$(REPOSITORY_NAME)))
OPERATION_NAME := $(strip $(patsubst $(FAMILY_NAME)-%,%,$(REPOSITORY_NAME)))
UPPER_FAMILY_NAME := $(subst z,Z,$(subst y,Y,$(subst x,X,$(subst w,W,$(subst v,V,$(subst u,U,$(subst t,T,$(subst s,S,$(subst r,R,$(subst q,Q,$(subst p,P,$(subst o,O,$(subst n,N,$(subst m,M,$(subst l,L,$(subst k,K,$(subst j,J,$(subst i,I,$(subst h,H,$(subst g,G,$(subst f,F,$(subst e,E,$(subst d,D,$(subst c,C,$(subst b,B,$(subst a,A,$(FAMILY_NAME)))))))))))))))))))))))))))
LIB_NAME := $(subst -,_,$(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))))
UPPER_LIB_NAME := $(subst z,Z,$(subst y,Y,$(subst x,X,$(subst w,W,$(subst v,V,$(subst u,U,$(subst t,T,$(subst s,S,$(subst r,R,$(subst q,Q,$(subst p,P,$(subst o,O,$(subst n,N,$(subst m,M,$(subst l,L,$(subst k,K,$(subst j,J,$(subst i,I,$(subst h,H,$(subst g,G,$(subst f,F,$(subst e,E,$(subst d,D,$(subst c,C,$(subst b,B,$(subst a,A,$(LIB_NAME)))))))))))))))))))))))))))
NP := $(strip $(shell nproc))
CPU_LIST := $(shell seq 0 $$(( $(NP) - 1 )) | paste -sd "," -)
MT_THREADS ?= 2
MT_CPU_LIST ?= 0-1
MT_TOTAL_ITERATIONS ?= 3200000000

# --- Tools ---
CC = gcc
AS = yasm
PERF = /usr/local/bin/perf
RM = rm -rf
MKDIR = mkdir -p
AR = ar
STRIP = strip
RL = ranlib
CPPCHECK = cppcheck
OBJCOPY = objcopy
NM = nm

# --- Directories ---
SRC_DIR = src
BUILD_DIR = build
BIN_DIR = bin
LIBS_DIR = libs
TESTS_DIR = tests
BENCH_DIR = benchmarks
INCLUDE_DIR = include
DIST_DIR = dist

CORE_NAME := $(FAMILY_NAME)-core
CORE_DIR  := $(LIBS_DIR)/$(CORE_NAME)
REPORTS_DIR = $(BENCH_DIR)/reports
# Pinned C11 framework dependency. CI installs the reviewed public v1.0.0
# flat distribution under dist; this project consumes its header, archive and tools.
BENCHMARK_FRAMEWORK_DIR := $(LIBS_DIR)/benchmark-framework
BENCHMARK_CORE_DIR := $(BENCHMARK_FRAMEWORK_DIR)/$(DIST_DIR)
BENCHMARK_CORE_INCLUDE := $(BENCHMARK_CORE_DIR)
BENCHMARK_CORE_LIB := $(BENCHMARK_CORE_DIR)/libbenchmark_framework.a
BENCH_MATRIX_TOOL := $(BENCHMARK_CORE_DIR)/tools/bench_matrix
BENCH_STATS_TOOL := $(BENCHMARK_CORE_DIR)/tools/benchmark_stats
BENCH_ADAPTER_DIR := $(BENCH_DIR)/adapter
BENCH_ADAPTER_SOURCE := $(BENCH_ADAPTER_DIR)/$(LIB_NAME)_benchmark_adapter.c
BENCH_ADAPTER_HEADER := $(BENCH_ADAPTER_DIR)/$(LIB_NAME)_benchmark_adapter.h
BENCH_ADAPTER_OBJ := $(BUILD_DIR)/$(LIB_NAME)_benchmark_adapter.o
BENCH_ADAPTER_TEST_SOURCE := $(TESTS_DIR)/benchmark_adapter/test_$(LIB_NAME)_benchmark_adapter.c
BENCH_ADAPTER_TEST_BIN := $(BIN_DIR)/test_$(LIB_NAME)_benchmark_adapter
BENCH_MATRIX_PROFILE ?= $(BENCH_DIR)/profiles/$(LIB_NAME)_full.json
BENCH_MATRIX_REPORT ?= $(REPORTS_DIR)/$(REPORT_NAME)_matrix.json
BENCH_MATRIX_SUMMARY ?= $(REPORTS_DIR)/$(REPORT_NAME)_matrix_summary.json
DIST_INCLUDE_DIR = $(DIST_DIR)/$(INCLUDE_DIR)
DIST_LIB_DIR = $(DIST_DIR)/$(LIBS_DIR)

# 1. Очищаем исходный список от любых случайных пробелов сразу при получении
SUBMODULES_RAW := $(strip $(patsubst $(LIBS_DIR)/%/,%,$(wildcard $(LIBS_DIR)/*/)))

# 2. Собираем финальный список, также оборачивая результат в strip
SUBMODULES := $(strip $(filter $(CORE_NAME),$(SUBMODULES_RAW)) $(filter-out $(CORE_NAME),$(SUBMODULES_RAW)))

# Отделяем сабмодули с исходниками (есть Makefile) от вендорных (нет Makefile)
SRC_SUBMODULES  := $(strip $(foreach d,$(SUBMODULES),$(if $(wildcard $(LIBS_DIR)/$(d)/Makefile),$(d),)))
DIST_SUBMODULES := $(strip $(foreach d,$(SUBMODULES),$(if $(filter $(d),$(SRC_SUBMODULES)),,$(d))))
# benchmark-framework is built only by benchmark_framework. The generic loop
# appends root CFLAGS as a command-line override, which would otherwise leak
# incompatible include paths into json-lib's independent C11 build.
GENERIC_BUILD_SUBMODULES := $(filter-out benchmark-framework,$(SRC_SUBMODULES))


# Генерируем все возможные пути для обоих типов модулей
SRC_SUBMODULES_INCLUDE_DIR = $(foreach d,$(SRC_SUBMODULES),$(LIBS_DIR)/$(d)/$(INCLUDE_DIR))
DIST_SUBMODULES_INCLUDE_DIR = $(foreach d,$(DIST_SUBMODULES),$(LIBS_DIR)/$(d)/$(DIST_DIR))
SUBMODULES_INCLUDE_DIR := $(strip $(SRC_SUBMODULES_INCLUDE_DIR) $(DIST_SUBMODULES_INCLUDE_DIR))

# # Динамический выбор пути к главному заголовку
# # Сначала проверяем, существует ли файл в корневом INCLUDE_DIR
# ifneq ($(wildcard $(INCLUDE_DIR)/$(FAMILY_NAME).h),)
#     FAMILY_PATH = $(INCLUDE_DIR)
# else
#     # Если в корне нет, выбираем путь внутри CORE_NAME (как и было раньше)
#     ifneq ($(filter $(CORE_NAME),$(DIST_SUBMODULES)),)
#         FAMILY_PATH = $(LIBS_DIR)/$(CORE_NAME)/$(DIST_DIR)
#     else
#         FAMILY_PATH = $(LIBS_DIR)/$(CORE_NAME)/$(INCLUDE_DIR)
#     endif
# endif
# Динамический выбор пути к главному заголовку
ifneq ($(wildcard $(INCLUDE_DIR)/$(FAMILY_NAME).h),)
    # 1. Приоритет: Корневой INCLUDE_DIR
    FAMILY_PATH = $(INCLUDE_DIR)
else
    # 2. Проверяем стандартные пути общего модуля (CORE_NAME)
    ifneq ($(filter $(CORE_NAME),$(DIST_SUBMODULES)),)
	CORE_DIST_PATH = $(LIBS_DIR)/$(CORE_NAME)/$(DIST_DIR)
	CORE_INC_PATH  = $(LIBS_DIR)/$(CORE_NAME)/$(INCLUDE_DIR)

	# Проверяем, существует ли файл в DIST, если нет - в INC
	ifneq ($(wildcard $(CORE_DIST_PATH)/$(FAMILY_NAME).h),)
	    FAMILY_PATH = $(CORE_DIST_PATH)
	else
	    ifneq ($(wildcard $(CORE_INC_PATH)/$(FAMILY_NAME).h),)
	        FAMILY_PATH = $(CORE_INC_PATH)
	    else
	        # 3. ФИНАЛЬНЫЙ ВАРИАНТ: Если в стандартных местах нет,
	        # ищем файл вообще по всем путям субмодулей
	        # Находим полный путь к файлу, а затем отсекаем имя файла, чтобы оставить только папку
	        FOUND_FILE := $(wildcard $(foreach dir,$(SUBMODULES_INCLUDE_DIR),$(dir)/$(FAMILY_NAME).h))
	        FAMILY_PATH := $(patsubst %/$(FAMILY_NAME).h,%,$(FOUND_FILE))
	    endif
	endif
    else
	# Если CORE_NAME не в DIST_SUBMODULES, пробуем его INCLUDE
	ifneq ($(wildcard $(LIBS_DIR)/$(CORE_NAME)/$(INCLUDE_DIR)/$(FAMILY_NAME).h),)
	    FAMILY_PATH = $(LIBS_DIR)/$(CORE_NAME)/$(INCLUDE_DIR)
	else
	    # Аналогичный поиск по всем путям, если даже тут не нашли
	    FOUND_FILE := $(wildcard $(foreach dir,$(SUBMODULES_INCLUDE_DIR),$(dir)/$(FAMILY_NAME).h))
	    FAMILY_PATH := $(patsubst %/$(FAMILY_NAME).h,%,$(FOUND_FILE))
	endif
    endif
endif
# FAMILY_HEADER берется именно из того пути, который мы определили динамически
FAMILY_HEADER := $(FAMILY_PATH)/$(FAMILY_NAME).h
ifneq ($(strip $(FAMILY_PATH)),)
    # Переменная инициализирована и не пуста
else
    # Переменная либо не существует, либо пуста
    FAMILY_PATH := $(dir $(firstword $(wildcard $(foreach dir,$(SUBMODULES_INCLUDE_DIR),$(dir)/$(FAMILY_NAME)_core.h))))
    FAMILY_HEADER := $(FAMILY_PATH)$(FAMILY_NAME)_core.h
    FAMILY_SYMLINK := $(FAMILY_PATH)$(FAMILY_NAME).h
endif

SUBMODULES_DIST_DIR := $(foreach d,$(DIST_SUBMODULES),$(LIBS_DIR)/$(d)/$(DIST_DIR))
SUBMODULES_DIST_LIB := $(foreach d,$(DIST_SUBMODULES),$(subst -,_,$(d)))

# Собираем OBJECTS только для тех сабмодулей, у которых реально есть исходники в src/
OBJECTS         := $(foreach d,$(GENERIC_BUILD_SUBMODULES),$(if $(wildcard $(LIBS_DIR)/$(d)/src/$(subst -,_,$(d)).c $(LIBS_DIR)/$(d)/src/$(subst -,_,$(d)).asm),$(LIBS_DIR)/$(d)/build/$(subst -,_,$(d)).o,))

# Собираем все заголовочные файлы сабмодулей
SRC_SUBMODULES_HEADERS_RAW := $(foreach dir,$(SRC_SUBMODULES_INCLUDE_DIR),$(wildcard $(dir)/*.h))
DIST_SUBMODULES_HEADERS_RAW := $(foreach dir,$(DIST_SUBMODULES_INCLUDE_DIR),$(wildcard $(dir)/*.h))
SUBMODULES_HEADERS_RAW := $(foreach dir,$(SUBMODULES_INCLUDE_DIR),$(wildcard $(dir)/*.h))

# Выносим bignum.h на первое место, а затем добавляем все остальные файлы
# Очищаем список всех заголовков от ЛЮБЫХ путей, которые заканчиваются на $(FAMILY_NAME).h
# Шаблон %$(FAMILY_NAME).h удалит файл, даже если он лежит в другой папке
SRC_HEADERS_REST := $(filter-out $(FAMILY_HEADER),$(SRC_SUBMODULES_HEADERS_RAW))
SRC_SUBMODULES_HEADERS := $(filter %.h, $(strip $(FAMILY_HEADER) $(SRC_HEADERS_REST)))
DIST_HEADERS_REST := $(filter-out $(FAMILY_HEADER),$(DIST_SUBMODULES_HEADERS_RAW))
DIST_SUBMODULES_HEADERS := $(filter %.h, $(strip $(FAMILY_HEADER) $(DIST_HEADERS_REST)))
HEADERS_REST := $(filter-out $(FAMILY_HEADER),$(SUBMODULES_HEADERS_RAW))
SUBMODULES_HEADERS := $(filter %.h, $(strip $(FAMILY_HEADER) $(HEADERS_REST)))

# --- Source & Target Files ---
ASM_SRC := $(SRC_DIR)/$(LIB_NAME).asm

ifeq ($(strip $(USE_ASM)),auto)
    ifneq ($(wildcard $(ASM_SRC)),)
	SRC_EXT := asm
    else
	SRC_EXT := c
    endif
else ifeq ($(strip $(USE_ASM)),yes)
    SRC_EXT := asm
else
    SRC_EXT := c
endif

C_SRC = $(SRC_DIR)/$(LIB_NAME).$(SRC_EXT)
HEADER = $(INCLUDE_DIR)/$(LIB_NAME).h
OBJ = $(BUILD_DIR)/$(LIB_NAME).o

TEST_SRCS := $(wildcard $(TESTS_DIR)/*.c)
TEST_BINS_MT := $(filter $(TESTS_DIR)/%_mt.c,$(TEST_SRCS))
TEST_BINS    := $(patsubst $(TESTS_DIR)/%.c,$(BIN_DIR)/%,$(TEST_SRCS))
ALL_TEST_BINS := $(TEST_BINS) $(BENCH_ADAPTER_TEST_BIN)

BENCH_BIN = bench_$(LIB_NAME)
BENCH_BIN_ST = $(BIN_DIR)/$(BENCH_BIN)
BENCH_BIN_MT = $(BIN_DIR)/$(BENCH_BIN)_mt
BENCH_BINS = $(BENCH_BIN_ST) $(BENCH_BIN_MT)
BENCH_SRC_ST = $(BENCH_DIR)/bench_$(LIB_NAME).c
BENCH_SRC_MT = $(BENCH_DIR)/bench_$(LIB_NAME)_mt.c
BENCH_RUNTIME_ST = $(REPORTS_DIR)/$(REPORT_NAME)_st_bench_runtime.txt
BENCH_RUNTIME_MT = $(REPORTS_DIR)/$(REPORT_NAME)_mt_bench_runtime.txt

STATIC_LIB = $(DIST_DIR)/lib$(LIB_NAME).a
SINGLE_HEADER = $(DIST_DIR)/$(LIB_NAME).h

# --- Flags ---
CFLAGS_BASE = -std=c11 -Wall -Wextra -pedantic -I$(INCLUDE_DIR) -I$(BENCH_ADAPTER_DIR) -I$(BENCHMARK_CORE_INCLUDE) $(addprefix -I , $(SUBMODULES_INCLUDE_DIR))
ASFLAGS_BASE = -f elf64
LDFLAGS = -no-pie -lm

# Динамически линкуем все вендорные библиотеки (те, что попали в DIST_SUBMODULES)
# Заменяем дефисы на подчеркивания для имени библиотеки (например, bignum-common -> -lbignum_common)
# $(addprefix -L, $(SUBMODULES_DIST_DIR)) $(addprefix -l, $(SUBMODULES_DIST_LIB))
LDFLAGS += $(foreach d,$(DIST_SUBMODULES),-L$(LIBS_DIR)/$(d)/dist -l$(subst -,_,$(d)))

#Особый случай/Special Case
ifeq ($(strip $(OPERATION_NAME)),shift-right)
    LDFLAGS += -lgmp
endif

# --- Sanitizer flags ---
ifeq ($(strip $(SAN)),address)
    SAN_CFLAGS  := -fsanitize=address -g -O1 -fno-omit-frame-pointer
    SAN_LDFLAGS := -fsanitize=address
    SAN_LABEL   := AddressSanitizer
else ifeq ($(strip $(SAN)),undefined)
    SAN_CFLAGS  := -fsanitize=undefined -g -O1 -fno-omit-frame-pointer
    SAN_LDFLAGS := -fsanitize=undefined
    SAN_LABEL   := UndefinedBehaviorSanitizer
else ifeq ($(strip $(SAN)),thread)
    $(warning SAN=thread не инструментирует yasm. Используйте `make test_helgrind` для гонок.)
    SAN_CFLAGS  :=
    SAN_LDFLAGS :=
    SAN_LABEL   := (none)
else
    SAN_CFLAGS  :=
    SAN_LDFLAGS :=
    SAN_LABEL   := (none)
endif

SAN_LOG_PREFIX := $(BIN_DIR)/sanitize_

ifeq ($(strip $(CONFIG)), release)
    CFLAGS = $(CFLAGS_BASE) -O2 -march=x86-64 $(SAN_CFLAGS)
    ASFLAGS = $(ASFLAGS_BASE)
else
    CFLAGS = $(CFLAGS_BASE) -g $(SAN_CFLAGS)
    ASFLAGS = $(ASFLAGS_BASE) -g dwarf2
endif

CFLAGS += -Wl,-z,noexecstack
LDFLAGS += $(SAN_LDFLAGS)

# Helgrind cannot reliably decode every instruction emitted by -march=native.
# Build Helgrind test binaries with a conservative baseline ISA instead.
HELGRIND_CFLAGS := $(CFLAGS_BASE) -O1 -g -fno-omit-frame-pointer -march=x86-64 -Wl,-z,noexecstack

# --- Perf-specific settings ---
ifeq ($(SRC_EXT),asm)
ASM_LABELS := $(shell grep -E '^[[:space:]]*\.[A-Za-z0-9_].*:' $(ASM_SRC) 2>/dev/null | sed -E 's/^[[:space:]]*\.([A-Za-z0-9_]+):/\1/; s/[[:space:]]\+/|/g' )
else
ASM_LABELS :=
endif
space := $(empty) $(empty)
ASM_LABELS := $(subst $(space),|,$(ASM_LABELS))

# perf --symbol-filter uses literal substring matching rather than a regex.
# LIB_NAME therefore selects the public entry symbol and all module-owned
# helpers, including C `_` names and ASM-qualified labels, for every module.
PERF_SYMBOL_FILTER = $(LIB_NAME)
# Raw perf.data сохраняются рядом с текстовыми отчётами для повторного анализа.
PERF_DATA_ST = $(REPORTS_DIR)/$(REPORT_NAME)_st.perf.data
PERF_DATA_MT = $(REPORTS_DIR)/$(REPORT_NAME)_mt.perf.data
REPORT_FILE_ST = $(REPORTS_DIR)/$(REPORT_NAME)_st.txt
REPORT_FILE_MT = $(REPORTS_DIR)/$(REPORT_NAME)_mt.txt
STAT_FILE_ST = $(REPORTS_DIR)/$(REPORT_NAME)_st_stat.csv
STAT_FILE_MT = $(REPORTS_DIR)/$(REPORT_NAME)_mt_stat.csv
STAT_RUNTIME_ST = $(REPORTS_DIR)/$(REPORT_NAME)_st_runtime.txt
STAT_RUNTIME_MT = $(REPORTS_DIR)/$(REPORT_NAME)_mt_runtime.txt
PERF_RUNS ?= 5
PERF_EVENTS ?= cycles,instructions,cache-references,cache-misses,branches,branch-misses
KEEP_PERF ?= 1
RECORD_OPT = -F 1000 -m 16M -e cycles,cache-misses,branch-misses -g --call-graph fp
REPORT_OPT = --percent-limit 1.0 --sort comm,dso,symbol --symbol-filter=$(PERF_SYMBOL_FILTER)

.PHONY: all build benchmark_framework lint docs test test_sanitize test_helgrind bench bench_full bench_cl bench_matrix bench_stat bench_stat_st bench_stat_mt install generate-header dist clean help show-calc unlink-symlink

all: build
build: $(OBJ) $(OBJECTS)

# --- Обычный прогон: однократно, без санитайзеров.
test: $(FAMILY_SYMLINK) $(ALL_TEST_BINS)
	@echo "=== Running unit tests (CONFIG=$(CONFIG), SAN=$(SAN_LABEL)) ==="
	@total=0; fail=0; \
	for t in $(ALL_TEST_BINS); do \
	  total=$$((total+1)); \
	  echo "--- $$t ---"; \
	  if ./$$t; then :; else fail=$$((fail+1)); echo "*** $$t FAILED ***"; fi; \
	done; \
	echo "=== Summary: $$fail / $$total failed ==="; \
	test $$fail -eq 0

# --- Прогон под ASan/UBSan.
# Логика: доверяем exit code санитайзера. ASan при наличии проблемы
# возвращает ненулевой код (по умолчанию halt_on_error=1), UBSan — тоже.
# halt_on_error=0 нужен, чтобы при ОДНОЙ найденной проблеме прогон
# продолжился и мы увидели ВСЕ проблемы, а не упали на первой.
# Exit code в этом случае = 0 (тест формально прошёл), поэтому после
# прогона проверяем stderr на маркеры санитайзера, которые пишутся
# ТОЛЬКО при реальных проблемах ("==PID==ERROR:", "runtime error:", "leak").
# Использование:
#   make test_sanitize SAN=address
#   make test_sanitize SAN=undefined CONFIG=debug
test_sanitize: $(FAMILY_SYMLINK) $(ALL_TEST_BINS)
	@echo "=== Running tests under $(SAN_LABEL) (CONFIG=$(CONFIG)) ==="
	@total=0; fail=0; san_fail=0; \
	for t in $(ALL_TEST_BINS); do \
	  total=$$((total+1)); \
	  name=$$(basename $$t); \
	  log=$(SAN_LOG_PREFIX)$$name.log; \
	  echo "--- $$t (log: $$log) ---"; \
	  rm -f $$log; \
	  ASAN_OPTIONS=halt_on_error=0:detect_leaks=1:abort_on_error=0 \
	  UBSAN_OPTIONS=halt_on_error=0:print_stacktrace=1:abort_on_error=0 \
	    ./$$t > $$log 2>&1; \
	  rc=$$?; \
	  # Маркеры, которые санитайзеры пишут ТОЛЬКО при реальных проблемах. \
	  # Эти строки не встречаются в обычном выводе тестов. \
	  if grep -qE '(==[0-9]+==(ERROR|WARNING|runtime error|AddressSanitizer|LeakSanitizer)|SUMMARY: AddressSanitizer|runtime error:|leak [A-Za-z]+ detected)' $$log; then \
	    echo "  SANITIZER ISSUE (rc=$$rc, see $$log)"; \
	    san_fail=$$((san_fail+1)); \
	  elif [ $$rc -ne 0 ]; then \
	    echo "  TEST FAILED (rc=$$rc, see $$log)"; \
	    fail=$$((fail+1)); \
	  else \
	    echo "  OK"; \
	  fi; \
	done; \
	echo "=== Summary: tests=$$total, failed=$$fail, sanitizer_issues=$$san_fail ==="; \
	test $$fail -eq 0 && test $$san_fail -eq 0

# --- Прогон *_mt тестов под Helgrind.
# Использование:
#   make test_helgrind
# Требования: valgrind (apt install valgrind).
test_helgrind: CFLAGS := $(HELGRIND_CFLAGS)
test_helgrind: $(FAMILY_SYMLINK) $(TEST_BINS)
	@echo "=== Running MT tests under Helgrind (CONFIG=$(CONFIG)) ==="
	@total=0; fail=0; \
	mt_binaries="$(patsubst $(TESTS_DIR)/%.c,$(BIN_DIR)/%,$(TEST_BINS_MT))"; \
	for t in $$mt_binaries; do \
	  if [ ! -x $$t ]; then continue; fi; \
	  total=$$((total+1)); \
	  name=$$(basename $$t); \
	  log=$(BIN_DIR)/helgrind_$$name.log; \
	  echo "--- $$t (log: $$log) ---"; \
	  rm -f $$log; \
	  if $(VALGRIND) --tool=helgrind --error-exitcode=42 --log-file=$$log ./$$t > /dev/null 2>&1; then \
	    echo "  OK (no races detected)"; \
	  else \
	    rc=$$?; \
	    if [ $$rc -eq 42 ]; then \
	      echo "  RACE DETECTED (see $$log)"; fail=$$((fail+1)); \
	    else \
	      echo "  TEST FAILED (rc=$$rc, see $$log)"; fail=$$((fail+1)); \
	    fi; \
	  fi; \
	done; \
	echo "=== Summary: $$fail / $$total helgrind runs found races ==="; \
	test $$fail -eq 0

# rev.12: clean убран из зависимостей; ST и MT — отдельные таргеты;
# MT бенмарк собирается с -pthread.
bench: $(FAMILY_SYMLINK) $(REPORTS_DIR) bench_st bench_mt
	@echo ""
	@echo "Both bench reports written to $(REPORTS_DIR)/"
	@ls -l $(REPORTS_DIR)/$(REPORT_NAME)_*.txt

bench_st: $(FAMILY_SYMLINK) $(BENCH_BIN_ST)
	@echo "=== ST benchmark for report: $(REPORT_NAME) (CONFIG=$(CONFIG)) ==="
	@$(MKDIR) $(REPORTS_DIR)
	@sudo sysctl -w kernel.perf_event_max_sample_rate=10000 > /dev/null
	@rm -f $(BENCH_RUNTIME_ST)
	@taskset 0x1 $(PERF) record $(RECORD_OPT) -o $(PERF_DATA_ST) -- $(BENCH_BIN_ST) --data-mode $(DATA_MODE) > $(BENCH_RUNTIME_ST) 2>&1
	@test "$$(grep -c '^Benchmark finished[.]$$' $(BENCH_RUNTIME_ST))" -eq 1 || { echo "ERROR: ST benchmark did not complete; see $(BENCH_RUNTIME_ST)"; exit 1; }
	@grep -q "data_mode=$(DATA_MODE)" $(BENCH_RUNTIME_ST) || { echo "ERROR: ST data mode mismatch; see $(BENCH_RUNTIME_ST)"; exit 1; }
	@grep -q 'elapsed_seconds=' $(BENCH_RUNTIME_ST) || { echo "ERROR: ST runtime output is incomplete; see $(BENCH_RUNTIME_ST)"; exit 1; }
	@$(PERF) report -i $(PERF_DATA_ST) $(REPORT_OPT) --dsos $(BENCH_BIN) --stdio > $(REPORT_FILE_ST)
	@if [ "$(KEEP_PERF)" = "0" ]; then $(RM) $(PERF_DATA_ST); else echo "ST raw perf: $(PERF_DATA_ST)"; fi
	@echo "ST report: $(REPORT_FILE_ST)"

bench_mt: $(FAMILY_SYMLINK) $(BENCH_BIN_MT)
	@echo "=== MT benchmark for report: $(REPORT_NAME) (CONFIG=$(CONFIG)) ==="
	@$(MKDIR) $(REPORTS_DIR)
	@sudo sysctl -w kernel.perf_event_max_sample_rate=20000 > /dev/null
	@rm -f $(BENCH_RUNTIME_MT)
	@taskset --cpu-list $(MT_CPU_LIST) $(PERF) record $(RECORD_OPT) -o $(PERF_DATA_MT) -- $(BENCH_BIN_MT) --threads $(MT_THREADS) --total-iterations $(MT_TOTAL_ITERATIONS) --data-mode $(DATA_MODE) > $(BENCH_RUNTIME_MT) 2>&1
	@test "$$(grep -c '^Benchmark finished[.]$$' $(BENCH_RUNTIME_MT))" -eq 1 || { echo "ERROR: MT benchmark did not complete; see $(BENCH_RUNTIME_MT)"; exit 1; }
	@grep -q "data_mode=$(DATA_MODE)" $(BENCH_RUNTIME_MT) || { echo "ERROR: MT data mode mismatch; see $(BENCH_RUNTIME_MT)"; exit 1; }
	@grep -q 'elapsed_seconds=' $(BENCH_RUNTIME_MT) || { echo "ERROR: MT runtime output is incomplete; see $(BENCH_RUNTIME_MT)"; exit 1; }
	@$(PERF) report -i $(PERF_DATA_MT) $(REPORT_OPT) --dsos $(BENCH_BIN)_mt --stdio > $(REPORT_FILE_MT)
	@if [ "$(KEEP_PERF)" = "0" ]; then $(RM) $(PERF_DATA_MT); else echo "MT raw perf: $(PERF_DATA_MT)"; fi
	@echo "MT report: $(REPORT_FILE_MT)"

# Повторяем perf stat для сравнительных исследований.
# Пример: make bench_stat CONFIG=release REPORT_NAME=baseline PERF_RUNS=7 DATA_MODE=all_nonzero
bench_full: $(FAMILY_SYMLINK) $(REPORTS_DIR)
	@set -e; for mode in all_zero all_nonzero mixed; do \
	        report_name="$(REPORT_NAME)_$${mode}"; \
	        echo "=== Full benchmark mode: $${mode}, report=$${report_name} ==="; \
	        $(MAKE) --no-print-directory bench CONFIG=$(CONFIG) REPORT_NAME=$${report_name} DATA_MODE=$${mode} KEEP_PERF=$(KEEP_PERF); \
	        $(MAKE) --no-print-directory bench_stat CONFIG=$(CONFIG) REPORT_NAME=$${report_name} DATA_MODE=$${mode} PERF_RUNS=$(PERF_RUNS); \
	done

# Cloud environment workflow: use only software events supported without a PMU.
# The regular system perf is not compatible with the cloud kernel, so the
# kernel-matched binary configured by PERF is required. No symlink is created.
bench_cl: PERF_EVENTS := task-clock,context-switches,cpu-migrations,page-faults
bench_cl: $(FAMILY_SYMLINK) $(REPORTS_DIR)
	@echo "=== Cloud benchmark (CONFIG=$(CONFIG), RUNS=$(PERF_RUNS)) ==="
	@if [ ! -x "$(PERF)" ]; then \
	echo "INFO: compatible perf is missing at $(PERF); standard perf cannot be used for this cloud kernel."; \
	exit 1; \
	fi
	@echo "INFO: no standard-perf symlink is created; using kernel-matched $(PERF)."
	@echo "INFO: hardware PMU events are unavailable; using PERF_EVENTS=$(PERF_EVENTS)."
	@set -e; for mode in all_zero all_nonzero mixed; do \
	report_name="$(REPORT_NAME)_cl_$${mode}"; \
	echo "=== Cloud benchmark mode: $${mode}, report=$${report_name} ==="; \
	$(MAKE) --no-print-directory bench_stat \
	    CONFIG=$(CONFIG) REPORT_NAME=$${report_name} DATA_MODE=$${mode} \
	    PERF_RUNS=$(PERF_RUNS) PERF_EVENTS=$(PERF_EVENTS) \
	    MT_THREADS=$(MT_THREADS) MT_CPU_LIST=$(MT_CPU_LIST) \
	    MT_TOTAL_ITERATIONS=$(MT_TOTAL_ITERATIONS); \
	done


# Parameterized direct-run matrix. It uses no PMU events and is therefore
# available in cloud environments where only software perf events are exposed.
# It writes raw JSON samples and a statistical summary; BENCH_BASELINE enables
# an explicit regression gate against a reviewed reference artifact.
bench_matrix: CONFIG := release
bench_matrix: $(FAMILY_SYMLINK) $(BENCH_BINS) $(BENCHMARK_CORE_LIB) $(BENCH_MATRIX_TOOL) $(BENCH_STATS_TOOL) | $(REPORTS_DIR)
	@echo "=== Parameterized C11 benchmark matrix (CONFIG=$(CONFIG), RUNS=$(BENCH_MATRIX_REPETITIONS)) ==="
	@test -x "$(BENCH_MATRIX_TOOL)" || { echo "ERROR: missing C11 matrix tool: $(BENCH_MATRIX_TOOL)"; exit 1; }
	@test -x "$(BENCH_STATS_TOOL)" || { echo "ERROR: missing C11 statistics tool: $(BENCH_STATS_TOOL)"; exit 1; }
	@test $$(( $(BENCH_MATRIX_MT_TOTAL_ITERATIONS) % $(MT_THREADS) )) -eq 0 || { echo "ERROR: BENCH_MATRIX_MT_TOTAL_ITERATIONS must be divisible by MT_THREADS"; exit 1; }
	@$(BENCH_MATRIX_TOOL) \
	    --manifest $(BENCH_MATRIX_PROFILE) \
	    --output $(BENCH_MATRIX_REPORT) \
	    --st-binary $(BENCH_BIN_ST) \
	    --mt-binary $(BENCH_BIN_MT) \
	    --repetitions $(BENCH_MATRIX_REPETITIONS) \
	    --iterations $(BENCH_MATRIX_ITERATIONS) \
	    --mt-total-iterations $(BENCH_MATRIX_MT_TOTAL_ITERATIONS) \
	    --threads $(MT_THREADS) \
	    --warmup $(BENCH_MATRIX_WARMUP) \
	    --data-count $(BENCH_MATRIX_DATA_COUNT) \
	    --seed $(BENCH_MATRIX_SEED) \
	    --timeout-seconds $(BENCH_MATRIX_TIMEOUT_SECONDS)
	@$(BENCH_STATS_TOOL) \
	    --input $(BENCH_MATRIX_REPORT) \
	    --output $(BENCH_MATRIX_SUMMARY) \
	    --threshold-pct $(BENCH_REGRESSION_THRESHOLD_PCT) \
	    $(if $(strip $(BENCH_BASELINE)),--baseline $(BENCH_BASELINE))
	@echo "Matrix samples: $(BENCH_MATRIX_REPORT)"
	@echo "Matrix summary: $(BENCH_MATRIX_SUMMARY)"

bench_stat: bench_stat_st bench_stat_mt
	@echo "ST stat: $(STAT_FILE_ST)"
	@echo "MT stat: $(STAT_FILE_MT)"

bench_stat_st: $(FAMILY_SYMLINK) $(BENCH_BIN_ST)
	@echo "=== ST perf stat: $(REPORT_NAME) (CONFIG=$(CONFIG), RUNS=$(PERF_RUNS)) ==="
	@$(MKDIR) $(REPORTS_DIR)
	@printf 'CONFIG=$(CONFIG) DATA_MODE=$(DATA_MODE) PERF_RUNS=$(PERF_RUNS) PERF_EVENTS=$(PERF_EVENTS) CPU_LIST=0\n' > $(STAT_RUNTIME_ST)
	@taskset 0x1 $(PERF) stat -r $(PERF_RUNS) -x, -e $(PERF_EVENTS) -o $(STAT_FILE_ST) -- $(BENCH_BIN_ST) --data-mode $(DATA_MODE) >> $(STAT_RUNTIME_ST) 2>&1
	@test "$$(grep -c '^Benchmark finished[.]$$' $(STAT_RUNTIME_ST))" -eq $(PERF_RUNS) || { echo "ERROR: ST perf stat expected $(PERF_RUNS) completed runs; see $(STAT_RUNTIME_ST)"; exit 1; }
	@grep -q "data_mode=$(DATA_MODE)" $(STAT_RUNTIME_ST) || { echo "ERROR: ST perf stat data mode mismatch; see $(STAT_RUNTIME_ST)"; exit 1; }
	@grep -q 'elapsed_seconds=' $(STAT_RUNTIME_ST) || { echo "ERROR: ST perf stat runtime output is incomplete; see $(STAT_RUNTIME_ST)"; exit 1; }

bench_stat_mt: $(FAMILY_SYMLINK) $(BENCH_BIN_MT)
	@echo "=== MT perf stat: $(REPORT_NAME) (CONFIG=$(CONFIG), RUNS=$(PERF_RUNS)) ==="
	@$(MKDIR) $(REPORTS_DIR)
	@printf 'CONFIG=$(CONFIG) DATA_MODE=$(DATA_MODE) PERF_RUNS=$(PERF_RUNS) PERF_EVENTS=$(PERF_EVENTS) MT_THREADS=$(MT_THREADS) MT_CPU_LIST=$(MT_CPU_LIST) MT_TOTAL_ITERATIONS=$(MT_TOTAL_ITERATIONS)\n' > $(STAT_RUNTIME_MT)
	@taskset --cpu-list $(MT_CPU_LIST) $(PERF) stat -r $(PERF_RUNS) -x, -e $(PERF_EVENTS) -o $(STAT_FILE_MT) -- $(BENCH_BIN_MT) --threads $(MT_THREADS) --total-iterations $(MT_TOTAL_ITERATIONS) --data-mode $(DATA_MODE) >> $(STAT_RUNTIME_MT) 2>&1
	@test "$$(grep -c '^Benchmark finished[.]$$' $(STAT_RUNTIME_MT))" -eq $(PERF_RUNS) || { echo "ERROR: MT perf stat expected $(PERF_RUNS) completed runs; see $(STAT_RUNTIME_MT)"; exit 1; }
	@grep -q "data_mode=$(DATA_MODE)" $(STAT_RUNTIME_MT) || { echo "ERROR: MT perf stat data mode mismatch; see $(STAT_RUNTIME_MT)"; exit 1; }
	@grep -q 'elapsed_seconds=' $(STAT_RUNTIME_MT) || { echo "ERROR: MT perf stat runtime output is incomplete; see $(STAT_RUNTIME_MT)"; exit 1; }

install: clean $(FAMILY_SYMLINK) $(OBJ) $(OBJECTS) | $(DIST_INCLUDE_DIR) $(DIST_LIB_DIR)
	@printf "%s" "Installing product to $(DIST_DIR)/ (CONFIG=$(CONFIG))..."
	@if [ -f "$(INCLUDE_DIR)/$(FAMILY_NAME).h" ]; then \
	        cp "$(INCLUDE_DIR)/$(FAMILY_NAME).h" "$(DIST_INCLUDE_DIR)/"; \
	fi
	@if [ ! -f "$(DIST_INCLUDE_DIR)/$(FAMILY_NAME).h" ]; then \
	        cp "$(FAMILY_HEADER)" "$(DIST_INCLUDE_DIR)/$(FAMILY_NAME).h"; \
	fi
	@cp $(HEADER) $(SRC_SUBMODULES_HEADERS) $(DIST_INCLUDE_DIR)/
	@cp $(OBJ) $(OBJECTS) $(DIST_LIB_DIR)/
#       @$(foreach d,$(DIST_SUBMODULES), \
	        cd $(DIST_LIB_DIR) && $(AR) x ../../$(LIBS_DIR)/$(d)/dist/lib$(subst -,_,$(d)).a && cd ../..; \
	)
	@echo "Ok"
	@tree $(DIST_DIR)/
	@cp $(TESTS_DIR)/test_$(LIB_NAME)_runner.c $(DIST_DIR)/
	@$(CC) $(DIST_DIR)/test_$(LIB_NAME)_runner.c  $(DIST_DIR)/$(LIBS_DIR)/*.o -I$(DIST_DIR)/$(INCLUDE_DIR) -o $(DIST_DIR)/test_$(LIB_NAME)_runner -no-pie
	@$(DIST_DIR)/test_$(LIB_NAME)_runner
	@$(RM) $(DIST_DIR)/test_$(LIB_NAME)_runner

generate-header: $(FAMILY_SYMLINK)
	@$(MKDIR) $(DIST_DIR)
	@printf "%s" "Generating single-file header..."
	@echo "#ifndef $(UPPER_LIB_NAME)_SINGLE_H" > $(SINGLE_HEADER)
	@echo "#define $(UPPER_LIB_NAME)_SINGLE_H" >> $(SINGLE_HEADER)
	@echo "" >> $(SINGLE_HEADER)
	@if [ -n "$(strip $(SRC_SUBMODULES_HEADERS))" ]; then \
	        sed -e '/#include "$(FAMILY_NAME).h"/d' -e '/#include <$(FAMILY_NAME).h>/d' $(SRC_SUBMODULES_HEADERS) >> $(SINGLE_HEADER); \
	else \
	        echo "\n\tSRC-Submodules is empty. Use family header"; \
	        sed -e '/#include "$(FAMILY_NAME).h"/d' -e '/#include <$(FAMILY_NAME).h>/d' $(FAMILY_HEADER) >> $(SINGLE_HEADER); \
	fi
	echo "\n/* --- Included from include/$(LIB_NAME).h --- */" >> $(SINGLE_HEADER)
	sed -e '/$(UPPER_LIB_NAME)_H/d' -e '/#include <$(FAMILY_NAME).h>/d' -e '/#include "$(FAMILY_NAME).h"/d' $(HEADER) >> $(SINGLE_HEADER)
	@echo "" >> $(SINGLE_HEADER)
	@echo "#endif // $(UPPER_LIB_NAME)_SINGLE_H" >> $(SINGLE_HEADER)
	@echo "\n\tStep 1: Removing duplicate code blocks..."
	@awk ' \
	BEGIN { in_guard = 0; depth = 0; } \
	{ \
	        stripped = $$0; sub(/^[[:space:]]*/, "", stripped); \
	        if (in_guard == 1) { \
	                if (stripped ~ /^#(if|ifndef|ifdef)/) { depth++; } \
	                else if (stripped ~ /^#endif/) { \
	                        depth--; \
	                        if (depth == 0) in_guard = 0; \
	                } \
	                next; \
	        } \
	        if (stripped ~ /^#ifndef[[:space:]]+[A-Za-z0-9_]+/) { \
	                split(stripped, p, /[[:space:]]+/); name = p[2]; \
	                if (seen[name]) { in_guard = 1; depth = 1; next; } \
	                seen[name] = 1; \
	        } \
	        print $$0; \
	}' $(SINGLE_HEADER) > $(SINGLE_HEADER)_tmp.h
	@echo "\tStep 2: Removing duplicate Doxygen blocks..."
	@awk ' \
	BEGIN { in_comment = 0; } \
	{ \
	        stripped = $$0; sub(/^[[:space:]]*/, "", stripped); \
	        if (in_comment == 1) { \
	                if (stripped ~ /\*\//) { in_comment = 0; } \
	                next; \
	        } \
	        if (stripped ~ /^\/\*\*/) { \
	                # Мы нашли Doxygen-блок. Проверяем, видели ли мы его раньше. \
	                # Чтобы идентифицировать блок, мы создаем хеш из первых двух строк. \
	                block_id = stripped; \
	                getline next_line; \
	                block_id = block_id " " next_line; \
	                \
	                if (seen_doc[block_id]) { \
	                        in_comment = 1; \
	                        # Нужно пропустить текущую строку, так как она уже в block_id \
	                        # Но мы должны проверить, не закрылся ли комментарий сразу \
	                        if (next_line ~ /\*\//) { in_comment = 0; } \
	                        next; \
	                } \
	                seen_doc[block_id] = 1; \
	                print stripped; \
	                print next_line; \
	                next; \
	        } \
	        print $$0; \
	}' $(SINGLE_HEADER)_tmp.h > $(SINGLE_HEADER)_final.h
	@rm -f $(SINGLE_HEADER)_tmp.h
	@mv $(SINGLE_HEADER)_final.h $(SINGLE_HEADER)
	@echo "Done. Result saved to $(SINGLE_HEADER)"
	@echo "Ok"

dist: clean $(FAMILY_SYMLINK)
	@echo "Creating single-file header distribution in $(DIST_DIR)/ (CONFIG=$(CONFIG))...."
	@$(MKDIR) $(DIST_DIR)
	@$(MAKE) -s build CONFIG=release
	@printf "%s" "Stripping object files, keeping symbol $(LIB_NAME)..."
	@$(STRIP) --strip-debug $(OBJ) $(OBJECTS) || true;
	@$(STRIP) --strip-unneeded $(OBJ) $(OBJECTS) || true;
	@echo "Ok"
	@printf "%s" "Create static library lib$(LIB_NAME).a ..."
	@$(AR) rcs $(STATIC_LIB) $(OBJ) $(OBJECTS)
#       @$(foreach d,$(DIST_SUBMODULES), \
	$(MKDIR) $(BUILD_DIR)/tmp_$(d) && \
	cd $(BUILD_DIR)/tmp_$(d) && \
	$(AR) x ../../$(LIBS_DIR)/$(d)/dist/lib$(subst -,_,$(d)).a && \
	$(AR) r ../../$(STATIC_LIB) *.o && \
	cd ../..; \
	)
	@$(RL) $(STATIC_LIB)
	@echo "Ok"
	@$(NM) -g --defined-only  $(STATIC_LIB)
	@$(MAKE) -s generate-header
	@cp README.md $(DIST_DIR)/
	@cp LICENSE $(DIST_DIR)/
	@cp $(TESTS_DIR)/test_$(LIB_NAME)_runner.c $(DIST_DIR)/
	@$(CC) $(DIST_DIR)/test_$(LIB_NAME)_runner.c -L$(DIST_DIR) -l$(LIB_NAME) -o $(DIST_DIR)/test_$(LIB_NAME)_runner -no-pie
	@$(DIST_DIR)/test_$(LIB_NAME)_runner
	@$(RM) $(DIST_DIR)/test_$(LIB_NAME)_runner
	@echo "Distribution created successfully in $(DIST_DIR)/ "
	@ls -l $(DIST_DIR)

# --- Compilation Rules ---
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@echo "Compiling C: $< -> $@ (CONFIG=$(CONFIG))..."
	@$(MKDIR) $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.asm
	@echo "Assembling ASM: $< -> $@ (CONFIG=$(CONFIG))..."
	@$(MKDIR) $(BUILD_DIR)
	$(AS) $(ASFLAGS) -o $@ $<

$(OBJ): $(C_SRC)
	@echo "Builds the main object file '$(OBJ)' (CONFIG=$(CONFIG))..."
	@$(MKDIR) $(BUILD_DIR)
ifeq ($(SRC_EXT),c)
	$(CC) $(CFLAGS) -c $(C_SRC) -o $(OBJ)
else
	$(AS) $(ASFLAGS) -o $(OBJ) $(C_SRC)
endif


$(OBJECTS):
	@echo "Building source submodules... (CONFIG=$(CONFIG))... "
	@$(foreach d,$(GENERIC_BUILD_SUBMODULES), \
	  (echo "\tBuild for $(d) ..." && $(MAKE) -C $(LIBS_DIR)/$(d) -s build CONFIG=release USE_ASM=auto CFLAGS+=-Wl,-z,noexecstack) || echo "\n\t\t⚠️  $(d) no rule build\n"; \
	)


$(BIN_DIR)/%: $(TESTS_DIR)/%.c $(OBJ) $(OBJECTS) | $(BIN_DIR)
	@$(MKDIR) $(BIN_DIR)
	@$(CC) $(CFLAGS) $< $(OBJECTS) $(OBJ) -o $@ $(LDFLAGS) \
	  $(if $(filter %_mt,$*),-pthread)
benchmark_framework:
# @$(MAKE) -C $(BENCHMARK_FRAMEWORK_DIR) build CONFIG=release

docs:
	@$(MKDIR) $(BUILD_DIR)/docs
	@sed 's#^OUTPUT_DIRECTORY.*#OUTPUT_DIRECTORY       = $(abspath $(BUILD_DIR)/docs)#; s#^STRIP_FROM_PATH.*#STRIP_FROM_PATH        = $(abspath .)#' docs/Doxyfile | doxygen -

$(BENCHMARK_CORE_LIB): benchmark_framework

$(BENCH_ADAPTER_OBJ): $(BENCH_ADAPTER_SOURCE) $(BENCH_ADAPTER_HEADER) $(BENCHMARK_CORE_LIB) | $(BUILD_DIR)
#	@echo "Compiling C11 bignum benchmark adapter: $< -> $@ (CONFIG=$(CONFIG))..."
	@$(CC) $(CFLAGS) -c $< -o $@

$(BENCH_BIN_ST): $(BENCH_SRC_ST) $(BENCH_ADAPTER_OBJ) $(BENCHMARK_CORE_LIB) $(OBJ) $(OBJECTS) | $(BIN_DIR)
	@$(CC) $(CFLAGS) $< $(BENCH_ADAPTER_OBJ) $(OBJECTS) $(OBJ) $(BENCHMARK_CORE_LIB) -o $@ $(LDFLAGS) -pthread

$(BENCH_BIN_MT): $(BENCH_SRC_MT) $(BENCH_ADAPTER_OBJ) $(BENCHMARK_CORE_LIB) $(OBJ) $(OBJECTS) | $(BIN_DIR)
	@$(CC) $(CFLAGS) $< $(BENCH_ADAPTER_OBJ) $(OBJECTS) $(OBJ) $(BENCHMARK_CORE_LIB) -o $@ $(LDFLAGS) -pthread

$(BENCH_ADAPTER_TEST_BIN): $(BENCH_ADAPTER_TEST_SOURCE) $(BENCH_ADAPTER_OBJ) $(BENCHMARK_CORE_LIB) $(OBJ) $(OBJECTS) | $(BIN_DIR)
	@$(CC) $(CFLAGS) $< $(BENCH_ADAPTER_OBJ) $(OBJECTS) $(OBJ) $(BENCHMARK_CORE_LIB) -o $@ $(LDFLAGS) -pthread

# --- Utility Targets ---
$(BIN_DIR) $(REPORTS_DIR) $(DIST_INCLUDE_DIR) $(DIST_LIB_DIR):
	@$(MKDIR) $@

# The symlink is a normal file target; if it already exists and points to
# the correct source make will consider it up‑to‑date.
$(FAMILY_SYMLINK): $(FAMILY_HEADER)
	@echo "Creating symlink: $@ → $(notdir $<)"
	@ln -sf $(notdir $<) $@

# Удаляем только если это действительно симлинк
unlink-symlink:
	@if [ -L "$(FAMILY_PATH)/$(FAMILY_NAME).h" ]; then \
	        echo "Cleaning up symlink $(FAMILY_PATH)/$(FAMILY_NAME).h"; \
	        rm -f "$(FAMILY_PATH)/$(FAMILY_NAME).h"; \
	else \
	        echo "$(FAMILY_PATH)/$(FAMILY_NAME).h is not symlink. Leave untuched..."; \
	fi

lint:
	@echo "Running static analysis on C source files..."
	@$(CPPCHECK) --std=c11 --enable=all --error-exitcode=1 --suppress=missingIncludeSystem \
	    --inline-suppr --inconclusive --check-config \
	    -I$(INCLUDE_DIR) $(addprefix -I , $(SUBMODULES_INCLUDE_DIR)) \
	    $(TESTS_DIR)/ $(BENCH_DIR)/ $(DIST_DIR)/ $(SRC_DIR)/ $(LIBS_DIR)/

clean:
	@$(MAKE) unlink-symlink --no-print-directory
	@echo "Cleaning up build artifacts (build/, bin/, dist/)..."
	@$(RM) $(BUILD_DIR) $(BIN_DIR) $(DIST_DIR)
	@echo "Cleaning up submodule artifacts:" ;
	@$(foreach d,$(SRC_SUBMODULES), \
	  if [ -f $(LIBS_DIR)/$(d)/Makefile ]; then \
	    (printf "%s" "Clean for $(d) : " && $(MAKE) -C $(LIBS_DIR)/$(d) -s clean) || echo "\n\t\t⚠️  $(d) has no rule clean\n"; \
	  else \
	    echo "Skipping clean for $(d) (no Makefile found)"; \
	  fi; \
	)


help:
	@echo "Usage: make <target> [CONFIG=release] [REPORT_NAME=my_report]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all/build        Builds the main object file."
	@echo "  lint             Static analysis on C sources."
	@echo "  test             Builds and runs all unit tests."
	@echo "  test_sanitize   Runs tests under sanitizer: make test_sanitize SAN={address|undefined}"
	@echo "  test_helgrind   Runs *_mt tests under valgrind --tool=helgrind for race detection."
	@echo "  bench            perf record/report benchmark; raw perf.data kept by default."
	@echo "  bench_full       Run bench and bench_stat for all_zero, all_nonzero and mixed."
	@echo "  bench_cl         Cloud-compatible repeated perf stat for all modes (software events only)."
	@echo "  bench_stat       Repeated perf stat runs for ST and MT."
	@echo "  bench_stat_st   Repeated ST perf stat runs."
	@echo "  bench_stat_mt   Repeated MT perf stat runs."
	@echo "  bench_matrix    Run pinned C11 JSON matrix and statistics aggregation."
	@echo "  install          Installs product into dist/ for internal use."
	@echo "  dist             Builds a single-header + static-lib distribution in dist/."
	@echo "  clean            Removes build/, bin/, dist/."
	@echo "  help             Shows this help message."
	@echo ""
	@echo "Logs:"
	@echo "  Sanitizer logs: \$$(BIN_DIR)/sanitize_<test>.log"
	@echo "  Helgrind logs:  \$$(BIN_DIR)/helgrind_<test>_mt.log"
	@echo ""
	@echo "Benchmark variables: DATA_MODE=all_nonzero|all_zero|mixed PERF_RUNS=5 PERF_EVENTS=<events> KEEP_PERF=1"
	@echo "  Matrix: BENCH_MATRIX_PROFILE=benchmarks/profiles/bignum_template_full.json BENCH_MATRIX_REPETITIONS=7"
	@echo "  BENCH_MATRIX_ITERATIONS=200000000 BENCH_MATRIX_MT_TOTAL_ITERATIONS=320000000 BENCH_BASELINE=<reviewed JSON>"
	@echo "  MT defaults: MT_THREADS=2 MT_CPU_LIST=0-1 MT_TOTAL_ITERATIONS=3200000000"
	@echo "  MT-1: make bench_mt MT_THREADS=1 MT_CPU_LIST=0 MT_TOTAL_ITERATIONS=3200000000"
	@echo "  MT-2: make bench_mt MT_THREADS=2 MT_CPU_LIST=0-1 MT_TOTAL_ITERATIONS=3200000000"
	@echo "  MT_TOTAL_ITERATIONS is divided evenly across MT_THREADS."
	@echo ""
	@echo "Optimization Cycle Example:"
	@echo "  1. make bench REPORT_NAME=baseline"
	@echo "  2. ...edit code..."
	@echo "  3. make test"
	@echo "  4. make bench REPORT_NAME=opt_v1"
	@echo "  5. diff -u benchmarks/reports/baseline_st.txt benchmarks/reports/opt_v1_st.txt"
	@echo ""
	@echo "Parameterized Matrix Benchmark Example:"
	@echo "  Runs the pinned C11 benchmark matrix without PMU/perf events and writes raw samples plus a JSON summary."
	@echo "  Standard smoke matrix:"
	@echo "    make clean"
	@echo "    make bench_matrix CONFIG=release REPORT_NAME=baseline BENCH_MATRIX_PROFILE=benchmarks/profiles/bignum_template_standard.json BENCH_MATRIX_REPETITIONS=7"
	@echo "  Full matrix with the default workload:"
	@echo "    make bench_matrix CONFIG=release REPORT_NAME=baseline BENCH_MATRIX_PROFILE=benchmarks/profiles/bignum_template_full.json BENCH_MATRIX_REPETITIONS=7"
	@echo "  Compare a candidate with a previous run:"
	@echo "    make clean"
	@echo "    make bench_matrix CONFIG=release REPORT_NAME=opt_v1 BENCH_MATRIX_PROFILE=benchmarks/profiles/bignum_template_standard.json BENCH_MATRIX_REPETITIONS=7"
	@echo "    diff -u benchmarks/reports/baseline_matrix_summary.json benchmarks/reports/opt_v1_matrix_summary.json"
	@echo "  Enable the reviewed-baseline regression gate:"
	@echo "    make bench_matrix CONFIG=release REPORT_NAME=opt_v1 BENCH_BASELINE=benchmarks/reports/baseline_matrix_summary.json"
	@echo "  Smoke-test controls: BENCH_MATRIX_ITERATIONS=N BENCH_MATRIX_MT_TOTAL_ITERATIONS=N BENCH_MATRIX_WARMUP=N BENCH_MATRIX_DATA_COUNT=N BENCH_MATRIX_SEED=N"
	@echo "  BENCH_MATRIX_MT_TOTAL_ITERATIONS must be divisible by MT_THREADS; use the default workload for timing studies."
	@echo "  Output: benchmarks/reports/<REPORT_NAME>_matrix.json and benchmarks/reports/<REPORT_NAME>_matrix_summary.json"
	@echo ""
	@echo "Repeated perf stat Comparison Example:"
	@echo "  Input modes: all_nonzero measures the hot non-zero path; all_zero measures zero path; mixed alternates 0/non-zero to expose branch effects."
	@echo "  1. make clean"
	@echo "  2. make test CONFIG=release"
	@echo "  3. make bench_stat CONFIG=release REPORT_NAME=baseline PERF_RUNS=7 KEEP_PERF=1"
	@echo "  4. ...edit code..."
	@echo "  5. make clean"
	@echo "  6. make test CONFIG=release"
	@echo "  7. make bench_stat CONFIG=release REPORT_NAME=opt_v1 PERF_RUNS=7 KEEP_PERF=1"
	@echo "  8. diff -u benchmarks/reports/baseline_st_runtime.txt benchmarks/reports/opt_v1_runtime.txt"
	@echo "  9. diff -u benchmarks/reports/baseline_st_stat.csv benchmarks/reports/opt_v1_st_stat.csv"
	@echo " 10. diff -u benchmarks/reports/baseline_mt_stat.csv benchmarks/reports/opt_v1_mt_stat.csv"
	@echo " 11. perf report -i benchmarks/reports/baseline_st.perf.data --stdio"
	@echo " 12. perf report -i benchmarks/reports/opt_v1_st.perf.data --stdio"
	@echo ""
	@echo "Cloud three-mode study (requires a kernel-matched perf at \$$(PERF)):"
	@echo "  make bench_cl CONFIG=release REPORT_NAME=baseline PERF_RUNS=7"
	@echo "  Uses task-clock, context-switches, cpu-migrations and page-faults; no raw perf.data is recorded."
	@echo "  Smoke-test controls (environment, not Make variables):"
	@echo "    BIGNUM_BENCH_ITERATIONS=N BIGNUM_BENCH_MT_TOTAL_ITERATIONS=N BIGNUM_BENCH_SEED=N"
	@echo "    The MT total must be divisible by MT_THREADS; use the default workload for timing studies."
	@echo ""
	@echo "Full three-mode study:"
	@echo "  make bench_full CONFIG=release REPORT_NAME=baseline PERF_RUNS=7 KEEP_PERF=1"
	@echo "  Reports are suffixed _all_zero, _all_nonzero and _mixed."
	@echo "  Compare each mode separately; require identical data_fingerprint and checksum before timing comparisons."
show-calc:
	@echo "REPOSITORY_NAME = '$(REPOSITORY_NAME)'"
	@echo "FAMILY_NAME = '$(FAMILY_NAME)'"
	@echo "OPERATION_NAME = '$(OPERATION_NAME)'"
	@echo "LIB_NAME = '$(LIB_NAME)'"
	@echo "UPPER_LIB_NAME = '$(UPPER_LIB_NAME)'"
	@echo "NP = '$(NP)'"
	@echo "CPU_LIST = '$(CPU_LIST)'"
	@echo "ASM_LABELS = '$(ASM_LABELS)'"
	@echo "Количество меток: $(words $(subst |, ,$(ASM_LABELS)))"
	@echo "OBJ = '$(OBJ)'"
	@echo "OBJECTS = '$(OBJECTS)'"
	@echo "C_SRC = '$(C_SRC)'"
	@echo "HEADER = '$(HEADER)'"
	@echo "FAMILY_HEADER = '$(FAMILY_HEADER)'"
	@echo "FAMILY_PATH = '$(FAMILY_PATH)'"
	@echo "FAMILY_SYMLINK = '$(FAMILY_SYMLINK)'"
	@echo "SINGLE_HEADER = '$(SINGLE_HEADER)'"
	@echo "SRC_EXT = '$(SRC_EXT)'"
	@echo "USE_ASM = '$(USE_ASM)'"
	@echo "ASM_SRC = '$(ASM_SRC)'"
	@echo "SUBMODULES = '$(SUBMODULES)'"
	@echo "CORE_NAME = '$(CORE_NAME)'"
	@echo "SRC_SUBMODULES_INCLUDE_DIR = '$(SRC_SUBMODULES_INCLUDE_DIR)'"
	@echo "DIST_SUBMODULES_INCLUDE_DIR = '$(DIST_SUBMODULES_INCLUDE_DIR)'"
	@echo "SUBMODULES_INCLUDE_DIR = '$(SUBMODULES_INCLUDE_DIR)'"
	@echo "SUBMODULES_DIST_DIR = '$(SUBMODULES_DIST_DIR)'"
	@echo "SUBMODULES_DIST_LIB = '$(SUBMODULES_DIST_LIB)'"
	@echo "SRC_SUBMODULES_HEADERS_RAW = '$(SRC_SUBMODULES_HEADERS_RAW)'"
	@echo "SRC_SUBMODULES_HEADERS = '$(SRC_SUBMODULES_HEADERS)'"
	@echo "DIST_SUBMODULES_HEADERS_RAW = '$(DIST_SUBMODULES_HEADERS_RAW)'"
	@echo "DIST_SUBMODULES_HEADERS = '$(DIST_SUBMODULES_HEADERS)'"
	@echo "SUBMODULES_HEADERS_RAW = '$(SUBMODULES_HEADERS_RAW)'"
	@echo "SUBMODULES_HEADERS = '$(SUBMODULES_HEADERS)'"
	@echo "TEST_BINS_MT = '$(TEST_BINS_MT)'"
	@echo "TEST_BINS = '$(TEST_BINS)'"
	@echo "SAN = $(SAN) ($(SAN_LABEL))"
	@echo "HELGRIND = $(HELGRIND)"
	@echo "SRC_SUBMODULES = '$(SRC_SUBMODULES)'"
	@echo "DIST_SUBMODULES = '$(DIST_SUBMODULES)'"
