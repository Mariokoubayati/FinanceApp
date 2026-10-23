# FinanceApp automatic iOS refresh

This setup keeps the Personal Team build of `FinanceApp` available on the paired iPhone without publishing it. After the one-time installation, there is no routine Xcode work, App Store upload, IPA packaging, or **Run** button to remember.

The per-user LaunchAgent starts a lightweight check at login and every 30 minutes while the Mac is awake. The check exits without building or querying the phone while the last verified installed provisioning profile has more than 48 hours remaining. Inside that window it requests a connection to the paired phone, renews the development signing, validates the new app and profile, installs the app, verifies the installation, and records the result. Scheduled renewals do not unexpectedly bring the app to the foreground; the supervised setup test launches it once. If the phone is temporarily unavailable, no success is recorded and the next scheduled check retries automatically.

## Unavoidable Apple constraints

- The Mac must be awake with this user logged in. This setup does not change power settings or wake a powered-off Mac.
- The signing keychain must be available to the logged-in user. Xcode must already be signed in to the Apple ID/Personal Team used by this project.
- The iPhone must remain trusted and paired with Xcode, have Developer Mode enabled, and be reachable over its configured Wi-Fi connection or USB during at least one renewal attempt.
- Xcode does not have to remain open after pairing. A new trust, Developer Mode, or unlock prompt from macOS/iOS still requires a person to accept it.
- If the Mac and phone are never simultaneously available before the seven-day profile expires, no local automation can prevent that expiration. Checks every 30 minutes provide multiple chances during the 48-hour renewal window.
- Builds require at least 1 GB of free disk space. This is a minimum preflight check, not a guarantee for every Xcode build. The job discards its own disposable `~/Library/Caches/FinanceAppRefresh/DerivedData` after a verified renewal and before a build if space is low. A fresh-profile check also removes leftovers from a previous successful build. State, logs, profile backups, project source, and other applications' caches are preserved.
- Warnings use macOS notifications. Allow notifications for the script runner if macOS requests it; Focus or notification settings can suppress their presentation.

## Files and retained data

| Purpose | Location |
| --- | --- |
| Installed refresh script | `~/Library/Application Support/FinanceAppRefresh/bin/refresh-finance-app.zsh` |
| Renewal state and recoverable profile backups | `~/Library/Application Support/FinanceAppRefresh/` |
| Rotated refresh/build logs | `~/Library/Logs/FinanceAppRefresh/` |
| Derived data, lock, and disposable cache | `~/Library/Caches/FinanceAppRefresh/` |
| Installed LaunchAgent | `~/Library/LaunchAgents/com.mario.financeapp.refresh.plist` |

No Apple ID password or app-specific password is stored. Signing remains Xcode's responsibility through the user's keychain. Runtime directories are private to the user, and a changed installed script or plist is backed up before replacement.

## Install or update

From Terminal, run:

```zsh
/bin/zsh /Users/koubayati/FinanceApp/Automation/iOSRefresh/install-refresh-agent.zsh install
```

The installer validates both zsh files and the plist, copies the runtime script atomically, renders absolute user/Xcode paths, unloads any prior copy of the same label, and bootstraps the new agent. It is safe to rerun after these source files are updated. `RunAtLoad` requests the first normal check immediately.

## Verify

Check the installed files and launchd registration:

```zsh
/bin/zsh /Users/koubayati/FinanceApp/Automation/iOSRefresh/install-refresh-agent.zsh status
```

Check the app/profile/device view without rebuilding or installing (this can establish the phone connection):

```zsh
/bin/zsh "$HOME/Library/Application Support/FinanceAppRefresh/bin/refresh-finance-app.zsh" --status
```

Inspect the service and recent self-managed logs:

```zsh
/bin/launchctl print "gui/$(/usr/bin/id -u)/com.mario.financeapp.refresh"
/usr/bin/tail -n 100 "$HOME/Library/Logs/FinanceAppRefresh/refresh.log"
/usr/bin/tail -n 100 "$HOME/Library/Logs/FinanceAppRefresh/xcodebuild.log"
```

Request another normal scheduled-style check immediately:

```zsh
/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/com.mario.financeapp.refresh"
```

That command is normally a quick no-op while more than 48 hours remain. For a supervised end-to-end renewal test only, keep the paired phone nearby and run:

```zsh
/bin/zsh "$HOME/Library/Application Support/FinanceAppRefresh/bin/refresh-finance-app.zsh" --force-renew
```

`--force-renew --no-launch` performs the same renewal but suppresses the final foreground app launch. Neither command publishes the app.

## Retry and troubleshooting behavior

- A normal check that finds a fresh profile exits successfully without rebuilding.
- An idle, disconnected tunnel is not treated as proof that the phone is unreachable. The script makes up to two app-query connection attempts and checks the connected device's identity, pairing, and Developer Mode again. A successful device-list or cached-details response alone is not enough.
- An unavailable or locked phone, low disk space, unavailable signing identity, failed package resolution, failed build, or failed validation does not advance the recorded successful state. Later interval checks retry.
- Interval checks do not wake the Mac; attempts missed while asleep are not replayed. The next interval check after wake retries, and login triggers a check immediately. A powered-off or logged-out Mac cannot run a user LaunchAgent.
- Failures warn after the second attempt, immediately for low disk space or a last verified profile within 24 hours of expiry, then at most daily for the same urgency. Reaching the 24-hour window or expiry triggers a fresh warning. Failed notification commands are retried. Notifications are attempted even when the disk is too full to save failure state.
- Manual Xcode installs do not update this utility's state. Its recorded expiry can therefore be older than the phone's current profile; the next verified renewal updates that baseline. A cached profile is never assumed to have reached the phone.
- `refresh.log` contains the concise decision and result. `xcodebuild.log` contains build details. Both are bounded by the refresh script rather than by launchd's standard-output file descriptors.
- `device-connection.log` retains bounded diagnostic output from connection attempts, including failures hidden by the previous reachability check.
- If `status` reports that the service is not loaded, rerun `install`. If device checks fail, open Xcode's Devices and Simulators window once and confirm that the same iPhone is trusted and available over the network.

Run the isolated regression checks without contacting a phone or changing the installed agent:

```zsh
/usr/bin/python3 /Users/koubayati/FinanceApp/Automation/iOSRefresh/tests/test_refresh.py
```

## Uninstall, preserve, or purge

Unload the job and remove only its installed plist and runtime script:

```zsh
/bin/zsh /Users/koubayati/FinanceApp/Automation/iOSRefresh/install-refresh-agent.zsh uninstall
```

An ordinary uninstall intentionally preserves state, profile backups, logs, and cache for diagnosis or a later reinstall.

To explicitly and permanently delete those retained directories as well, use the separate `--purge` argument:

```zsh
/bin/zsh /Users/koubayati/FinanceApp/Automation/iOSRefresh/install-refresh-agent.zsh uninstall --purge
```

Purge is irreversible from this utility. To restore automation after either form of uninstall, run `install` again.
