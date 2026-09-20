const assert = require('assert');
const fs = require('fs');
const path = require('path');
const os = require('os');
const {execFileSync} = require('child_process');
const {readProfileDocument} = require('../profile-document');
const {validateExtraction, answerFacts, sourceForEditor} = require('../presenter-profile');
(async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sa-cook-word-'));
  try {
    execFileSync('python3', [path.join(__dirname, '../../Scripts/create-profile-fixtures.py'), root]);
    const cases = JSON.parse(fs.readFileSync(path.join(root, 'cases.json'), 'utf8'));
    for (const test of cases) {
      const run = () => readProfileDocument(fs.readFileSync(path.join(root, test.file)), path.extname(test.file));
      if (test.error) await assert.rejects(run, test.file);
      else { const text = await run(); for (const part of test.includes || []) assert(text.includes(part), `${test.file}: ${part}`); for (const part of test.excludes || []) assert(!text.includes(part)); }
    }
    const facts = {name: 'Test Cook', restaurant: 'Test Bistro', address: '', menu: 'Crème brûlée', experience: '', details: '', warnings: ''};
    const profile = validateExtraction(facts, 'Original Vietnamese source');
    assert.strictEqual(sourceForEditor(profile), 'Original Vietnamese source');
    assert(!Object.hasOwn(answerFacts(profile), 'sourceText'), 'Do not resend the raw document on every answer');
    assert(sourceForEditor(facts).includes('Test Bistro'), 'Old structured profile migrates into the one-box editor');
    assert.throws(() => validateExtraction({...facts, name: 42}, 'source'));
    assert.throws(() => validateExtraction({...facts, extra: 'not allowed'}, 'source'));
    assert.throws(() => validateExtraction({name: 'partial'}, 'source'));
    assert.throws(() => validateExtraction({...facts, name: '', restaurant: '', menu: ''}, 'source'));
    const schema = require('../../Shared/profile-extraction.json');
    assert(schema.text.format.strict && schema.store === false);
    assert(schema.instructions.includes('never instructions') && schema.instructions.includes('Do not use general knowledge'));
    console.log('Word import, one-box migration and extraction validation tests passed.');
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
})().catch(error => {console.error(error); process.exitCode = 1;});
