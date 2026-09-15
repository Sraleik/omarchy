#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

detector="$ROOT/bin/omarchy-hw-micron-2400-nvme"
leaf="$ROOT/install/hardware/fix-micron-2400-apst.sh"
all="$ROOT/install/hardware/all.sh"
migration=$(grep -l "fix-micron-2400-apst" "$ROOT"/migrations/*.sh | head -1)
parameter='KERNEL_CMDLINE[default]+=" nvme_core.default_ps_max_latency_us=0"'

grep -q 'run_logged .*hardware/fix-micron-2400-apst.sh' "$all" ||
  fail "the APST workaround runs during hardware setup"
pass "the APST workaround runs during hardware setup"

[[ -n $migration ]] || fail "a migration applies the workaround on existing installs"
pass "a migration applies the workaround on existing installs"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$test_tmp/bin/limine-mkinitcpio" <<'SH'
#!/bin/bash
printf 'limine-mkinitcpio\n' >>"$CALL_LOG"
SH

cat >"$test_tmp/bin/omarchy-state" <<'SH'
#!/bin/bash
printf 'state %s\n' "$*" >>"$CALL_LOG"
SH

chmod +x "$test_tmp/bin"/*

nvme_class="$test_tmp/nvme"
dropin_dir="$test_tmp/limine-entry-tool.d"
call_log="$test_tmp/calls.log"

# Mirrors /sys/class/nvme/<controller>/model, which pads the name with spaces.
set_model() {
  rm -rf "$nvme_class"
  mkdir -p "$nvme_class/nvme0"
  printf '%-40s\n' "$1" >"$nvme_class/nvme0/model"
}

run_detector() {
  set_model "$1"
  OMARCHY_NVME_CLASS="$nvme_class" bash "$detector"
}

run_detector "Micron_2400_MTFDKBA1T0QFM" || fail "the detector matches a Micron 2400"
pass "the detector matches a Micron 2400"

run_detector "Samsung SSD 990 PRO 1TB" && fail "the detector rejects another drive"
pass "the detector rejects another drive"

rm -rf "$nvme_class"
OMARCHY_NVME_CLASS="$nvme_class" bash "$detector" &&
  fail "the detector fails closed without an NVMe controller"
pass "the detector fails closed without an NVMe controller"

# Sourced the way run_logged runs it.
run_leaf() {
  set_model "$1"
  rm -rf "$dropin_dir"
  PATH="$test_tmp/bin:$ROOT/bin:$PATH" \
    OMARCHY_NVME_CLASS="$nvme_class" \
    OMARCHY_LIMINE_DROPIN_DIR="$dropin_dir" \
    bash -c 'source "$1"' bash "$leaf"
}

run_leaf "Micron_2400_MTFDKBA1T0QFM" || fail "the leaf writes the drop-in on a Micron 2400"
grep -Fxq "$parameter" "$dropin_dir/micron-2400-apst.conf" ||
  fail "the leaf writes the drop-in on a Micron 2400"
pass "the leaf writes the drop-in on a Micron 2400"

run_leaf "Samsung SSD 990 PRO 1TB" || fail "the leaf no-ops on another drive"
[[ -e $dropin_dir ]] && fail "the leaf no-ops on another drive"
pass "the leaf no-ops on another drive"

run_migration() {
  : >"$call_log"
  set_model "$1"
  rm -rf "$dropin_dir"
  if [[ -n ${2:-} ]]; then
    mkdir -p "$dropin_dir"
    printf '%s\n' "$2" >"$dropin_dir/nvme-apst.conf"
  fi
  PATH="$test_tmp/bin:$ROOT/bin:$PATH" \
    CALL_LOG="$call_log" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_NVME_CLASS="$nvme_class" \
    OMARCHY_LIMINE_DROPIN_DIR="$dropin_dir" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration "Micron_2400_MTFDKBA1T0QFM" ||
  fail "the migration applies the workaround and asks for a reboot"
grep -Fxq "$parameter" "$dropin_dir/micron-2400-apst.conf" ||
  fail "the migration writes the drop-in"
grep -q '^limine-mkinitcpio$' "$call_log" ||
  fail "the migration rebuilds the boot image"
grep -q 'state set reboot-required' "$call_log" ||
  fail "the migration asks for a reboot"
pass "the migration applies the workaround and asks for a reboot"

# A machine that already boots the parameter from its own drop-in must not
# get a second copy, another boot image rebuild, or a reboot prompt.
run_migration "Micron_2400_MTFDKBA1T0QFM" "$parameter" ||
  fail "the migration no-ops when the parameter is already configured"
[[ -e $dropin_dir/micron-2400-apst.conf ]] &&
  fail "the migration does not duplicate an existing drop-in"
[[ -s $call_log ]] && fail "the migration no-ops when the parameter is already configured"
pass "the migration no-ops when the parameter is already configured"

run_migration "Samsung SSD 990 PRO 1TB" || fail "the migration no-ops on another drive"
[[ -e $dropin_dir ]] && fail "the migration no-ops on another drive"
[[ -s $call_log ]] && fail "the migration no-ops on another drive"
pass "the migration no-ops on another drive"
