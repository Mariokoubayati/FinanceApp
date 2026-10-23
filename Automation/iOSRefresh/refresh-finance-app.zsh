#!/bin/zsh

setopt NO_UNSET PIPE_FAIL
umask 077

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

typeset -r PROJECT="/Users/koubayati/FinanceApp/FinanceApp.xcodeproj"
typeset -r PROGRAM_NAME="${0:t}"
typeset -r SCHEME="FinanceApp"
typeset -r CONFIGURATION="Debug"
typeset -r PRODUCT_NAME="FinanceApp"
typeset -r BUNDLE_ID="com.mario.financeapp"
typeset -r TEAM_ID="488536L2N4"
typeset -r APPLICATION_ID="${TEAM_ID}.${BUNDLE_ID}"
typeset -r CORE_DEVICE_ID="A466D016-C9E0-51FB-84CA-AFBE9BB0CE7A"
typeset -r DEVICE_UDID="00008140-00104D9634E3001C"

[[ -n "${HOME:-}" && "${HOME}" == /* && "${HOME}" != "/" ]] || {
	print -u2 -r -- "error: HOME must be an absolute user home directory"
	exit 1
}

typeset -r SUPPORT_ROOT="${HOME}/Library/Application Support/FinanceAppRefresh"
typeset -r PROFILE_BACKUP_ROOT="${SUPPORT_ROOT}/profile-backups"
typeset -r STATE_FILE="${SUPPORT_ROOT}/state.plist"
typeset -r CACHE_ROOT="${HOME}/Library/Caches/FinanceAppRefresh"
typeset -r DERIVED_DATA="${CACHE_ROOT}/DerivedData"
typeset -r LOCK_DIR="${CACHE_ROOT}/run.lock"
typeset -r LOG_DIR="${HOME}/Library/Logs/FinanceAppRefresh"
typeset -r REFRESH_LOG="${LOG_DIR}/refresh.log"
typeset -r BUILD_LOG="${LOG_DIR}/xcodebuild.log"
typeset -r CONNECTION_LOG="${LOG_DIR}/device-connection.log"
typeset -r PROFILE_DIR="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
typeset -r REFRESH_LEAD_SECONDS=172800
typeset -r MIN_NEW_VALIDITY_SECONDS=518400
typeset -r BUILD_TIMEOUT_SECONDS=2700
typeset -r MIN_BUILD_FREE_KB=1048576
typeset -r NOTICE_INTERVAL_SECONDS=86400

typeset MODE="normal"
typeset LAUNCH_AFTER_INSTALL="false"
typeset TEMP_ROOT=""
typeset LOCK_HELD="false"
typeset ACTIVE_CHILD_PID=0
typeset ACTIVE_WATCHER_PID=0
typeset ATTEMPTED_REFRESH="false"
typeset QUARANTINE_ACTIVE="false"
typeset QUARANTINE_DIR=""
typeset LAST_ERROR=""
typeset DEVICE_ERROR=""
typeset DEVICE_TUNNEL=""

typeset CURRENT_PROFILE=""
typeset CURRENT_UUID=""
typeset CURRENT_CREATION=""
typeset CURRENT_EXPIRATION=""
typeset -i CURRENT_EXPIRATION_EPOCH=0
typeset -ga MATCHING_PROFILES

typeset NEW_UUID=""
typeset NEW_CREATION=""
typeset NEW_EXPIRATION=""
typeset -i NEW_EXPIRATION_EPOCH=0
typeset BASELINE_UUID=""
typeset BASELINE_CREATION=""
typeset BASELINE_EXPIRATION=""
typeset -i BASELINE_EXPIRATION_EPOCH=0
typeset STATE_NEEDS_RETRY="false"

usage() {
	print -r -- "Usage: ${PROGRAM_NAME} [--status | --force-renew [--no-launch]]"
	print -r -- ""
	print -r -- "  no arguments   Check the real profile expiration and refresh only within 48 hours."
	print -r -- "  --status       Show cached-profile, recorded-state, and device reachability status."
	print -r -- "  --force-renew  Perform one supervised end-to-end profile renewal now."
	print -r -- "  --no-launch    With --force-renew, do not bring FinanceApp to the foreground."
}

log() {
	local level="$1"
	shift
	print -r -- "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ') [${level}] $*"
}

die() {
	LAST_ERROR="$*"
	log ERROR "$*"
	exit 1
}

ensure_private_directory() {
	local directory="$1"
	[[ ! -L "${directory}" ]] || die "refusing symlinked directory: ${directory}"
	[[ ! -e "${directory}" || -d "${directory}" ]] || die "expected a directory: ${directory}"
	/bin/mkdir -p "${directory}" || die "could not create directory: ${directory}"
	/bin/chmod 700 "${directory}" || die "could not secure directory: ${directory}"
}

rotate_log() {
	local file="$1"
	local max_bytes="$2"
	local size=0
	[[ ! -L "${file}" ]] || die "refusing symlinked log: ${file}"
	if [[ -f "${file}" ]]; then
		size="$(/usr/bin/stat -f '%z' "${file}" 2>/dev/null || print 0)"
		if (( size > max_bytes )); then
			/bin/mv -f "${file}" "${file}.1" || die "could not rotate log: ${file}"
		fi
	fi
	/usr/bin/touch "${file}" || die "could not create log: ${file}"
	/bin/chmod 600 "${file}" || die "could not secure log: ${file}"
}

prepare_runtime() {
	ensure_private_directory "${SUPPORT_ROOT}"
	ensure_private_directory "${PROFILE_BACKUP_ROOT}"
	ensure_private_directory "${CACHE_ROOT}"
	ensure_private_directory "${DERIVED_DATA}"
	ensure_private_directory "${LOG_DIR}"
}

prepare_work_area() {
	TEMP_ROOT="$(/usr/bin/mktemp -d /private/tmp/financeapp-refresh.XXXXXX)" || \
		die "could not create a temporary directory; check the Mac's free disk space"
}

clear_refresh_build_cache() {
	# This directory belongs exclusively to this job. The lock, installed
	# script, state, logs and profile backups all live outside it.
	[[ "${CACHE_ROOT}" == "${HOME}/Library/Caches/FinanceAppRefresh" && \
		"${DERIVED_DATA}" == "${CACHE_ROOT}/DerivedData" && \
		! -L "${DERIVED_DATA}" ]] || return 1
	/bin/rm -rf -- "${DERIVED_DATA}" || return 1
	log INFO "Removed this refresh job's disposable build cache."
}

check_disk_space() {
	local available_kb
	available_kb="$(/bin/df -Pk "${CACHE_ROOT}" | /usr/bin/awk 'NR == 2 { print $4 }')"
	[[ "${available_kb}" == <-> ]] || die "could not determine free disk space for the refresh build"
	if (( available_kb < MIN_BUILD_FREE_KB )); then
		clear_refresh_build_cache || die "could not reclaim the refresh job's own build cache while disk space is low"
		available_kb="$(/bin/df -Pk "${CACHE_ROOT}" | /usr/bin/awk 'NR == 2 { print $4 }')"
		[[ "${available_kb}" == <-> ]] || die "could not determine free disk space after build-cache cleanup"
	fi
	(( available_kb >= MIN_BUILD_FREE_KB )) || \
		die "low disk space: only $(( available_kb / 1024 )) MB free; free at least 1 GB on this Mac so FinanceApp can renew"
	log INFO "Build disk-space check passed ($(( available_kb / 1024 )) MB free)."
}

setup_logging() {
	rotate_log "${REFRESH_LOG}" 1048576
	exec >>"${REFRESH_LOG}" 2>&1
	log INFO "Starting FinanceApp refresh check (mode=${MODE})."
}

release_lock() {
	[[ "${LOCK_HELD}" == "true" ]] || return 0
	/bin/rm -f "${LOCK_DIR}/pid" 2>/dev/null || true
	/bin/rmdir "${LOCK_DIR}" 2>/dev/null || true
	LOCK_HELD="false"
}

acquire_lock() {
	if /bin/mkdir "${LOCK_DIR}" 2>/dev/null; then
		print -r -- "$$" >"${LOCK_DIR}/pid" || die "could not record the refresh lock owner"
		LOCK_HELD="true"
		return 0
	fi

	local existing_pid=""
	if [[ -f "${LOCK_DIR}/pid" ]]; then
		existing_pid="$(<"${LOCK_DIR}/pid")"
	fi
	if [[ "${existing_pid}" == <-> ]] && /bin/kill -0 "${existing_pid}" 2>/dev/null; then
		log INFO "Another FinanceApp refresh is already running (pid ${existing_pid}); exiting."
		return 1
	fi

	/bin/rm -f "${LOCK_DIR}/pid" 2>/dev/null || true
	/bin/rmdir "${LOCK_DIR}" 2>/dev/null || \
		die "stale lock directory contains unexpected files: ${LOCK_DIR}"
	/bin/mkdir "${LOCK_DIR}" || die "could not acquire refresh lock"
	print -r -- "$$" >"${LOCK_DIR}/pid" || die "could not record the refresh lock owner"
	LOCK_HELD="true"
}

decode_profile() {
	local profile="$1"
	local output="$2"
	/usr/bin/openssl smime -inform der -verify -noverify -in "${profile}" -out "${output}" \
		>/dev/null 2>&1
}

plist_raw() {
	local plist="$1"
	local key="$2"
	/usr/bin/plutil -extract "${key}" raw -o - "${plist}" 2>/dev/null
}

iso_to_epoch() {
	local value="$1"
	TZ=UTC /bin/date -j -f '%Y-%m-%dT%H:%M:%SZ' "${value}" '+%s' 2>/dev/null
}

find_matching_profiles() {
	MATCHING_PROFILES=()
	CURRENT_PROFILE=""
	CURRENT_UUID=""
	CURRENT_CREATION=""
	CURRENT_EXPIRATION=""
	CURRENT_EXPIRATION_EPOCH=0

	local profile decoded app_id expiration expiration_epoch uuid creation
	local -i index=0
	for profile in "${PROFILE_DIR}"/*.mobileprovision(N); do
		(( index += 1 ))
		decoded="${TEMP_ROOT}/cached-profile-${index}.plist"
		decode_profile "${profile}" "${decoded}" || continue
		app_id="$(plist_raw "${decoded}" 'Entitlements.application-identifier')" || continue
		[[ "${app_id}" == "${APPLICATION_ID}" ]] || continue
		MATCHING_PROFILES+=("${profile}")
		expiration="$(plist_raw "${decoded}" 'ExpirationDate')" || continue
		expiration_epoch="$(iso_to_epoch "${expiration}")" || continue
		if (( expiration_epoch >= CURRENT_EXPIRATION_EPOCH )); then
			uuid="$(plist_raw "${decoded}" 'UUID')" || continue
			creation="$(plist_raw "${decoded}" 'CreationDate')" || continue
			CURRENT_PROFILE="${profile}"
			CURRENT_UUID="${uuid}"
			CURRENT_CREATION="${creation}"
			CURRENT_EXPIRATION="${expiration}"
			CURRENT_EXPIRATION_EPOCH="${expiration_epoch}"
		fi
	done
}

read_device_connection() {
	local output="${TEMP_ROOT}/devices.json"
	local outcome identifier pairing developer_mode udid
	/bin/rm -f "${output}" 2>/dev/null || true
	/usr/bin/xcrun devicectl list devices \
		--filter "identifier == '${CORE_DEVICE_ID}'" \
		--timeout 30 --json-output "${output}" >/dev/null 2>&1 || return 1
	[[ -f "${output}" ]] || return 1
	outcome="$(plist_raw "${output}" 'info.outcome')" || return 1
	identifier="$(plist_raw "${output}" 'result.devices.0.identifier')" || return 1
	DEVICE_TUNNEL="$(plist_raw "${output}" 'result.devices.0.connectionProperties.tunnelState')" || return 1
	pairing="$(plist_raw "${output}" 'result.devices.0.connectionProperties.pairingState')" || return 1
	developer_mode="$(plist_raw "${output}" 'result.devices.0.deviceProperties.developerModeStatus')" || return 1
	udid="$(plist_raw "${output}" 'result.devices.0.hardwareProperties.udid')" || return 1
	[[ "${outcome}" == "success" && "${identifier}" == "${CORE_DEVICE_ID}" && \
		"${pairing}" == "paired" && \
		"${developer_mode}" == "enabled" && "${udid}" == "${DEVICE_UDID}" ]]
}

device_is_reachable() {
	DEVICE_ERROR="the intended iPhone was not found with matching pairing, identity, and Developer Mode; check Xcode's Devices window"
	read_device_connection || return 1
	[[ "${DEVICE_TUNNEL}" != "connected" ]] || return 0

	# Listing devices only reports a snapshot. An app query actually requests a
	# connection; unlike device details, it cannot succeed with cached data.
	local probe="${TEMP_ROOT}/connection-probe.json"
	local attempt outcome
	rotate_log "${CONNECTION_LOG}" 1048576
	DEVICE_ERROR="could not connect to the paired iPhone after two attempts; unlock it, connect by USB and accept any Trust prompt (details: ${CONNECTION_LOG})"
	for attempt in 1 2; do
		log INFO "Requesting a connection to the paired iPhone (attempt ${attempt}, previous tunnel=${DEVICE_TUNNEL})."
		/bin/rm -f "${probe}" 2>/dev/null || true
		if /usr/bin/xcrun devicectl device info apps \
			--device "${CORE_DEVICE_ID}" --bundle-id "${BUNDLE_ID}" \
			--timeout 45 --json-output "${probe}" >>"${CONNECTION_LOG}" 2>&1; then
			outcome="$(plist_raw "${probe}" 'info.outcome')" || outcome=""
			if [[ "${outcome}" == "success" ]] && read_device_connection && \
				[[ "${DEVICE_TUNNEL}" == "connected" ]]; then
				log INFO "Established and verified the connection to the intended iPhone."
				return 0
			fi
		fi
		(( attempt == 2 )) || /bin/sleep 3
	done
	return 1
}

quarantine_matching_profiles() {
	local timestamp profile destination
	timestamp="$(/bin/date -u '+%Y%m%dT%H%M%SZ')"
	QUARANTINE_DIR="${PROFILE_BACKUP_ROOT}/${timestamp}-$$"
	ensure_private_directory "${QUARANTINE_DIR}"
	QUARANTINE_ACTIVE="true"

	for profile in "${MATCHING_PROFILES[@]}"; do
		[[ -f "${profile}" && ! -L "${profile}" ]] || \
			die "refusing unexpected cached profile entry: ${profile}"
		destination="${QUARANTINE_DIR}/${profile:t}"
		[[ ! -e "${destination}" ]] || die "profile backup already exists: ${destination}"
		/bin/mv "${profile}" "${destination}" || die "could not back up cached profile: ${profile:t}"
	done
	log INFO "Backed up ${#MATCHING_PROFILES[@]} matching cached profile(s) to ${QUARANTINE_DIR}."
}

restore_quarantined_profiles() {
	[[ "${QUARANTINE_ACTIVE}" == "true" && -d "${QUARANTINE_DIR}" ]] || return 0
	local backup destination
	local -i restore_failed=0
	if ! /bin/mkdir -p "${PROFILE_DIR}" 2>/dev/null; then
		log ERROR "Could not recreate the Xcode profile directory; backups remain in ${QUARANTINE_DIR}."
		return 1
	fi
	for backup in "${QUARANTINE_DIR}"/*.mobileprovision(N); do
		destination="${PROFILE_DIR}/${backup:t}"
		if [[ ! -e "${destination}" ]]; then
			/bin/mv "${backup}" "${destination}" 2>/dev/null || restore_failed=1
		elif ! /usr/bin/cmp -s "${backup}" "${destination}"; then
			restore_failed=1
		fi
	done
	if (( restore_failed != 0 )); then
		log ERROR "Could not fully restore the previous cached profiles; recoverable backups remain in ${QUARANTINE_DIR}."
		return 1
	fi
	log WARN "Restored the previous FinanceApp cached profile(s) after an unsuccessful refresh."
	QUARANTINE_ACTIVE="false"
}

run_with_timeout() {
	local seconds="$1"
	shift
	local marker="${TEMP_ROOT}/command-timed-out"
	local exit_code
	/bin/rm -f "${marker}" 2>/dev/null || true

	"$@" &
	ACTIVE_CHILD_PID=$!
	(
		/bin/sleep "${seconds}"
		if /bin/kill -0 "${ACTIVE_CHILD_PID}" 2>/dev/null; then
			/usr/bin/touch "${marker}"
			/bin/kill -TERM "${ACTIVE_CHILD_PID}" 2>/dev/null || true
			/bin/sleep 15
			/bin/kill -KILL "${ACTIVE_CHILD_PID}" 2>/dev/null || true
		fi
	) &
	ACTIVE_WATCHER_PID=$!

	if wait "${ACTIVE_CHILD_PID}"; then
		exit_code=0
	else
		exit_code=$?
	fi
	ACTIVE_CHILD_PID=0
	/bin/kill "${ACTIVE_WATCHER_PID}" 2>/dev/null || true
	wait "${ACTIVE_WATCHER_PID}" 2>/dev/null || true
	ACTIVE_WATCHER_PID=0
	[[ ! -f "${marker}" ]] || return 124
	return "${exit_code}"
}

plist_set_string() {
	local plist="$1" key="$2" value="$3"
	if /usr/bin/plutil -extract "${key}" raw -o - "${plist}" >/dev/null 2>&1; then
		/usr/bin/plutil -replace "${key}" -string "${value}" "${plist}"
	else
		/usr/bin/plutil -insert "${key}" -string "${value}" "${plist}"
	fi
}

plist_set_integer() {
	local plist="$1" key="$2" value="$3"
	if /usr/bin/plutil -extract "${key}" raw -o - "${plist}" >/dev/null 2>&1; then
		/usr/bin/plutil -replace "${key}" -integer "${value}" "${plist}"
	else
		/usr/bin/plutil -insert "${key}" -integer "${value}" "${plist}"
	fi
}

plist_set_bool() {
	local plist="$1" key="$2" value="$3"
	if /usr/bin/plutil -extract "${key}" raw -o - "${plist}" >/dev/null 2>&1; then
		/usr/bin/plutil -replace "${key}" -bool "${value}" "${plist}"
	else
		/usr/bin/plutil -insert "${key}" -bool "${value}" "${plist}"
	fi
}

load_installed_baseline() {
	BASELINE_UUID=""
	BASELINE_CREATION=""
	BASELINE_EXPIRATION=""
	BASELINE_EXPIRATION_EPOCH=0
	STATE_NEEDS_RETRY="false"

	[[ -f "${STATE_FILE}" && ! -L "${STATE_FILE}" ]] || return 0
	local state_uuid state_creation state_expiration state_epoch needs_retry
	state_uuid="$(plist_raw "${STATE_FILE}" 'ProfileUUID')" || state_uuid=""
	state_creation="$(plist_raw "${STATE_FILE}" 'ProfileCreationDate')" || state_creation=""
	state_expiration="$(plist_raw "${STATE_FILE}" 'ProfileExpirationDate')" || state_expiration=""
	needs_retry="$(plist_raw "${STATE_FILE}" 'NeedsRetry')" || needs_retry="false"
	[[ "${needs_retry}" == "true" ]] && STATE_NEEDS_RETRY="true"
	if [[ -n "${state_uuid}" && -n "${state_expiration}" ]]; then
		state_epoch="$(iso_to_epoch "${state_expiration}")" || state_epoch=0
		if (( state_epoch > 0 )); then
			BASELINE_UUID="${state_uuid}"
			BASELINE_CREATION="${state_creation}"
			BASELINE_EXPIRATION="${state_expiration}"
			BASELINE_EXPIRATION_EPOCH="${state_epoch}"
		fi
	fi
}

write_success_state() {
	local temporary="${STATE_FILE}.tmp.$$"
	/usr/bin/plutil -create xml1 "${temporary}" || die "could not create refresh state"
	plist_set_string "${temporary}" 'BundleIdentifier' "${BUNDLE_ID}" || die "could not record bundle ID"
	plist_set_string "${temporary}" 'ProfileUUID' "${NEW_UUID}" || die "could not record profile UUID"
	plist_set_string "${temporary}" 'ProfileCreationDate' "${NEW_CREATION}" || die "could not record profile creation"
	plist_set_string "${temporary}" 'ProfileExpirationDate' "${NEW_EXPIRATION}" || die "could not record profile expiration"
	plist_set_string "${temporary}" 'InstalledAt' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" || die "could not record install time"
	plist_set_string "${temporary}" 'LastResult' 'success' || die "could not record result"
	plist_set_integer "${temporary}" 'ConsecutiveFailures' 0 || die "could not reset failure count"
	plist_set_bool "${temporary}" 'NeedsRetry' false || die "could not reset retry state"
	/bin/chmod 600 "${temporary}" || die "could not secure refresh state"
	/bin/mv -f "${temporary}" "${STATE_FILE}" || die "could not install refresh state"
}

record_failure() {
	local temporary="${STATE_FILE}.tmp.$$"
	local failures=0 last_notice=0 last_urgency=-1 now urgency=0 message=""
	local notice_sent="false"
	now="$(/bin/date '+%s')"
	if [[ -f "${STATE_FILE}" && ! -L "${STATE_FILE}" ]]; then
		failures="$(plist_raw "${STATE_FILE}" 'ConsecutiveFailures' 2>/dev/null || print 0)"
		last_notice="$(plist_raw "${STATE_FILE}" 'LastNotifiedAtEpoch' 2>/dev/null || print 0)"
		last_urgency="$(plist_raw "${STATE_FILE}" 'LastNotifiedUrgency' 2>/dev/null || print 0)"
	fi
	[[ "${failures}" == <-> ]] || failures=0
	[[ "${last_notice}" == <-> ]] || last_notice=0
	[[ "${last_urgency}" == <-> ]] || last_urgency=-1
	(( failures += 1 ))
	if (( BASELINE_EXPIRATION_EPOCH > 0 )); then
		if (( BASELINE_EXPIRATION_EPOCH <= now )); then
			urgency=2
			message="The last verified FinanceApp profile has expired. "
		elif (( BASELINE_EXPIRATION_EPOCH - now <= 86400 )); then
			urgency=1
			message="FinanceApp expires within 24 hours. "
		fi
	fi
	# Notify before writing state, so a full disk cannot hide the failure.
	# Retry undelivered notifications and repeat daily or on expiry escalation.
	if { (( failures >= 2 || urgency > 0 )) || [[ "${LAST_ERROR}" == *disk* ]]; } && \
		(( last_notice == 0 || now - last_notice >= NOTICE_INTERVAL_SECONDS || urgency > last_urgency )); then
		if /usr/bin/osascript - "${message}Renewal failed: ${LAST_ERROR:-unknown error}. Checks retry every 30 minutes while this Mac is awake." \
			>/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
	display notification (item 1 of argv) with title "FinanceApp needs attention"
end run
APPLESCRIPT
		then
			notice_sent="true"
		else
			log WARN "macOS did not accept the renewal notification; the next failed check will retry it."
		fi
	fi
	if [[ -f "${STATE_FILE}" && ! -L "${STATE_FILE}" ]]; then
		/bin/cp "${STATE_FILE}" "${temporary}" 2>/dev/null || return 0
	else
		/usr/bin/plutil -create xml1 "${temporary}" 2>/dev/null || return 0
	fi
	plist_set_string "${temporary}" 'BundleIdentifier' "${BUNDLE_ID}" >/dev/null 2>&1 || return 0
	plist_set_string "${temporary}" 'LastResult' 'failure' >/dev/null 2>&1 || return 0
	plist_set_string "${temporary}" 'LastFailureAt' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" >/dev/null 2>&1 || return 0
	plist_set_string "${temporary}" 'LastFailureMessage' "${LAST_ERROR:-Refresh command failed}" >/dev/null 2>&1 || return 0
	plist_set_integer "${temporary}" 'ConsecutiveFailures' "${failures}" >/dev/null 2>&1 || return 0
	plist_set_bool "${temporary}" 'NeedsRetry' true >/dev/null 2>&1 || return 0
	if [[ "${notice_sent}" == "true" ]]; then
		plist_set_integer "${temporary}" 'LastNotifiedAtEpoch' "${now}" >/dev/null 2>&1 || return 0
		plist_set_integer "${temporary}" 'LastNotifiedUrgency' "${urgency}" >/dev/null 2>&1 || return 0
	fi
	if [[ -n "${BASELINE_UUID}" && -n "${BASELINE_EXPIRATION}" ]]; then
		plist_set_string "${temporary}" 'ProfileUUID' "${BASELINE_UUID}" >/dev/null 2>&1 || return 0
		plist_set_string "${temporary}" 'ProfileCreationDate' "${BASELINE_CREATION}" >/dev/null 2>&1 || return 0
		plist_set_string "${temporary}" 'ProfileExpirationDate' "${BASELINE_EXPIRATION}" >/dev/null 2>&1 || return 0
	fi
	/bin/chmod 600 "${temporary}" 2>/dev/null || true
	/bin/mv -f "${temporary}" "${STATE_FILE}" 2>/dev/null || return 0
}

build_app() {
	rotate_log "${BUILD_LOG}" 5242880
	: >"${BUILD_LOG}"
	log INFO "Starting a clean device build; detailed output is in ${BUILD_LOG}."
	if run_with_timeout "${BUILD_TIMEOUT_SECONDS}" \
		/usr/bin/xcodebuild \
		-project "${PROJECT}" \
		-scheme "${SCHEME}" \
		-configuration "${CONFIGURATION}" \
		-destination "id=${DEVICE_UDID}" \
		-derivedDataPath "${DERIVED_DATA}" \
		-allowProvisioningUpdates \
		-allowProvisioningDeviceRegistration \
		CODE_SIGN_STYLE=Automatic \
		DEVELOPMENT_TEAM="${TEAM_ID}" \
		PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
		clean build >"${BUILD_LOG}" 2>&1; then
		log INFO "Xcode device build succeeded."
	else
		local exit_code=$?
		if (( exit_code == 124 )); then
			die "Xcode build exceeded $(( BUILD_TIMEOUT_SECONDS / 60 )) minutes"
		fi
		die "Xcode device build failed (exit ${exit_code}); see ${BUILD_LOG}"
	fi
}

validate_built_app() {
	local app_path="$1"
	local info_plist="${app_path}/Info.plist"
	local embedded="${app_path}/embedded.mobileprovision"
	local decoded="${TEMP_ROOT}/embedded-profile.plist"
	local product_bundle app_id profile_team devices_xml now remaining

	[[ -d "${app_path}" && ! -L "${app_path}" ]] || die "expected built app was not found: ${app_path}"
	[[ -f "${info_plist}" && -f "${embedded}" ]] || die "built app is missing Info.plist or embedded.mobileprovision"
	/usr/bin/codesign --verify --strict --verbose=2 "${app_path}" >>"${BUILD_LOG}" 2>&1 || \
		die "built app failed code-signature verification"
	product_bundle="$(plist_raw "${info_plist}" 'CFBundleIdentifier')" || die "could not read the built bundle ID"
	[[ "${product_bundle}" == "${BUNDLE_ID}" ]] || die "built bundle ID is ${product_bundle}, expected ${BUNDLE_ID}"

	decode_profile "${embedded}" "${decoded}" || die "could not decode the built app's provisioning profile"
	app_id="$(plist_raw "${decoded}" 'Entitlements.application-identifier')" || die "built profile has no application identifier"
	profile_team="$(plist_raw "${decoded}" 'TeamIdentifier.0')" || die "built profile has no team identifier"
	NEW_UUID="$(plist_raw "${decoded}" 'UUID')" || die "built profile has no UUID"
	NEW_CREATION="$(plist_raw "${decoded}" 'CreationDate')" || die "built profile has no creation date"
	NEW_EXPIRATION="$(plist_raw "${decoded}" 'ExpirationDate')" || die "built profile has no expiration date"
	NEW_EXPIRATION_EPOCH="$(iso_to_epoch "${NEW_EXPIRATION}")" || die "built profile expiration is not parseable"
	[[ "${app_id}" == "${APPLICATION_ID}" && "${profile_team}" == "${TEAM_ID}" ]] || \
		die "built profile does not match the expected FinanceApp team and bundle"

	devices_xml="${TEMP_ROOT}/provisioned-devices.xml"
	/usr/bin/plutil -extract ProvisionedDevices xml1 -o "${devices_xml}" "${decoded}" 2>/dev/null || \
		die "built profile has no provisioned-device list"
	/usr/bin/grep -Fq "<string>${DEVICE_UDID}</string>" "${devices_xml}" || \
		die "built profile does not include the intended iPhone"

	now="$(/bin/date '+%s')"
	remaining=$(( NEW_EXPIRATION_EPOCH - now ))
	(( remaining >= MIN_NEW_VALIDITY_SECONDS )) || \
		die "built profile has less than six days of validity remaining"
	if (( BASELINE_EXPIRATION_EPOCH > 0 )); then
		(( NEW_EXPIRATION_EPOCH > BASELINE_EXPIRATION_EPOCH )) || \
			die "Xcode reused the old profile expiration instead of renewing it"
		[[ "${NEW_UUID}" != "${BASELINE_UUID}" ]] || \
			die "Xcode reused the old provisioning-profile UUID"
	fi
	log INFO "Validated build profile ${NEW_UUID} expiring ${NEW_EXPIRATION}."
}

install_and_verify_app() {
	local app_path="$1"
	local install_json="${TEMP_ROOT}/install.json"
	local apps_json="${TEMP_ROOT}/apps.json"
	local outcome installed_bundle

	/bin/rm -f "${install_json}" "${apps_json}" 2>/dev/null || true
	log INFO "Installing the validated app on the paired iPhone."
	/usr/bin/xcrun devicectl device install app \
		--device "${CORE_DEVICE_ID}" --timeout 180 --json-output "${install_json}" \
		"${app_path}" >/dev/null 2>&1 || die "devicectl could not install FinanceApp"
	outcome="$(plist_raw "${install_json}" 'info.outcome')" || die "install result did not contain an outcome"
	[[ "${outcome}" == "success" ]] || die "devicectl reported an unsuccessful installation"

	/usr/bin/xcrun devicectl device info apps \
		--device "${CORE_DEVICE_ID}" --bundle-id "${BUNDLE_ID}" \
		--timeout 60 --json-output "${apps_json}" >/dev/null 2>&1 || \
		die "could not verify the installed FinanceApp"
	outcome="$(plist_raw "${apps_json}" 'info.outcome')" || die "app query did not contain an outcome"
	installed_bundle="$(plist_raw "${apps_json}" 'result.apps.0.bundleIdentifier')" || \
		die "FinanceApp was not returned by the post-install query"
	[[ "${outcome}" == "success" && "${installed_bundle}" == "${BUNDLE_ID}" ]] || \
		die "post-install verification did not find the expected FinanceApp"
	log INFO "FinanceApp installation was verified on the iPhone."
}

launch_app_if_requested() {
	[[ "${LAUNCH_AFTER_INSTALL}" == "true" ]] || return 0
	if /usr/bin/xcrun devicectl device process launch \
		--device "${CORE_DEVICE_ID}" --timeout 60 "${BUNDLE_ID}" >/dev/null 2>&1; then
		log INFO "FinanceApp launched successfully for the supervised verification."
	else
		log WARN "FinanceApp was installed and verified, but iOS did not allow the optional foreground launch."
	fi
}

show_status() {
	find_matching_profiles
	print -r -- "FinanceApp automatic refresh"
	print -r -- "Bundle ID: ${BUNDLE_ID}"
	if [[ -n "${CURRENT_PROFILE}" ]]; then
		local now remaining_hours
		now="$(/bin/date '+%s')"
		remaining_hours=$(( (CURRENT_EXPIRATION_EPOCH - now) / 3600 ))
		print -r -- "Cached profile UUID: ${CURRENT_UUID}"
		print -r -- "Cached profile created: ${CURRENT_CREATION}"
		print -r -- "Cached profile expires: ${CURRENT_EXPIRATION} (${remaining_hours} hours remaining)"
	else
		print -r -- "Cached profile: not found"
	fi
	if device_is_reachable; then
		print -r -- "Paired iPhone reachable: yes"
	else
		print -r -- "Paired iPhone reachable: no"
		print -r -- "Device check: ${DEVICE_ERROR}"
	fi
	if [[ -f "${STATE_FILE}" && ! -L "${STATE_FILE}" ]]; then
		print -r -- "Recorded state:"
		/usr/bin/plutil -p "${STATE_FILE}"
	else
		print -r -- "Recorded state: none yet"
	fi
}

on_exit() {
	local exit_code=$?
	if (( ACTIVE_WATCHER_PID > 0 )); then
		/bin/kill "${ACTIVE_WATCHER_PID}" 2>/dev/null || true
		wait "${ACTIVE_WATCHER_PID}" 2>/dev/null || true
		ACTIVE_WATCHER_PID=0
	fi
	if (( ACTIVE_CHILD_PID > 0 )); then
		/bin/kill -TERM "${ACTIVE_CHILD_PID}" 2>/dev/null || true
		local -i stop_attempt=0
		while /bin/kill -0 "${ACTIVE_CHILD_PID}" 2>/dev/null && (( stop_attempt < 10 )); do
			/bin/sleep 1
			(( stop_attempt += 1 ))
		done
		if /bin/kill -0 "${ACTIVE_CHILD_PID}" 2>/dev/null; then
			/bin/kill -KILL "${ACTIVE_CHILD_PID}" 2>/dev/null || true
		fi
		wait "${ACTIVE_CHILD_PID}" 2>/dev/null || true
		ACTIVE_CHILD_PID=0
	fi
	if (( exit_code != 0 )); then
		restore_quarantined_profiles || true
		if [[ "${ATTEMPTED_REFRESH}" == "true" ]]; then
			record_failure
		fi
	fi
	release_lock
	if [[ -n "${TEMP_ROOT}" && -d "${TEMP_ROOT}" ]]; then
		/bin/rm -rf "${TEMP_ROOT}" 2>/dev/null || true
	fi
	return "${exit_code}"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if (( $# > 0 )); then
	case "$1" in
		--status)
			MODE="status"
			shift
			;;
		--force-renew)
			MODE="force"
			LAUNCH_AFTER_INSTALL="true"
			shift
			if (( $# > 0 )) && [[ "$1" == "--no-launch" ]]; then
				LAUNCH_AFTER_INSTALL="false"
				shift
			fi
			;;
		-h|--help|help)
			usage
			exit 0
			;;
		*)
			usage >&2
			exit 2
			;;
	esac
fi
(( $# == 0 )) || {
	usage >&2
	exit 2
}

# Load the last verified expiry before any writes, including runtime setup.
# Failures creating directories/temp files must also be recorded and notified.
load_installed_baseline
[[ "${MODE}" == "status" ]] || ATTEMPTED_REFRESH="true"
prepare_runtime
if [[ "${MODE}" == "status" ]]; then
	prepare_work_area
	show_status
	exit 0
fi

setup_logging
if ! acquire_lock; then
	exit 0
fi

[[ -d "${PROJECT}" ]] || die "Xcode project was not found: ${PROJECT}"
typeset -i now remaining
now="$(/bin/date '+%s')"
remaining=$(( BASELINE_EXPIRATION_EPOCH - now ))

if [[ "${MODE}" == "normal" && "${STATE_NEEDS_RETRY}" != "true" && -n "${BASELINE_UUID}" ]] && \
	(( remaining > REFRESH_LEAD_SECONDS )); then
	log INFO "Installed profile ${BASELINE_UUID} remains valid until ${BASELINE_EXPIRATION}; no refresh is needed."
	if [[ -d "${DERIVED_DATA}/Build" ]]; then
		clear_refresh_build_cache || log WARN "Could not remove the previous refresh build cache."
	fi
	exit 0
fi

ATTEMPTED_REFRESH="true"
if [[ -n "${BASELINE_UUID}" ]]; then
	log INFO "Refreshing installed profile ${BASELINE_UUID}, which expires ${BASELINE_EXPIRATION}."
else
	log INFO "No verified installed-profile baseline exists; a verified installation is required."
fi

check_disk_space
prepare_work_area
find_matching_profiles
device_is_reachable || die "${DEVICE_ERROR}; a later scheduled check will retry"
log INFO "The intended paired iPhone is connected and Developer Mode is enabled."

typeset reuse_pending_profile="false"
if [[ -z "${BASELINE_UUID}" ]] && \
	(( CURRENT_EXPIRATION_EPOCH - now >= MIN_NEW_VALIDITY_SECONDS )); then
	reuse_pending_profile="true"
	log INFO "Using the fresh cached profile ${CURRENT_UUID} for the first verified installation."
elif [[ "${MODE}" == "normal" && "${STATE_NEEDS_RETRY}" == "true" ]] && \
	(( CURRENT_EXPIRATION_EPOCH - now >= MIN_NEW_VALIDITY_SECONDS )) && \
	{ (( BASELINE_EXPIRATION_EPOCH == 0 )) || \
	  { (( CURRENT_EXPIRATION_EPOCH > BASELINE_EXPIRATION_EPOCH )) && [[ "${CURRENT_UUID}" != "${BASELINE_UUID}" ]]; }; }; then
	reuse_pending_profile="true"
	log INFO "Reusing the already-renewed cached profile ${CURRENT_UUID} for this installation retry."
else
	quarantine_matching_profiles
fi
build_app
typeset -r APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/${PRODUCT_NAME}.app"
validate_built_app "${APP_PATH}"
install_and_verify_app "${APP_PATH}"
write_success_state
QUARANTINE_ACTIVE="false"
log INFO "Automatic refresh completed successfully; the new profile expires ${NEW_EXPIRATION}."
launch_app_if_requested
clear_refresh_build_cache || log WARN "Refresh succeeded, but its disposable build cache could not be removed."

exit 0
