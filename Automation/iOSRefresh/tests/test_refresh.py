"""Isolated regressions: fake Apple services, real zsh/plists, no phone access."""

import json
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile
import time
import unittest


SOURCE = Path(__file__).resolve().parents[1]
SCRIPT = (SOURCE / "refresh-finance-app.zsh").read_text()
DEVICE_ID = "A466D016-C9E0-51FB-84CA-AFBE9BB0CE7A"
UDID = "00008140-00104D9634E3001C"

FAKE_XCRUN = r'''#!/usr/bin/python3
import json, os, pathlib, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ["FINANCE_TEST_ROOT"])
events = root / "calls"
previous = events.read_text() if events.exists() else ""
probe = "apps" in args
with events.open("a") as out:
    out.write(("probe" if probe else "list") + "\n")
mode = os.environ.get("DEVICE_MODE", "reconnect")
connected = mode == "connected" or (mode == "reconnect" and "probe" in previous)
device = {
    "identifier": "A466D016-C9E0-51FB-84CA-AFBE9BB0CE7A",
    "hardwareProperties": {"udid": "wrong" if mode == "wrong" else "00008140-00104D9634E3001C"},
    "deviceProperties": {"developerModeStatus": "enabled"},
    "connectionProperties": {"pairingState": "paired", "tunnelState": "connected" if connected else "disconnected"},
}
output = {"info": {"outcome": "success"}, "result": {"apps": []} if probe else {"devices": [device]}}
pathlib.Path(args[args.index("--json-output") + 1]).write_text(json.dumps(output))
'''

FAKE_DF = r'''#!/bin/zsh
print -r -- "Filesystem 1024-blocks Used Available Capacity Mounted on"
available="${FREE_KB:-4000000}"
if [[ "${SPACE_AFTER_CLEAN:-false}" == "true" && ! -d "${FINANCE_TEST_ROOT}/Library/Caches/FinanceAppRefresh/DerivedData/Build" ]]; then
    available=4000000
fi
print -r -- "disk 10000000 1 ${available} 1% /"
'''

FAKE_NOTICE = r'''#!/bin/zsh
/bin/cat >/dev/null
print -r -- "$*" >>"${FINANCE_TEST_ROOT}/notices"
exit "${NOTICE_EXIT:-0}"
'''


class RefreshTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="finance-refresh-test-", dir="/private/tmp")
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, FINANCE_TEST_ROOT=str(self.root))
        self.script = SCRIPT.replace('"${HOME}/Library/', '"${FINANCE_TEST_ROOT}/Library/')
        self.script = self.script.replace("/private/tmp/financeapp-refresh.XXXXXX", str(self.root / "work.XXXXXX"))
        for command, stub in (("/usr/bin/xcrun", FAKE_XCRUN),
                              ("/bin/df", FAKE_DF),
                              ("/usr/bin/osascript", FAKE_NOTICE)):
            path = self.root / Path(command).name
            path.write_text(stub)
            path.chmod(0o700)
            self.script = self.script.replace(command, shlex.quote(str(path)))
        self.state = self.root / "Library/Application Support/FinanceAppRefresh/state.plist"

    def tearDown(self):
        self.temp.cleanup()

    def run_shell(self, body="", full=False, **env):
        code = self.script if full else self.script.split("\ntrap on_exit EXIT", 1)[0] + "\n" + body
        path = self.root / "run.zsh"
        path.write_text(code)
        return subprocess.run(["/bin/zsh", str(path)], env=dict(self.env, **env),
                              text=True, capture_output=True, timeout=20)

    def save_state(self, **extra):
        self.state.parent.mkdir(parents=True, exist_ok=True)
        state = {"ProfileUUID": "previous-profile", "ProfileCreationDate": "2026-01-01T00:00:00Z",
                 "ProfileExpirationDate": "2026-01-08T00:00:00Z", "ConsecutiveFailures": 0,
                 "LastResult": "success", "NeedsRetry": False}
        state.update(extra)
        self.state.write_bytes(plistlib.dumps(state))

    def read_state(self):
        return plistlib.loads(self.state.read_bytes())

    def notices(self):
        path = self.root / "notices"
        return path.read_text().splitlines() if path.exists() else []

    def test_idle_phone_is_actively_connected(self):
        result = self.run_shell("prepare_runtime; prepare_work_area; device_is_reachable")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "calls").read_text().splitlines(), ["list", "probe", "list"])

    def test_cached_success_without_connection_is_rejected(self):
        result = self.run_shell("prepare_runtime; prepare_work_area; device_is_reachable", DEVICE_MODE="unavailable")
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.root / "calls").read_text().count("probe"), 2)

    def test_wrong_phone_never_gets_a_connection_request(self):
        result = self.run_shell("prepare_runtime; prepare_work_area; device_is_reachable", DEVICE_MODE="wrong")
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.root / "calls").read_text(), "list\n")

    def test_connected_phone_does_not_need_a_probe(self):
        result = self.run_shell("prepare_runtime; prepare_work_area; device_is_reachable", DEVICE_MODE="connected")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "calls").read_text(), "list\n")

    def test_low_disk_stops_before_phone_or_profile_changes(self):
        self.save_state()
        result = self.run_shell(full=True, FREE_KB="100000")
        self.assertEqual(result.returncode, 1)
        state = self.read_state()
        self.assertIn("low disk space", state["LastFailureMessage"])
        self.assertEqual(state["ProfileUUID"], "previous-profile")
        self.assertTrue(state["NeedsRetry"])
        self.assertFalse((self.root / "calls").exists())
        self.assertEqual(len(self.notices()), 1)

    def test_unparseable_disk_space_fails_closed(self):
        result = self.run_shell("prepare_runtime; check_disk_space", FREE_KB="unknown")
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not determine free disk", result.stdout)

    def test_low_disk_can_reclaim_only_the_jobs_build_cache(self):
        self.save_state()
        cache = self.root / "Library/Caches/FinanceAppRefresh"
        build = cache / "DerivedData/Build"
        build.mkdir(parents=True)
        (build / "generated-app").write_text("disposable")
        result = self.run_shell('''
prepare_runtime
/bin/mkdir "${LOCK_DIR}"
print -r -- "$$" >"${LOCK_DIR}/pid"
check_disk_space
''', FREE_KB="100", SPACE_AFTER_CLEAN="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(build.exists())
        self.assertTrue((cache / "run.lock/pid").exists())
        self.assertEqual(self.read_state()["ProfileUUID"], "previous-profile")

    def test_fresh_install_prunes_old_build_without_touching_phone(self):
        self.save_state(ProfileExpirationDate="2099-01-08T00:00:00Z")
        build = self.root / "Library/Caches/FinanceAppRefresh/DerivedData/Build"
        build.mkdir(parents=True)
        result = self.run_shell(full=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(build.exists())
        self.assertFalse((self.root / "calls").exists())
        self.assertEqual(self.read_state()["LastResult"], "success")

    def test_fresh_verified_install_skips_disk_and_device_work(self):
        self.save_state(ProfileExpirationDate="2099-01-08T00:00:00Z")
        result = self.run_shell(full=True, FREE_KB="100")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "calls").exists())
        self.assertEqual(self.read_state()["LastResult"], "success")
        self.assertFalse(list(self.root.glob("work.*")))

    def test_notification_repeats_daily_and_escalates_on_expiry(self):
        result = self.run_shell('''
prepare_runtime
LAST_ERROR="phone connection failed"
record_failure
record_failure
record_failure
old_notice=$(( $(/bin/date '+%s') - 86401 ))
plist_set_integer "${STATE_FILE}" LastNotifiedAtEpoch "${old_notice}"
record_failure
BASELINE_EXPIRATION_EPOCH=$(( $(/bin/date '+%s') + 3600 ))
record_failure
BASELINE_EXPIRATION_EPOCH=$(( $(/bin/date '+%s') - 1 ))
record_failure
record_failure
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        notices = self.notices()
        self.assertEqual(len(notices), 4)
        self.assertIn("within 24 hours", notices[2])
        self.assertIn("has expired", notices[3])
        self.assertEqual(self.read_state()["ConsecutiveFailures"], 7)
        self.assertEqual(self.read_state()["LastNotifiedUrgency"], 2)

    def test_failed_notifications_are_retried_without_losing_state(self):
        self.save_state(ConsecutiveFailures=140)
        result = self.run_shell('prepare_runtime; LAST_ERROR="phone unavailable"; record_failure; record_failure', NOTICE_EXIT="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.notices()), 2)
        self.assertEqual(self.read_state()["ConsecutiveFailures"], 142)
        self.assertNotIn("LastNotifiedAtEpoch", self.read_state())

    def test_temp_directory_failure_is_recorded_and_warns(self):
        self.save_state()
        self.script = self.script.replace("/usr/bin/mktemp", "/usr/bin/false")
        result = self.run_shell(full=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("temporary directory", self.read_state()["LastFailureMessage"])
        self.assertEqual(len(self.notices()), 1)

    def test_notification_is_attempted_even_if_failure_state_cannot_be_saved(self):
        self.save_state(ConsecutiveFailures=140)
        self.script = self.script.replace("/bin/cp", "/usr/bin/false")
        result = self.run_shell('prepare_runtime; LAST_ERROR="low disk space"; record_failure')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.notices()), 1)
        self.assertEqual(self.read_state()["ConsecutiveFailures"], 140)

    def test_success_clears_failure_and_notification_state(self):
        self.save_state(ConsecutiveFailures=140, LastNotifiedAtEpoch=int(time.time()), LastNotifiedUrgency=2)
        result = self.run_shell('''
prepare_runtime
NEW_UUID="renewed-profile"
NEW_CREATION="2026-10-17T11:00:00Z"
NEW_EXPIRATION="2026-10-24T11:00:00Z"
write_success_state
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        self.assertEqual(state["LastResult"], "success")
        self.assertEqual(state["ConsecutiveFailures"], 0)
        self.assertFalse(state["NeedsRetry"])
        self.assertNotIn("LastNotifiedAtEpoch", state)

    def test_half_hour_schedule(self):
        agent = plistlib.loads((SOURCE / "com.mario.financeapp.refresh.plist").read_bytes())
        self.assertEqual(agent["StartInterval"], 1800)
        self.assertTrue(agent["RunAtLoad"])
        self.assertNotIn("StartCalendarInterval", agent)


if __name__ == "__main__":
    unittest.main(verbosity=2)
