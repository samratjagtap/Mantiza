"""Writes the App Intents index (Metadata.appintents) for the app and the widget.

iOS only lists an app's actions (Siri phrases, Shortcuts actions, Control Centre buttons, Live
Activity buttons) from this index. Xcode writes it with Apple's appintentsmetadataprocessor, which
only runs on a Mac. Off a Mac, the open-source stand-in from rules_applecross (Apache 2.0, kept in
tools/appintents) writes the same content from the compiler's constant values, which the build
already leaves in .build.

Run from apps/mantiza AFTER `xtool dev build` and BEFORE `xtool dev` (which packs the result, listed
under `resources` in xtool.yml):

    python3 scripts/make_intents.py
"""
import json
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
TOOL = APP.parent.parent / "tools" / "appintents" / "appintentsmetadataprocessor.py"
OBJECTS = APP / ".build" / "out" / "Intermediates.noindex" / "Mantiza.build"
# The Xcode build the index claims to come from (27.0; the stand-in was compared against it).
XCODE_BUILD = "27A5194"
# module -> where its index goes (xtool.yml lists these folders as resources)
MODULES = {"Mantiza": APP / "Generated" / "app", "MantizaWidget": APP / "Generated" / "widget"}

configs = sorted(OBJECTS.glob("*-iphoneos"), key=lambda p: p.stat().st_mtime, reverse=True)
if not configs:
    sys.exit(f"No build found in {OBJECTS}: run `xtool dev build` first")

for module, out in MODULES.items():
    values = sorted((configs[0] / f"{module}-t.build" / "Objects-normal" / "arm64").glob("*.swiftconstvalues"))
    if not values:
        sys.exit(f"No constant values for {module}: run `xtool dev build` first")
    out.mkdir(parents=True, exist_ok=True)
    listing = out / "const-values.txt"
    listing.write_text("\n".join(str(v) for v in values) + "\n", encoding="utf-8")
    done = subprocess.run([sys.executable, "-I", str(TOOL), "--compile-time-extraction", "--output", str(out),
                           "--module-name", module, "--xcode-version", XCODE_BUILD,
                           "--swift-const-vals-list", str(listing)])
    listing.unlink()
    if done.returncode != 0:
        sys.exit(f"The App Intents index for {module} could not be written (see the message above)")
    data = json.loads((out / "Metadata.appintents" / "extract.actionsdata").read_text(encoding="utf-8"))
    print(f"{module}: {len(data['actions'])} actions ({', '.join(sorted(data['actions']))}), "
          f"{len(data['autoShortcuts'])} Siri shortcuts")
