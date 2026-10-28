# 2026-10-23T12:53:18.637229700
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

vitis.dispose()

vitis.dispose()

