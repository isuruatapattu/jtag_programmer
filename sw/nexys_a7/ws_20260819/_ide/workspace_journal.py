# 2026-08-19T16:39:53.901903
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260819")

platform = client.get_component(name="pf_nexys_a7")
status = platform.build()

comp = client.get_component(name="app_mb_svf_player")
comp.build()

vitis.dispose()

