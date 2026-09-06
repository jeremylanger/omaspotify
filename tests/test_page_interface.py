#!/usr/bin/env python3
"""Guards the boundary between Panel.qml and the page files it loads.

The pages used to be written inside Panel.qml, where they could reach anything
in that file's scope. They are separate files now and receive the panel through
a single `panel` property, so a page that reaches for something the panel does
not expose only breaks at runtime. Quickshell's UI types cannot be built in the
offscreen test runner, so these checks are static.
"""

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = ROOT / "Panel.qml"
PAGES = sorted(ROOT.glob("*Page.qml"))

# Things every Item has, which a page may legitimately read off the panel.
ITEM_MEMBERS = {
    "objectName", "parent", "children", "width", "height",
    "visible", "opacity", "enabled", "x", "y", "z",
}


def strip_strings(text):
    text = re.sub(r'"(\\.|[^"\\])*"', '""', text)
    return re.sub(r"'(\\.|[^'\\])*'", "''", text)


def panel_members():
    text = PANEL.read_text()
    members = set(re.findall(r"^\s{2}(?:readonly\s+)?property\s+\S+\s+(\w+)", text, re.M))
    members |= set(re.findall(r"^\s{2}function\s+(\w+)", text, re.M))
    members |= set(re.findall(r"^\s{2}signal\s+(\w+)", text, re.M))
    return members | ITEM_MEMBERS


def panel_ids():
    return set(re.findall(r"^\s*id:\s*(\w+)", PANEL.read_text(), re.M)) - {"root"}


class PageInterface(unittest.TestCase):
    def test_pages_were_found(self):
        self.assertTrue(PAGES, "no page files were found next to Panel.qml")

    def test_every_panel_member_a_page_uses_exists(self):
        available = panel_members()
        for page in PAGES:
            used = set(re.findall(r"\bpage\.panel\.(\w+)", page.read_text()))
            missing = sorted(used - available)
            self.assertFalse(
                missing,
                f"{page.name} reads {missing} from the panel, "
                f"but Panel.qml does not expose them",
            )

    def test_no_page_reaches_into_the_panel_by_id(self):
        ids = panel_ids()
        for page in PAGES:
            text = page.read_text()
            local = set(re.findall(r"^\s*id:\s*(\w+)", text, re.M)) | {"page"}
            code = strip_strings(text)
            for name in sorted(ids - local):
                match = re.search(r"(?<![\w.])" + re.escape(name) + r"(?![\w])", code)
                self.assertIsNone(
                    match,
                    f"{page.name} line {code[:match.start()].count(chr(10)) + 1} "
                    f"uses '{name}', which is an id inside Panel.qml"
                    if match else "",
                )

    def test_every_page_takes_the_panel_the_same_way(self):
        for page in PAGES:
            text = page.read_text()
            self.assertIn("property var panel: null", text,
                          f"{page.name} does not declare a panel property")
            self.assertEqual(
                1, len(re.findall(r"^  id: ", text, re.M)),
                f"{page.name} must declare exactly one root id",
            )

    def test_panel_builds_every_page_it_can_show(self):
        text = PANEL.read_text()
        shown = set(re.findall(r"return\s+(\w+Page)\b", text))
        built = set(re.findall(r"^    id: (\w+Page)$", text, re.M))
        self.assertTrue(shown, "Panel.qml selects no pages")
        self.assertFalse(sorted(shown - built),
                         f"Panel.qml can show {sorted(shown - built)} but never builds them")


if __name__ == "__main__":
    unittest.main(verbosity=1, exit=not sys.stdout.isatty())
