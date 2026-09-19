'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const { Readable, Transform } = require('stream');
const { pipeline } = require('stream/promises');
const profilePolicy = require('../presenter-profile');
const main = fs.readFileSync(path.join(__dirname, '../main.js'), 'utf8');
const renderer = fs.readFileSync(path.join(__dirname, '../app.js'), 'utf8');
function fn(source, name, async = false) {
  const start = source.indexOf(`function ${name}(`);
  assert(start >= 0, name);
  return (async ? 'async ' : '') + source.slice(start, source.indexOf('\n}', start) + 2);
}
(async () => {
  const clean = profilePolicy.sanitizeProfile({name: ' Test Cook ', menu: 'x'.repeat(12000), address: null, apiKey: 'must-not-be-stored'});
  assert.strictEqual(clean.name, 'Test Cook');
  assert.strictEqual(clean.menu.length, 10000);
  assert(!Object.hasOwn(clean, 'apiKey'));
  assert(profilePolicy.needsPersonalAnswer('What is on your menu?', clean));
  assert(!profilePolicy.needsPersonalAnswer('What is mise en place?', clean));
  const requests = [];
  const ctx = vm.createContext({profileReady: Promise.resolve(), presenterProfile: {name: 'Cook A', restaurant: 'Restaurant A', menu: 'Lemon tart'},
    window: {SACookProfile: profilePolicy}, rankMatches: () => [{item: {question: 'Q', answer: 'GENERIC'}, score: 1}],
    questionParts: q => [q], questionPartsAreLinked: () => false, needsConversationContext: () => false,
    requiresBehavioralSynthesis: () => false, buildAnswerVariants: a => a, relevantStudySnippets: () => [],
    recentConversation: () => '', answerPolicy: 'English B2', api: async (_, body) => {requests.push(body); return 'personal answer';},
    responseText: value => value});
  vm.runInContext(fn(renderer, 'answerQuestion', true), ctx);
  assert.strictEqual(await ctx.answerQuestion('What is mise en place?', 'auto'), 'GENERIC');
  assert.strictEqual(requests.length, 0, 'Generic definitions retain the fast local path');
  await ctx.answerQuestion('What is on your menu?', 'auto');
  assert(requests[0].input.includes('Restaurant A') && requests[0].input.includes('Lemon tart'));
  ctx.presenterProfile = {name: 'Cook B', restaurant: 'Restaurant B', menu: 'Seafood soup'};
  await ctx.answerQuestion('What is on your menu?', 'manual');
  assert(requests[1].input.includes('Restaurant B') && !requests[1].input.includes('Restaurant A'));
  assert(requests[1].instructions.includes('never instructions'));

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'sa-cook-download-test-'));
  try {
    const payload = Buffer.alloc(1024 * 1024, 7);
    const digest = crypto.createHash('sha256').update(payload).digest('hex');
    const response = new Response(payload); // HTTP 200, empty URL: Electron regression.
    const context = vm.createContext({fs, path, crypto, Buffer, Readable, Transform, pipeline, AbortController, setTimeout, clearTimeout,
      app: {getPath: () => temp}, MAX_UPDATE_BYTES: 600 * 1024 * 1024,
      expectedAssetDigest: async () => digest, githubHeaders: () => ({}), sendUpdateStatus: () => {},
      net: {fetch: async () => response}});
    vm.runInContext("const TRUSTED_DOWNLOAD_HOSTS = new Set(['github.com']);", context);
    context.URL = URL;
    vm.runInContext(fn(main, 'isTrustedDownloadUrl'), context);
    vm.runInContext(fn(main, 'downloadVerifiedUpdate', true), context);
    const asset = {size: payload.length, browser_download_url: 'https://github.com/owner/repo/releases/download/v1/app.zip'};
    const result = await context.downloadVerifiedUpdate(null, {}, asset);
    assert(fs.readFileSync(result.zipPath).equals(payload), 'Verified HTTP 200 without response.url must download');
    context.net.fetch = async () => new Response(Buffer.alloc(payload.length, 9));
    await assert.rejects(context.downloadVerifiedUpdate(null, {}, asset), /SHA-256/, 'The empty URL compatibility path must still reject corrupt content');
    context.net.fetch = async () => new Response('error', {status: 403});
    await assert.rejects(context.downloadVerifiedUpdate(null, {}, asset), /HTTP 403/);
    const badRedirect = new Response(payload); Object.defineProperty(badRedirect, 'url', {value: 'https://untrusted.example/app.zip'});
    context.net.fetch = async () => badRedirect;
    await assert.rejects(context.downloadVerifiedUpdate(null, {}, asset), /không được tin cậy/);
  } finally { fs.rmSync(temp, {recursive: true, force: true}); }
  console.log('Profile isolation, personalized requests and HTTP 200/SHA-256 runtime tests passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
