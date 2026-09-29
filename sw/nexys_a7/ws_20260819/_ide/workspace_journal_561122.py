# 2026-08-19T14:01:44.843064
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260819")

platform = client.get_component(name="pf_nexys_a7")
status = platform.build()

status = platform.build()

comp = client.get_component(name="app_mb_svf_player")
comp.build()

client.delete_component(name="app_mb_svf_player")

client.delete_component(name="componentName")

client.delete_component(name="componentName")

client.delete_component(name="componentName")

client.delete_component(name="componentName")

client.delete_component(name="componentName")

comp = client.create_app_component(name="app_mb_svf_player",platform = "$COMPONENT_LOCATION/../pf_nexys_a7/export/pf_nexys_a7/pf_nexys_a7.xpfm",domain = "standalone_microblaze_0")

status = platform.build()

comp.build()

vitis.dispose()

