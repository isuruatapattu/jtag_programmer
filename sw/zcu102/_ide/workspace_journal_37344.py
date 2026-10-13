# 2026-10-08T12:41:19.595275800
import vitis

client = vitis.create_client()
client.set_workspace(path="zcu102")

comp = client.get_component(name="app_hello_world")
comp.build()

comp.build()

comp.build()

status = comp.clean()

comp.build()

comp.build()

comp.build()

platform = client.get_component(name="platform")
status = platform.build()

status = comp.clean()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

vitis.dispose()

