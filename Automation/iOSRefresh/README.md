# FinanceApp automatic iOS refresh

This setup keeps the Personal Team build of `FinanceApp` available on the paired iPhone without publishing it. After the one-time installation, there is no routine Xcode work, App Store upload, IPA packaging, or **Run** button to remember.

The per-user LaunchAgent starts a lightweight check at login and at 09:30, 13:30, 17:30, and 21:30 local time. The check exits without building while the installed provisioning profile has more than 48 hours remaining. Inside that window it renews the development signing, validates the new app and profile, installs the app on the intended phone, verifies the installation, and records the result. Scheduled renewals do not unexpectedly bring the app to the foreground; the supervised setup test launches it once. If the phone is temporarily unavailable, no success is recorded and the next scheduled check retries automatically.

## Unavoidable Apple constraints

- The Mac must be awake with this user logged in. This setup does not change power settings or wake a powered-off Mac.
- The signing keychain must be available to the logged-in user. Xcode must already be signed in to the Apple ID/Personal Team used by this project.
- The iPhone must remain trusted and paired with Xcode, have Developer Mode enabled, and be reachable over its configured Wi-Fi connection or USB during at least one renewal attempt.
- Xcode does not have to remain open after pairing. A new trust, Developer Mode, or unlock prompt from macOS/iOS still requires a person to accept it.
- If the Mac and phone are never simultaneously available before the seven-day profile expires, no local automation can prevent that expiration. The four daily attempts provide multiple chances during the 48-hour renewal window.

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

Check the app/profile/device view without changing anything:

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
- An unavailable or locked phone, unavailable signing identity, failed package resolution, failed build, or failed validation does not advance the recorded successful state. The later calendar entries retry.
- When the Mac sleeps through a calendar time, launchd can run the missed event after wake; multiple missed events may be coalesced. A powered-off or logged-out Mac cannot run a user LaunchAgent.
- `refresh.log` contains the concise decision and result. `xcodebuild.log` contains build details. Both are bounded by the refresh script rather than by launchd's standard-output file descriptors.
- If `status` reports that the service is not loaded, rerun `install`. If device checks fail, open Xcode's Devices and Simulators window once and confirm that the same iPhone is trusted and available over the network.

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
