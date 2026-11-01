# /// script
# requires-python = ">=3.10,<3.15"
# dependencies = ["mijiaAPI==5.0.0"]
# ///
"""One-shot MIoT cloud helper. JSON on stdout; never emit credentials."""
import argparse
import base64
import json
import subprocess
import sys
import requests

# Bound individual cloud requests; a network failure must not hold the UI indefinitely.
_request = requests.sessions.Session.request
def _bounded_request(self, method, url, **kwargs):
    kwargs.setdefault("timeout", 15)
    return _request(self, method, url, **kwargs)
from mijiaAPI import mijiaAPI, mijiaDevice


def verify_shutdown_guard(alias):
    if not alias or alias.startswith('-') or any(c.isspace() for c in alias):
        raise ValueError('需要有效的 SSH 主机别名，以检查 Windows 断电关机保护。')
    script = r"""$t=Get-ScheduledTask -TaskName 'Acckion Power Guard Monitor' -ErrorAction Stop; if($t.State -ne 'Running'){exit 2}; if(-not ($t.Actions.Arguments -match '-Mode Monitor')){exit 3}; Write-Output 'POWER_GUARD_READY'"""
    encoded = base64.b64encode(script.encode('utf-16le')).decode('ascii')
    result = subprocess.run(
        ['/usr/bin/ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=6',
         '-o', 'StrictHostKeyChecking=yes', alias,
         'powershell.exe -NoProfile -NonInteractive -EncodedCommand ' + encoded],
        capture_output=True, timeout=15,
    )
    if result.returncode != 0 or b'POWER_GUARD_READY' not in result.stdout:
        raise RuntimeError('无法确认 Windows 断电关机保护正在运行，未断开插座。请检查 SSH 连接及 Power Guard 任务。')


def main():
    requests.sessions.Session.request = _bounded_request
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('resolve', 'status', 'on', 'off'))
    parser.add_argument('--name')
    parser.add_argument('--device')
    parser.add_argument('--guard-host')
    args = parser.parse_args()
    api = mijiaAPI()
    if not api.available:
        raise RuntimeError('米家登录已失效。请在终端运行 uvx mijiaAPI login，扫码后再试。')
    devices = api.get_devices_list()
    matches = [d for d in devices if (
        str(d.get('did')) == args.device if args.device else d.get('name') == args.name
    )]
    if len(matches) != 1:
        raise ValueError('未找到唯一匹配的插座，请检查米家中的设备名称。')
    info = matches[0]
    if info.get('isOnline') is False:
        raise RuntimeError('插座当前离线，无法确认电源状态。')
    plug = mijiaDevice(api, did=str(info['did']))
    # Only this verified model is supported: its other `on-*` properties control protections.
    if plug.model != 'cuco.plug.v3':
        raise ValueError('目前只支持已验证的 cuco.plug.v3 插座，未操作此设备。')
    if args.command in ('on', 'off'):
        target = args.command == 'on'
        current = plug.get('on-2')
        # Idempotent: never power-cycle a running PC when clicking Power On.
        if current != target:
            if not target:
                verify_shutdown_guard(args.guard_host)
            plug.set('on-2', target)
            if plug.get('on-2') != target:
                raise RuntimeError('米家云端未确认电源变更，请在米家 App 核对。')
    output = {'did': str(info['did']), 'name': plug.name, 'model': plug.model,
              'on': plug.get('on-2')}
    # Optional telemetry must not turn a confirmed power action into an apparent failure.
    for key, prop in [('watts', 'electric-power'), ('fault', 'fault')]:
        try:
            output[key] = plug.get(prop)
        except Exception:
            output[key] = None
    print(json.dumps(output, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'error': str(exc)}, ensure_ascii=False), flush=True)
        sys.exit(1)
