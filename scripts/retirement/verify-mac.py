#!/usr/bin/env python3
"""Allowlist the minimal app's own contents; Sparkle is the only embedded framework."""
import pathlib, plistlib, subprocess, sys
app=pathlib.Path(sys.argv[1])
p=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert p['CFBundleIdentifier'] in ['local.classwise.mac.apple-ai-beta','local.classwise.mac.test','local.classwise.mac.update-test']
assert p['CFBundleShortVersionString']=='0.5.1' and int(p['CFBundleVersion'])>=11
assert not any(k.startswith('BYESchedule') for k in p)
allowed={'Info.plist','MacOS','Resources','Frameworks','_CodeSignature'}
assert set(x.name for x in (app/'Contents').iterdir())<=allowed
assert set(x.name for x in (app/'Contents/MacOS').iterdir())=={'Classwise'}
assert set(x.name for x in (app/'Contents/Resources').iterdir())=={'AppIcon.icns','LibreBaskerville-Bold.ttf','THIRD_PARTY_NOTICES.txt'}
assert set(x.name for x in (app/'Contents/Frameworks').iterdir())=={'Sparkle.framework'}
binary=(app/'Contents/MacOS/Classwise').read_bytes()
for marker in [b'prod-apiweb.pasadena.edu',b'ratemyprofessors.com',b'bye-schedule-api',b'ClasswiseCore',b'RMPReader',b'BYEAPI',b'bye_pk_']:
    assert marker not in binary, 'Retirement binary contains a legacy implementation marker'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('Minimal Mac package allowlist, legacy-code exclusion and signature passed.')
