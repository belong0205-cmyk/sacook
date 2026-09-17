const assert = require('assert');
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, '..', 'app.js'), 'utf8');

assert(!source.includes('gpt-live-transcribe'), 'AUTO must not call a non-file transcription model before the supported model');
assert(source.includes("const models = ['gpt-transcribe', 'gpt-4o-transcribe']"), 'AUTO must prefer the current transcription model with a supported fallback');
assert(source.includes("form.append('keywords[]', term)"), 'culinary keyword hints must be sent to gpt-transcribe');
for (const leadIn of ['all right', 'let me ask', "i(?:'d| would) like to", "i(?:'m| am) curious"])
  assert(source.includes(leadIn), `natural interviewer lead-in must be recognised: ${leadIn}`);
assert(source.includes('const SILENCE_MS = 900'), 'AUTO must close a finished question quickly without waiting too long');
assert(source.includes('const AUTO_SEGMENT_MS = 2500'), 'AUTO must transcribe shorter rolling chunks so questions are not delayed by later speech');
assert(source.includes('AUTO_TURN_GRACE_MS'), 'AUTO must wait briefly for connected fragments after silence');
assert(source.includes('AUTO_INTERVAL_GRACE_MS'), 'AUTO must have a bounded endpoint when BlackHole background audio never becomes silent');
assert(source.includes("reason === 'silence' ? AUTO_TURN_GRACE_MS : AUTO_INTERVAL_GRACE_MS"), 'AUTO must close complete interval questions more cautiously than silence-ended questions');
assert(source.includes('looksLikeAnswerStart(clean)'), 'AUTO must close the pending question instead of appending the following answer');
assert(source.includes("if (job.reason === 'silence') autoTurnEnded = true"), 'AUTO must wait for the complete silence-ended transcription queue');
assert(source.includes("finishAutoTurn()"), 'AUTO must submit after the detected turn closes');
assert(source.includes('submitAutoTurn(pending)'), 'AUTO must classify a full turn before creating answer records');
assert(!source.includes("submitQuestion('auto', part)"), 'AUTO must not spam separate records for one speaking turn');
assert(source.includes('single underlying request'), 'linked or repeated question fragments must produce one answer');
assert(source.includes('independent questions'), 'genuinely separate questions can still be handled inside one answer record');
assert(source.includes('questionPartsAreLinked(parts)'), 'AUTO must classify linked follow-ups before answering');

console.log('Windows recognition pipeline tests passed.');
