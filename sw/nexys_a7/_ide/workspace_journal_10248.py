# 2026-10-22T16:47:37.350487
import vitis

client = vitis.create_client()
client.set_workspace(path="nexys_a7")

comp = client.get_component(name="app_mb_svf_player")
comp.build()

comp.build()

status = comp.clean()

platform = client.get_component(name="platform")
status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

