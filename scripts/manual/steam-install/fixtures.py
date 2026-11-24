"""Builds the shortcuts.vdf files for scripts/manual/steam-install.sh, byte by byte.

Written apart from install-steamos.sh's writer on purpose, from the format as Steam,
Steam ROM Manager and BoilR write it. Usage: fixtures.py KIND OUT [ARGS...]
  simple OUT                  two ordinary shortcuts, keys 0 and 1
  odd OUT                     shortcuts Steam and other tools leave behind (see odd())
  nonseq OUT                  keys 0, 1, 5
  legacy OUT APPDIR ID        an older Anchorage AppImage in APPDIR, appid ID
  middle OUT EXPECTED APPIMAGE   Anchorage between two others; EXPECTED is the file
                              after --uninstall (the last one renumbered 2 -> 1)
  garbage OUT                 not a VDF file
  many OUT N                  N ordinary shortcuts, keys 0 to N-1
"""

import struct
import sys


def z(text):
    return text.encode("utf-8") + b"\x00"


def s(name, value):
    return b"\x01" + z(name) + z(value)


def i32(name, value):
    return b"\x02" + z(name) + struct.pack("<I", value & 0xFFFFFFFF)


def f32(name, value):
    return b"\x03" + z(name) + struct.pack("<f", value)


def u64(name, value):
    return b"\x07" + z(name) + struct.pack("<Q", value)


def i64(name, value):
    return b"\x0a" + z(name) + struct.pack("<q", value)


def m(name, *items):
    return b"\x00" + z(name) + b"".join(items) + b"\x08"


def tags(*names):
    return m("tags", *(s(str(n), t) for n, t in enumerate(names)))


def vdf(*entries):
    return m("shortcuts", *entries) + b"\x08"


def steam_entry(key, appid, name, exe, start, *tag_names, last=0):
    """A shortcut the way the current Steam client writes one."""
    return m(
        key,
        i32("appid", appid),
        s("AppName", name),
        s("Exe", exe),
        s("StartDir", start),
        s("icon", ""),
        s("ShortcutPath", ""),
        s("LaunchOptions", ""),
        i32("IsHidden", 0),
        i32("AllowDesktopConfig", 1),
        i32("AllowOverlay", 1),
        i32("OpenVR", 0),
        i32("Devkit", 0),
        s("DevkitGameID", ""),
        i32("DevkitOverrideAppID", 0),
        i32("LastPlayTime", last),
        s("FlatpakAppID", ""),
        tags(*tag_names),
    )


def simple():
    return vdf(
        steam_entry("0", 0xC0FFEE01, "Firefox", '"/usr/bin/firefox"', '"/usr/bin/"', "favorite"),
        steam_entry("1", 0x9ABCDEF0, "Konsole", '"/usr/bin/konsole"', '"/usr/bin/"', last=1700000000),
    )


def odd():
    return vdf(
        steam_entry("0", 0x8000_0001, "Firefox", '"/usr/bin/firefox"', '"/usr/bin/"', "favorite", "Web"),
        # An old client's lowercase keys, no appid, no tags.
        m("1", s("appname", "Old Game"), s("exe", '"C:\\Games\\old.exe"'), s("StartDir", '"C:\\Games\\"')),
        # Unicode, quotes and backslashes; every value type; maps inside maps.
        m(
            "2",
            i32("appid", 0xFFFFFFFF),
            s("AppName", 'Pokémon "Snap" \\ 日本語'),
            s("Exe", '"/home/deck/My Games/run me.sh"'),
            s("StartDir", '"/home/deck/My Games/"'),
            s("LaunchOptions", "%command% --fullscreen"),
            f32("rating", 4.5),
            u64("bigid", 0xFEDCBA9876543210),
            i64("negative", -42),
            m("extra", m("deeper", s("k", "v"), i32("n", 7)), s("after", "x")),
            tags("Emulators", "N64"),
        ),
        # Called Anchorage, but somewhere else: not the installer's, never touched.
        steam_entry("3", 0x8123_4567, "Anchorage", '"/opt/Anchorage/Anchorage.AppImage"', '"/opt/Anchorage"'),
        # Empty strings.
        m("4", i32("appid", 0x8000_0000), s("AppName", ""), s("Exe", ""), tags()),
    )


def nonseq():
    return vdf(
        steam_entry("0", 0x80000010, "A", '"/a"', '"/"'),
        steam_entry("1", 0x80000011, "B", '"/b"', '"/"'),
        steam_entry("5", 0x80000015, "C", '"/c"', '"/"'),
    )


def legacy(appdir, appid):
    return vdf(
        steam_entry("0", 0xC0FFEE01, "Firefox", '"/usr/bin/firefox"', '"/usr/bin/"'),
        steam_entry(
            "1", appid, "Anchorage", f'"{appdir}/Anchorage-1.0.0-x86_64.AppImage"', f'"{appdir}"', "Ports", last=1690000000
        ),
    )


def middle(appimage):
    import zlib

    exe = f'"{appimage}"'
    appid = zlib.crc32((exe + "Anchorage").encode()) | 0x80000000
    first = steam_entry("0", 0xC0FFEE01, "Firefox", '"/usr/bin/firefox"', '"/usr/bin/"', "favorite")
    ours = steam_entry("1", appid, "Anchorage", exe, '"' + appimage.rsplit("/", 1)[0] + '"')
    last_body = steam_entry("2", 0x9ABCDEF0, "Konsole", '"/usr/bin/konsole"', '"/usr/bin/"')[len(z("2")) + 1 :]
    before = vdf(first, ours, b"\x00" + z("2") + last_body)
    after = vdf(first, b"\x00" + z("1") + last_body)
    return before, after


def main():
    kind, out = sys.argv[1], sys.argv[2]
    if kind == "simple":
        data = simple()
    elif kind == "odd":
        data = odd()
    elif kind == "nonseq":
        data = nonseq()
    elif kind == "legacy":
        data = legacy(sys.argv[3], int(sys.argv[4]))
    elif kind == "middle":
        data, expected = middle(sys.argv[4])
        with open(sys.argv[3], "wb") as f:
            f.write(expected)
    elif kind == "many":
        n = int(sys.argv[3])
        data = vdf(*(steam_entry(str(k), 0x80000000 | k, f"Game {k}", f'"/games/{k}/run"', f'"/games/{k}"', "N64") for k in range(n)))
    elif kind == "garbage":
        data = b"\x00shortcuts\x00\x00broken\x00\x09\x09nonsense"
    else:
        sys.exit(f"unknown fixture {kind}")
    with open(out, "wb") as f:
        f.write(data)


main()
