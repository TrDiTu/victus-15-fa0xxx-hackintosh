#!/usr/bin/env bash
# make-offline-stick.sh - build the OFFLINE macOS installer stick (two partitions).
#
#   ./make-offline-stick.sh              preflight + print the plan, change nothing  (default)
#   ./make-offline-stick.sh --write      actually partition and fill the stick (asks first)
#   ./make-offline-stick.sh --verify     read-only: is this stick a finished offline installer?
#
# STATUS: drafted 2026-10-21, NEVER RUN. Partitioning /dev/sda erases the only copy of
# com.apple.recovery.boot/BaseSystem.dmg, so it needs the human's explicit go-ahead first
# (AGENTS.md): the recovery image lives in $RECOVERY and is re-copied from there.
#
# Layout (MBR, 29.3 GiB stick = 61,440,000 sectors):
#   p1 start 2048, 1 GiB,  type 0x0C, bootable, FAT32 label OPENCORE
#        EFI/ + com.apple.recovery.boot/
#   p2 start 2099200, rest, type 0x07, ExFAT label UnPlugged
#        InstallAssistant.pkg (15.66 GB - cannot live on FAT32, 4 GiB file limit) + UnPlugged.command
#
# Safety rules are the same as make-1401-stick.sh: USB whole disk only, never a disk holding a
# mounted system path, never a disk with OS partition types, size limits, serial + size re-checked
# immediately before erasing, and MBR-only partitioning (no GPT backup table to clobber).
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# ---- what to write ---------------------------------------------------------
EFI=${EFI:-$REPO/EFI}                                  # this repo's working EFI (TGL spoof)
RECOVERY=${RECOVERY:-$REPO/.downloads/recovery-backup} # BaseSystem.dmg + BaseSystem.chunklist
PKG=${PKG:-$REPO/.downloads/InstallAssistant.pkg}      # gibMacOS 15.8.1 (24H32)
UNPLUGGED=${UNPLUGGED:-$REPO/.downloads/UnPlugged}     # corpnewt/UnPlugged clone
LABEL_EFI=${LABEL_EFI:-OPENCORE}
LABEL_DATA=${LABEL_DATA:-UnPlugged}
VOL_ID=${VOL_ID:-0C0FFEE1}                             # FAT volume serial

PART1_START=2048
PART1_SIZE=2097152                                     # sectors = exactly 1 GiB
PART2_START=$((PART1_START + PART1_SIZE))              # 2099200

MIN_PKG_BYTES=$((14 * 1000 * 1000 * 1000))             # sanity floor for a 15.66 GB package
# Verified 2026-10-21 (tools/verify-xar-pkg.py, TOC + all 5 members). Set to an empty string to skip.
EXPECT_PKG_SHA256=${EXPECT_PKG_SHA256-e4532e3337431292a7f227fcde7eb57f7b907547e2a26b43d3aab5a3f6e44781}
# The repo's config.plist has the machine identity scrubbed (REPLACEME serial/MLB/UUID/ROM), which
# is what it must stay like in a public repo. The SMBIOS that actually booted lives in
# .downloads/recovery-backup/config.plist.stick-working (git-ignored). Point IDENTITY_CONFIG at it
# to put a bootable identity on the new stick instead of the placeholders.
IDENTITY_CONFIG=${IDENTITY_CONFIG:-$REPO/.downloads/recovery-backup/config.plist.stick-working}

# ---- which stick -----------------------------------------------------------
DEV=${DEV:-/dev/sda}
# The real stick serial must never be committed (public repo, AGENTS.md), so it lives in
# .stick-serial (git-ignored) or in the environment:  EXPECT_SERIAL=<serial> ./make-offline-stick.sh
if [ -z "${EXPECT_SERIAL+x}" ] && [ -f "$REPO/.stick-serial" ]; then
  EXPECT_SERIAL=$(head -1 "$REPO/.stick-serial" | tr -d '[:space:]')
fi
EXPECT_SERIAL=${EXPECT_SERIAL-CHANGEME-STICK-SERIAL}   # empty = accept any stick
MIN_BYTES=$((8 * 1000 * 1000 * 1000))
MAX_BYTES=$((64 * 1000 * 1000 * 1000))
OS_PARTTYPES_GPT="c12a7328-f81f-11d2-ba4b-00a0c93ec93b 7c3457ef-0000-11aa-aa11-00306543ecac
48465300-0000-11aa-aa11-00306543ecac e3c9e316-0b5c-4db8-817d-f92df00215ae
de94bba4-06d1-4d40-a16a-bfd50179d6ac"
OS_PARTTYPES_MBR="0xef 0x27 0xaf 0x83 0x8e 0xfd"

