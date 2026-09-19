const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(require('path').join(__dirname, '../app.js'), 'utf8');
// Execute the actual application functions with a controlled clock and network.
function applicationFunction(name) {
  const start = source.indexOf(`function ${name}(`);
  assert(start >= 0, name);
  const end = source.indexOf('\n}', start) + 2;
  return source.slice(start, end);
}
function fixture() {
  let now = 0, id = 0;
  const timers = new Map(), answered = [];
  const lane = {pending: '', pendingPieces: 0, queue: [], transcribing: false};
  const ctx = vm.createContext({lanes: {auto: lane}, sessionId: 1,
    autoFlushTimer: null, AUTO_TURN_GRACE_MS: 950, AUTO_INTERVAL_GRACE_MS: 1350,
    performance: {now: () => now}, recording: false, lastVoiceAt: 0, SILENCE_MS: 900,
    $: () => ({checked: true}), setLaneLive: () => {},
    submitQuestion: (_, q) => answered.push(q),
    setTimeout: (fn, delay) => {timers.set(++id, {fn, at: now + delay}); return id;},
    clearTimeout: key => timers.delete(key)});
  for (const name of ['wordCount', 'cleanSpeech', 'looksLikeQuestion', 'extractQuestionCandidate',
    'appendPending', 'isLikelyCompleteQuestion', 'looksLikeAnswerStart', 'handleAutoPiece',
    'finishAutoTurn', 'submitAutoTurn', 'scheduleAutoTurnFinish']) {
    vm.runInContext(applicationFunction(name), ctx);
  }
  return {ctx, lane, answered, advance(ms) {
    now += ms;
    for (const [key, timer] of [...timers]) if (timer.at <= now) {timers.delete(key); timer.fn();}
  }};
}
let f = fixture();
assert(f.ctx.isLikelyCompleteQuestion('What is stock?'), 'Three-word culinary questions must be accepted');
assert(f.ctx.isLikelyCompleteQuestion('How can we use a thermometer?'), 'Embedded we use is not an answer');
f.lane.transcribing = true;
f.ctx.handleAutoPiece('What is the difference between cleaning and sanitising?', 'interval');
f.advance(1400); // The network is still busy when the endpoint expires.
f.lane.transcribing = false;
f.advance(300);
assert.strictEqual(f.answered.length, 1, 'Busy queue must not permanently lose its endpoint');
f = fixture();
f.ctx.handleAutoPiece('What is the difference between cleaning and sanitising?', 'interval');
f.ctx.handleAutoPiece('', 'interval');
f.advance(1400);
assert.strictEqual(f.answered.length, 1, 'Empty background transcription must not cancel the endpoint');
f = fixture();
f.ctx.handleAutoPiece('What is the difference between', 'interval');
f.advance(600);
assert.strictEqual(f.answered.length, 0);
f.ctx.handleAutoPiece('cleaning and sanitising?', 'silence');
f.advance(1000);
assert.deepStrictEqual(f.answered, ['What is the difference between cleaning and sanitising?']);
f = fixture();
f.ctx.handleAutoPiece('How do you make a stock?', 'interval');
f.ctx.handleAutoPiece('I use bones and vegetables.', 'interval');
assert.deepStrictEqual(f.answered, ['How do you make a stock?']);
f = fixture();
f.ctx.handleAutoPiece('What are the ingredients?', 'silence');
f.advance(600);
f.ctx.handleAutoPiece('Okay, in your Caesar dressing, what do you have in that?', 'silence');
f.advance(600);
assert.strictEqual(f.answered.length, 0, 'The first fragment must not close a linked turn');
f.advance(400);
assert.strictEqual(f.answered.length, 1);
assert(f.answered[0].includes('ingredients') && f.answered[0].includes('Caesar dressing'));
f = fixture();
f.ctx.recording = true;
f.ctx.handleAutoPiece('What are the ingredients?', 'interval');
f.ctx.lastVoiceAt = 1350;
f.advance(1400);
assert.strictEqual(f.answered.length, 0, 'Speech between recorder chunks must postpone closing');
f.ctx.handleAutoPiece('In the Caesar dressing?', 'silence');
f.advance(1000);
assert.strictEqual(f.answered.length, 1);
f.ctx.sessionId++;
f.ctx.handleAutoPiece('What is stock?', 'silence');
f.ctx.sessionId++;
f.advance(1500);
assert.strictEqual(f.answered.length, 1, 'Old-session callbacks must not submit');
console.log('AUTO runtime regression tests passed.');

(async () => {
  const requests = [];
  const context = vm.createContext({FormData, Blob, speechHints: [], cleanSpeech: value => value,
    transcriptionPrompt: () => 'Cooking interview',
    api: async (_, form) => {
      requests.push(form);
      if (requests.length === 1) throw Object.assign(new Error('Model not available'), {status: 404});
      return {text: 'What is stock?'};
    }});
  vm.runInContext('async ' + applicationFunction('transcribeBlob'), context);
  assert.strictEqual(await context.transcribeBlob(new Blob(['audio'], {type: 'audio/wav'}), 'auto'), 'What is stock?');
  assert.deepStrictEqual(requests[0].getAll('languages[]'), ['en']);
  assert(!requests[0].has('language'), 'Current model must not receive legacy language field');
  assert.strictEqual(requests[1].get('language'), 'en');
  assert(!requests[1].has('languages[]'), 'Legacy model must not receive current language field');
  console.log('Transcription request and fallback tests passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
