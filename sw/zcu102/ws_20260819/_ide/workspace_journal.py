# 2026-08-19T16:28:46.797918
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260819")

advanced_options = client.create_advanced_options_dict(dt_overlay="0")

platform = client.create_platform_component(name = "pf_zynq",hw_design = "$COMPONENT_LOCATION/../../../../hw/zcu102_jtag_programmer/design_2_wrapper.xsa",os = "standalone",cpu = "psu_cortexa53_0",domain_name = "standalone_psu_cortexa53_0",generate_dtb = False,advanced_options = advanced_options,architecture = "64-bit",compiler = "gcc")

platform = client.get_component(name="pf_zynq")
status = platform.build()

comp = client.create_app_component(name="app_hello_world",platform = "$COMPONENT_LOCATION/../pf_zynq/export/pf_zynq/pf_zynq.xpfm",domain = "standalone_psu_cortexa53_0",template = "hello_world")

status = platform.build()

comp = client.get_component(name="app_hello_world")
comp.build()

comp = client.create_app_component(name="app_zynq_svf_player",platform = "$COMPONENT_LOCATION/../pf_zynq/export/pf_zynq/pf_zynq.xpfm",domain = "standalone_psu_cortexa53_0")

client.delete_component(name="app_zynq_svf_player")

client.delete_component(name="componentName")

comp = client.create_app_component(name="app_svf_player",platform = "$COMPONENT_LOCATION/../pf_zynq/export/pf_zynq/pf_zynq.xpfm",domain = "standalone_psu_cortexa53_0")

status = platform.build()

comp = client.get_component(name="app_svf_player")
comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = comp.clean()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

vitis.dispose()

