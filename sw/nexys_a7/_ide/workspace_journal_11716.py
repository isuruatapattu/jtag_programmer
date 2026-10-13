# 2026-10-08T13:38:18.615236600
import vitis

client = vitis.create_client()
client.set_workspace(path="nexys_a7")

comp = client.get_component(name="app_mb_jtag_verifier")
status = comp.clean()

platform = client.get_component(name="platform")
status = platform.build()

comp.build()

