#!/usr/bin/env python3
import json
from pathlib import Path
import shutil  # Imported for directory removal functions


# List of kernel directories to be deleted
kernels_to_delete = ["xcpp17", "xcpp20", "xcpp23", "xc11", "xc17"]

print("--- Deleting Unwanted Kernel Directories ---")
for kernel_name in kernels_to_delete:
    kernel_path = Path(f".pixi/envs/kernels/share/jupyter/kernels/{kernel_name}")
    if kernel_path.exists() and kernel_path.is_dir():
        print(f"Deleting directory: {kernel_path}")
        shutil.rmtree(kernel_path)
    else:
        print(f"Directory not found, skipping: {kernel_path}")

print("--- Deletion Complete ---\n")

# Original script logic to update remaining kernels
print("--- Updating Display Names for Remaining Kernels ---")
kernels_to_update = [ ("Python","xpython"), 
                      ("OCaml","xocaml"), 
                      ("SQL","xsqlite"), 
                      ("C","xc23"), 
                      ("JavaScript","xjavascript"),
                      ("R","xr"),                     
                      ("Octave","xoctave"),
                      ("Lua","xlua")
                      ]

for display_name, kernel in kernels_to_update:
    kernel_json = Path(f".pixi/envs/kernels/share/jupyter/kernels/{kernel}/kernel.json")
    
    # Check if the kernel.json file exists before trying to modify it
    if kernel_json.exists():
        try:
            data = json.loads(kernel_json.read_text())
            data["display_name"] = display_name
            kernel_json.write_text(json.dumps(data, indent=2))
            print(f"Updated display name for '{kernel}' to '{display_name}'")
        except Exception as e:
            print(f"Could not update {kernel}: {e}")
    else:
        print(f"Kernel '{kernel}' not found, skipping update.")