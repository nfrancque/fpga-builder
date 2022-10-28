"""
Copyright 2021 Intrepid Control Systems
Author: Nathan Francque

FPGA build/deploy script

"""

from pathlib import Path
from fpga_builder import builder

FILE_DIR = Path(__file__).parent.absolute()

DEVICE_NAMES = [
    "device_a",
    "device_b",
]

# TCL scripts for generating Vivado projects
TCL_FILES = {
    "device_a": FILE_DIR / "device_a/build.tcl",
    "device_b": FILE_DIR / "device_b/build.tcl",
}

VIVADO_VERSIONS = {
    "radethermax1g": "2019.1",
}

# deploy to Xilinx SDK hardware platform directory
DEPLOY_DIRS = {
    "device_a": FILE_DIR / "../projects/device_a/hardware",
    "device_b": FILE_DIR / "../projects/device_b/hardware",
}

builder.build_default(
    DEVICE_NAMES,
    TCL_FILES,
    deploy_hw_dirs=DEPLOY_DIRS,
    vivado_versions=VIVADO_VERSIONS,
)