MODE=dry
for a in "$@"; do
  case $a in
    --write)   MODE=write ;;
    --dry-run) MODE=dry ;;
    --verify)  MODE=verify ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
die()  { printf 'STOP: %s\n' "$*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }
run()  { if [ "$MODE" = write ]; then "$@"; else printf '   would run: %s\n' "$*"; fi; }

# ---- identify the stick, refuse everything else ---------------------------
identify() {
  step "the stick"
  [ -b "$DEV" ] || die "$DEV is not a block device."
  NAME=$(basename "$DEV")
  [ -d "/sys/block/$NAME" ] || die "$DEV is a partition, not a whole disk. Pick the whole disk."
  read -r SIZE TRAN RM HOTPLUG SERIAL <<<"$(lsblk -bdno SIZE,TRAN,RM,HOTPLUG,SERIAL "$DEV" | tr -s ' ')"
  MODEL=$(lsblk -dno MODEL "$DEV" | sed 's/^ *//; s/ *$//')
  say "   $DEV  $MODEL  $((SIZE / 1000000000)) GB  serial=${SERIAL:-<none>}  tran=${TRAN:-?} removable=$RM"

  [ "${TRAN:-}" = "usb" ] || { [ "$RM" = 1 ] && [ "$HOTPLUG" = 1 ]; } \
    || die "$DEV is not a USB disk (transport ${TRAN:-unknown}). Refusing."
  if [ -n "${EXPECT_SERIAL:-}" ] && [ "${SERIAL:-}" != "$EXPECT_SERIAL" ]; then
    die "expected stick serial $EXPECT_SERIAL, found ${SERIAL:-<none>}. Refusing - set EXPECT_SERIAL= to accept any."
  fi
  [ "$SIZE" -ge "$MIN_BYTES" ] || die "$DEV is smaller than 8 GB - the package alone is 15.66 GB."
  [ "$SIZE" -le "$MAX_BYTES" ] || die "$DEV is bigger than 64 GB - that is a drive, not a stick. Refusing."

  local m os_mnt
  while read -r m; do
    [ -n "$m" ] || continue
    for os_mnt in / /boot /boot/efi /efi /home /usr /var '[SWAP]'; do
      [ "$m" = "$os_mnt" ] && die "$DEV holds $os_mnt - this is the system you are running on. Refusing."
    done
  done < <(lsblk -rno MOUNTPOINTS "$DEV" | grep -v '^$' || true)

  local p t os_type
  while read -r p t; do
    [ -n "${p:-}" ] || continue
    for os_type in $OS_PARTTYPES_GPT $OS_PARTTYPES_MBR; do
      if [ "${t,,}" = "${os_type,,}" ]; then die "$p has partition type $t (an operating system lives there). Refusing."; fi
    done
  done < <(lsblk -rno PATH,PARTTYPE "$DEV" | awk 'NF==2')

  SEC=0
  [ -r "/sys/block/$NAME/size" ] && SEC=$(cat "/sys/block/$NAME/size")
  P1="${DEV}1"; P2="${DEV}2"
  case $NAME in
    *[0-9]) P1="${DEV}p1"; P2="${DEV}p2" ;;
  esac
}

unmount_dev() {
  local mp src
  while read -r mp; do
    [ -n "$mp" ] || continue
    src=$(findmnt -no SOURCE --target "$mp" 2>/dev/null || true)
    say "   unmounting $mp"
    if [ -n "$src" ]; then sudo umount "$mp" || udisksctl unmount -b "$src" >/dev/null; else sudo umount "$mp"; fi
  done < <(lsblk -rno MOUNTPOINTS "$DEV" | grep -v '^$' || true)
}

mount_part() {
  local part=$1 ro=${2:-rw} mp out opts=()
  [ "$ro" = ro ] && opts=(-o ro)
  MOUNTED_BY_US=0
  mp=$(lsblk -rno MOUNTPOINTS "$part" 2>/dev/null | grep -v '^$' | head -1 || true)
  if [ -n "$mp" ] && [ -d "$mp" ]; then MNT=$mp; return 0; fi
  MNT=""
  [ -b "$part" ] || return 1
  MOUNTED_BY_US=1
  if out=$(udisksctl mount -b "$part" "${opts[@]}" 2>/dev/null); then
    MNT=$(printf '%s\n' "$out" | sed -n 's/.* at \(.*\)\.$/\1/p')
  fi
  if [ -z "$MNT" ] || [ ! -d "$MNT" ]; then
    MNT=$(mktemp -d /tmp/offline-stick-XXXXXX)
    sudo mount "${opts[@]}" "$part" "$MNT" || return 1
  fi
  return 0
}

