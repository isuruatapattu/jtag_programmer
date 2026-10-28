# 2026-10-23T18:38:03.424221600
import vitis

client = vitis.create_client()
client.set_workspace(path="nexys_a7")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_mb_jtag_verifier")
comp.build()

comp = client.get_component(name="app_mb_svf_player")
status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

vitis.dispose()

