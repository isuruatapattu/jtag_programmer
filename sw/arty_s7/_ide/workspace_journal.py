# 2026-10-22T16:15:51.805408300
import vitis

client = vitis.create_client()
client.set_workspace(path="arty_s7")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.create_app_component(name="hello_world",platform = "$COMPONENT_LOCATION/../platform/export/platform/platform.xpfm",domain = "standalone_microblaze_0",template = "hello_world")

status = platform.build()

comp = client.get_component(name="hello_world")
comp.build()

client.delete_component(name="platform")

client.delete_component(name="componentName")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../../hw/arty_s7_jtag_programmer/design_1_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

status = platform.build()

status = platform.build()

comp.build()

comp = client.create_app_component(name="app_mb_jtag_verifier",platform = "$COMPONENT_LOCATION/../platform/export/platform/platform.xpfm",domain = "standalone_microblaze_0")

