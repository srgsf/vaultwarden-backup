#!/bin/bash

. /app/includes.sh

function clear_dir() {
    rm -rf "${BACKUP_DIR}"
}

function backup_init() {
    NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"
    # backup vaultwarden database file
    BACKUP_FILE_DB="${BACKUP_DIR}/db.${NOW}.sqlite3"
    # backup vaultwarden config file
    BACKUP_FILE_CONFIG="${BACKUP_DIR}/config.${NOW}.json"
    # backup vaultwarden rsakey files
    BACKUP_FILE_RSAKEY="${BACKUP_DIR}/rsakey.${NOW}.tar"
    # backup vaultwarden attachments directory
    BACKUP_FILE_ATTACHMENTS="${BACKUP_DIR}/attachments.${NOW}.tar"
    # backup vaultwarden sends directory
    BACKUP_FILE_SENDS="${BACKUP_DIR}/sends.${NOW}.tar"
    # backup zip file
    BACKUP_FILE_ZIP="${BACKUP_DIR}/backup.${NOW}.${ZIP_TYPE}"
}

function backup_db() {
    color blue "backup vaultwarden sqlite database"

    if [[ -f "${DATA_DB}" ]]; then
        sqlite3 "${DATA_DB}" ".backup '${BACKUP_FILE_DB}'"
    else
        color yellow "not found vaultwarden sqlite database, skipping"
    fi
}

function backup_config() {
    color blue "backup vaultwarden config"

    if [[ -f "${DATA_CONFIG}" ]]; then
        cp -f "${DATA_CONFIG}" "${BACKUP_FILE_CONFIG}"
    else
        color yellow "not found vaultwarden config, skipping"
    fi
}

function backup_rsakey() {
    color blue "backup vaultwarden rsakey"

    local FIND_RSAKEY=$(find "${DATA_RSAKEY_DIRNAME}" -name "${DATA_RSAKEY_BASENAME}*" | xargs -I {} basename {})
    local FIND_RSAKEY_COUNT=$(echo "${FIND_RSAKEY}" | wc -l)

    if [[ "${FIND_RSAKEY_COUNT}" -gt 0 ]]; then
        echo "${FIND_RSAKEY}" | tar -c -C "${DATA_RSAKEY_DIRNAME}" -f "${BACKUP_FILE_RSAKEY}" -T -

        color blue "display rsakey tar file list"

        tar -tf "${BACKUP_FILE_RSAKEY}"
    else
        color yellow "not found vaultwarden rsakey, skipping"
    fi
}

function backup_attachments() {
    color blue "backup vaultwarden attachments"

    if [[ -d "${DATA_ATTACHMENTS}" ]]; then
        tar -c -C "${DATA_ATTACHMENTS_DIRNAME}" -f "${BACKUP_FILE_ATTACHMENTS}" "${DATA_ATTACHMENTS_BASENAME}"

        color blue "display attachments tar file list"

        tar -tf "${BACKUP_FILE_ATTACHMENTS}"
    else
        color yellow "not found vaultwarden attachments directory, skipping"
    fi
}

function backup_sends() {
    color blue "backup vaultwarden sends"

    if [[ -d "${DATA_SENDS}" ]]; then
        tar -c -C "${DATA_SENDS_DIRNAME}" -f "${BACKUP_FILE_SENDS}" "${DATA_SENDS_BASENAME}"

        color blue "display sends tar file list"

        tar -tf "${BACKUP_FILE_SENDS}"
    else
        color yellow "not found vaultwarden sends directory, skipping"
    fi
}

function backup() {
    mkdir -p "${BACKUP_DIR}"

    backup_db
    backup_config
    backup_rsakey
    backup_attachments
    backup_sends

    ls -lah "${BACKUP_DIR}"
}

function backup_package() {
    if [[ "${ZIP_ENABLE}" == "TRUE" ]]; then
        color blue "package backup file"

        UPLOAD_FILE="${BACKUP_FILE_ZIP}"

        if [[ "${ZIP_TYPE}" == "zip" ]]; then
            7z a -tzip -mx=9 -p"${ZIP_PASSWORD}" "${BACKUP_FILE_ZIP}" "${BACKUP_DIR}"/*
        else
            7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on -p"${ZIP_PASSWORD}" "${BACKUP_FILE_ZIP}" "${BACKUP_DIR}"/*
        fi

        ls -lah "${BACKUP_DIR}"

        color blue "display backup ${ZIP_TYPE} file list"

        7z l "${BACKUP_FILE_ZIP}"
    else
        color yellow "skip package backup files"

        UPLOAD_FILE="${BACKUP_DIR}"
    fi
}

function upload() {
    REMOTE=$1
    color blue "upload backup file to ${REMOTE} storage system"

    # upload file not exist
    if [[ ! -e "${UPLOAD_FILE}" ]]; then
        color red "upload file not found"

       send_status_fail "Backup file upload failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Reason: Upload file not found."

        return 1
    fi

    rclone copy "${UPLOAD_FILE}" "${REMOTE}"
    if [[ $? != 0 ]]; then
        color red "upload failed"

        send_status_fail "Backup file upload to ${REMOTE} failed at $(date +"%Y-%m-%d %H:%M:%S %Z")."

        return 1
    fi
}

function clear_history() {
    if [[ "${BACKUP_KEEP_DAYS}" -gt 0 ]]; then
        color blue "delete ${BACKUP_KEEP_DAYS} days ago backup files"
        REMOTE=$1
        mapfile -t RCLONE_DELETE_LIST < <(rclone lsf "${REMOTE}" --min-age "${BACKUP_KEEP_DAYS}d")

        for RCLONE_DELETE_FILE in "${RCLONE_DELETE_LIST[@]}"
        do
            color yellow "deleting \"${RCLONE_DELETE_FILE}\""

            rclone delete "${REMOTE}/${RCLONE_DELETE_FILE}"
            if [[ $? != 0 ]]; then
                color red "delete \"${RCLONE_DELETE_FILE}\" failed in ${REMOTE}"
            fi
        done
    fi
}

function upload_and_clear_all() {
    for i in ${RCLONE_REMOTE}
    do
        CUR=$(echo "$i" | sed 's/\"//g')
        upload ${CUR}
        if [[ $? == 0 ]]; then
           send_status_success "Backup file was successfully uploaded to ${CUR} at $(date +"%Y-%m-%d %H:%M:%S %Z")"
           clear_history "${CUR}"
        fi
    done
}

color blue "running backup program..."

init_env
check_rclone_remotes
clear_dir
backup_init
backup
backup_package
upload_and_clear_all
clear_dir
send_ping

color none ""
