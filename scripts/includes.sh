#!/bin/bash

ENV_FILE="/.env"
BACKUP_DIR="/bitwarden/backup"
RESTORE_DIR="/bitwarden/restore"
RESTORE_EXTRACT_DIR="/bitwarden/extract"

#################### Function ####################
########################################
# Print colorful message.
# Arguments:
#     color
#     message
# Outputs:
#     colorful message
########################################
function color() {
    case $1 in
        red)     echo -e "\033[31m$2\033[0m" ;;
        green)   echo -e "\033[32m$2\033[0m" ;;
        yellow)  echo -e "\033[33m$2\033[0m" ;;
        blue)    echo -e "\033[34m$2\033[0m" ;;
        none)    echo "$2" ;;
    esac
}

########################################
# Check storage system connection success.
# Arguments:
#     None
########################################
function check_rclone_connection() {
    rclone config show "${RCLONE_REMOTE_NAME}" > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        color red "rclone configuration information not found"
        color blue "Please configure rclone first, check https://github.com/ttionya/vaultwarden-backup/blob/master/README.md#backup"
        exit 1
    fi

    rclone mkdir "${RCLONE_REMOTE}"
    if [[ $? != 0 ]]; then
        color red "storage system connection failure"
        exit 1
    fi
}

########################################
# Check file is exist.
# Arguments:
#     file
########################################
function check_file_exist() {
    if [[ ! -f "$1" ]]; then
        color red "cannot access $1: No such file"
        exit 1
    fi
}

########################################
# Check directory is exist.
# Arguments:
#     directory
########################################
function check_dir_exist() {
    if [[ ! -d "$1" ]]; then
        color red "cannot access $1: No such directory"
        exit 1
    fi
}


########################################
# Send status.
# Arguments:
#     message
########################################
function send_status() {
    if [[ "${TELEGRAM_ENABLE}" == "FALSE" ]]; then
        return
    fi

}

########################################
# Send health check ping.
# Arguments:
#     None
########################################
function send_ping() {
    if [[ -z "${PING_URL}" ]]; then
        return
    fi

    wget "${PING_URL}" -T 15 -t 10 -O /dev/null -q
    if [[ $? != 0 ]]; then
        color red "ping sending failed"
    else
        color blue "ping send was successfully"
    fi
}

########################################
# Export variables from .env file.
# Arguments:
#     None
# Outputs:
#     variables with prefix 'DOTENV_'
# Reference:
#     https://gist.github.com/judy2k/7656bfe3b322d669ef75364a46327836#gistcomment-3632918
########################################
function export_env_file() {
    if [[ -f "${ENV_FILE}" ]]; then
        color blue "find \"${ENV_FILE}\" file and export variables"
        set -a
        source <(cat "${ENV_FILE}" | sed -e '/^#/d;/^\s*$/d' -e 's/\(\w*\)[ \t]*=[ \t]*\(.*\)/DOTENV_\1=\2/')
        set +a
    fi
}

########################################
# Get variables from
#     environment variables,
#     secret file in environment variables,
#     secret file in .env file,
#     environment variables in .env file.
# Arguments:
#     variable name
# Outputs:
#     variable value
########################################
function get_env() {
    local VAR="$1"
    local VAR_FILE="${VAR}_FILE"
    local VAR_DOTENV="DOTENV_${VAR}"
    local VAR_DOTENV_FILE="DOTENV_${VAR_FILE}"
    local VALUE=""

    if [[ -n "${!VAR:-}" ]]; then
        VALUE="${!VAR}"
    elif [[ -n "${!VAR_FILE:-}" ]]; then
        VALUE="$(cat "${!VAR_FILE}")"
    elif [[ -n "${!VAR_DOTENV_FILE:-}" ]]; then
        VALUE="$(cat "${!VAR_DOTENV_FILE}")"
    elif [[ -n "${!VAR_DOTENV:-}" ]]; then
        VALUE="${!VAR_DOTENV}"
    fi

    export "${VAR}=${VALUE}"
}

