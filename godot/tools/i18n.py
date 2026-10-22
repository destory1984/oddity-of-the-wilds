"""Collect every Korean string shown in the game into i18n/text.csv (the translation table).

Keys are the Korean text itself, so code keeps reading naturally and Godot falls back to Korean
when a language column is still empty. Story lines "speaker|face|text" give two keys: speaker and text.

  python tools/i18n.py          rewrite the table: add new keys, keep existing translations, drop unused keys
  python tools/i18n.py --check  exit 1 if the table is out of date (used by dev.py check)
"""
import csv
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "i18n" / "text.csv"
LANGS = ["ko", "en", "ja", "zh_CN"]
SOURCES = ["main.gd", "hud.gd", "story_lines.gd", "village.gd", "marsh.gd"]
HANGUL = re.compile(r"[가-힣]")
LITERAL = re.compile(r'"((?:[^"\\n]|\.)*)"')


def keys_in_code():
    keys = []
    for name in SOURCES:
        for line in (ROOT / name).read_text(encoding="utf-8").splitlines():
            for lit in LITERAL.findall(line):
                if not HANGUL.search(lit):
                    continue
                parts = lit.split("|", 2)
                for k in ([parts[0], parts[2]] if len(parts) == 3 else [lit]):
                    if HANGUL.search(k) and k not in keys:
                        keys.append(k)
    return keys


def read_table():
    if not TABLE.exists():
        return {}
    rows = list(csv.reader(io.StringIO(TABLE.read_text(encoding="utf-8"))))
    head = rows[0]
    return {r[0]: dict(zip(head[1:], r[1:])) for r in rows[1:] if r}


def render(keys, old):
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["keys"] + LANGS)
    for k in keys:
        prev = old.get(k, {})
        w.writerow([k, k] + [prev.get(lang, "") for lang in LANGS[1:]])
    return out.getvalue()


def project_with(langs):
    """project.godot with the translation list naming only languages that have text
    (Godot makes no .translation file for an empty column, and a missing file is an error)."""
    proj = (ROOT / "project.godot").read_text(encoding="utf-8")
    files = ", ".join(f'"res://i18n/text.{lang}.translation"' for lang in langs)
    return re.sub(r"locale/translations=PackedStringArray\(.*\)", f"locale/translations=PackedStringArray({files})", proj)


def main():
    old = read_table()
    keys = keys_in_code()
    text = render(keys, old)
    langs = ["ko"] + [lang for lang in LANGS[1:] if any(old.get(k, {}).get(lang) for k in keys)]
    proj = project_with(langs)
    if "--check" in sys.argv:
        stale = not TABLE.exists() or TABLE.read_text(encoding="utf-8") != text
        if stale or (ROOT / "project.godot").read_text(encoding="utf-8") != proj:
            print("i18n/text.csv is out of date: run python tools/i18n.py")
            return 1
        return 0
    TABLE.write_text(text, encoding="utf-8")
    (ROOT / "project.godot").write_text(proj, encoding="utf-8")
    print(f"{TABLE.relative_to(ROOT)}: {text.count(chr(10)) - 1} keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
