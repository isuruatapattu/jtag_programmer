# 2026-11-03T22:15:13.129137400
import vitis

client = vitis.create_client()
client.set_workspace(path="nexys_a7")

comp = client.get_component(name="app_mb_svf_player")
status = comp.clean()

platform = client.get_component(name="platform")
status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

