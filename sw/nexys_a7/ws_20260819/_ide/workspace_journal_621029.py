# 2026-08-19T15:20:10.651546
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260819")

platform = client.get_component(name="pf_nexys_a7")
status = platform.build()

comp = client.get_component(name="app_mb_svf_player")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

