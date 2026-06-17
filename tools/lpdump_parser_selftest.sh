#!/system/bin/sh
# Offline parser self-test. Run on Linux/Android shell from extracted package dir.
set -eu
TMPDIR="${TMPDIR:-/tmp}"
LPDUMP="$TMPDIR/sfrw-lpdump.sample"
SLOT="_a"
INCLUDE_UNSLOTTED_PARTITIONS=true
ALLOW_PARTITIONS="system system_ext product vendor odm"
DENY_PARTITIONS="boot init_boot vendor_boot vbmeta vbmeta_system vbmeta_vendor pvmfw misc metadata userdata cache modem* bluetooth* abl* xbl* aop* tz* hyp* keymaster* qupfw* uefisecapp* devcfg* dsp* oplus* my_* reserve* cust*"
cat >"$LPDUMP" <<'SAMPLE'
Metadata slot count: 2
Partition table:
------------------------
Name: system_a
Group: qti_dynamic_partitions_a
Name: vendor_a
Group: qti_dynamic_partitions_a
Name: product_a
Group: oplus_dynamic_partitions_a
Name: system_b
Group: qti_dynamic_partitions_b
Name: system_a-cow
Group: qti_dynamic_partitions_a
Name: vendor_dlkm_a
Group: qti_dynamic_partitions_a
Name: my_heytap
Group: oplus_dynamic_partitions_a
Block device table:
Name: super
Size: 9126805504
Group table:
Name: qti_dynamic_partitions_a
Maximum size: 4500000000
Name: oplus_dynamic_partitions_a
Maximum size: 200000000
Name: qti_dynamic_partitions_b
Maximum size: 4500000000
Super partition layout:
SAMPLE
is_true(){ case "$(echo "$1"|tr '[:upper:]' '[:lower:]')" in true|1|yes|y|on) return 0;; *) return 1;; esac; }
strip_slot_suffix(){ case "$1" in *_a|*_b) echo "${1%??}";; *) echo "$1";; esac; }
is_snapshot_partition(){ case "$1" in scratch|scratch_*|*_scratch|*-cow|*_cow|cow_*|*snapshot*|*_snapshot|*-snapshot|*tmp-cow*|*-cow-img*) return 0;; *) return 1;; esac; }
part_matches_slot(){ p="$1"; [ -z "$SLOT" ]&&return 0; case "$p" in *"$SLOT") return 0;; *_a|*_b) return 1;; *) is_true "$INCLUDE_UNSLOTTED_PARTITIONS"&&return 0||return 1;; esac; }
list_lpdump_partition_names(){ busybox awk 'BEGIN{pt=0}/^Partition table:/{pt=1;next}/^Block device table:/||/^Group table:/||/^Super partition layout:/{pt=0}pt&&/^Name:/{print $2}' "$LPDUMP"; }
list_target_partitions(){ for p in $(list_lpdump_partition_names); do is_snapshot_partition "$p"&&continue; part_matches_slot "$p"||continue; echo "$p"; done | busybox awk '!seen[$0]++'; }
partition_group_for(){ busybox awk -v part="$1" 'BEGIN{pt=0;hit=0}/^Partition table:/{pt=1;next}/^Block device table:/||/^Group table:/||/^Super partition layout:/{pt=0}pt&&/^Name:/{hit=($2==part)}hit&&/^Group:/{print $2;exit}' "$LPDUMP"; }
group_max_for(){ busybox awk -v grp="$1" 'BEGIN{gt=0;hit=0}/^Group table:/{gt=1;next}/^Super partition layout:/||/^Block device table:/||/^Partition table:/{if(gt)gt=0}gt&&/^Name:/{hit=($2==grp)}hit&&/^Maximum size:/{print $3;exit}' "$LPDUMP"; }
part_match_list(){ p="$1"; base="$(strip_slot_suffix "$p")"; shift; for pat in "$@"; do [ -z "$pat" ]&&continue; case "$p" in $pat) return 0;; esac; case "$base" in $pat) return 0;; esac; done; return 1; }
is_rw_candidate_partition(){ p="$1"; is_snapshot_partition "$p"&&return 1; set -f; part_match_list "$p" $DENY_PARTITIONS; r=$?; set +f; [ "$r" = 0 ]&&return 1; set -f; part_match_list "$p" $ALLOW_PARTITIONS; r=$?; set +f; [ "$r" = 0 ]; }
list_rw_candidate_partitions(){ for p in $(list_target_partitions); do is_rw_candidate_partition "$p"&&echo "$p"; done | busybox awk '!seen[$0]++'; }
echo "TARGETS: $(list_target_partitions | tr '\012' ' ')"
echo "RW:      $(list_rw_candidate_partitions | tr '\012' ' ')"
for p in $(list_target_partitions); do
  if is_rw_candidate_partition "$p"; then mode=RW; else mode=PRESERVE; fi
  echo "$mode $p => $(partition_group_for "$p") / $(group_max_for "$(partition_group_for "$p")")"
done
