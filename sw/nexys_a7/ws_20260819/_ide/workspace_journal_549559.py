# 2026-08-19T12:26:11.754341
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260819")

advanced_options = client.create_advanced_options_dict(dt_overlay="0")

platform = client.create_platform_component(name = "pf_nexys_a7",hw_design = "$COMPONENT_LOCATION/../../../../hw/nexys_a7_jtag_programmer_2025.01/design_1_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",generate_dtb = False,advanced_options = advanced_options,compiler = "gcc")

comp = client.create_app_component(name="app_mb_svf_player",platform = "$COMPONENT_LOCATION/../pf_nexys_a7/export/pf_nexys_a7/pf_nexys_a7.xpfm",domain = "standalone_microblaze_0")

comp = client.get_component(name="app_mb_svf_player")
status = comp.import_files(from_loc="", files=["/users2/athapatt/my_ws/jtag_programmer/sw/nexys_a7/ws_20260818/app_mb_svf_player/src", "/users2/athapatt/my_ws/jtag_programmer/sw/nexys_a7/ws_20260818/app_mb_svf_player/external", "/users2/athapatt/my_ws/jtag_programmer/sw/nexys_a7/ws_20260818/app_mb_svf_player/build", "/users2/athapatt/my_ws/jtag_programmer/sw/nexys_a7/ws_20260818/app_mb_svf_player/assets"])

platform = client.get_component(name="pf_nexys_a7")
status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

status = platform.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

vitis.dispose()

