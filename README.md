# axioo-hype7-survival-kit

Definitive Linux stability guide, hardware quirks analysis, and verified kernel tuning for the **Axioo HYPE 7 AMD (X7-2)** (AMD Ryzen 7 5825U / Barcelo APU).

---

## Overview

The **Axioo HYPE 7 AMD (X7-2)** is a budget-friendly laptop featuring an octa-core AMD Ryzen 7 5825U processor and a BALLISTA ADV NVMe SSD. While performing well under Windows, running modern Linux distributions out-of-the-box (Arch Linux, Omarchy, Debian, Ubuntu, Fedora) frequently triggers two severe hardware/firmware failures:

1. **Random Spontaneous Reboots:** The laptop abruptly resets without a kernel panic while typing, browsing, or sitting idle.
2. **Suspend-to-BIOS Loop:** Putting the laptop to sleep (closing the lid or `systemctl suspend`) triggers an immediate reboot that lands directly into the **UEFI BIOS Setup**, because the NVMe SSD has dropped off the PCIe bus.

This repository documents the underlying root causes from first principles and provides the exact, verified configuration needed to achieve 100% stability.

---

## Hardware Profile

| Component | Specification |
| :--- | :--- |
| **Model** | Axioo HYPE 7 AMD X7-2 |
| **CPU** | AMD Ryzen 7 5825U (8 Cores / 16 Threads, Zen 3 / Barcelo APU) |
| **GPU** | AMD Radeon Graphics (Barcelo iGPU) |
| **SSD** | BALLISTA ADV 1TB NVMe M.2 SSD |
| **CPU Driver** | `amd-pstate-epp` (CPPC Autonomous) |
| **Default Sleep Mode** | S0ix (Modern Standby / `s2idle`) |

---

## Symptoms and Diagnostic Summary

### 1. Spontaneous Reboots (The CPPC / Idle Crash)
* **Symptom:** The machine restarts instantly without any log entry in `dmesg` or `journalctl`.
* **Cause:** The use of legacy forum advice such as `idle=nomwait` or `processor.max_cstate=5` breaks AMD CPPC core synchronization. When `MWAIT` is replaced with legacy `HLT`, core voltage drops below the stability threshold during idle transitions, causing a hardware watchdog reset.
* **Fix:** Completely remove `idle=nomwait` and `processor.max_cstate`. Let `amd-pstate-epp` operate autonomously.

### 2. Suspend Failure, BIOS Loop, & Spinning Fans
* **Symptom:** Suspending causes an instant reboot that drops directly into the BIOS Setup utility, OR under `s2idle` the cooling fan and keyboard backlight stay continuously active during sleep.
* **Cause:**
  - The stock BALLISTA ADV NVMe controller fails to resume from PCIe Active State Power Management (ASPM) and Autonomous Power State Transitions (APST).
  - The SSD disappears from the PCIe bus. When the system resets, the UEFI POST probe detects zero bootable storage devices and automatically redirects to BIOS Setup.
  - Furthermore, using `s2idle` (Modern Standby) leaves the Embedded Controller (EC) in S0 state, keeping the cooling fan spinning and keyboard backlight powered during sleep.
* **Fix:** Disable APST via `nvme_core.default_ps_max_latency_us=0`, disable PCIe ASPM via `pcie_aspm=off`, and enforce true S3 sleep via `mem_sleep_default=deep`.

For the complete technical breakdown, see [docs/root-cause.md](docs/root-cause.md).

---

## The Tested Working Fix

Add the following kernel parameters to your bootloader configuration:

```text
nvme_core.default_ps_max_latency_us=0 pcie_aspm=off mem_sleep_default=deep
```

### Parameter Breakdown:

* **`nvme_core.default_ps_max_latency_us=0`**  
  Disables NVMe Autonomous Power State Transitions (APST). Keeps the BALLISTA SSD controller active, preventing controller crashes when transitioning into low-power states.
* **`pcie_aspm=off`**  
  Disables PCIe Active State Power Management. Prevents PCIe link power throttling on the SSD bus, eliminating the bug where the drive drops off the bus entirely.
* **`mem_sleep_default=deep`**  
  Enforces ACPI S3 deep sleep. Physically asserts `SLP_S3#` to completely shut down the cooling fan, keyboard backlight LEDs, and display panel, preventing bag overheat and battery drain.

> **CRITICAL WARNING:**  
> Ensure that `idle=nomwait` and `processor.max_cstate=...` are **COMPLETELY REMOVED** from your kernel command line.

---

## Implementation Guides

### 1. Limine Bootloader (Omarchy / Arch Linux)

If you are using Limine with `limine-entry-tool`, edit `/etc/default/limine`:

```bash
sudo nvim /etc/default/limine
```

Ensure `KERNEL_CMDLINE[default]` includes the parameters:

```bash
ESP_PATH="/boot"
KERNEL_CMDLINE[default]+="nvme_core.default_ps_max_latency_us=0 pcie_aspm=off mem_sleep_default=deep initramfs_async=0 quiet splash"
BOOT_ORDER="linux-omarchy, linux-omarchy-*, *, *fallback, Snapshots"
```

Rebuild your boot entries:
```bash
sudo limine-entry-tool
```

### 2. GRUB Bootloader (Debian / Ubuntu / Fedora)

Edit `/etc/default/grub`:

```bash
sudo nvim /etc/default/grub
```

Append the parameters to `GRUB_CMDLINE_LINUX_DEFAULT`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet nvme_core.default_ps_max_latency_us=0 pcie_aspm=off mem_sleep_default=deep"
```

Update GRUB:
```bash
# Debian / Ubuntu:
sudo update-grub

# Arch / Fedora:
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

---

## Diagnostic Script

This repository includes a standalone diagnostic script to audit your hardware profile, sleep mode, and kernel command line.

```bash
git clone https://github.com/muadzhdz/axioo-hype7-survival-kit.git
cd axioo-hype7-survival-kit
./scripts/check-hardware.sh
```

Example verified output:
```text
=== Axioo Hype 7 AMD (X7-2) Linux Hardware Diagnostic ===

1. System Profile:
   Vendor       : Axioo
   Product Name : HYPE 7 AMD X7-2
   BIOS Version : 23.06
   Processor    : AMD Ryzen 7 5825U with Radeon Graphics
   CPU Driver   : amd-pstate-epp

2. NVMe Storage:
nvme0n1 BALLISTA ADV 953.9G nvme

3. ACPI Sleep Mode:
   Available modes: s2idle [deep]
   Status         : OK (True S3 deep sleep active - fan, keyboard backlight, and panel fully power down)

4. Kernel Command Line Audit:
   [OK] No known toxic kernel parameters detected.

5. Recommended Stability Parameters:
   [OK] nvme_core.default_ps_max_latency_us=0 is active (APST power-state sleep disabled).
   [OK] pcie_aspm=off is active (PCIe link power management disabled).
   [OK] mem_sleep_default=deep is active (True S3 sleep with fan/backlight power cut).
```

---

## Authors & Maintenance

* **Mu'adz Hudzaifah** ([@muadzhdz](https://github.com/muadzhdz))
* Developed on Omarchy (Arch Linux / Hyprland Workstation)

---

## License

MIT License. Free to use, fork, and distribute for all Linux users.
