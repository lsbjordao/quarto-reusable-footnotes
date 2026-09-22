#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "_output" / "index.html"
text = HTML.read_text(encoding="utf-8")

reused = len(re.findall(r'class="footnote-ref reusable-footnote-ref"', text))
notes = len(re.findall(r'<li id="fn\d+"', text))
backlink_groups = len(re.findall(r'class="reusable-footnote-backlinks"', text))

assert reused == 9, f"Esperadas 9 recorrências reutilizadas; encontradas {reused}."
assert notes == 9, f"Esperadas 9 notas reais; encontradas {notes}."
assert backlink_groups == 7, f"Esperados 7 grupos de backlinks; encontrados {backlink_groups}."

print("OK: HTML com 9 notas reais, 9 recorrências e backlinks discretos.")
