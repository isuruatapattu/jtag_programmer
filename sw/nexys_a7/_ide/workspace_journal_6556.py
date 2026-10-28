# 2026-10-23T11:32:49.194260100
import vitis

client = vitis.create_client()
client.set_workspace(path="nexys_a7")

vitis.dispose()

