#!/usr/bin/env bash
# axioo-hype7-survival-kit - Hardware & Kernel Diagnostics Script
set -euo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}=== Axioo Hype 7 AMD (X7-2) Linux Hardware Diagnostic ===${RESET}\n"

# 1. Hardware Identification
VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
BIOS_VER=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "Unknown")
CPU_MODEL=$(lscpu | awk -F: '/Model name/ {print $2}' | sed 's/^[ \t]*//' || echo "Unknown")
SCALING_DRIVER=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "Unknown")

echo -e "${BOLD}1. System Profile:${RESET}"
echo -e "   Vendor       : $VENDOR"
echo -e "   Product Name : $PRODUCT"
echo -e "   BIOS Version : $BIOS_VER"
echo -e "   Processor    : $CPU_MODEL"
echo -e "   CPU Driver   : $SCALING_DRIVER"

# 2. Storage / NVMe
echo -e "\n${BOLD}2. NVMe Storage:${RESET}"
lsblk -d -o NAME,MODEL,SIZE,TRAN | grep -i nvme || echo "   No NVMe devices detected."

# 3. Sleep Mode State
echo -e "\n${BOLD}3. ACPI Sleep Mode:${RESET}"
if [[ -f /sys/power/mem_sleep ]]; then
  MEM_SLEEP=$(cat /sys/power/mem_sleep)
  echo -e "   Available modes: $MEM_SLEEP"
  if [[ "$MEM_SLEEP" =~ \[deep\] ]]; then
    echo -e "   Status         : ${GREEN}OK (True S3 deep sleep active - fan, keyboard backlight, and panel fully power down)${RESET}"
  elif [[ "$MEM_SLEEP" =~ \[s2idle\] ]]; then
    echo -e "   Status         : ${YELLOW}NOTICE (Modern Standby s2idle active - fan and keyboard backlight may remain powered)${RESET}"
  fi
else
  echo -e "   ${YELLOW}/sys/power/mem_sleep not supported or unavailable.${RESET}"
fi

# 4. Kernel Command Line Audit
echo -e "\n${BOLD}4. Kernel Command Line Audit:${RESET}"
CMDLINE=$(cat /proc/cmdline)
echo -e "   Current cmdline: ${CYAN}${CMDLINE}${RESET}\n"

# Audit dangerous parameters
DANGEROUS=0
if [[ "$CMDLINE" =~ idle=nomwait ]]; then
  echo -e "   [${RED}FAIL${RESET}] Found 'idle=nomwait' - causes AMD Zen 3 CPPC core synchronization crash & spontaneous reboot!"
  DANGEROUS=1
fi
if [[ "$CMDLINE" =~ processor\.max_cstate ]]; then
  echo -e "   [${RED}FAIL${RESET}] Found 'processor.max_cstate' - invalid C-state restriction for AMD Zen 3, induces core instability!"
  DANGEROUS=1
fi

if (( DANGEROUS == 0 )); then
  echo -e "   [${GREEN}OK${RESET}] No known toxic kernel parameters detected."
fi

# Audit recommended parameters
echo -e "\n${BOLD}5. Recommended Stability Parameters:${RESET}"
if [[ "$CMDLINE" =~ nvme_core\.default_ps_max_latency_us=0 ]]; then
  echo -e "   [${GREEN}OK${RESET}] nvme_core.default_ps_max_latency_us=0 is active (APST power-state sleep disabled)."
else
  echo -e "   [${YELLOW}MISSING${RESET}] nvme_core.default_ps_max_latency_us=0 (recommended to prevent Ballista NVMe controller freeze)."
fi

if [[ "$CMDLINE" =~ pcie_aspm=off ]]; then
  echo -e "   [${GREEN}OK${RESET}] pcie_aspm=off is active (PCIe link power management disabled)."
else
  echo -e "   [${YELLOW}MISSING${RESET}] pcie_aspm=off (recommended to prevent NVMe dropping off PCIe bus)."
fi

if [[ "$CMDLINE" =~ mem_sleep_default=deep ]]; then
  echo -e "   [${GREEN}OK${RESET}] mem_sleep_default=deep is active (True S3 sleep with fan/backlight power cut)."
else
  echo -e "   [${YELLOW}MISSING${RESET}] mem_sleep_default=deep (recommended to power down fan and keyboard backlight in sleep)."
fi

echo -e "\n${BOLD}${CYAN}Diagnostic complete.${RESET}"
