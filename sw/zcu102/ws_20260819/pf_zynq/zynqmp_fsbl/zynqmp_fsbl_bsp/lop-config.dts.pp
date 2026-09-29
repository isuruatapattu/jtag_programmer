# 1 "/users2/athapatt/my_ws/jtag_programmer/sw/zcu102/ws_20260819/pf_zynq/zynqmp_fsbl/zynqmp_fsbl_bsp/lop-config.dts"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "/users2/athapatt/my_ws/jtag_programmer/sw/zcu102/ws_20260819/pf_zynq/zynqmp_fsbl/zynqmp_fsbl_bsp/lop-config.dts"

/dts-v1/;
/ {
        compatible = "system-device-tree-v1,lop";
        lops {
                lop_0 {
                        compatible = "system-device-tree-v1,lop,load";
                        load = "assists/baremetal_validate_comp_xlnx.py";
                };

                lop_1 {
                    compatible = "system-device-tree-v1,lop,assist-v1";
                    node = "/";
                    outdir = "/users2/athapatt/my_ws/jtag_programmer/sw/zcu102/ws_20260819/pf_zynq/zynqmp_fsbl/zynqmp_fsbl_bsp";
                    id = "module,baremetal_validate_comp_xlnx";
                    options = "psu_cortexa53_0 /tools/Xilinx/2025.1/Vitis/data/embeddedsw/lib/sw_services/xilffs_v5_4/src /users2/athapatt/my_ws/jtag_programmer/sw/zcu102/ws_20260819/_ide/.wsdata/.repo.yaml";
                };

                lop_2 {
                    compatible = "system-device-tree-v1,lop,assist-v1";
                    node = "/";
                    outdir = "/users2/athapatt/my_ws/jtag_programmer/sw/zcu102/ws_20260819/pf_zynq/zynqmp_fsbl/zynqmp_fsbl_bsp";
                    id = "module,baremetal_validate_comp_xlnx";
                    options = "psu_cortexa53_0 /tools/Xilinx/2025.1/Vitis/data/embeddedsw/lib/sw_services/xilsecure_v5_5/src /users2/athapatt/my_ws/jtag_programmer/sw/zcu102/ws_20260819/_ide/.wsdata/.repo.yaml";
                };

                lop_3 {
                    compatible = "system-device-tree-v1,lop,assist-v1";
                    node = "/";
                    outdir = "/users2/athapatt/my_ws/jtag_programmer/sw/zcu102/ws_20260819/pf_zynq/zynqmp_fsbl/zynqmp_fsbl_bsp";
                    id = "module,baremetal_validate_comp_xlnx";
                    options = "psu_cortexa53_0 /tools/Xilinx/2025.1/Vitis/data/embeddedsw/lib/sw_services/xilpm_v6_0/src /users2/athapatt/my_ws/jtag_programmer/sw/zcu102/ws_20260819/_ide/.wsdata/.repo.yaml";
                };

        };
    };
