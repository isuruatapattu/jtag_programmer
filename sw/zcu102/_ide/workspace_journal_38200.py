# 2026-10-12T10:20:26.318455200
import vitis

client = vitis.create_client()
client.set_workspace(path="zcu102")

platform = client.create_platform_component(name = "platform_v2",hw_design = "$COMPONENT_LOCATION/../../../hw/zcu102_jtag_programmer/design_2_wrapper_v2.xsa",os = "standalone",cpu = "psu_cortexa53_0",domain_name = "standalone_psu_cortexa53_0",architecture = "64-bit",compiler = "gcc")

platform = client.get_component(name="platform_v2")
status = platform.build()

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_svf_player")
comp.build()

comp = client.create_app_component(name="input_test",platform = "$COMPONENT_LOCATION/../platform_v2/export/platform_v2/platform_v2.xpfm",domain = "standalone_psu_cortexa53_0")

platform = client.get_component(name="platform_v2")
status = platform.build()

comp.build()

status = platform.build()

comp = client.get_component(name="input_test")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

