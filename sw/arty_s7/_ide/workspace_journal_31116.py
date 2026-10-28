# 2026-10-23T12:53:51.963630300
import vitis

client = vitis.create_client()
client.set_workspace(path="arty_s7")

comp = client.get_component(name="app_mb_jtag_verifier")
status = comp.clean()

platform = client.get_component(name="platform")
status = platform.build()

comp.build()

status = comp.clean()

status = comp.clean()

status = platform.build()

comp.build()

