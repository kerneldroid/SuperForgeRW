#!/system/bin/sh
# Run in recovery shell or rooted Android shell: sh tools/check_f2fs_tools_recovery.sh
PATH=/system/bin:/system/xbin:/vendor/bin:/sbin:/bin:/usr/bin:$PATH
for t in make_f2fs mkfs.f2fs sload_f2fs sload.f2fs resize.f2fs fsck.f2fs; do
  p="$(command -v "$t" 2>/dev/null)"
  if [ -n "$p" ]; then
    echo "OK  $t -> $p"
  else
    echo "MISS $t"
  fi
done
