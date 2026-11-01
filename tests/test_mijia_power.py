"""Verify power actions cannot bypass the guard or touch unrelated MIoT switches."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch
import contextlib
import io

fake_library = types.ModuleType('mijiaAPI')
fake_library.mijiaAPI = object
fake_library.mijiaDevice = object
fake_requests = types.ModuleType('requests')
fake_requests.sessions = types.SimpleNamespace(Session=type('Session', (), {'request': lambda *a, **kw: None}))
with patch.dict(sys.modules, {'mijiaAPI': fake_library, 'requests': fake_requests}):
    spec = importlib.util.spec_from_file_location('power', Path(__file__).parents[1] / 'Limelight/macOS/PowerControl/mijia_power.py')
    power = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(power)

class Plug:
    model = 'cuco.plug.v3'
    name = 'Test Plug'
    def __init__(self, on):
        self.on = on
        self.writes = []
    def get(self, prop):
        return {'on-2': self.on, 'electric-power': 42, 'fault': 0}[prop]
    def set(self, prop, value):
        self.writes.append((prop, value))
        if prop != 'on-2':
            raise AssertionError('Wrong MIoT switch')
        self.on = value

class PowerSafetyTests(unittest.TestCase):
    def run_command(self, command, plug, guard=None):
        api = types.SimpleNamespace(available=True, get_devices_list=lambda: [
            {'did': '123', 'name': 'Test Plug', 'isOnline': True}])
        with patch.object(power, 'mijiaAPI', return_value=api), \
             patch.object(power, 'mijiaDevice', return_value=plug), \
             patch.object(power, 'verify_shutdown_guard', side_effect=guard) as check, \
             patch.object(sys, 'argv', ['helper', command, '--device', '123', '--guard-host', 'pc']), \
             contextlib.redirect_stdout(io.StringIO()):
            power.main()
            return check.call_count

    def test_status_never_writes(self):
        plug=Plug(True)
        self.run_command('status', plug)
        self.assertEqual(plug.writes, [])

    def test_power_on_does_not_cycle_live_pc(self):
        plug=Plug(True)
        self.run_command('on', plug)
        self.assertEqual(plug.writes, [])

    def test_power_on_targets_supply_switch(self):
        plug=Plug(False)
        self.run_command('on', plug)
        self.assertEqual(plug.writes, [('on-2', True)])

    def test_guard_failure_leaves_power_on(self):
        plug=Plug(True)
        with self.assertRaises(RuntimeError):
            self.run_command('off', plug, RuntimeError('No guard'))
        self.assertTrue(plug.on)
        self.assertEqual(plug.writes, [])

    def test_off_requires_guard_then_verifies_state(self):
        plug=Plug(True)
        self.assertEqual(self.run_command('off', plug), 1)
        self.assertFalse(plug.on)
        self.assertEqual(plug.writes, [('on-2', False)])

    def test_unverified_model_is_rejected(self):
        plug=Plug(True)
        plug.model='different.plug'
        with self.assertRaises(ValueError):
            self.run_command('off', plug)
        self.assertEqual(plug.writes, [])

    def test_ssh_option_is_rejected_before_process_launch(self):
        with patch.object(power.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                power.verify_shutdown_guard('-oProxyCommand=bad')
            run.assert_not_called()

if __name__ == '__main__':
    unittest.main()
