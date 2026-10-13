# 2026-10-08T12:43:03.850211500
import vitis

client = vitis.create_client()
client.set_workspace(path="nexys_a7")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../../hw/nexys_a7_jtag_programmer_2025.01/design_1_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_mb_jtag_verifier")
comp.build()

