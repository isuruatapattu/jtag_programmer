# 2026-08-19T12:23:12.869864
import vitis

client = vitis.create_client()
client.set_workspace(path="ws_20260818")

comp = client.get_component(name="pf_nexys_a7")
comp.build()

platform = client.get_component(name="pf_nexys_a7")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../../../hw/nexys_a7_jtag_programmer_2025.01/design_1_wrapper.xsa")

status = platform.build()

comp = client.get_component(name="app_mb_svf_player")
comp.build()

status = platform.build()

vitis.dispose()

