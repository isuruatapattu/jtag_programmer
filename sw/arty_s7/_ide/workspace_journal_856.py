# 2026-10-23T11:34:16.215459500
import vitis

client = vitis.create_client()
client.set_workspace(path="arty_s7")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_mb_jtag_verifier")
comp.build()

vitis.dispose()

