# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "C:\\dev\\projects\\jtag_programmer\\sw\\nexys_a7\\ws_20260818\\pf_nexys_a7\\microblaze_0\\standalone_microblaze_0\\bsp\\include\\sleep.h"
  "C:\\dev\\projects\\jtag_programmer\\sw\\nexys_a7\\ws_20260818\\pf_nexys_a7\\microblaze_0\\standalone_microblaze_0\\bsp\\include\\xiltimer.h"
  "C:\\dev\\projects\\jtag_programmer\\sw\\nexys_a7\\ws_20260818\\pf_nexys_a7\\microblaze_0\\standalone_microblaze_0\\bsp\\include\\xtimer_config.h"
  "C:\\dev\\projects\\jtag_programmer\\sw\\nexys_a7\\ws_20260818\\pf_nexys_a7\\microblaze_0\\standalone_microblaze_0\\bsp\\lib\\libxiltimer.a"
  )
endif()
