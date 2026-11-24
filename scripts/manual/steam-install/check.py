"""Checks what install-steamos.sh wrote, with an independent parser (ValvePython's vdf)
and zlib's CRC-32. Usage: check.py COMMAND ARGS...; exits non-zero with a message.

  ours VDF APPIMAGE GRID ART [KEY] [APPID]   exactly one shortcut for APPIMAGE, with the
                                     fields, ID and grid files INT-28/INT-29 ask for
  appended OLD NEW KEY               NEW is OLD plus one shortcut KEY at the end, and
                                     OLD's bytes are all still there, unchanged
  legacy OLD NEW KEY APPIMAGE        NEW is OLD with shortcut KEY's Exe and StartDir
                                     moved to APPIMAGE and nothing else changed
  count VDF N                        VDF has N shortcuts
  appid EXE NAME                     prints Steam's shortcut ID for EXE + NAME
"""

import hashlib
import os
import sys
import zlib

import vdf

ART = {"p": "steam-portrait.png", "": "steam-wide.png", "_hero": "steam-hero.png",
       "_logo": "steam-logo.png", "_icon": "steam-icon.png"}


def fail(msg):
    sys.exit(f"check failed: {msg}")


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    try:
        return data, vdf.binary_loads(data)["shortcuts"]
    except Exception as e:  # noqa: BLE001
        fail(f"{path} does not parse: {e}")


def field(entry, name):
    for k, v in entry.items():
        if k.lower() == name.lower():
            return v
    return None


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def steam_id(exe, name):
    return zlib.crc32((exe + name).encode("utf-8")) | 0x80000000


def ours(path, appimage, grid, art, key=None, appid=None):
    _, sc = load(path)
    exe = f'"{appimage}"'
    found = [(k, e) for k, e in sc.items() if isinstance(e, dict) and field(e, "Exe") == exe]
    if len(found) != 1:
        fail(f"{len(found)} shortcuts for {exe} in {path}")
    k, e = found[0]
    want_id = int(appid) if appid else steam_id(exe, "Anchorage")
    got_id = (field(e, "appid") or 0) & 0xFFFFFFFF
    if got_id != want_id:
        fail(f"appid {got_id}, expected {want_id}")
    expect = {
        "AppName": "Anchorage",
        "StartDir": '"' + os.path.dirname(appimage) + '"',
        "LaunchOptions": "",
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
        "icon": f"{grid}/{want_id}_icon.png",
    }
    if not appid:
        expect.update({"OpenVR": 0, "Devkit": 0, "LastPlayTime": 0, "FlatpakAppID": "", "ShortcutPath": ""})
    for name, value in expect.items():
        if field(e, name) != value:
            fail(f"{name} is {field(e, name)!r}, expected {value!r}")
    if field(e, "tags") is None:
        fail("no tags map")
    if key is not None and k != key:
        fail(f"shortcut key {k!r}, expected {key!r}")
    for suffix, name in ART.items():
        img = f"{grid}/{want_id}{suffix}.png"
        if not os.path.isfile(img) or sha(img) != sha(f"{art}/{name}"):
            fail(f"{img} is missing or not {name}")
    print(want_id)


def appended(old_path, new_path, key):
    old, old_sc = load(old_path)
    new, new_sc = load(new_path)
    if new[: len(old) - 2] != old[:-2] or new[-2:] != b"\x08\x08":
        fail("the old bytes are not an unchanged prefix of the new file")
    if list(new_sc.keys()) != list(old_sc.keys()) + [key]:
        fail(f"keys {list(new_sc.keys())}, expected {list(old_sc.keys()) + [key]}")
    rest = {k: v for k, v in new_sc.items() if k != key}
    if rest != dict(old_sc):
        fail("another shortcut changed")


def legacy(old_path, new_path, key, appimage):
    _, old_sc = load(old_path)
    _, new_sc = load(new_path)
    if list(old_sc.keys()) != list(new_sc.keys()):
        fail("the keys changed")
    for k in old_sc:
        o, n = dict(old_sc[k]), dict(new_sc[k])
        if k == key:
            o["Exe"] = f'"{appimage}"'
            o["StartDir"] = '"' + os.path.dirname(appimage) + '"'
            if list(o.keys()) != list(n.keys()):
                fail(f"field order changed: {list(n.keys())}")
        if o != n:
            fail(f"shortcut {k} differs: {n}")


def count(path, n):
    _, sc = load(path)
    if len(sc) != int(n):
        fail(f"{len(sc)} shortcuts, expected {n}")


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "ours":
        ours(*args)
    elif cmd == "appended":
        appended(*args)
    elif cmd == "legacy":
        legacy(*args)
    elif cmd == "count":
        count(*args)
    elif cmd == "appid":
        print(steam_id(args[0], args[1]))
    else:
        fail(f"unknown command {cmd}")


main()