########################################
# Initialization environment variables.
# Arguments:
#     None
# Outputs:
#     environment variables
########################################
function init_env() {
    # export
    export_env_file

    init_env_dir

    # CRON
    get_env CRON
    CRON="${CRON:-"5 * * * *"}"

    # RCLONE_REMOTE_NAME
    get_env RCLONE_REMOTE_NAME
    RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME:-"BitwardenBackup"}"

    # RCLONE_REMOTE_DIR
    get_env RCLONE_REMOTE_DIR
    RCLONE_REMOTE_DIR="${RCLONE_REMOTE_DIR:-"/BitwardenBackup/"}"

    # RCLONE_REMOTE
    RCLONE_REMOTE=$(echo "${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_DIR}" | sed 's@\(/*\)$@@')

    # ZIP_ENABLE
    get_env ZIP_ENABLE
    ZIP_ENABLE=$(echo "${ZIP_ENABLE}" | tr '[a-z]' '[A-Z]')
    if [[ "${ZIP_ENABLE}" == "FALSE" ]]; then
        ZIP_ENABLE="FALSE"
    else
        ZIP_ENABLE="TRUE"
    fi

    # ZIP_PASSWORD
    get_env ZIP_PASSWORD
    ZIP_PASSWORD="${ZIP_PASSWORD:-"WHEREISMYPASSWORD?"}"

    # ZIP_TYPE
    get_env ZIP_TYPE
    ZIP_TYPE=$(echo "${ZIP_TYPE}" | tr '[A-Z]' '[a-z]')
    if [[ "${ZIP_TYPE}" == "7z" ]]; then
        ZIP_TYPE="7z"
    else
        ZIP_TYPE="zip"
    fi

    # BACKUP_KEEP_DAYS
    get_env BACKUP_KEEP_DAYS
    BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-"0"}"

    # BACKUP_FILE_DATE_FORMAT
    get_env BACKUP_FILE_DATE_SUFFIX
    BACKUP_FILE_DATE_FORMAT=$(echo "%Y%m%d${BACKUP_FILE_DATE_SUFFIX}" | sed 's/[^0-9a-zA-Z%_-]//g')

    # PING_URL
    get_env PING_URL
    PING_URL="${PING_URL:-""}"

    # TELEGRAM_ENABLE
    # CHAT_ID
    get_env TELEGRAM_ENABLE
    get_env CHAT_ID
    TELEGRAM_ENABLE=$(echo "${TELEGRAM_ENABLE}" | tr '[a-z]' '[A-Z]')
    if [[ "${TELEGRAM_ENABLE}" == "TRUE" && "${CHAT_ID}" ]]; then
        TELEGRAM_ENABLE="TRUE"
    else
        TELEGRAM_ENABLE="FALSE"
    fi

    # MESSAGE_WHEN_SUCCESS
    get_env MESSAGE_WHEN_SUCCESS
    MESSAGE_WHEN_SUCCESS=$(echo "${MESSAGE_WHEN_SUCCESS}" | tr '[a-z]' '[A-Z]')
    if [[ "${MESSAGE_WHEN_SUCCESS}" == "FALSE" ]]; then
        MESSAGE_WHEN_SUCCESS="FALSE"
    else
        MESSAGE_WHEN_SUCCESS="TRUE"
    fi

    # MESSAGE_WHEN_FAILURE
    get_env MESSAGE_WHEN_FAILURE
    MESSAGE_WHEN_FAILURE=$(echo "${MESSAGE_WHEN_FAILURE}" | tr '[a-z]' '[A-Z]')
    if [[ "${MESSAGE_WHEN_FAILURE}" == "FALSE" ]]; then
        MESSAGE_WHEN_FAILURE="FALSE"
    else
        MESSAGE_WHEN_FAILURE="TRUE"
    fi

    # TIMEZONE
    get_env TIMEZONE
    local TIMEZONE_MATCHED_COUNT=$(ls "/usr/share/zoneinfo/${TIMEZONE}" 2> /dev/null | wc -l)
    if [[ "${TIMEZONE_MATCHED_COUNT}" -ne 1 ]]; then
        TIMEZONE="UTC"
    fi

    color yellow "========================================"
    color yellow "DATA_DIR: ${DATA_DIR}"
    color yellow "DATA_DB: ${DATA_DB}"
    color yellow "DATA_CONFIG: ${DATA_CONFIG}"
    color yellow "DATA_RSAKEY: ${DATA_RSAKEY}"
    color yellow "DATA_ATTACHMENTS: ${DATA_ATTACHMENTS}"
    color yellow "DATA_SENDS: ${DATA_SENDS}"
    color yellow "========================================"
    color yellow "CRON: ${CRON}"
    color yellow "RCLONE_REMOTE_NAME: ${RCLONE_REMOTE_NAME}"
    color yellow "RCLONE_REMOTE_DIR: ${RCLONE_REMOTE_DIR}"
    color yellow "RCLONE_REMOTE: ${RCLONE_REMOTE}"
    color yellow "ZIP_ENABLE: ${ZIP_ENABLE}"
    color yellow "ZIP_PASSWORD: ${#ZIP_PASSWORD} Chars"
    color yellow "ZIP_TYPE: ${ZIP_TYPE}"
    color yellow "BACKUP_FILE_DATE_FORMAT: ${BACKUP_FILE_DATE_FORMAT}"
    color yellow "BACKUP_KEEP_DAYS: ${BACKUP_KEEP_DAYS}"
    if [[ -n "${PING_URL}" ]]; then
        color yellow "PING_URL: ${PING_URL}"
    fi
    color yellow "TELEGRAM_ENABLE: ${TELEGRAM_ENABLE}"
    if [[ "${TELEGRAM_ENABLE}" == "TRUE" ]]; then
        color yellow "CHAT_ID: ${CHAT_ID}"
        color yellow "MESSAGE_WHEN_SUCCESS: ${MESSAGE_WHEN_SUCCESS}"
        color yellow "MESSAGE_WHEN_FAILURE: ${MESSAGE_WHEN_FAILURE}"
    fi
    color yellow "TIMEZONE: ${TIMEZONE}"
    color yellow "========================================"
}

