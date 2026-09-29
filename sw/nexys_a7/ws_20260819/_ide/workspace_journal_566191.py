# 2026-08-19T14:26:46.489301
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260819")

platform = client.get_component(name="pf_nexys_a7")
status = platform.build()

comp = client.get_component(name="app_mb_svf_player")
status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

vitis.dispose()

