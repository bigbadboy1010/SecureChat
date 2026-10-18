#!/usr/bin/env python3
"""Fail closed before automated distribution of the next security beta."""
import json
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parent.parent
project = (root / 'PrivateChat.xcodeproj/project.pbxproj').read_text()
builds = [int(b) for b in re.findall(r'CURRENT_PROJECT_VERSION\s*=\s*(\d+);', project)]
gate = json.loads((root / 'Config/SecurityReleaseGate.json').read_text())
if not builds:
    sys.exit('Cannot determine build: TestFlight upload blocked.')
if max(builds) >= gate['minimumBuild']:
    if gate.get('uploadAllowed') is not True or not gate.get('checks') or not all(value is True for value in gate['checks'].values()):
        sys.exit('TestFlight upload blocked: ' + gate['reason'])
print('Security release gate passed for this build.')
