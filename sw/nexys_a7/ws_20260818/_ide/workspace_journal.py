# 2026-08-18T12:10:06.529073500
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260818")

platform = client.create_platform_component(name = "pf_nexys_a7",hw_design = "$COMPONENT_LOCATION/../../../../hw/nexys_a7_jtag_programmer/design_1_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

platform = client.get_component(name="pf_nexys_a7")
status = platform.build()

comp = client.get_component(name="app_mb_svf_player")
comp.build()

comp.build()

status = comp.clean()

status = comp.clean()

comp.build()

