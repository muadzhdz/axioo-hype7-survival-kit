# Deep Root Cause Analysis: Hardware, Kernel, & ACPI Failures

This document details the underlying engineering causes behind the spontaneous reboots and suspend failures on the **Axioo HYPE 7 AMD (X7-2)** running Linux.

---

## 1. The AMD Zen 3 (Barcelo) CPPC & Idle Collision

### The Symptom:
The laptop suddenly restarts without warning while idle or performing light workloads (browsing, editing text). No kernel panic, OOPS, or crash dump is recorded to disk.

### The Mechanism:
The AMD Ryzen 7 5825U is an octa-core Zen 3 (Barcelo/Cezanne refresh) APU utilizing AMD's Collaborative Power and Performance Control (CPPC) driver (`amd-pstate-epp`).

1. **How Zen 3 Coordinates Core States:**  
   In modern AMD processors, CPU cores autonomously negotiate frequency and C-states via the System Management Unit (SMU). When a core goes idle, it relies on the `MWAIT` instruction to enter power-gated states while maintaining interconnect coherency.
2. **The `idle=nomwait` Trap:**  
   Common forum advice for old 1st-generation Ryzen desktops suggests passing `idle=nomwait` to resolve lockups. On Zen 3 with `amd-pstate-epp`, this is catastrophic:
   - Disabling `MWAIT` forces the kernel to fallback to the legacy x86 `HLT` instruction for the idle loop.
   - Under `HLT`, the CPPC firmware cannot properly predict or synchronize transient core sleep and wake requests across CCX clusters.
   - When one core idles and drops its voltage (Vcore) while another core bursts to boost frequency, the core regulator drops below the minimum operating threshold (~0.7V).
   - This triggers an immediate hardware Machine Check Exception (MCE) or power supply supervisor reset. The system restarts instantaneously before any kernel buffer can be flushed to disk.
3. **The `processor.max_cstate=5` Myth:**  
   `processor.max_cstate` is designed for Intel ACPI implementations (which feature C1 through C10 states). AMD Zen processors do not have a C5 state; they operate in C0, C1/C1E, and C2 (CC6). Passing Intel C-state numbers to an AMD Barcelo CPU corrupts the kernel ACPI processor driver state machine.

---

## 2. ACPI Modern Standby (S0ix / s2idle) vs. True S3 (`deep`)

### The Dilemma:
* Under `s2idle` (Modern Standby), the Embedded Controller (EC) keeps power rails active because the SoC remains in an S0 idle state. On the Axioo Hype 7, this causes the **cooling fan to continue spinning** and the **keyboard backlight to remain illuminated** during sleep. This leads to battery drain and dangerous thermal buildup when carried in a backpack.
* Under `deep` (ACPI S3), the chipset pulls the hardware `SLP_S3#` line low, which physically cuts power to the fan motor, keyboard backlight LEDs, and display panel, keeping only RAM in self-refresh mode.

### Why Did S3 Sleep Fail Previously?
Earlier reports incorrectly attributed S3 sleep failures to broken ACPI DSDT tables or EC firmware limitations. In reality, **S3 sleep failure was entirely caused by the BALLISTA NVMe controller dropping off the PCIe bus (see Section 3 below)**.

When waking from S3 without PCIe ASPM workarounds, the NVMe SSD failed to re-enumerate before the kernel attempted disk I/O, resulting in an immediate kernel panic, system reset, and boot-to-BIOS loop.

Once PCIe ASPM and APST are stabilized (`pcie_aspm=off` and `nvme_core.default_ps_max_latency_us=0`), **ACPI S3 (`mem_sleep_default=deep`) functions with 100% stability**, providing true hardware sleep where fans and LEDs shut down completely.

---

## 3. The BALLISTA ADV NVMe Controller Bug

### The Symptom:
Why does the reboot land directly into the **BIOS Setup Utility** instead of the bootloader (Limine/GRUB)?

### The Mechanism:
The stock storage drive is a **BALLISTA ADV 1TB NVMe SSD**, an entry-level OEM drive with non-standard controller firmware:

1. **Kernel Log Evidence:**  
   ```text
   nvme nvme0: Ignoring bogus Namespace Identifiers
   nvme nvme0: AWUPF ignored, only NAWUPF accepted
   ```
2. **PCIe ASPM & APST Failure:**  
   When the PCIe bus enters Active State Power Management (ASPM L1 / L1.2) or the NVMe controller transitions into low-power states via Autonomous Power State Transition (APST), the controller firmware fails to wake in time.
3. **PCIe Link Drop:**  
   The NVMe drive drops off the PCIe bus entirely. When the system resets, the SSD controller requires several seconds to perform an internal power cycle.
4. **UEFI POST Detection:**  
   When the UEFI BIOS initializes and probes the PCIe bus for bootable media, the SSD has not yet re-enumerated. Under standard UEFI firmware specifications, when zero bootable devices are detected, the firmware **immediately falls back to the BIOS Setup Utility interface**.

---

## 4. The Unified Solution

By enforcing three targeted kernel parameters, all failure modes are eliminated:

| Parameter | Function | Solves |
| :--- | :--- | :--- |
| **`nvme_core.default_ps_max_latency_us=0`** | Disables NVMe APST deep sleep | Prevents Ballista controller freeze |
| **`pcie_aspm=off`** | Disables PCIe Active State Power Management | Prevents SSD drop-off from PCIe bus |
| **`mem_sleep_default=deep`** | Enforces ACPI S3 deep sleep | Powers down fan, keyboard backlight, and panel |
| **Purge `idle=nomwait` & `processor.max_cstate`** | Restores autonomous CPPC `amd-pstate-epp` | Fixes random spontaneous reboots |
