# 2026-10-08T13:08:04.562299300
import vitis

client = vitis.create_client()
client.set_workspace(path="zcu102")

comp = client.get_component(name="app_hello_world")
status = comp.clean()

platform = client.get_component(name="platform")
status = platform.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp = client.get_component(name="app_svf_player")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

