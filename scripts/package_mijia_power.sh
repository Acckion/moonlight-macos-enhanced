#!/bin/bash
# Package a local power-control build without replacing the upstream installation.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source_app=${1:-"$root/build/Build/Products/Release/MoonlightEnhanced.app"}
staging=$(mktemp -d "${TMPDIR:-/private/tmp}/moonlight-power-package.XXXXXX")
app="$staging/MoonlightPower.app"
ditto --noextattr --norsrc "$source_app" "$app"
python3 - "$app" <<'PY'
import plistlib,sys,subprocess
from pathlib import Path
app=Path(sys.argv[1]); info=app/'Contents/Info.plist'
p=plistlib.loads(info.read_bytes())
p['CFBundleDisplayName']='Moonlight Power'
p['UpdateDisplayVersion']='1.3.9 + Power'
# The upstream updater cannot preserve local features. Leave it unconfigured in this package.
# No signature verification is bypassed: SparkleUpdateManager simply never creates an updater.
p['SUPublicEDKey']=''
p['SUEnableAutomaticChecks']=False
info.write_bytes(plistlib.dumps(p))
for locale,name in [('zh-Hans','Moonlight 电源版'),('en','Moonlight Power')]:
    path=app/f'Contents/Resources/{locale}.lproj/InfoPlist.strings'
    values=plistlib.loads(subprocess.check_output(['/usr/bin/plutil','-convert','xml1','-o','-',str(path)])) if path.exists() else {}
    values['CFBundleDisplayName']=name
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(plistlib.dumps(values,fmt=plistlib.FMT_BINARY))
PY
python3 "$root/scripts/sign_app_bundle.py" "$app" \
  --entitlements "$root/Moonlight.entitlements" \
  --extension-entitlements "$root/FileProviderExtension/FileProvider.entitlements"
mkdir -p "$root/dist"
ditto --noextattr --norsrc -c -k --keepParent "$app" "$root/dist/MoonlightPower.app.zip"
printf '\nSigned app: %s\nArchive: %s\n' "$app" "$root/dist/MoonlightPower.app.zip"
