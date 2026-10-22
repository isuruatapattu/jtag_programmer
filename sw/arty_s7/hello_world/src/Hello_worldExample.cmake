set(IOMODULE_NUM_DRIVER_INSTANCES "")
set(UARTLITE_NUM_DRIVER_INSTANCES "axi_uartlite_0")
set(UARTLITE0_PROP_LIST "0x40600000")
list(APPEND TOTAL_UARTLITE_PROP_LIST UARTLITE0_PROP_LIST)
set(UARTNS550_NUM_DRIVER_INSTANCES "")
set(UARTPS_NUM_DRIVER_INSTANCES "")
set(UARTPSV_NUM_DRIVER_INSTANCES "")
set(mig_7series_0_memory_0 "0x80000000;0x10000000")
set(microblaze_0_local_memory_dlmb_bram_if_cntlr_memory_0 "0x50;0xffb0")
set(DDR mig_7series_0_memory_0)
set(CODE mig_7series_0_memory_0)
set(DATA mig_7series_0_memory_0)
set(TOTAL_MEM_CONTROLLERS "mig_7series_0_memory_0;microblaze_0_local_memory_dlmb_bram_if_cntlr_memory_0")
set(MEMORY_SECTION "MEMORY
{
	mig_7series_0_memory_0 : ORIGIN = 0x80000000, LENGTH = 0x10000000
	microblaze_0_local_memory_dlmb_bram_if_cntlr_memory_0 : ORIGIN = 0x50, LENGTH = 0xffb0
}")
set(STACK_SIZE 0x400)
set(HEAP_SIZE 0x800)
