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
  const helpers = vm.createContext({});
  vm.runInContext(fn(renderer, 'parseAnswerVariants'), helpers);
  vm.runInContext(fn(renderer, 'pairedRetryBody'), helpers);
  const englishVariants = helpers.parseAnswerVariants('Short: Short: Keep food separate.\n\nFull: Full: Store raw food below ready-to-eat food.');
  assert.strictEqual(englishVariants.short, 'Keep food separate.');
  assert.strictEqual(englishVariants.full, 'Store raw food below ready-to-eat food.');
  const vietnameseVariants = helpers.parseAnswerVariants('Ngắn: Ngắn: Giữ riêng thực phẩm sống.\n\nĐầy đủ: Đầy đủ: Bảo quản thực phẩm sống ở kệ dưới.');
  assert.strictEqual(vietnameseVariants.short, 'Giữ riêng thực phẩm sống.');
  assert.strictEqual(vietnameseVariants.full, 'Bảo quản thực phẩm sống ở kệ dưới.');
  const fastBody = {max_output_tokens: 420, text: {format: {name: 'paired_bilingual_answer'}}};
  assert.strictEqual(helpers.pairedRetryBody(fastBody, {status: 'completed'}), null, 'A completed fast response must not retry');
  assert.strictEqual(helpers.pairedRetryBody(fastBody, {status: 'incomplete'}).max_output_tokens, 640, 'An incomplete fast response retries at 640');
  assert.strictEqual(helpers.pairedRetryBody({...fastBody, max_output_tokens: 640}, {status: 'incomplete'}), null, 'The expanded request must not loop');
  const shortFastBody = {max_output_tokens: 220, text: {format: {name: 'paired_bilingual_short_answer'}}};
  assert.strictEqual(helpers.pairedRetryBody(shortFastBody, {status: 'incomplete'}).max_output_tokens, 320, 'Short retries remain small and fast');
  const clean = profilePolicy.sanitizeProfile({name: ' Test Cook ', menu: 'x'.repeat(12000), address: null, apiKey: 'must-not-be-stored'});
  assert.strictEqual(clean.name, 'Test Cook');
  assert.strictEqual(clean.menu.length, 10000);
  assert(!Object.hasOwn(clean, 'apiKey'));
  assert(profilePolicy.needsPersonalAnswer('What is on your menu?', clean));
  assert(!profilePolicy.needsPersonalAnswer('What is mise en place?', clean));
  const requests = [];
  const ctx = vm.createContext({profileReady: Promise.resolve(), presenterProfile: {name: 'Cook A', restaurant: 'Restaurant A', menu: 'Lemon tart'},
    window: {SACookProfile: profilePolicy}, answerEvidence: () => ({matches: [{item: {question: 'Q', answer: 'GENERIC'}, score: 1}], snippets: []}),
    questionParts: q => [q], questionPartsAreLinked: () => false, needsConversationContext: () => false,
    requiresBehavioralSynthesis: () => false, isVietnameseQuestion: text => /[ăâđêôơư]|câu hỏi/i.test(text || ''), buildAnswerVariants: a => a, relevantStudySnippets: () => [],
    vietnameseQuestionForDisplay: q => q, cleanSpeech: q => String(q || '').trim(), packTranslatedAnswer: a => a, extractVietnameseQuestionFromAnswer: a => ({question: '', answer: a}),
    packPairedBilingualAnswer: (englishAnswer, vietnameseQuestion, vietnameseAnswer) => JSON.stringify({englishAnswer, vietnameseQuestion, vietnameseAnswer}),
    ApiError: class ApiError extends Error {},
    recentConversation: () => '', answerPolicy: 'English B2', api: async (_, body) => {requests.push(body); return body.text ? JSON.stringify({english_short:'Short EN',english_full:'Full EN',vietnamese_question:'Câu hỏi tiếng Việt?',vietnamese_short:'Ngắn VI',vietnamese_full:'Đầy đủ VI'}) : 'personal answer';},
    responseText: value => value, pairedRetryBody: helpers.pairedRetryBody});
  for (const name of ['parseAnswerVariants', 'removeLeadingAnswerVariantLabels', 'buildShortAnswerDisplay', 'pairedShortAnswerBody', 'pairedFullAnswerBody']) vm.runInContext(fn(renderer, name), ctx);
  vm.runInContext(fn(renderer, 'requestAnswerBody', true), ctx);
  vm.runInContext(fn(renderer, 'answerQuestion', true), ctx);
  assert.strictEqual(await ctx.answerQuestion('What is mise en place?', 'auto'), 'GENERIC');
  assert.strictEqual(requests.length, 0, 'Generic definitions retain the fast local path');
  await ctx.answerQuestion('What is on your menu?', 'auto');
  assert(requests[0].input.includes('Restaurant A') && requests[0].input.includes('Lemon tart'));
  ctx.presenterProfile = {name: 'Cook B', restaurant: 'Restaurant B', menu: 'Seafood soup'};
  const partials=[];
  const finalPaired=await ctx.answerQuestion('What is on your menu?', 'manual', false, value => partials.push(value));
  assert(requests[1].input.includes('Restaurant B') && !requests[1].input.includes('Restaurant A'));
  assert(requests[1].instructions.includes('never instructions'));
  assert.strictEqual(partials.length, 1, 'The bilingual Short answer is published before Full');
  assert.strictEqual(requests[1].text.format.name, 'paired_bilingual_short_answer');
  assert.strictEqual(requests[1].max_output_tokens, 220);
  assert.strictEqual(requests[1].model, 'gpt-4.1-mini');
  assert.strictEqual(requests[1].reasoning, undefined);
  assert.strictEqual(requests[2].text.format.name, 'paired_bilingual_full_answer');
  assert.strictEqual(requests[2].max_output_tokens, 360);
  assert(requests[2].input.includes('APPROVED SHORT ANSWERS'));
  assert(finalPaired.includes('Full EN'), 'The terminal result adds Full after Short');
  let failureCall=0;
  ctx.api=async () => {
    failureCall += 1;
    if(failureCall===1) return JSON.stringify({english_short:'Safe short answer',vietnamese_question:'Câu hỏi an toàn?',vietnamese_short:'Câu trả lời ngắn an toàn'});
    throw new ctx.ApiError('Full timed out');
  };
  const partialOnly=await ctx.answerQuestion('How do you work safely?', 'manual');
  assert(partialOnly.includes('Safe short answer'), 'A Full failure keeps the valid Short answer');

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
