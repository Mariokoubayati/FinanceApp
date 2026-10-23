#!/bin/zsh

setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

typeset -r LABEL="com.mario.financeapp.refresh"
typeset -r PROGRAM_NAME="${0:t}"
typeset -r SCRIPT_DIR="${0:A:h}"
typeset -r SOURCE_SCRIPT="${SCRIPT_DIR}/refresh-finance-app.zsh"
typeset -r SOURCE_PLIST="${SCRIPT_DIR}/${LABEL}.plist"

[[ -n "${HOME:-}" && "${HOME}" == /* && "${HOME}" != "/" ]] || {
	print -u2 -r -- "error: HOME must be an absolute user home directory"
	exit 1
}

typeset -r SUPPORT_ROOT="${HOME}/Library/Application Support/FinanceAppRefresh"
typeset -r BIN_DIR="${SUPPORT_ROOT}/bin"
typeset -r BACKUP_ROOT="${SUPPORT_ROOT}/backups"
typeset -r RUNTIME_SCRIPT="${BIN_DIR}/refresh-finance-app.zsh"
typeset -r LOG_DIR="${HOME}/Library/Logs/FinanceAppRefresh"
typeset -r CACHE_ROOT="${HOME}/Library/Caches/FinanceAppRefresh"
typeset -r LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
typeset -r INSTALLED_PLIST="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
typeset -r USER_ID="$(/usr/bin/id -u)"
typeset -r DOMAIN="gui/${USER_ID}"
typeset -r SERVICE_TARGET="${DOMAIN}/${LABEL}"
typeset -r SAFE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

[[ "${USER_ID}" != "0" ]] || {
	print -u2 -r -- "error: run this per-user installer without sudo"
	exit 1
}

die() {
	print -u2 -r -- "error: $*"
	exit 1
}

note() {
	print -r -- "$*"
}

usage() {
	print -r -- "Usage: ${PROGRAM_NAME} [install | status | uninstall [--purge]]"
	print -r -- ""
	print -r -- "  install             Validate, install, and load the per-user agent (default)."
	print -r -- "  status              Report installed files and launchd load state."
	print -r -- "  uninstall           Unload the agent and remove only installed executable files."
	print -r -- "  uninstall --purge   Also permanently remove retained state, backups, logs, and cache."
}

ensure_private_directory() {
	local directory="$1"

	[[ ! -L "${directory}" ]] || die "refusing symlinked directory: ${directory}"
	if [[ -e "${directory}" && ! -d "${directory}" ]]; then
		die "expected a directory: ${directory}"
	fi
	/bin/mkdir -p "${directory}"
	/bin/chmod 700 "${directory}"
}

ensure_launch_agents_directory() {
	[[ ! -L "${LAUNCH_AGENTS_DIR}" ]] || die "refusing symlinked LaunchAgents directory"
	if [[ -e "${LAUNCH_AGENTS_DIR}" && ! -d "${LAUNCH_AGENTS_DIR}" ]]; then
		die "expected a directory: ${LAUNCH_AGENTS_DIR}"
	fi
	if [[ ! -d "${LAUNCH_AGENTS_DIR}" ]]; then
		/bin/mkdir -p "${LAUNCH_AGENTS_DIR}"
		/bin/chmod 700 "${LAUNCH_AGENTS_DIR}"
	fi
}

ensure_log_file() {
	local log_file="$1"

	[[ ! -L "${log_file}" ]] || die "refusing symlinked log file: ${log_file}"
	if [[ -e "${log_file}" && ! -f "${log_file}" ]]; then
		die "expected a regular log file: ${log_file}"
	fi
	if [[ ! -e "${log_file}" ]]; then
		/usr/bin/touch "${log_file}"
	fi
	/bin/chmod 600 "${log_file}"
}

validate_sources() {
	local source_label
	local selected_developer_dir

	[[ -f "${SOURCE_SCRIPT}" && ! -L "${SOURCE_SCRIPT}" ]] || \
		die "missing refresh script beside installer: ${SOURCE_SCRIPT}"
	[[ -f "${SOURCE_PLIST}" && ! -L "${SOURCE_PLIST}" ]] || \
		die "missing LaunchAgent plist beside installer: ${SOURCE_PLIST}"

	/bin/zsh -n "${SOURCE_SCRIPT}" || die "refresh script failed zsh syntax validation"
	/usr/bin/plutil -lint "${SOURCE_PLIST}" >/dev/null || die "source plist failed validation"

	source_label="$(/usr/bin/plutil -extract Label raw -o - "${SOURCE_PLIST}")" || \
		die "source plist has no readable Label"
	[[ "${source_label}" == "${LABEL}" ]] || \
		die "source plist label is '${source_label}', expected '${LABEL}'"

	selected_developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null)" || \
		die "Xcode command-line tools are not selected"
	[[ -d "${selected_developer_dir}" ]] || \
		die "selected developer directory does not exist: ${selected_developer_dir}"
	if ! DEVELOPER_DIR="${selected_developer_dir}" /usr/bin/xcrun --find xcodebuild >/dev/null 2>&1; then
		die "the selected developer directory does not provide xcodebuild"
	fi
	if ! DEVELOPER_DIR="${selected_developer_dir}" /usr/bin/xcrun --find devicectl >/dev/null 2>&1; then
		die "the selected developer directory does not provide devicectl; select a full current Xcode"
	fi

	REPLY="${selected_developer_dir}"
}

prepare_directories() {
	ensure_private_directory "${SUPPORT_ROOT}"
	ensure_private_directory "${BIN_DIR}"
	ensure_private_directory "${BACKUP_ROOT}"
	ensure_private_directory "${BACKUP_ROOT}/installer"
	ensure_private_directory "${LOG_DIR}"
	ensure_private_directory "${CACHE_ROOT}"
	ensure_launch_agents_directory
	ensure_log_file "${LOG_DIR}/refresh.log"
	ensure_log_file "${LOG_DIR}/xcodebuild.log"
}

backup_existing_file() {
	local existing_file="$1"
	local backup_name="$2"
	local backup_mode="$3"
	local backup_directory="${BACKUP_ROOT}/installer/${INSTALL_TIMESTAMP}"

	[[ -e "${existing_file}" ]] || return 0
	[[ -f "${existing_file}" && ! -L "${existing_file}" ]] || \
		die "refusing to replace non-regular file: ${existing_file}"

	ensure_private_directory "${backup_directory}"
	/bin/cp -p "${existing_file}" "${backup_directory}/${backup_name}"
	/bin/chmod "${backup_mode}" "${backup_directory}/${backup_name}"
}

install_candidate() {
	local candidate="$1"
	local destination="$2"
	local backup_name="$3"
	local mode="$4"

	if [[ -e "${destination}" ]]; then
		[[ -f "${destination}" && ! -L "${destination}" ]] || \
			die "refusing to replace non-regular file: ${destination}"
		if /usr/bin/cmp -s "${candidate}" "${destination}"; then
			/bin/chmod "${mode}" "${destination}"
			/bin/rm -f "${candidate}"
			return 0
		fi
		backup_existing_file "${destination}" "${backup_name}" "${mode}"
	fi

	/bin/chmod "${mode}" "${candidate}"
	/bin/mv -f "${candidate}" "${destination}"
}

install_runtime_script() {
	local temporary_script

	temporary_script="$(/usr/bin/mktemp "${BIN_DIR}/.refresh-finance-app.zsh.XXXXXX")" || \
		die "could not create a temporary runtime script"
	if ! /bin/cp "${SOURCE_SCRIPT}" "${temporary_script}"; then
		/bin/rm -f "${temporary_script}"
		die "could not copy the refresh script"
	fi
	/bin/chmod 700 "${temporary_script}"
	if ! /bin/zsh -n "${temporary_script}"; then
		/bin/rm -f "${temporary_script}"
		die "copied refresh script failed zsh syntax validation"
	fi
	install_candidate "${temporary_script}" "${RUNTIME_SCRIPT}" \
		"refresh-finance-app.zsh" 700
}

install_launch_agent_plist() {
	local selected_developer_dir="$1"
	local temporary_plist

	temporary_plist="$(/usr/bin/mktemp "${LAUNCH_AGENTS_DIR}/.${LABEL}.plist.XXXXXX")" || \
		die "could not create a temporary LaunchAgent plist"
	if ! /bin/cp "${SOURCE_PLIST}" "${temporary_plist}"; then
		/bin/rm -f "${temporary_plist}"
		die "could not copy the LaunchAgent plist"
	fi

	if ! /usr/bin/plutil -remove ProgramArguments "${temporary_plist}" || \
		! /usr/bin/plutil -insert ProgramArguments -array "${temporary_plist}" || \
		! /usr/bin/plutil -insert ProgramArguments.0 -string "/bin/zsh" "${temporary_plist}" || \
		! /usr/bin/plutil -insert ProgramArguments.1 -string "${RUNTIME_SCRIPT}" "${temporary_plist}" || \
		! /usr/bin/plutil -replace EnvironmentVariables.DEVELOPER_DIR -string "${selected_developer_dir}" "${temporary_plist}" || \
		! /usr/bin/plutil -replace EnvironmentVariables.HOME -string "${HOME}" "${temporary_plist}" || \
		! /usr/bin/plutil -replace EnvironmentVariables.PATH -string "${SAFE_PATH}" "${temporary_plist}" || \
		! /usr/bin/plutil -replace StandardOutPath -string "/dev/null" "${temporary_plist}" || \
		! /usr/bin/plutil -replace StandardErrorPath -string "/dev/null" "${temporary_plist}"; then
		/bin/rm -f "${temporary_plist}"
		die "could not render the LaunchAgent plist"
	fi

	/bin/chmod 600 "${temporary_plist}"
	if ! /usr/bin/plutil -lint "${temporary_plist}" >/dev/null; then
		/bin/rm -f "${temporary_plist}"
		die "rendered LaunchAgent plist failed validation"
	fi
	install_candidate "${temporary_plist}" "${INSTALLED_PLIST}" \
		"${LABEL}.plist" 600
}

bootout_if_loaded() {
	if /bin/launchctl print "${SERVICE_TARGET}" >/dev/null 2>&1; then
		/bin/launchctl bootout "${SERVICE_TARGET}" || \
			die "could not unload ${SERVICE_TARGET}"
	fi
}

bootstrap_agent() {
	local bootstrap_output=""
	local attempt=1

	/bin/launchctl enable "${SERVICE_TARGET}" >/dev/null 2>&1 || \
		die "could not enable ${SERVICE_TARGET}"

	while (( attempt <= 3 )); do
		if bootstrap_output="$(/bin/launchctl bootstrap "${DOMAIN}" "${INSTALLED_PLIST}" 2>&1)"; then
			/bin/launchctl print "${SERVICE_TARGET}" >/dev/null 2>&1 || \
				die "launchd accepted the plist but the service is not visible"
			return 0
		fi
		if (( attempt < 3 )); then
			/bin/sleep 1
		fi
		(( attempt += 1 ))
	done

	die "could not load ${SERVICE_TARGET}: ${bootstrap_output}"
}

install_agent() {
	local selected_developer_dir

	validate_sources
	selected_developer_dir="${REPLY}"
	prepare_directories
	INSTALL_TIMESTAMP="$(/bin/date -u '+%Y%m%dT%H%M%SZ')-$$"
	install_runtime_script
	install_launch_agent_plist "${selected_developer_dir}"
	bootout_if_loaded
	bootstrap_agent

	note "Installed and loaded ${LABEL}."
	note "The RunAtLoad check has been requested; later checks run every 30 minutes while this Mac is awake."
	note "Refresh log: ${LOG_DIR}/refresh.log"
}

show_status() {
	local problems=0

	note "Label: ${LABEL}"
	note "Runtime script: ${RUNTIME_SCRIPT}"
	if [[ -f "${RUNTIME_SCRIPT}" && ! -L "${RUNTIME_SCRIPT}" ]]; then
		if /bin/zsh -n "${RUNTIME_SCRIPT}"; then
			note "Runtime script valid: yes"
		else
			note "Runtime script valid: no"
			problems=1
		fi
	else
		note "Runtime script installed: no"
		problems=1
	fi

	note "LaunchAgent plist: ${INSTALLED_PLIST}"
	if [[ -f "${INSTALLED_PLIST}" && ! -L "${INSTALLED_PLIST}" ]]; then
		if /usr/bin/plutil -lint "${INSTALLED_PLIST}" >/dev/null; then
			note "LaunchAgent plist valid: yes"
		else
			note "LaunchAgent plist valid: no"
			problems=1
		fi
	else
		note "LaunchAgent plist installed: no"
		problems=1
	fi

	if /bin/launchctl print "${SERVICE_TARGET}" >/dev/null 2>&1; then
		note "Loaded in ${DOMAIN}: yes"
	else
		note "Loaded in ${DOMAIN}: no"
		problems=1
	fi
	note "Refresh log: ${LOG_DIR}/refresh.log"
	note "Schedule: at login and every 30 minutes while this Mac is awake"

	return "${problems}"
}

uninstall_agent() {
	local purge_requested="$1"

	bootout_if_loaded
	/bin/rm -f "${INSTALLED_PLIST}"
	/bin/rm -f "${RUNTIME_SCRIPT}"
	note "Uninstalled ${LABEL}."

	if [[ "${purge_requested}" == "true" ]]; then
		[[ "${SUPPORT_ROOT}" == "${HOME}/Library/Application Support/FinanceAppRefresh" ]] || \
			die "refusing purge because support path failed its safety check"
		[[ "${LOG_DIR}" == "${HOME}/Library/Logs/FinanceAppRefresh" ]] || \
			die "refusing purge because log path failed its safety check"
		[[ "${CACHE_ROOT}" == "${HOME}/Library/Caches/FinanceAppRefresh" ]] || \
			die "refusing purge because cache path failed its safety check"
		/bin/rm -rf "${SUPPORT_ROOT}" "${LOG_DIR}" "${CACHE_ROOT}"
		note "Purged retained state, backups, logs, and cache. This data is not recoverable from this utility."
	else
		note "Preserved state, backups, logs, and cache. Use 'uninstall --purge' only if you intend to delete them."
	fi
}

typeset action="${1:-install}"
if (( $# > 0 )); then
	shift
fi

case "${action}" in
	install)
		(( $# == 0 )) || die "install takes no additional arguments"
		install_agent
		;;
	status)
		(( $# == 0 )) || die "status takes no additional arguments"
		show_status
		;;
	uninstall)
		if (( $# == 0 )); then
			uninstall_agent false
		elif (( $# == 1 )) && [[ "$1" == "--purge" ]]; then
			uninstall_agent true
		else
			die "uninstall accepts only the optional --purge argument"
		fi
		;;
	-h|--help|help)
		(( $# == 0 )) || die "help takes no additional arguments"
		usage
		;;
	*)
		usage >&2
		die "unknown action: ${action}"
		;;
esac