# only unmount what this script mounted; leave the desktop's mounts alone
umount_if_ours() {
  local part=$1
  [ "${MOUNTED_BY_US:-0}" = 1 ] || return 0
  sudo umount "$MNT" 2>/dev/null || udisksctl unmount -b "$part" >/dev/null 2>&1 || true
}

# ---- read-only verification of a finished stick ---------------------------
if [ "$MODE" = verify ]; then
  identify
  fails=0
  ok()  { printf '   ok    %s\n' "$*"; }
  bad() { printf '   FAIL  %s\n' "$*"; fails=$((fails + 1)); }

  step "partition table"
  [ "$(lsblk -dno PTTYPE "$DEV")" = dos ] && ok "MBR (dos)" || bad "not an MBR table"
  [ "$(lsblk -rno PARTTYPE "$P1")" = 0xc ] && ok "p1 type 0x0C (FAT32 LBA)" || bad "p1 type $(lsblk -rno PARTTYPE "$P1")"
  [ "$(lsblk -dno LABEL "$P1")" = "$LABEL_EFI" ] && ok "p1 label $LABEL_EFI" || bad "p1 label '$(lsblk -dno LABEL "$P1")'"
  if [ -b "$P2" ]; then
    [ "$(lsblk -rno PARTTYPE "$P2")" = 0x7 ] && ok "p2 type 0x07 (ExFAT)" || bad "p2 type $(lsblk -rno PARTTYPE "$P2")"
    [ "$(lsblk -dno FSTYPE "$P2")" = exfat ] && ok "p2 ExFAT" || bad "p2 is $(lsblk -dno FSTYPE "$P2")"
  else
    bad "p2 is missing (the stick still has only one partition)"
  fi

  step "contents of p1"
  mount_part "$P1" ro || bad "p1 could not be mounted read-only (mount it in your file manager first, or run with an askpass helper)"
  trap 'umount_if_ours "$P1"' EXIT
  [ -f "$MNT/EFI/OC/config.plist" ] && ok "EFI/OC/config.plist" || bad "EFI/OC/config.plist missing"
  if [ -n "$IDENTITY_CONFIG" ] && [ -f "$IDENTITY_CONFIG" ]; then
    if cmp -s "$IDENTITY_CONFIG" "$MNT/EFI/OC/config.plist"; then ok "config.plist is the identity-bearing copy"
    else bad "config.plist is not $IDENTITY_CONFIG"; fi
    if diff -r -x config.plist "$EFI" "$MNT/EFI" >/dev/null 2>&1; then ok "everything else matches this repo's EFI/ byte for byte"
    else bad "EFI (other than config.plist) differs from $EFI"; fi
  else
    if diff -r "$EFI" "$MNT/EFI" >/dev/null 2>&1; then ok "EFI matches this repo's EFI/ byte for byte"
    else bad "EFI differs from $EFI"; fi
  fi
  [ -f "$MNT/com.apple.recovery.boot/BaseSystem.dmg" ] && ok "BaseSystem.dmg" || bad "BaseSystem.dmg missing"
  [ -f "$MNT/com.apple.recovery.boot/BaseSystem.chunklist" ] && ok "BaseSystem.chunklist" || bad "BaseSystem.chunklist missing"
  if [ -f "$MNT/com.apple.recovery.boot/BaseSystem.dmg" ] && [ -f "$RECOVERY/BaseSystem.dmg" ]; then
    [ "$(sha256sum "$MNT/com.apple.recovery.boot/BaseSystem.dmg" | cut -d' ' -f1)" = \
      "$(sha256sum "$RECOVERY/BaseSystem.dmg" | cut -d' ' -f1)" ] \
      && ok "recovery image matches the local backup" || bad "recovery image differs from the backup"
  fi
  umount_if_ours "$P1"; trap - EXIT

  step "contents of p2"
  if [ -b "$P2" ] && mount_part "$P2" ro; then
    trap 'umount_if_ours "$P2"' EXIT
    [ -f "$MNT/InstallAssistant.pkg" ] && ok "InstallAssistant.pkg ($(stat -c %s "$MNT/InstallAssistant.pkg") B)" \
      || bad "InstallAssistant.pkg missing"
    [ -e "$MNT/UnPlugged.command" ] && ok "UnPlugged.command" || bad "UnPlugged.command missing"
    if [ -f "$MNT/InstallAssistant.pkg" ] && [ -n "$EXPECT_PKG_SHA256" ]; then
      [ "$(sha256sum "$MNT/InstallAssistant.pkg" | cut -d' ' -f1)" = "$EXPECT_PKG_SHA256" ] \
        && ok "package sha256 matches" || bad "package sha256 differs"
    fi
    umount_if_ours "$P2"; trap - EXIT
  else
    bad "p2 not mountable - there would be nothing to install from"
  fi

  step "result"
  if [ "$fails" = 0 ]; then say "   PASS: $DEV holds a finished offline installer stick."; exit 0; fi
  say "   FAILED: $fails problem(s) above."; exit 1
