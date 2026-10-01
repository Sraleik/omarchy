echo "Keep the Micron 2400 NVMe SSD out of its APST power states"

# Look for the parameter rather than for the leaf's own drop-in: a hand-written
# one, or /etc/default/limine, may already carry it. The rebuild is tracked
# separately because the drop-in lands before limine-mkinitcpio runs, so a
# failed rebuild must not look complete to the retry; a kernel already booted
# with a parameter that was already configured needs no rebuild at all.
dropin_dir="${OMARCHY_LIMINE_DROPIN_DIR:-/etc/limine-entry-tool.d}"
limine_conf="${OMARCHY_KERNEL_LIMINE_CONF:-/etc/default/limine}"
running_cmdline="${OMARCHY_RUNNING_CMDLINE:-/proc/cmdline}"
rebuild_marker="${OMARCHY_LIMINE_REBUILD_MARKER:-/var/lib/omarchy/migrations/1789462366}"

omarchy-cmd-present limine-mkinitcpio || exit 0
omarchy-hw-micron-2400-nvme || exit 0

wrote_dropin=0

if ! grep -rqs "nvme_core.default_ps_max_latency_us=" "$dropin_dir" "$limine_conf"; then
  source "$OMARCHY_PATH/install/hardware/fix-micron-2400-apst.sh"
  wrote_dropin=1
fi

# A drop-in written just now is in no boot image yet, even when this boot had
# the parameter typed in at the Limine menu to get the machine up.
if [[ ! -e $rebuild_marker ]] &&
  { (( wrote_dropin )) || ! grep -qs "nvme_core.default_ps_max_latency_us=" "$running_cmdline"; }; then
  sudo limine-mkinitcpio
  sudo install -Dm644 /dev/null "$rebuild_marker"
  omarchy-state set reboot-required
fi
