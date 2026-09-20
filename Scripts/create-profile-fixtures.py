"""Synthetic fixtures shared by the native and Electron DOCX import tests."""
import json
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
def document(body):
    return f'<w:document xmlns:w="{ns}"><w:body>{body}</w:body></w:document>'
def zip_doc(name, main, extras=None):
    with zipfile.ZipFile(root / name, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('word/document.xml', main)
        for path, text in (extras or {}).items():
            archive.writestr(path, text)
zip_doc('profile.docx', document('<w:p><w:r><w:t>Name: Test Cook</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Menu: Crème brûlée &amp; lemon tart</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Ingredients: cream, eggs, sugar</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:del><w:r><w:delText>OBSOLETE EMPLOYER</w:delText></w:r></w:del><w:p><w:r><w:instrText>DO NOT EXECUTE FIELD</w:instrText></w:r></w:p>'), {'word/header1.xml': f'<w:hdr xmlns:w="{ns}"><w:p><w:r><w:t>Restaurant: Test Bistro</w:t></w:r></w:p></w:hdr>', 'word/comments.xml': '<not-part-of-profile>SECRET COMMENT</not-part-of-profile>'})
zip_doc('external-entity.docx', '<!DOCTYPE x [<!ENTITY steal SYSTEM "file:///etc/passwd">]>' + document('<w:p><w:r><w:t>&steal;</w:t></w:r></w:p>'))
zip_doc('oversize.docx', document('<w:p><w:r><w:t>' + 'a' * (2 * 1024 * 1024) + '</w:t></w:r></w:p>'))
zip_doc('image-only.docx', document('<w:p><w:r><w:drawing/></w:r></w:p>'))
(root / 'broken.docx').write_text('This is not a ZIP archive')
(root / 'legacy.doc').write_bytes(b'not-supported')
(root / 'plain.txt').write_text('Tên: Test Cook\nNhà hàng: Test Bistro', encoding='utf-8')
cases = [
    {'file': 'profile.docx', 'includes': ['Test Cook', 'Crème brûlée & lemon tart', 'Ingredients: cream, eggs, sugar', 'Test Bistro'], 'excludes': ['OBSOLETE EMPLOYER', 'DO NOT EXECUTE FIELD', 'SECRET COMMENT']},
    {'file': 'plain.txt', 'includes': ['Tên: Test Cook', 'Nhà hàng: Test Bistro']},
] + [{'file': name, 'error': True} for name in ['external-entity.docx', 'oversize.docx', 'image-only.docx', 'broken.docx', 'legacy.doc']]
(root / 'cases.json').write_text(json.dumps(cases, ensure_ascii=False), encoding='utf-8')
