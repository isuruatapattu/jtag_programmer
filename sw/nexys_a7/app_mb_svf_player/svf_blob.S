    .section .rodata.svf, "a"
    .balign 4

    .global nexys_a7_01_svf_start
    .global nexys_a7_01_svf_end

nexys_a7_01_svf_start:
    .incbin "@APP_SVF_FILE@"
nexys_a7_01_svf_end:
    .balign 4
