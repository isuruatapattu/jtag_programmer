# 2026-08-19T14:30:12.422645
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260819")

comp = client.get_component(name="app_mb_svf_player")
status = comp.clean()

platform = client.get_component(name="pf_nexys_a7")
status = platform.build()

comp.build()

