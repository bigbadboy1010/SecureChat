#!/usr/bin/env python3
"""Fail closed before automated distribution of the next security beta."""
import json
import argparse
import plistlib
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parent.parent
project = (root / 'PrivateChat.xcodeproj/project.pbxproj').read_text()
builds = [int(b) for b in re.findall(r'CURRENT_PROJECT_VERSION\s*=\s*(\d+);', project)]
gate = json.loads((root / 'Config/SecurityReleaseGate.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--staging-upload-only', action='store_true', help='Check the owner-authorized upload to Apple only; this never grants tester distribution.')
args = parser.parse_args()
if not builds:
    sys.exit('Cannot determine build: TestFlight upload blocked.')
if args.staging_upload_only:
    staging = gate.get('stagingUpload', {})
    info = plistlib.loads((root / 'Config/Info.plist').read_bytes())
    if (staging.get('ownerAuthorized') is not True
            or set(builds) != {staging.get('build')}
            or staging.get('testerDistributionAllowed') is not False
            or info.get('ITSAppUsesNonExemptEncryption') is not True
            or 'ITSEncryptionExportComplianceCode' in info):
        sys.exit('Staging upload blocked: explicit build authorization and truthful pending encryption declaration required.')
    print('Apple upload-only authorization passed. Tester distribution and security acceptance remain blocked.')
    sys.exit(0)
if max(builds) >= gate['minimumBuild']:
    if gate.get('uploadAllowed') is not True or not gate.get('checks') or not all(value is True for value in gate['checks'].values()):
        sys.exit('TestFlight upload blocked: ' + gate['reason'])
print('Security release gate passed for this build.')
