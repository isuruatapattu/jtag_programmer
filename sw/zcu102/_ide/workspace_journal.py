# 2026-10-13T10:19:10.780478900
import vitis

client = vitis.create_client()
client.set_workspace(path="zcu102")

platform = client.get_component(name="platform_v2")
status = platform.build()

comp = client.get_component(name="app_svf_player")
comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

