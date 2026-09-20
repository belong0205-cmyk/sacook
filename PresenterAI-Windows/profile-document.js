'use strict';
const yauzl = require('yauzl');
const {DOMParser} = require('@xmldom/xmldom');
const MAX_FILE = 10 * 1024 * 1024;
const MAX_XML = 2 * 1024 * 1024;
const MAX_TEXT = 40000;
const WORD_NS = new Set(['http://schemas.openxmlformats.org/wordprocessingml/2006/main', 'http://purl.oclc.org/ooxml/wordprocessingml/main']);
function wordXMLText(xml) {
  if (/<!DOCTYPE|<!ENTITY/i.test(xml)) throw new Error('File Word có XML không được hỗ trợ.');
  const doc = new DOMParser({onError: (_level, message) => { throw new Error(`XML Word không hợp lệ: ${message.slice(0, 100)}`); }}).parseFromString(xml, 'application/xml');
  const output = [];
  let characters = 0;
  function add(text) { characters += text.length; if (characters > MAX_TEXT) throw new Error('Nội dung vượt quá 40.000 ký tự. Hãy chia nhỏ file.'); output.push(text); }
  function visit(node, depth = 0) {
    if (depth > 150) throw new Error('Cấu trúc Word quá phức tạp.');
    const word = WORD_NS.has(node.namespaceURI);
    if (word && ['del', 'moveFrom', 'instrText'].includes(node.localName)) return;
    if (word && node.localName === 't') { add(node.textContent || ''); return; }
    if (word && ['tab', 'br', 'cr'].includes(node.localName)) add(node.localName === 'tab' ? '\t' : '\n');
    for (let child = node.firstChild; child; child = child.nextSibling) visit(child, depth + 1);
    if (word && ['p', 'tr'].includes(node.localName)) add('\n');
    if (word && node.localName === 'tc') add('\t');
  }
  visit(doc);
  return output.join('').replace(/\n{3,}/g, '\n\n').trim();
}
async function readProfileDocument(buffer, extension) {
  if (!buffer.length || buffer.length > MAX_FILE) throw new Error('File phải nhỏ hơn 10 MB và không rỗng.');
  if (extension === '.txt' || extension === '.md') {
    const text = new TextDecoder('utf-8', {fatal: true}).decode(buffer).trim();
    if (!text || text.length > MAX_TEXT) throw new Error('Nội dung cần có chữ và không vượt quá 40.000 ký tự.');
    return text;
  }
  if (extension !== '.docx') throw new Error('Hãy lưu file Word thành .docx (không dùng .doc), hoặc dán nội dung vào ô nhập.');
  return new Promise((resolve, reject) => {
    yauzl.fromBuffer(buffer, {lazyEntries: true, validateEntrySizes: true, strictFileNames: true}, (error, zip) => {
      if (error) return reject(new Error('Không đọc được Word. File phải là .docx không đặt mật khẩu.'));
      const parts = new Map(); let count = 0, total = 0, finished = false;
      const fail = error => { if (finished) return; finished = true; zip.close(); reject(error); };
      zip.on('error', fail);
      zip.on('entry', entry => {
        if (++count > 2000) return fail(new Error('File Word chứa quá nhiều thành phần.'));
        if (!/^word\/(document|header\d+|footer\d+)\.xml$/.test(entry.fileName)) return zip.readEntry();
        if (parts.has(entry.fileName) || parts.size >= 24 || entry.uncompressedSize > MAX_XML || (entry.generalPurposeBitFlag & 1)) return fail(new Error('File Word bị trùng, quá lớn hoặc có mật khẩu.'));
        zip.openReadStream(entry, (error, stream) => {
          if (error) return fail(error);
          const chunks = []; let size = 0;
          stream.on('error', fail);
          stream.on('data', chunk => { size += chunk.length; total += chunk.length; if (size > MAX_XML || total > 6 * MAX_XML) { stream.destroy(); fail(new Error('Nội dung giải nén quá lớn.')); } else chunks.push(chunk); });
          stream.on('end', () => {
            if (finished) return;
            try { parts.set(entry.fileName, wordXMLText(Buffer.concat(chunks).toString('utf8'))); zip.readEntry(); } catch (error) { fail(error); }
          });
        });
      });
      zip.on('end', () => {
        if (finished) return;
        if (!parts.has('word/document.xml')) return fail(new Error('File không chứa tài liệu Word hợp lệ.'));
        const order = [...parts.keys()].sort((a, b) => (a === 'word/document.xml' ? -1 : b === 'word/document.xml' ? 1 : a.localeCompare(b)));
        const text = order.map(key => parts.get(key)).filter(Boolean).join('\n\n');
        if (!text || text.length > MAX_TEXT) return fail(new Error(text ? 'Nội dung vượt quá 40.000 ký tự. Hãy chia nhỏ file.' : 'Không tìm thấy chữ. File chỉ có ảnh cần chuyển thành văn bản trước.'));
        finished = true; resolve(text);
      });
      zip.readEntry();
    });
  });
}
module.exports = {readProfileDocument, wordXMLText};