fi

# ---- preflight: everything that goes on the stick --------------------------
step "1/6 inputs"
[ -f "$EFI/OC/config.plist" ] || die "$EFI/OC/config.plist is missing."
say "   EFI          $EFI  ($(find "$EFI" -type f | wc -l) files, $(du -sh "$EFI" | cut -f1))"
[ -f "$RECOVERY/BaseSystem.dmg" ] && [ -f "$RECOVERY/BaseSystem.chunklist" ] \
  || die "recovery image missing in $RECOVERY - copy it off the old stick first (see notes/offline-installer-plan.md)."
say "   recovery     $RECOVERY  ($(stat -c %s "$RECOVERY/BaseSystem.dmg") B)"
[ -f "$PKG" ] || die "$PKG is missing."
pkg_bytes=$(stat -c %s "$PKG")
[ "$pkg_bytes" -ge "$MIN_PKG_BYTES" ] || die "$PKG is only $pkg_bytes B - the download is incomplete or wrong."
say "   package      $PKG  ($pkg_bytes B)"
if [ -n "$EXPECT_PKG_SHA256" ]; then
  got=$(sha256sum "$PKG" | cut -d' ' -f1)
  [ "$got" = "$EXPECT_PKG_SHA256" ] || die "$PKG sha256 is $got, expected $EXPECT_PKG_SHA256."
  say "   package sha256 verified"
else
  say "   package sha256 NOT checked (set EXPECT_PKG_SHA256 to enforce it)"
fi
[ -e "$UNPLUGGED" ] || die "$UNPLUGGED is missing - clone github.com/corpnewt/UnPlugged there."
[ -e "$UNPLUGGED/UnPlugged.command" ] || die "$UNPLUGGED/UnPlugged.command is missing."
say "   UnPlugged    $UNPLUGGED"
command -v mkfs.exfat >/dev/null || die "mkfs.exfat not found - install exfatprogs (Arch: sudo pacman -S exfatprogs)."

step "2/6 the stick"
identify
say "   sectors: $SEC"
need=$((PART2_START + 1))
[ "$SEC" -gt "$PART2_START" ] || die "the stick is too small for a 1 GiB EFI partition plus the package."
say "   p1 $P1  sectors $PART1_START..$((PART1_START + PART1_SIZE - 1))  1 GiB FAT32 $LABEL_EFI"
say "   p2 $P2  sectors $PART2_START..$((SEC - 1))  $(( (SEC - PART2_START) * 512 / 1000000000 )) GB ExFAT $LABEL_DATA"

step "3/6 the plan"
say "   Everything on $DEV will be erased, including the current 1401 recovery stick."
say "   Type the device name ($NAME) to continue:"
if [ "$MODE" != write ]; then
  say "   (dry run - not asking, not erasing; re-run with --write to do it)"
fi

step "4/6 erase and format"
if [ "$MODE" != write ]; then
  while read -r mp; do [ -n "$mp" ] && say "   would unmount $mp"; done < <(lsblk -rno MOUNTPOINTS "$DEV" | grep -v '^$' || true)
  say "   would run: printf 'label: dos\\nstart=$PART1_START, size=$PART1_SIZE, type=c, bootable\\nstart=$PART2_START, type=7\\n' | sudo sfdisk $DEV"
  say "   would run: sudo mkfs.vfat -F 32 -n $LABEL_EFI -i $VOL_ID $P1"
  say "   would run: sudo mkfs.exfat -n $LABEL_DATA -c 128K $P2"
  say "   would run: mount $P1, copy EFI/ and com.apple.recovery.boot/, diff -r"
  say "   would run: mount $P2, copy InstallAssistant.pkg and UnPlugged.command, sha256 both"
  exit 0
