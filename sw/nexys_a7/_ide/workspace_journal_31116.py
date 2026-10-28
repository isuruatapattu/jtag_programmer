# 2026-10-28T13:20:08.171793800
import vitis

client = vitis.create_client()
client.set_workspace(path="nexys_a7")

vitis.dispose()

