# 2026-10-06T18:26:45.639750800
import vitis

client = vitis.create_client()
client.set_workspace(path="zcu102")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../../hw/zcu102_jtag_programmer/design_2_wrapper.xsa",os = "standalone",cpu = "psu_cortexa53_0",domain_name = "standalone_psu_cortexa53_0",architecture = "64-bit",compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_svf_player")
comp.build()

vitis.dispose()

