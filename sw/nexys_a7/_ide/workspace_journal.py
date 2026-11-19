# 2026-11-13T14:51:34.102327600
import vitis

client = vitis.create_client()
client.set_workspace(path="nexys_a7")

platform = client.create_platform_component(name = "platform_custom_gpio",hw_design = "$COMPONENT_LOCATION/../../../hw/nexys_a7_jtag_programmer_custom_gpio/design_1_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

comp = client.clone_component(name="app_mb_svf_player",new_name="app_mb_svf_player_custom_gpio")

platform = client.get_component(name="platform_custom_gpio")
status = platform.build()

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_mb_svf_player_custom_gpio")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

vitis.dispose()

