# 2026-10-22T15:57:54.849061200
import vitis

client = vitis.create_client()
client.set_workspace(path="arty_s7")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../../hw/arty_s7_jtag_programmer/design_1_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

