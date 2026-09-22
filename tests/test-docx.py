#!/usr/bin/env python3
from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DOCX = ROOT / "_output" / "index.docx"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
q = lambda local: f"{{{W}}}{local}"

assert DOCX.exists(), f"Arquivo não encontrado: {DOCX}"
with ZipFile(DOCX) as z:
    document_xml = z.read("word/document.xml")
    footnotes_xml = z.read("word/footnotes.xml")
    document = ET.fromstring(document_xml)
    footnotes = ET.fromstring(footnotes_xml)

    refs = list(document.iter(q("footnoteReference")))
    reused = [
        h for h in document.iter(q("hyperlink"))
        if (h.get(q("anchor")) or "").startswith("rfn_note_")
    ]
    real_notes = [
        fn for fn in footnotes.findall(q("footnote"))
        if not fn.get(q("type")) and fn.get(q("id")) not in {"-1", "0"}
    ]
    bookmark_names = {
        b.get(q("name")) for b in footnotes.iter(q("bookmarkStart"))
        if b.get(q("name"))
    }

    assert refs, "Nenhuma nota Word real encontrada."
    assert len(real_notes) == 9, f"Esperadas 9 notas reais, encontradas {len(real_notes)}."
    assert len(reused) == 9, f"Esperadas 9 recorrências, encontradas {len(reused)}."
    assert all(h.get(q("anchor")) in bookmark_names for h in reused), (
        "Há hiperlink reutilizado sem bookmark de destino na nota canônica."
    )
    assert b"__REUSABLE_FOOTNOTE_GROUP_" not in footnotes_xml, (
        "Marcadores invisíveis de processamento permaneceram no DOCX final."
    )

print("OK: 9 notas reais, 9 recorrências reutilizadas e destinos internos válidos.")
