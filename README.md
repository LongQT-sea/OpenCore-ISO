## OpenCore-ISO - OpenCore for Proxmox VE / QEMU

A carefully crafted [OpenCore](https://github.com/acidanthera/opencorepkg) **ISO** image for running macOS virtual machines on **Proxmox VE** and **QEMU/KVM**.
Built from scratch with a clean, efficient architecture — no legacy configurations, no OVMF patches, no kernel patches, true vanilla macOS.

Supports every Intel-based macOS release from **[Mac OS X 10.4 Tiger](https://dortania.github.io/OpenCore-Install-Guide/installer-guide/mac-install-dmg.html#acidanthera-images)** through **[macOS 26 Tahoe](https://github.com/LongQT-sea/macos-iso-builder)**.

> [!TIP]
> This is likely the best way to run macOS on AMD hardware while retaining full hypervisor access for other VMs.
> Also overcomes a lot of AMD CPU limitations listed in the [Dortania guide](https://dortania.github.io/Anti-Hackintosh-Buyers-Guide/CPU.html#cpus-to-avoid).

Looking to run macOS on **VMware**? See https://github.com/DrDonk/OC4VM by David Parsons.

---

<details>
<summary>Table of Contents</summary>

- [Download](#download)
- [Quick Start Guide](#quick-start-guide)
  - [1. Create a New VM](#1-create-a-new-vm)
  - [2. General](#2-general)
  - [3. OS](#3-os)
  - [4. System](#4-system)
  - [5. Hard Disk](#5-hard-disk)
  - [6. CPU](#6-cpu)
  - [7. Memory](#7-memory)
  - [8. Network](#8-network)
  - [9. Finalize](#9-finalize)
  - [10. Troubleshooting](#10-troubleshooting)
- [Post-Install](#post-install)
- [macOS Tahoe Cursor Freeze Fix](#macos-tahoe-cursor-freeze-fix)
- [Contributing](#contributing)
- [Credits](#credits)
- [License & Attribution](#license--attribution)
- [Disclaimer](#disclaimer)
</details>

---

## Download

* Latest OpenCore-ISO: [LongQT-OpenCore-v0.7.iso](https://github.com/LongQT-sea/OpenCore-ISO/releases/download/v0.7/LongQT-OpenCore-v0.7.iso)
* macOS installers and recovery ISOs (only supported source): [macos-iso-builder](https://github.com/LongQT-sea/macos-iso-builder)

> [!IMPORTANT]
> These ISOs are **true CD/DVD ISO images**. Add them to your VM as a **CD/DVD drive**.<br>
> Do **NOT** change **`media=cdrom`** to **`media=disk`** in the VM config.

> [!TIP]
> Run [`Create_macOS_ISO.command`](/Create_macOS_ISO.command) inside your VM to download the full macOS installer from Apple and generate a proper DVD-format macOS installer ISO.

---

## Quick Start Guide

### 1. Create a New VM
Open the Proxmox VE web interface and create a new VM.

### 2. General

* **VM ID**: Any available ID
* **Name**: Any name you like

### 3. OS

* **ISO Image**: Select `LongQT-OpenCore-v0.X.iso`
* **Guest OS Type**: Leave as default (`Linux`)

### 4. System

* **Machine Type**: q35
* **BIOS**: OVMF (UEFI)
* **Add EFI Disk**: [✓] Enabled
* **Pre-Enroll Keys**: [✗] Untick to disable Secure Boot
* **QEMU Guest Agent**:

  * [✓] Enable for macOS 10.14 – macOS 26
  * [✗] Leave as default for macOS 10.4 – macOS 10.13

### 5. Hard Disk

The **disk bus type** depends on your needs:

* **VirtIO** – Better performance
* **SATA** – Supports TRIM/Discard for more efficient storage usage

| macOS Version            | Supports Bus Type       |
| ------------------------ | ----------------------- |
| macOS 10.15 – macOS 26   | `SATA` / `VirtIO Block` |
| macOS 10.4 – macOS 10.14 | `SATA`                  |

> [!TIP]
> Using SATA with **SSD emulation** and **Discard** enabled automatically enables TRIM — no need to run `trimforce enable`.

### 6. CPU

> [!CAUTION]
> Follow these CPU settings carefully! Incorrect CPU configuration will cause boot failure.

#### Type (Model)

| macOS Version            | Recommended CPU Type                               |
| ------------------------ | -------------------------------------------------- |
| macOS 10.11 – macOS 26   | `Skylake-Client-v4`, `Skylake-Server-v4` (AVX-512) |
| macOS 10.4 – macOS 10.10 | `Nehalem`                                          |

#### Cores
Choose based on your hardware (`power of 2`): 1 / 2 / 4 / 8 / 16 / 32 / 64
> [!TIP]
> For non-power-of-2 counts, use multiple sockets:
> | Target Cores | Cores | Sockets |
> |---|---|---|
> | 6 | 2 | 3 |
> | 12 | 4 | 3 |
> | 20 | 4 | 5 |
> | 24 | 8 | 3 |

> [!NOTE]
> **AMD CPUs:**
> * **macOS 10.4 – macOS 12**, tick [✓] **Advanced**, under **Extra CPU Flags**, turn off `pcid` and `spec-ctrl`. [^amdcpu1]
> * **macOS 13 – macOS 26**, you need to set the CPU manually via the Proxmox VE Shell[^amdcpu2], example:
>
>   ```
>   # For CPUs with AVX2 support
>   qm set [VMID] --args "-cpu Skylake-Client-v4,vendor=GenuineIntel"
>   
>   # For CPUs with AVX-512 support
>   qm set [VMID] --args "-cpu Skylake-Server-v4,vendor=GenuineIntel"
>   ```
> * If the VM fails to boot with more than 1 core, add `tsc=reliable` to the host kernel command line (`/etc/default/grub`).
> ---
> **Intel CPUs:**
> * Intel HEDT / E5-2xxx v3/v4 require overriding the CPUID `model`[^intel-hedt], example:
>
>   ```
>   qm set [VMID] --args "-cpu Broadwell-noTSX,model=158"
>   qm set [VMID] --args "-cpu Haswell-noTSX,model=158"
>   ```
> * Intel Haswell desktops need to override `stepping` when using `Haswell-noTSX`[^haswell]:
>   ```
>   qm set [VMID] --args "-cpu Haswell-noTSX,stepping=3"
>   ```
> * If you need to run nested virtualization software (such as Docker Desktop, VMware Fusion, or VirtualBox) inside the macOS VM, use QEMU named CPU model with the `+vmx` CPU flag, example:
>   ```
>   qm set [VMID] --args "-cpu Skylake-Client-v4,+vmx"
>   ```
> * Avoid using `host` passthrough CPU types[^hostcpu] — they can be [**~30% slower (single-core)** and **~44% slower (multi-core)**](https://browser.geekbench.com/v6/cpu/compare/14205183?baseline=14313138) compared to recommended CPU types.

For more details, see [QEMU CPU Guide – macOS Guests](https://github.com/LongQT-sea/qemu-cpu-guide?#macos-guests).

### 7. Memory

* **RAM**: Minimum 2 GB (4 GB or more recommended)
* [✗] Disable **Ballooning Device**

### 8. Network

Choose the correct adapter based on macOS version:

| macOS Version       | Network Adapter    |
| ------------------- | ------------------ |
| macOS 11 – 26       | `VirtIO` (default) |
| macOS 10.11 – 10.15 | `VMware vmxnet3`   |
| macOS 10.4 – 10.10  | `Intel E1000`      |

### 9. Finalize

Add an **additional CD/DVD drive** for the macOS installer or Recovery ISO, then start the VM to begin installation.

> [!TIP]
> * First-time installing macOS? Format the disk in **Disk Utility** before installing macOS.
> * **Skip iCloud login** during setup (configure it later, see [Post-Install](#post-install))

**Got it running?** Maybe give the repo a star... nah nevermind, do whatever.

### 10. Troubleshooting

If you encounter boot issues, check:
* Secure Boot is **disabled** (`Pre-Enroll Keys` unchecked)
* The ISO is mounted as a **CD/DVD**, not a disk
* Try a different **CPU model**
* For Mac OS X 10.4 Tiger, choose machine type q35, version 10.0 or older

Legacy OS X no-keyboard issue:
* Either add `-device usb-kbd` to the QEMU args or run `device_add usb-kbd` in the VM Monitor tab.

---

## Post-Install

### 1. Install OpenCore onto the macOS startup disk (macOS 10.11 – macOS 26)
   * Open **`LongQT-OpenCore`** on the Desktop and run **`Mount_EFI.command`** to mount the EFI partition.
   * Copy the **EFI** folder from **`LongQT-OpenCore/EFI_RELEASE/`** into that EFI partition. The VM will then boot from its own disk.
   * Run **`Install_Python3.command`**. Many apps and scripts need Python 3.
   * Copy **`Mount_EFI.command`**, **`ProperTree`**, and **`GenSMBIOS`** to the Desktop. You will need them to edit **`config.plist`**.
   * Remove the **LongQT-OpenCore** ISO from the VM **Hardware** tab.

### 2. To enable iCloud, iMessage, and other iServices
   * Follow [Dortania iServices](https://dortania.github.io/OpenCore-Post-Install/universal/iservices.html) guide to generate your own SMBIOS.
   * On macOS 15 and macOS 26, install [VMHide.kext](https://github.com/Carnations-Botanica/VMHide)

### 3. For smooth GUI performance and 3D acceleration
* Pass through a supported Intel iGPU or dGPU:
  * **Intel iGPU passthrough:** see [LongQT-sea/intel-igpu-passthru](https://github.com/LongQT-sea/intel-igpu-passthru)
  * **dGPU passthrough:** make sure your dGPU is supported, see [Dortania GPU Buyers Guide](https://dortania.github.io/GPU-Buyers-Guide/modern-gpus/amd-gpu.html#native-amd-gpus)

> [!IMPORTANT]
> For PCIe/dGPU passthrough on a **q35** machine:
> * Disable Resizable BAR / Smart Access Memory in UEFI/BIOS.
> * Disable QEMU ACPI-based PCI hotplug (revert to native PCIe hotplug). Run this in the Proxmox shell:
> ```sh
> clear; read -p "Enter your macOS VM ID number: " VMID; \
> ARGS="$(qm config $VMID | grep ^args: | cut -d' ' -f2-)"; \
> qm set $VMID -args "$ARGS -global ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off"
> ```

> [!TIP]
> If you need ReBAR enabled (for multi-GPU systems), set **BAR 0** of the dGPU you want to pass through to **256 MB**:
> ```sh
> # List current GPUs and resizable BAR sizes:
> lspci -d ::0300 -vv | grep -E 'VGA|BAR 0'
>
> # Unbind from whichever driver currently owns it (amdgpu, vfio-pci, ...):
> echo 0000:01:00.0 > /sys/bus/pci/drivers/vfio-pci/unbind
>
> # Set BAR 0 size: 8 = 256MB, 9 = 512MB, 10 = 1GB
> echo 8 > /sys/bus/pci/devices/0000:01:00.0/resource0_resize
> ```

> [!TIP]
> For a dummy sound device on modern macOS (e.g. for Parsec, Sunshine/Moonlight), run this in the Proxmox shell:
> ```sh
> clear; read -p "Enter your macOS VM ID number: " VMID; \
> ARGS="$(qm config $VMID | grep ^args: | cut -d' ' -f2-)"; \
> qm set $VMID -args "$ARGS -device virtio-sound,audiodev=dummy -audiodev none,id=dummy"
> ```

> [!TIP]
> To disable SIP, press <kbd>Spacebar</kbd> in the OpenCore boot menu and select **Toggle SIP**.

---

## macOS Tahoe Cursor Freeze Fix

On **macOS 26**, the cursor may randomly freeze. Quick workaround: toggle **Use tablet for pointer** in the VM's **Options** tab.

Better fix: disable **Use tablet for pointer** in the VM's **Options** tab, then run this in the Proxmox shell to use **`virtio-tablet-pci`** instead:
```sh
clear; read -p "Enter your macOS VM ID number: " VMID; \
ARGS="$(qm config $VMID | grep ^args: | cut -d' ' -f2-)"; \
qm set $VMID -args "$ARGS -device virtio-tablet"
```

> [!NOTE]
> With **`virtio-tablet-pci`**, middle-click acts as right-click in the VM.

Most reliable: pass through a physical mouse and keyboard along with an iGPU or dGPU. Otherwise, use remote desktop, e.g. **VNC Screen Sharing** (Settings → General → Sharing) or **Chrome Remote Desktop**.

---

## Contributing
Contributions are welcome! Please feel free to submit a pull request. For major changes, open a **Discussion** first to discuss what you would like to change.

## Credits
- [Acidanthera](https://github.com/acidanthera) team for OpenCorePkg and kexts.
- [CorpNewt](https://github.com/corpnewt) for ProperTree, GenSMBIOS.
- [Dortania](https://dortania.github.io/) for comprehensive guides.

## License & Attribution

This project is licensed under the MIT License (see [LICENSE](LICENSE) file).

It also includes components from Acidanthera and other developers, each with their own licenses. All third-party components retain their original licenses.

**If you create content using this project** (videos, blog posts, tutorials, articles):
- Please link back to this repository: `https://github.com/LongQT-sea/OpenCore-ISO`
- Mention that detailed **instructions** are in this GitHub repo.

Thank you for respecting the work that went into this project!

## Disclaimer
This project is provided "as is", without any warranties, and is intended for educational, research, and security testing purposes. In no event shall the authors or contributors be liable for any direct, indirect, incidental, special, or consequential damages arising from use of the project, even if advised of the possibility of such damages.

All product names, trademarks, and registered trademarks are property of their respective owners. All company, product, and service names used in this repository are for identification purposes only.

[^amdcpu1]: The `pcid` and `spec-ctrl` flags are Intel-only CPU features.
[^amdcpu2]: On macOS 13–26 running on AMD processors, these CPU flags `enforce,+kvm_pv_eoi,+kvm_pv_unhalt` (the default in Proxmox) prevent macOS from booting, so we override them with custom `-cpu` args.
[^intel-hedt]: Override the CPUID model to one used in real Macs (e.g., `model=158`, which corresponds to the Coffee Lake CPUID model).
[^haswell]: QEMU Haswell-noTSX CPU model has `stepping=4`, but macOS expects an earlier stepping (below 4).
[^hostcpu]: This is one of the main reasons I created this project. All other project use `host` when running on supported Intel CPUs.
