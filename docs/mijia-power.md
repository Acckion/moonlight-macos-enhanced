# Xiaomi smart-plug power control

The host context menu and in-stream menu include **Xiaomi Power**. This feature
is intended for a battery-equipped Windows laptop configured to boot on AC
attachment and to shut down with an independent Windows Power Guard task after
AC disconnection. It does not replace those firmware or Windows capabilities.

## Setup

1. Install `uv` on the Mac. It must be available at `/opt/homebrew/bin/uv` or
   `/usr/local/bin/uv`.
2. Run `uvx mijiaAPI==5.0.0 login` and scan the QR code with Xiaomi Home.
   Authentication is stored separately at `~/.config/mijia-api/auth.json`, never
   in the app, repository, host preferences, or exported streaming profiles.
3. Configure SSH public-key authentication and an SSH alias for the Windows host.
4. On Windows, install and start the `Acckion Power Guard Monitor` scheduled task
   (with `-Mode Monitor`) and verify cancellation by reconnecting AC. The monitor
   must work before login and the laptop needs a working battery.
5. Right-click the host → Xiaomi Power → Configure Smart Plug. Enter its exact
   Xiaomi Home name and the SSH host alias. Binding verifies the device and stores
   its stable device ID per Moonlight host; it does not switch power.

Only the verified `cuco.plug.v3` model is currently supported. Its power relay is
`on-2`; other `on-*` properties affect timers and protection settings. Additional
models must have explicit, tested property mappings before being enabled.

## Actions

- **Power On:** ensures the relay is on. It never power-cycles an already-on plug.
  Plug state is not evidence that Windows has finished booting; wait for discovery.
  An already-on plug cannot generate a new AC-attachment boot signal.
- **Shut Down via Power Guard:** asks for confirmation, verifies over SSH that the
  configured Windows guard task is running, then turns the relay off. A failed
  check leaves power on. Reconnecting power cancels the guard countdown.
- **Power Status:** reads relay state and optional power/fault telemetry.

Disconnecting the plug confirms only AC disconnection, not completed Windows
shutdown. Unsaved applications can block a non-forced shutdown, and a user can
cancel the countdown. After one write, the helper polls state without resending. Delayed cloud sync is
shown as pending, and a lost response is shown as unknown unless readback confirms
the requested state. Optional telemetry failures do not invalidate a confirmed
relay change.

The app does not force applications closed or wait for the
PC to go offline. An unavailable SSH connection blocks an on→off action. Power On
and status work independently of Windows being online.

All cloud operations run as short-lived helper processes; there is no background
service. `mijiaAPI` version 5.0.0 and its Python dependencies are resolved by `uv`
on first use, requiring internet access. This integration uses the third-party
mijiaAPI project and existing Xiaomi Cloud authentication. If authentication
expires, log in again from the terminal. Raw credentials and helper stderr are
not displayed in application alerts.

## Verification

`python3 -m unittest discover -s tests -p test_mijia_power.py -v` runs isolated
power-safety tests with fake devices; it never sends real relay writes. Actual
power-on/off checks should only be performed intentionally after saving work.

## Local package

After an arm64 Release build, run `scripts/package_mijia_power.sh`. This produces
`dist/MoonlightPower.app.zip` with local ad-hoc signatures and a distinct display
name. The packaged app leaves the upstream updater unconfigured to avoid
overwrites; it does not change the original application or its update settings.
The bundle identifier is retained so the local host library and settings are reused.
Do not run the original and local builds simultaneously.
