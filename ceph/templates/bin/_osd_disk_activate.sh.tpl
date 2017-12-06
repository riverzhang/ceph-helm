#!/bin/bash
set -ex

function osd_activate {
  if [[ -z "${OSD_DEVICE}" ]];then
    log "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  CEPH_DISK_OPTIONS=""
  CEPH_OSD_OPTIONS=""

  DATA_UUID=$(blkid -o value -s PARTUUID ${OSD_DEVICE}*1)
  LOCKBOX_UUID=$(blkid -o value -s PARTUUID ${OSD_DEVICE}3 || true)
  JOURNAL_PART=$(dev_part ${OSD_DEVICE} 2)
  ACTUAL_OSD_DEVICE=$(readlink -f ${OSD_DEVICE}) # resolve /dev/disk/by-* names

  # watch the udev event queue, and exit if all current events are handled
  udevadm settle --timeout=600

  # wait till partition exists then activate it
  if [[ -n "${OSD_JOURNAL}" ]]; then
    wait_for_file ${OSD_JOURNAL}
    chown ceph. ${OSD_JOURNAL}
    CEPH_OSD_OPTIONS="${CEPH_OSD_OPTIONS} --osd-journal ${OSD_JOURNAL}"
  else
    wait_for_file $(dev_part ${OSD_DEVICE} 1)
    chown ceph. $JOURNAL_PART
  fi

  chown ceph. /var/log/ceph

  DATA_PART=$(dev_part "${OSD_DEVICE}" 1)
  MOUNTED_PART=${DATA_PART}

  if [[ ${OSD_DMCRYPT} -eq 1 ]] && [[ ${OSD_FILESTORE} -eq 1 ]]; then
    get_dmcrypt_filestore_uuid
    mount_lockbox "$DATA_UUID" "$LOCKBOX_UUID"
    CEPH_DISK_OPTIONS+=('--dmcrypt')
    MOUNTED_PART="/dev/mapper/${DATA_UUID}"
    open_encrypted_parts_filestore
  elif [[ ${OSD_DMCRYPT} -eq 1 ]] && [[ ${OSD_BLUESTORE} -eq 1 ]]; then
    get_dmcrypt_bluestore_uuid
    mount_lockbox "$DATA_UUID" "$LOCKBOX_UUID"
    CEPH_DISK_OPTIONS+=('--dmcrypt')
    MOUNTED_PART="/dev/mapper/${DATA_UUID}"
    open_encrypted_parts_bluestore
  fi

  if [[ -z "${CEPH_DISK_OPTIONS[*]}" ]]; then
    ceph-disk -v --setuser ceph --setgroup disk activate --no-start-daemon "${DATA_PART}"
  else
    ceph-disk -v --setuser ceph --setgroup disk activate "${CEPH_DISK_OPTIONS[@]}" --no-start-daemon "${DATA_PART}"
  fi

  OSD_ID=$(grep "${MOUNTED_PART}" /proc/mounts | awk '{print $2}' | sed -r 's/^.*-([0-9]+)$/\1/')

  if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
    # Get the device used for block db and wal otherwise apply_ceph_ownership_to_disks will fail
    OSD_BLUESTORE_BLOCK_DB_TMP=$(resolve_symlink "${OSD_PATH}block.db")
# shellcheck disable=SC2034
    OSD_BLUESTORE_BLOCK_DB=${OSD_BLUESTORE_BLOCK_DB_TMP%?}
# shellcheck disable=SC2034
    OSD_BLUESTORE_BLOCK_WAL_TMP=$(resolve_symlink "${OSD_PATH}block.wal")
# shellcheck disable=SC2034
    OSD_BLUESTORE_BLOCK_WAL=${OSD_BLUESTORE_BLOCK_WAL_TMP%?}
  fi
  apply_ceph_ownership_to_disks

  log "SUCCESS"
  exec /usr/bin/ceph-osd ${CLI_OPTS} ${CEPH_OSD_OPTIONS} -f -i ${OSD_ID} --setuser ceph --setgroup disk
}