function init_env_dir() {
    # DATA_DIR
    get_env DATA_DIR
    DATA_DIR="${DATA_DIR:-"/bitwarden/data"}"
    check_dir_exist "${DATA_DIR}"

    # DATA_DB
    get_env DATA_DB
    DATA_DB="${DATA_DB:-"${DATA_DIR}/db.sqlite3"}"

    # DATA_CONFIG
    DATA_CONFIG="${DATA_DIR}/config.json"

    # DATA_RSAKEY
    get_env DATA_RSAKEY
    DATA_RSAKEY="${DATA_RSAKEY:-"${DATA_DIR}/rsa_key"}"
    DATA_RSAKEY_DIRNAME="$(dirname "${DATA_RSAKEY}")"
    DATA_RSAKEY_BASENAME="$(basename "${DATA_RSAKEY}")"

    # DATA_ATTACHMENTS
    get_env DATA_ATTACHMENTS
    DATA_ATTACHMENTS="$(dirname "${DATA_ATTACHMENTS:-"${DATA_DIR}/attachments"}/useless")"
    DATA_ATTACHMENTS_DIRNAME="$(dirname "${DATA_ATTACHMENTS}")"
    DATA_ATTACHMENTS_BASENAME="$(basename "${DATA_ATTACHMENTS}")"

    # DATA_SEND
    get_env DATA_SENDS
    DATA_SENDS="$(dirname "${DATA_SENDS:-"${DATA_DIR}/sends"}/useless")"
    DATA_SENDS_DIRNAME="$(dirname "${DATA_SENDS}")"
    DATA_SENDS_BASENAME="$(basename "${DATA_SENDS}")"
}
