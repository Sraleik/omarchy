echo "Keep the Micron 2400 NVMe SSD out of its APST power states"

# Hardware setup only runs during ISO finalization, so existing installs get
# the workaround here. The parameter may already be booted from a hand-written
# drop-in, and another user's migration may have applied this one: check the
# drop-in directory for the parameter itself rather than for this file, so the
# boot image is rebuilt once and only when it is missing.
dropin_dir="${OMARCHY_LIMINE_DROPIN_DIR:-/etc/limine-entry-tool.d}"

if omarchy-hw-micron-2400-nvme &&
  ! grep -qs "nvme_core.default_ps_max_latency_us=" "$dropin_dir"/*.conf; then
  source "$OMARCHY_PATH/install/hardware/fix-micron-2400-apst.sh"
  sudo limine-mkinitcpio
  omarchy-state set reboot-required
fi