fi

read -r answer
[ "$answer" = "$NAME" ] || die "not confirmed - nothing was erased."

unmount_dev
printf 'label: dos\nstart=%s, size=%s, type=c, bootable\nstart=%s, type=7\n' \
  "$PART1_START" "$PART1_SIZE" "$PART2_START" | sudo sfdisk "$DEV" >/dev/null
sudo partprobe "$DEV" 2>/dev/null || true
udevadm settle
for _ in $(seq 1 20); do [ -b "$P1" ] && [ -b "$P2" ] && break; sleep 0.5; done
[ -b "$P1" ] && [ -b "$P2" ] || die "partitions did not appear after partitioning."

for attempt in 1 2 3; do
  unmount_dev; udevadm settle
  if sudo mkfs.vfat -F 32 -n "$LABEL_EFI" -i "$VOL_ID" "$P1"; then break; fi
  [ "$attempt" = 3 ] && die "could not format $P1."
  sleep 2
done
unmount_dev; udevadm settle
# UnPlugged's README warns that macOS struggles to mount ExFAT volumes with an allocation unit
# above 1024 KB, so pin the cluster size instead of trusting the default.
sudo mkfs.exfat -n "$LABEL_DATA" -c 128K "$P2" || die "could not format $P2."
udevadm settle
say "   formatted $P1 (FAT32 $LABEL_EFI) and $P2 (ExFAT $LABEL_DATA)"

step "5/6 write the contents"
mount_part "$P1"
cleanup1() { sudo umount "$MNT" 2>/dev/null || udisksctl unmount -b "$P1" >/dev/null 2>&1 || true; }
trap cleanup1 EXIT
cp -a "$EFI/EFI" "$MNT"/
if [ -n "$IDENTITY_CONFIG" ] && [ -f "$IDENTITY_CONFIG" ]; then
  cp -a "$IDENTITY_CONFIG" "$MNT/EFI/OC/config.plist"
  say "   config.plist replaced with $IDENTITY_CONFIG (real SMBIOS, not the repo placeholders)"
fi
mkdir -p "$MNT/com.apple.recovery.boot"
cp -a "$RECOVERY/BaseSystem.dmg" "$RECOVERY/BaseSystem.chunklist" "$MNT/com.apple.recovery.boot/"
sync
diff -r -x config.plist "$EFI" "$MNT/EFI" >/dev/null || die "the written EFI differs from $EFI - do not boot this stick."
if [ -n "$IDENTITY_CONFIG" ] && [ -f "$IDENTITY_CONFIG" ]; then
  cmp -s "$IDENTITY_CONFIG" "$MNT/EFI/OC/config.plist" || die "config.plist on the stick is not the identity copy."
fi
[ "$(sha256sum "$MNT/com.apple.recovery.boot/BaseSystem.dmg" | cut -d' ' -f1)" = \
  "$(sha256sum "$RECOVERY/BaseSystem.dmg" | cut -d' ' -f1)" ] || die "the recovery image copy is corrupt."
say "   p1: EFI + com.apple.recovery.boot written and verified"
trap - EXIT; cleanup1

mount_part "$P2"
cleanup2() { sudo umount "$MNT" 2>/dev/null || udisksctl unmount -b "$P2" >/dev/null 2>&1 || true; }
trap cleanup2 EXIT
cp -a "$PKG" "$MNT/InstallAssistant.pkg"
cp -a "$UNPLUGGED/UnPlugged.command" "$MNT/"
sync
[ "$(stat -c %s "$MNT/InstallAssistant.pkg")" = "$pkg_bytes" ] || die "the package copy is truncated."
say "   p2: InstallAssistant.pkg ($pkg_bytes B) + UnPlugged.command written"

step "6/6 done"
say "   $DEV now holds:"
say "     p1 FAT32  $LABEL_EFI    EFI/ + com.apple.recovery.boot/"
say "     p2 ExFAT  $LABEL_DATA   InstallAssistant.pkg + UnPlugged.command"
say ""
say "   Check it any time with: $0 --verify"
say "   In recovery: /sbin/mount_exfat /dev/diskXsY /Volumes/UnPlugged, then ./UnPlugged.command"
