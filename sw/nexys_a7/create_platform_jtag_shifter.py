# Create the Vitis platform for the jtag_shifter hardware and build the
# matching application.
#
#   cd sw/nexys_a7
#   vitis -s create_platform_jtag_shifter.py
#
# Inputs:  hw/nexys_a7_jtag_programmer_jtag_shifter/design_1_wrapper.xsa
#          (written by that project's create_project.tcl)
# Outputs: sw/nexys_a7/platform_jtag_shifter (standalone, microblaze_0)
#          sw/nexys_a7/app_mb_svf_player_jtag_shifter build
#
# The existing sw/nexys_a7/platform and its applications are not touched.

import os
import sys

import vitis

WS = os.path.dirname(os.path.abspath(__file__))
XSA = os.path.normpath(os.path.join(
    WS, "..", "..", "hw", "nexys_a7_jtag_programmer_jtag_shifter",
    "design_1_wrapper.xsa"))
PLATFORM = "platform_jtag_shifter"
DOMAIN = "standalone_microblaze_0"
APP = "app_mb_svf_player_jtag_shifter"

if not os.path.isfile(XSA):
    sys.exit(f"XSA not found: {XSA}. Run create_project.tcl first.")

client = vitis.create_client()
client.set_workspace(path=WS)

if os.path.isdir(os.path.join(WS, PLATFORM)):
    platform = client.get_component(name=PLATFORM)
else:
    platform = client.create_platform_component(
        name=PLATFORM,
        hw_design=XSA,
        os="standalone",
        cpu="microblaze_0",
        domain_name=DOMAIN,
    )
platform.build()

xpfm = os.path.join(WS, PLATFORM, "export", PLATFORM, PLATFORM + ".xpfm")
if not os.path.isfile(xpfm):
    sys.exit(f"Platform build did not produce {xpfm}")

app = client.get_component(name=APP)
app.build()

vitis.dispose()
