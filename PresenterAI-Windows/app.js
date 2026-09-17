const $ = id => document.getElementById(id);

const AUTO_SEGMENT_MS = 2500;
const SPACE_TAIL_MS = 80;
const SILENCE_MS = 900;
const AUTO_TURN_GRACE_MS = 80;
const AUTO_INTERVAL_GRACE_MS = 520;
const MAX_SAVED_SEGMENTS = 30;
const MAX_SPACE_SECONDS = 90;
const stopWords = new Set('what when where which would could should please your you about tell have with that this from they them think important does into are the and for um uh ah yeah okay'.split(' '));

let qa = [];
let speechHints = [];
let answerPolicy = window.SACookB1.DEFAULT_POLICY;
let studyChunks = [];
let studyChunkIndex = new Map();
let recording = false;
let sourceStream = null;
let audioStream = null;
let recorder = null;
let recorderChunks = [];
let segmentTimer = null;
let segmentStartedAt = 0;
let segmentStopping = false;
let segmentHasSignal = false;
let segmentPeak = 0;
let nextSegmentId = 0;
let savedSegments = [];
let manualCommitPending = false;
let manualRecorder = null;
let manualPeak = 0;
let audioContext = null;
let analyser = null;
let audioSourceNode = null;
let spaceCaptureNode = null;
let spaceSilentGain = null;
let spaceCaptureMode = 'none';
let spacePcmChunks = [];
let spacePcmSamples = 0;
let nextSpaceCutId = 0;
const pendingSpaceCuts = new Map();
let meterFrame = null;
let lastVoiceAt = 0;
let sessionId = 0;
let starting = false;
let autoFlushTimer = null;

const lanes = {
  auto: { cursor: 0, queue: [], transcribing: false, pending: '', pendingPieces: 0, lastAnswered: '', records: [], live: 'Đang nghe câu hỏi tiếp theo…' },
  manual: { cursor: 0, queue: [], transcribing: false, pending: '', pendingPieces: 0, lastAnswered: '', records: [], live: 'Đang nghe đến khi bạn bấm Space…' }
};

class ApiError extends Error {
  constructor(message, status = 0, code = '') { super(message); this.status = status; this.code = code; }
}

function setStatus(text, bad = false) {
  $('status').textContent = `● ${text}`;
  $('status').classList.toggle('error', bad);
}

function normalize(text) {
  return String(text || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
}

function contentWords(text) {
  return new Set(normalize(text).split(/\s+/).filter(word => word.length > 2 && !stopWords.has(word)));
}

function wordCount(text) { return String(text || '').trim().split(/\s+/).filter(Boolean).length; }

function cleanSpeech(text) {
  let out = String(text || '').replace(/\s+/g, ' ').trim();
  const aliases = [
    [/\b(?:me'?s|mees|meez|mis|means|meat) (?:in|en) place\b/gi, 'mise en place'],
    [/\b(?:mise and place|mise on place|missing place|misan place|mise place)\b/gi, 'mise en place'],
    [/\b(?:ala carte|a la cart|a la card|a la cat)\b/gi, 'à la carte'],
    [/\b(?:sue vide|sous feed|sue feed|soup feed)\b/gi, 'sous-vide'],
    [/\b(?:consume a|consomme|conso may)\b/gi, 'consommé'],
    [/\b(?:julian|julien|julianne)(?=\s+(?:cut|cuts|vegetable|vegetables)|\b)/gi, 'julienne'],
    [/\b(?:bruno'?s|brun noise)\b/gi, 'brunoise'],
    [/\b(?:bay shamel|bechamel)\b/gi, 'béchamel'],
    [/\b(?:velo tay|veloute)\b/gi, 'velouté'],
    [/\b(?:demi glass|demi gloss|demi glaze)\b/gi, 'demi-glace'],
    [/\b(?:mirror paw|mere poise|mira pwa)\b/gi, 'mirepoix'],
    [/\b(?:bouquet garney|bouquet garnet)\b/gi, 'bouquet garni'],
    [/\b(?:ban marie|bane marie|ben marie)\b/gi, 'bain-marie'],
    [/\b(?:holland days|holland day sauce)\b/gi, 'hollandaise'],
    [/\b(?:bear nays|bernese sauce)\b/gi, 'béarnaise'],
    [/\b(?:sanitizing|sanitize|sanitizer)\b/gi, match => ({ sanitizing: 'sanitising', sanitize: 'sanitise', sanitizer: 'sanitiser' })[match.toLowerCase()]],
    [/\bpaltry\b/gi, 'poultry'],
    [/\bverseti\b/gi, 'versatility']
  ];
  for (const [pattern, replacement] of aliases) out = out.replace(pattern, replacement);

  out = out
    .replace(/\b((?:do|does|did|can|could|would|should|will|may|might|must|to)\s+(?:(?:you|we|i|they|he|she)\s+)?)(?:gorilla|guerrilla)\b/gi, '$1grill')
    .replace(/\b((?:on|using|use|clean|cleaning|preheat|heat|scrub)\s+(?:(?:a|the|an)\s+)?)(?:gorilla|guerrilla)\b/gi, '$1grill')
    .replace(/\b(?:gorilla|guerrilla)\b(?=\s+(?:chicken|fish|steak|meat|vegetables?|poultry|seafood|lamb|beef|pork|salmon|barramundi|mushrooms?|sandwich|dish|or\s+(?:roasted|fried|baked|poached|steamed)))/gi, 'grilled');

  const stockContexts = [
    /\bwhat is (?:a |the )?stuff\b/gi,
    /\b(?:beef|chicken|fish|vegetable|veal|brown|white) stuff\b/gi,
    /\bstuff (?=quality|rotation|levels?|control|pot|take|taking|cubes?|bases?|production|preparation)\b/gi,
    /\bhow (?:long )?(?:do|would|can|should) you (?:make|prepare|clarify|strain|simmer|cool)[^?.!]{0,45}\bstuff\b/gi
  ];
  for (const pattern of stockContexts) out = out.replace(pattern, match => match.replace(/\bstuff\b/i, 'stock'));
  return out.replace(/\s+([?.!,])/g, '$1').trim();
}

function looksLikeQuestion(text) {
  const value = String(text || '').trim();
  if (!value) return false;
  if (value.endsWith('?')) return true;
  return /^(?:(?:okay|ok|all right|alright|right|well|so|please|and|now|then|next question|let me ask|i(?:'d| would) like to (?:ask|know)|i want to know|i(?:'m| am) curious(?: about)?)[,.: ]+)*(?:what|which|why|how|when|where|who|whose|whom|in what ways|can|could|do|does|did|are|is|was|were|would|will|should|may|might|must|have|tell (?:me|us)|(?:walk|talk|take) (?:me|us) through|share|explain|list|name|describe|identify|give|outline|define|compare|discuss|provide|state|mention|show|design|distinguish|demonstrate)\b/i.test(value);
}

function extractQuestionCandidate(text) {
  const clean = cleanSpeech(text);
  const withoutLeadIn = clean.replace(/^(?:(?:okay|ok|all right|alright|right|well|so|please|and|now|then|next question|let me ask|i(?:'d| would) like to (?:ask|know)|i want to know|i(?:'m| am) curious(?: about)?)[,.: ]+)+/i, '').trim();
  if (withoutLeadIn !== clean && looksLikeQuestion(withoutLeadIn)) return withoutLeadIn;
  if (looksLikeQuestion(clean)) return clean;
  const starter = /\b(?:what|which|why|how|when|where|who|whose|whom|in what ways|can|could|do|does|did|are|is|was|were|would|will|should|may|might|must|have|tell (?:me|us)|(?:walk|talk|take) (?:me|us) through|share|explain|list|name|describe|identify|give|outline|define|compare|discuss|provide|state|mention|show|design|distinguish|demonstrate)\b/gi;
  const matches = [...clean.matchAll(starter)];
  for (let index = matches.length - 1; index >= 0; index -= 1) {
    const prefix = clean.slice(0, matches[index].index);
    if (!prefix || /(?:[?.!]|\b(?:okay|ok|all right|alright|right|well|so|please|and|now|then|let me ask|i(?:'d| would) like to (?:ask|know)|i want to know|i(?:'m| am) curious(?: about)?))[,.: ]*$/i.test(prefix)) {
      const candidate = clean.slice(matches[index].index).trim();
      if (looksLikeQuestion(candidate)) return candidate;
    }
  }
  return '';
}

function appendPending(lane, piece) {
  const clean = cleanSpeech(piece);
  if (!clean) return lane.pending;
  if (lane.pending && clean.toLowerCase().startsWith(lane.pending.toLowerCase())) lane.pending = clean;
  else if (!lane.pending.toLowerCase().endsWith(clean.toLowerCase())) lane.pending = `${lane.pending} ${clean}`.trim();
  lane.pending = lane.pending.replace(/\s+/g, ' ').trim();
  lane.pendingPieces += 1;
  return lane.pending;
}

function isLikelyCompleteQuestion(text) {
  const clean = cleanSpeech(text);
  if (!looksLikeQuestion(clean) || wordCount(clean) < 4) return false;
  if (/\b(?:yes|yeah|i|we)\s+(?:use|have|keep|make|prepare|cook|clean|store|check|follow|do|can|will|would)\b/i.test(clean)) return false;
  if (/[?!.]$/.test(clean)) return true;
  return !/\b(?:a|an|the|of|for|to|with|between|and|or|in|on|from|by|your|their|my|our|than|such|as|whether|how|what|which|is|are|do|does|can|could|would|should)$/i.test(clean);
}

function looksLikeAnswerStart(text) {
  return /^(?:yes|yeah|correct|sure|okay[, ]+)?\s*(?:i|we)\s+(?:use|have|keep|make|prepare|cook|clean|store|check|follow|ensure|maintain|work|would|will|can|do)\b/i.test(cleanSpeech(text));
}

function editDistance(a, b) {
  const previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i += 1) {
    const current = [i];
    for (let j = 1; j <= b.length; j += 1) current[j] = Math.min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    previous.splice(0, previous.length, ...current);
  }
  return previous[b.length];
}

function rankMatches(question) {
  const queryNormal = normalize(question);
  const query = contentWords(question);
  if (!queryNormal || !query.size) return [];
  return qa.map(item => {
    const candidateNormal = item._normal || (item._normal = normalize(item.question));
    const candidate = item._words || (item._words = contentWords(item.question));
    let common = 0;
    for (const term of query) if (candidate.has(term)) common += 1;
    const recall = common / query.size;
    const precision = common / Math.max(1, candidate.size);
    const f1 = recall + precision ? (2 * recall * precision) / (recall + precision) : 0;
    let similarity = 0;
    if (common || queryNormal === candidateNormal) {
      const maximum = Math.max(queryNormal.length, candidateNormal.length);
      similarity = maximum ? 1 - editDistance(queryNormal, candidateNormal) / maximum : 0;
    }
    const exact = queryNormal === candidateNormal;
    const score = exact ? 1 : f1 * 0.62 + similarity * 0.38;
    return { item, score, common, recall, precision };
  }).filter(match => match.common || match.score === 1).sort((a, b) => b.score - a.score);
}

function buildStudyChunks(sources) {
  const chunks = [];
  for (const [source, raw] of sources) {
    const blocks = String(raw || '').replace(/\r/g, '').replace(/\f/g, '\n\n').split(/\n\s*\n/).map(value => value.replace(/[ \t]+/g, ' ').trim()).filter(Boolean);
    let buffer = '';
    const flush = () => {
      const text = buffer.trim();
      if (text.length >= 80) chunks.push({ source, text, words: contentWords(text) });
      buffer = '';
    };
    for (let block of blocks) {
      while (block.length > 1000) {
        if (buffer) flush();
        let cut = block.lastIndexOf(' ', 1000);
        if (cut < 500) cut = 1000;
        const text = block.slice(0, cut).trim();
        if (text.length >= 80) chunks.push({ source, text, words: contentWords(text) });
        block = block.slice(cut).trim();
      }
      if (buffer && buffer.length + block.length + 2 > 900) flush();
      buffer = buffer ? `${buffer}\n\n${block}` : block;
    }
    flush();
  }
  const index = new Map();
  chunks.forEach((chunk, chunkIndex) => {
    for (const word of chunk.words) {
      if (!index.has(word)) index.set(word, []);
      index.get(word).push(chunkIndex);
    }
  });
  studyChunks = chunks;
  studyChunkIndex = index;
}

function relevantStudySnippets(question, limit = 3) {
  const query = contentWords(question);
  const counts = new Map();
  for (const word of query) for (const chunkIndex of studyChunkIndex.get(word) || []) counts.set(chunkIndex, (counts.get(chunkIndex) || 0) + 1);
  return [...counts].map(([chunkIndex, common]) => {
    const chunk = studyChunks[chunkIndex];
    const coverage = common / Math.max(1, query.size);
    const density = common / Math.max(1, chunk.words.size);
    return { chunk, common, score: coverage * 0.82 + density * 0.18 };
  }).filter(item => item.common >= Math.min(2, query.size)).sort((a, b) => b.score - a.score || b.common - a.common).slice(0, limit).map(item => item.chunk);
}

function firstSpeakableSentences(answer, question = '', maximumWords = 45) {
  return window.SACookB1.simplifyAnswer(answer, question, maximumWords);
}

function simplifyAnswerOutput(answer, question = '', maximumWords = 45) {
  return window.SACookB1.simplifyAnswerOutput(answer, question, maximumWords);
}

function parseAnswerVariants(answer) {
  const clean = String(answer || '').trim();
  const labelled = clean.match(/(?:^|\n)\s*(?:short(?:\s+answer)?|short)\s*:\s*([\s\S]*?)(?:\n\s*(?:full(?:\s+answer)?|full)\s*:\s*([\s\S]*))$/i);
  if (labelled) return { short: labelled[1].trim(), full: labelled[2].trim() };
  return { short: '', full: clean };
}

function formatAnswerVariants(shortAnswer, fullAnswer) {
  const short = String(shortAnswer || '').trim();
  const full = String(fullAnswer || '').trim();
  if (!short && !full) return '';
  if (!full || normalize(short) === normalize(full)) return `Short: ${short || full}`;
  return `Short: ${short}\n\nFull: ${full}`;
}

function buildAnswerVariants(answer, question = '') {
  const parsed = parseAnswerVariants(answer);
  const fullSource = parsed.full || parsed.short || answer;
  const shortSource = parsed.short || fullSource;
  const short = simplifyAnswerOutput(shortSource, question, 28);
  const full = simplifyAnswerOutput(fullSource, question, 85);
  return formatAnswerVariants(short, full);
}

function escapeHtml(value) {
  return String(value || '').replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
}

function answerKeywordTerms(question, answer) {
  const terms = new Set([
    'HACCP', 'FIFO', 'mise en place', 'à la carte', 'sous-vide', 'roux', 'béchamel', 'velouté', 'hollandaise', 'béarnaise',
    'mirepoix', 'julienne', 'brunoise', 'bain-marie', 'cross-contamination', 'sanitising', 'sanitiser', 'stock',
    'temperature', 'danger zone', 'chef\'s knife', 'grill', 'grilled', 'poultry', 'seafood'
  ]);
  const combined = `${question || ''} ${answer || ''}`;
  for (const word of contentWords(question)) if (word.length >= 4 && new RegExp(`\\b${word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'i').test(answer || '')) terms.add(word);
  for (const match of combined.matchAll(/\b\d+(?:\.\d+)?\s*(?:°\s*)?[CF]\b|\b\d+\s*(?:minutes?|hours?)\b/gi)) terms.add(match[0]);
  return [...terms].filter(term => term && new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i').test(answer || '')).sort((a, b) => b.length - a.length).slice(0, 12);
}

function renderAnswerHtml(answer, question = '') {
  let html = escapeHtml(answer || '');
  html = html.replace(/^(Short|Full):/gmi, '<span class="answer-label">$1</span>');
  for (const term of answerKeywordTerms(question, answer)) {
    const pattern = new RegExp(`(^|[^\\p{L}\\p{N}])(${term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})(?=$|[^\\p{L}\\p{N}])`, 'giu');
    html = html.replace(pattern, '$1<strong>$2</strong>');
  }
  return html;
}

function responseText(data) {
  if (typeof data?.output_text === 'string' && data.output_text.trim()) return data.output_text.trim();
  const pieces = [];
  for (const item of data?.output || []) for (const part of item?.content || []) if (part?.type === 'output_text' && part.text) pieces.push(part.text);
  return pieces.join('\n').trim();
}

async function api(path, body, isForm = false) {
  const key = await window.saCook.getKey();
  if (!key) throw new ApiError('Hãy nhập OpenAI API key trong mục “AI key…”.');
  const headers = { Authorization: `Bearer ${key}` };
  if (!isForm) headers['Content-Type'] = 'application/json';
  const response = await fetch(`https://api.openai.com/v1/${path}`, { method: 'POST', headers, body: isForm ? body : JSON.stringify(body) });
  let data = null;
  try { data = await response.json(); } catch (_) { data = {}; }
  if (!response.ok) throw new ApiError(data?.error?.message || `HTTP ${response.status}`, response.status, data?.error?.code || '');
  return data;
}

function transcriptionPrompt(kind) {
  const priority = ['grill', 'grilled', 'grilling', 'stock', 'mise en place', 'à la carte', 'roux', 'béchamel', 'velouté', 'hollandaise', 'béarnaise', 'mirepoix', 'julienne', 'brunoise', 'sous-vide', 'bain-marie', 'HACCP', 'FIFO', 'sanitising', 'cross-contamination'];
  const vocabulary = [...new Set([...priority, ...speechHints])].slice(0, 90).join(', ');
  const recent = lanes[kind].records.slice(-4).map(record => record.question).join(' | ');
  return `Australian English commercial cookery skills-assessment interview. Preserve the exact question and culinary terminology, including French loanwords. Vocabulary: ${vocabulary}.${recent ? ` Recent questions: ${recent}.` : ''}`;
}

async function transcribeBlob(blob, kind, fast = false) {
  let firstError = null;
  // Do not try a live-only model on the file-transcription endpoint; that
  // added a guaranteed failed request to every AUTO turn in the old build.
  const models = ['gpt-transcribe', 'gpt-4o-transcribe'];
  for (let index = 0; index < models.length; index += 1) {
    const model = models[index];
    const form = new FormData();
    form.append('file', blob, blob.type.includes('wav') ? 'question.wav' : 'question.webm');
    form.append('model', model);
    form.append('language', 'en');
    form.append('prompt', transcriptionPrompt(kind));
    if (model === 'gpt-transcribe') {
      const priority = ['grill', 'grilled', 'stock', 'mise en place', 'à la carte', 'roux', 'béchamel', 'velouté', 'hollandaise', 'béarnaise', 'mirepoix', 'julienne', 'brunoise', 'sous-vide', 'bain-marie', 'HACCP', 'FIFO', 'sanitising', 'cross-contamination', "chef's knife"];
      for (const term of [...new Set([...priority, ...speechHints])].slice(0, 100)) form.append('keywords[]', term);
    }
    try { return cleanSpeech((await api('audio/transcriptions', form, true)).text || ''); }
    catch (error) {
      firstError ||= error;
      const unavailable = error.status === 400 || error.status === 403 || error.status === 404 || /model|unsupported|not found|access/i.test(error.message);
      if (index < models.length - 1 && unavailable) continue;
      throw error;
    }
  }
  throw firstError || new ApiError('Không thể nhận diện âm thanh.');
}

async function segmentTranscript(segment) {
  if (!segment.transcriptPromise) segment.transcriptPromise = transcribeBlob(segment.blob, 'auto').catch(error => { segment.transcriptPromise = null; throw error; });
  return segment.transcriptPromise;
}

function recentConversation(kind) {
  return lanes[kind].records.slice(0, -1).slice(-4).map(record => `Q: ${record.question}\nA: ${record.answer || ''}`).join('\n');
}

function needsConversationContext(question) {
  return window.SACookTurnPolicy.needsConversationContext(question);
}

function questionParts(question) {
  return window.SACookTurnPolicy.questionParts(question);
}

function questionPartsAreLinked(parts) {
  return window.SACookTurnPolicy.questionPartsAreLinked(parts);
}

function requiresBehavioralSynthesis(question) {
  return /\b(?:tell (?:me|us) about|describe|give (?:me|us)?\s*(?:an? )?example of|share)\b[\s\S]*\b(?:a time|situation|occasion|experience)\b/i.test(question || '')
    || /\b(?:tell|describe|share|give)\b[\s\S]*\b(?:you had|you handled|you faced|you solved|your experience)\b/i.test(question || '')
    || /\b(?:have you ever|how did you)\b/i.test(question || '');
}

async function answerQuestion(question, kind, forceAI = false) {
  const matches = rankMatches(question);
  const best = matches[0];
  const parts = questionParts(question);
  const multipart = parts.length > 1;
  const linkedMultipart = multipart && questionPartsAreLinked(parts);
  if (!forceAI && !multipart && !needsConversationContext(question) && !requiresBehavioralSynthesis(question) && best && (best.score === 1 || (best.score >= 0.76 && best.common >= 2 && best.recall >= 0.65))) return buildAnswerVariants(best.item.answer, question);

  const qaReferences = matches.slice(0, 7).map(match => `Q: ${match.item.question}\nA: ${match.item.answer}`);
  const textReferences = relevantStudySnippets(question).map(chunk => `${chunk.source}:\n${chunk.text}`);
  const references = [...qaReferences, ...textReferences].join('\n---\n');
  const recent = recentConversation(kind);
  const instructions = linkedMultipart
    ? 'The heard turn contains linked, repeated, or clarifying question fragments. Infer the single underlying request from the whole turn and recent conversation, then give one direct answer without numbering.'
    : multipart
    ? 'The heard turn contains independent questions. Answer every question in the same order with clearly numbered answers.'
    : 'Answer the exact heard question directly in two or three concise sentences.';
  const body = {
    model: 'gpt-4.1-mini', store: false, max_output_tokens: multipart && !linkedMultipart ? Math.min(300, parts.length * 110) : 130,
    instructions: `You help the presenter answer an Australian Cook skills-assessment interview. Answer only in English. ${instructions} ${answerPolicy} Return exactly two labelled sections: "Short:" with one direct answer the presenter can say immediately, and "Full:" with a fuller answer containing the useful details. Use clear, natural CEFR B2 vocabulary. For a behavioral question, give a concrete situation, action and result in the Full answer. A local reference is not proof that the presenter lived that event: without a real user example, answer with “I would” and never claim “I once”, “I handled”, or “I worked”. For a technical question, explain the idea directly and give a tradeoff only when asked or essential. When a question is vague, infer the skill being tested and answer it directly. Be confident, practical and accurate. Correct an obvious transcript error only when culinary context makes it certain. Use the local references first and reliable general culinary knowledge when they are insufficient. Never mention references, AI, or that data is missing.`,
    input: `HEARD QUESTION:\n${question}${recent ? `\n\nRECENT CONVERSATION — context only:\n${recent}` : ''}\n\nLOCAL SA COOK REFERENCES:\n${references || 'No close local reference.'}`
  };
  if (forceAI && (!best || best.score < 0.25)) {
    body.tools = [{ type: 'web_search', search_context_size: 'low' }];
    body.tool_choice = 'auto';
    body.max_tool_calls = 1;
  }
  const answer = responseText(await api('responses', body));
  if (!answer) throw new ApiError('OpenAI không trả về câu trả lời.');
  return buildAnswerVariants(answer, question);
}

function setLaneLive(kind, text) {
  lanes[kind].live = text;
  const node = $(kind === 'auto' ? 'autoLive' : 'manualLive');
  if (node) node.textContent = text;
}

function renderHistory(node, records) {
  node.replaceChildren();
  for (const record of records) {
    const exchange = document.createElement('div');
    exchange.className = 'past-exchange';
    const question = document.createElement('div');
    question.className = 'past-question';
    question.textContent = record.question;
    const answer = document.createElement('div');
    answer.className = 'past-answer';
    answer.innerHTML = renderAnswerHtml(record.answer, record.question);
    exchange.append(question, answer);
    node.append(exchange);
  }
}

function renderLane(kind) {
  const lane = lanes[kind];
  const prefix = kind === 'auto' ? 'auto' : 'manual';
  const latest = lane.records[lane.records.length - 1];
  $(prefix + 'Question').textContent = latest?.question || (kind === 'auto' ? 'Waiting for a question…' : 'Listen to the full question, then press Space.');
  const answerNode = $(prefix + 'Answer');
  const answerText = latest?.answer || (kind === 'auto' ? 'The AUTO answer will appear here.' : 'The SPACE answer will appear here.');
  answerNode.innerHTML = renderAnswerHtml(answerText, latest?.question || '');
  $(prefix + 'Live').textContent = lane.live;
  const previous = lane.records.slice(0, -1).reverse();
  renderHistory($(prefix + 'History'), previous);
}

async function answerRecord(kind, record, forceAI = false) {
  const generation = sessionId;
  const requestId = (record.requestId || 0) + 1;
  record.requestId = requestId;
  record.answer = 'Đang chuẩn bị câu trả lời…';
  setLaneLive(kind, kind === 'auto' ? 'AI đang trả lời • vẫn tiếp tục nghe…' : 'AI đang trả lời…');
  renderLane(kind);
  try {
    const answer = await answerQuestion(record.question, kind, forceAI);
    if (record.requestId !== requestId) return;
    record.answer = answer;
    setLaneLive(kind, kind === 'auto' ? 'Đang nghe câu hỏi tiếp theo…' : 'Đang nghe đến khi bạn bấm Space…');
    if (generation === sessionId) setStatus(recording ? 'Đang nghe…' : 'Sẵn sàng');
  } catch (error) {
    if (record.requestId !== requestId) return;
    record.answer = `Lỗi: ${error.message}`;
    setLaneLive(kind, 'Lỗi AI • bấm Retry để thử lại.');
    if (generation === sessionId) setStatus(error.message, true);
  }
  renderLane(kind);
}

function submitQuestion(kind, question) {
  const clean = cleanSpeech(question);
  if (!clean || wordCount(clean) < 3) return;
  const lane = lanes[kind];
  const identity = normalize(clean);
  if (identity && identity === lane.lastAnswered) return;
  lane.lastAnswered = identity;
  const record = { question: clean, answer: '' };
  lane.records.push(record);
  if (lane.records.length > 50) lane.records.shift();
  renderLane(kind);
  $(kind === 'auto' ? 'autoConversation' : 'manualConversation').scrollTop = 0;
  answerRecord(kind, record);
}

function handleAutoPiece(piece, reason) {
  if (!$('autoEnabled').checked) return;
  if (autoFlushTimer) { clearTimeout(autoFlushTimer); autoFlushTimer = null; }
  const lane = lanes.auto;
  const clean = cleanSpeech(piece);
  if (!clean) return;
  let pending = '';
  if (!lane.pending) {
    const candidate = extractQuestionCandidate(clean);
    if (!candidate) return;
    lane.pending = candidate;
    lane.pendingPieces = 1;
    pending = candidate;
  } else {
    // A following answer must not be appended to an already complete question.
    // This also closes AUTO when BlackHole never reaches absolute silence.
    if (isLikelyCompleteQuestion(lane.pending) && looksLikeAnswerStart(clean)) {
      const completed = lane.pending;
      lane.pending = '';
      lane.pendingPieces = 0;
      submitAutoTurn(completed);
      return;
    }
    pending = appendPending(lane, clean);
  }
  if (!pending) return;
  setLaneLive('auto', `Đang nghe: ${pending}`);
  if (isLikelyCompleteQuestion(pending)) {
    // Silence is fastest. Interval chunks still close a stable question after
    // a short revision window, which prevents continuous background audio from
    // leaving AUTO stuck forever.
    scheduleAutoTurnFinish(reason === 'silence' ? AUTO_TURN_GRACE_MS : AUTO_INTERVAL_GRACE_MS);
  }
}

function finishAutoTurn() {
  if (autoFlushTimer) { clearTimeout(autoFlushTimer); autoFlushTimer = null; }
  const lane = lanes.auto;
  const pending = cleanSpeech(lane.pending);
  lane.pending = '';
  lane.pendingPieces = 0;
  if (!pending || !looksLikeQuestion(pending) || wordCount(pending) < 3) {
    setLaneLive('auto', 'Đang nghe câu hỏi tiếp theo…');
    return;
  }
  submitAutoTurn(pending);
}

function submitAutoTurn(turn) {
  submitQuestion('auto', turn);
}

function scheduleAutoTurnFinish(delay = AUTO_TURN_GRACE_MS) {
  if (autoFlushTimer) clearTimeout(autoFlushTimer);
  autoFlushTimer = setTimeout(() => {
    autoFlushTimer = null;
    if (!lanes.auto.transcribing && !lanes.auto.queue.length) finishAutoTurn();
  }, delay);
}

function enqueueTranscription(kind, segments, reason = 'interval', generation = sessionId) {
  const usable = segments.filter(segment => segment.blob.size > 900);
  if (!usable.length) return;
  lanes[kind].queue.push({ segments: usable, reason, generation });
  drainTranscriptionQueue(kind);
}

function enqueueManualTranscription(blob, generation = sessionId) {
  if (!blob || blob.size <= 900) return setStatus('SPACE chưa nhận được âm thanh.', true);
  lanes.manual.queue.push({ blob, reason: 'space', generation });
  drainTranscriptionQueue('manual');
}

async function drainTranscriptionQueue(kind) {
  const lane = lanes[kind];
  if (lane.transcribing) return;
  lane.transcribing = true;
  let autoTurnEnded = false;
  while (lane.queue.length) {
    const job = lane.queue.shift();
    try {
      if (job.generation !== sessionId) continue;
      if (kind === 'auto' && !$('autoEnabled').checked) continue;
      setStatus(kind === 'auto' ? 'AUTO đang nhận diện…' : 'SPACE đang nhận diện…');
      setLaneLive(kind, kind === 'auto' ? 'Đang nhận diện câu hỏi…' : 'Đang nhận diện câu hỏi đã chốt…');
      let transcript = '';
      if (job.blob) transcript = cleanSpeech(await transcribeBlob(job.blob, kind, true));
      else {
        const pieces = [];
        for (const segment of job.segments) {
          const text = await segmentTranscript(segment);
          if (job.generation !== sessionId) break;
          if (text && pieces[pieces.length - 1]?.toLowerCase() !== text.toLowerCase()) pieces.push(text);
        }
        transcript = cleanSpeech(pieces.join(' '));
      }
      if (job.generation !== sessionId) continue;
      if (kind === 'auto') {
        handleAutoPiece(transcript, job.reason);
        if (job.reason === 'silence') autoTurnEnded = true;
      }
      else if (transcript) submitQuestion('manual', transcript);
      else if (kind === 'manual') setStatus('SPACE chưa nghe được câu hỏi.', true);
    } catch (error) {
      if (kind === 'auto' && job.reason === 'silence') autoTurnEnded = true;
      if (job.generation === sessionId) setStatus(error.message, true);
    }
  }
  lane.transcribing = false;
  if (kind === 'auto' && autoTurnEnded && !lane.queue.length) scheduleAutoTurnFinish();
}

function pruneSegments() {
  if (savedSegments.length > MAX_SAVED_SEGMENTS) savedSegments.splice(0, savedSegments.length - MAX_SAVED_SEGMENTS);
}

function finishSegment(blob, reason, hadSignal, generation) {
  if (generation !== sessionId) return;
  if (blob.size > 900) {
    const segment = { id: nextSegmentId++, blob, reason, hadSignal, generation, transcriptPromise: null };
    savedSegments.push(segment);
    lanes.auto.cursor = segment.id + 1;
    if (hadSignal && $('autoEnabled').checked) enqueueTranscription('auto', [segment], reason, generation);
    pruneSegments();
  }
}

function beginRecorderSegment() {
  if (!recording || !audioStream) return;
  const generation = sessionId;
  recorderChunks = [];
  segmentStopping = false;
  segmentHasSignal = false;
  segmentPeak = 0;
  segmentStartedAt = performance.now();
  const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus') ? 'audio/webm;codecs=opus' : 'audio/webm';
  recorder = new MediaRecorder(audioStream, { mimeType });
  recorder.ondataavailable = event => { if (event.data?.size) recorderChunks.push(event.data); };
  recorder.onstop = () => {
    clearTimeout(segmentTimer);
    const blob = new Blob(recorderChunks, { type: mimeType });
    const reason = recorder._stopReason || 'interval';
    const hadSignal = segmentHasSignal || segmentPeak > 0.002;
    if (recording) beginRecorderSegment();
    finishSegment(blob, reason, hadSignal, generation);
  };
  recorder.start();
  segmentTimer = setTimeout(() => stopRecorderSegment('interval'), AUTO_SEGMENT_MS);
}

function stopRecorderSegment(reason) {
  if (!recorder || recorder.state !== 'recording' || segmentStopping) return;
  segmentStopping = true;
  recorder._stopReason = reason;
  recorder.stop();
}

const spaceWorkletSource = `
class SpaceCaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunk = new Float32Array(2048);
    this.offset = 0;
    this.port.onmessage = event => {
      if (event.data && event.data.type === 'cut') {
        this.flush();
        this.port.postMessage({ type: 'cut', id: event.data.id });
      }
    };
  }
  flush() {
    if (!this.offset) return;
    const output = this.chunk.slice(0, this.offset);
    this.offset = 0;
    this.port.postMessage({ type: 'pcm', data: output.buffer }, [output.buffer]);
  }
  process(inputs) {
    const channels = inputs[0];
    if (!channels || !channels.length) return true;
    const length = channels[0].length;
    for (let frame = 0; frame < length; frame += 1) {
      let sample = 0;
      for (let channel = 0; channel < channels.length; channel += 1) sample += channels[channel][frame] || 0;
      this.chunk[this.offset++] = sample / channels.length;
      if (this.offset === this.chunk.length) this.flush();
    }
    return true;
  }
}
registerProcessor('space-capture', SpaceCaptureProcessor);
`;

function appendSpacePcm(buffer) {
  const chunk = new Float32Array(buffer);
  if (!chunk.length) return;
  spacePcmChunks.push(chunk);
  spacePcmSamples += chunk.length;
  const maximum = Math.round((audioContext?.sampleRate || 48000) * MAX_SPACE_SECONDS);
  while (spacePcmSamples > maximum && spacePcmChunks.length > 1) {
    spacePcmSamples -= spacePcmChunks.shift().length;
  }
}

function takeSpacePcm() {
  const output = new Float32Array(spacePcmSamples);
  let offset = 0;
  for (const chunk of spacePcmChunks) { output.set(chunk, offset); offset += chunk.length; }
  spacePcmChunks = [];
  spacePcmSamples = 0;
  return output;
}

function requestSpaceCut(generation) {
  return new Promise((resolve, reject) => {
    if (!spaceCaptureNode || spaceCaptureMode !== 'pcm') return reject(new Error('SPACE capture chưa sẵn sàng.'));
    const id = ++nextSpaceCutId;
    const timeout = setTimeout(() => {
      pendingSpaceCuts.delete(id);
      reject(new Error('SPACE capture không phản hồi. Hãy bật nghe lại.'));
    }, 1800);
    pendingSpaceCuts.set(id, { generation, resolve, reject, timeout });
    spaceCaptureNode.port.postMessage({ type: 'cut', id });
  });
}

function trimAndDownsample(samples, inputRate, outputRate = 16000) {
  const threshold = 0.0018;
  let first = 0;
  while (first < samples.length && Math.abs(samples[first]) < threshold) first += 1;
  if (first === samples.length) return new Float32Array();
  let last = samples.length - 1;
  while (last > first && Math.abs(samples[last]) < threshold) last -= 1;
  const start = Math.max(0, first - Math.round(inputRate * 0.24));
  const end = Math.min(samples.length, last + Math.round(inputRate * 0.14));
  const source = samples.subarray(start, end);
  if (inputRate <= outputRate) return new Float32Array(source);
  const ratio = inputRate / outputRate;
  const output = new Float32Array(Math.max(1, Math.floor(source.length / ratio)));
  for (let index = 0; index < output.length; index += 1) {
    const from = Math.floor(index * ratio);
    const to = Math.min(source.length, Math.max(from + 1, Math.floor((index + 1) * ratio)));
    let sum = 0;
    for (let cursor = from; cursor < to; cursor += 1) sum += source[cursor];
    output[index] = sum / (to - from);
  }
  return output;
}

function encodeWav(samples, sampleRate = 16000) {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);
  const write = (offset, value) => { for (let index = 0; index < value.length; index += 1) view.setUint8(offset + index, value.charCodeAt(index)); };
  write(0, 'RIFF'); view.setUint32(4, 36 + samples.length * 2, true); write(8, 'WAVE');
  write(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true); view.setUint32(28, sampleRate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  write(36, 'data'); view.setUint32(40, samples.length * 2, true);
  for (let index = 0; index < samples.length; index += 1) {
    const value = Math.max(-1, Math.min(1, samples[index]));
    view.setInt16(44 + index * 2, value < 0 ? value * 0x8000 : value * 0x7fff, true);
  }
  return new Blob([buffer], { type: 'audio/wav' });
}

function beginManualRecorder() {
  if (!recording || !audioStream) return;
  const generation = sessionId;
  const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus') ? 'audio/webm;codecs=opus' : 'audio/webm';
  const activeRecorder = new MediaRecorder(audioStream, { mimeType, audioBitsPerSecond: 32000 });
  const chunks = [];
  manualRecorder = activeRecorder;
  manualPeak = 0;
  activeRecorder.ondataavailable = event => { if (event.data?.size) chunks.push(event.data); };
  activeRecorder.onstop = () => {
    const shouldSubmit = activeRecorder._submit === true;
    const hadSignal = manualPeak > 0.002;
    const blob = new Blob(chunks, { type: mimeType });
    if (recording && generation === sessionId) beginManualRecorder();
    if (!shouldSubmit || generation !== sessionId) return;
    manualCommitPending = false;
    if (!hadSignal) return setStatus('SPACE chưa nghe được câu hỏi.', true);
    enqueueManualTranscription(blob, generation);
  };
  activeRecorder.onerror = () => {
    if (generation === sessionId) setStatus('SPACE recorder gặp lỗi. Hãy dừng và bật nghe lại.', true);
  };
  activeRecorder.start();
}

async function startMeter() {
  audioContext = new AudioContext({ latencyHint: 'interactive' });
  await audioContext.resume();
  analyser = audioContext.createAnalyser();
  analyser.fftSize = 1024;
  audioSourceNode = audioContext.createMediaStreamSource(audioStream);
  audioSourceNode.connect(analyser);
  spaceCaptureMode = 'none';
  spacePcmChunks = [];
  spacePcmSamples = 0;
  try {
    const moduleUrl = URL.createObjectURL(new Blob([spaceWorkletSource], { type: 'text/javascript' }));
    try { await audioContext.audioWorklet.addModule(moduleUrl); }
    finally { URL.revokeObjectURL(moduleUrl); }
    spaceCaptureNode = new AudioWorkletNode(audioContext, 'space-capture', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1] });
    spaceSilentGain = audioContext.createGain();
    spaceSilentGain.gain.value = 0;
    spaceCaptureNode.port.onmessage = event => {
      const message = event.data || {};
      if (message.type === 'pcm' && message.data) appendSpacePcm(message.data);
      if (message.type === 'cut') {
        const pending = pendingSpaceCuts.get(message.id);
        if (!pending) return;
        clearTimeout(pending.timeout);
        pendingSpaceCuts.delete(message.id);
        if (pending.generation !== sessionId) pending.reject(new Error('Phiên nghe đã thay đổi.'));
        else pending.resolve(takeSpacePcm());
      }
    };
    audioSourceNode.connect(spaceCaptureNode);
    spaceCaptureNode.connect(spaceSilentGain);
    spaceSilentGain.connect(audioContext.destination);
    spaceCaptureMode = 'pcm';
  } catch (_) {
    spaceCaptureMode = 'media-recorder';
    beginManualRecorder();
  }
  const samples = new Float32Array(analyser.fftSize);
  const tick = () => {
    if (!recording || !analyser) return;
    analyser.getFloatTimeDomainData(samples);
    let sum = 0;
    for (const value of samples) sum += value * value;
    const rms = Math.sqrt(sum / samples.length);
    segmentPeak = Math.max(segmentPeak, rms);
    manualPeak = Math.max(manualPeak, rms);
    const now = performance.now();
    if (rms > 0.003) {
      segmentHasSignal = true;
      lastVoiceAt = now;
    }
    const db = rms > 0 ? 20 * Math.log10(rms) : -100;
    const bars = Math.max(0, Math.min(8, Math.round((db + 58) / 6)));
    $('level').textContent = rms > 0.002 ? `Âm thanh ${'▮'.repeat(bars)}${'▯'.repeat(8 - bars)} ${Math.round(db)} dB` : 'Âm thanh: im lặng';
    if (segmentHasSignal && lastVoiceAt >= segmentStartedAt && now - lastVoiceAt >= SILENCE_MS && now - segmentStartedAt >= 700) stopRecorderSegment('silence');
    meterFrame = requestAnimationFrame(tick);
  };
  tick();
}

async function startListening() {
  if (starting) return;
  starting = true;
  const generation = ++sessionId;
  try {
    const key = await window.saCook.getKey();
    if (!key) { $('settings').click(); throw new Error('Hãy nhập OpenAI API key trước.'); }
    sourceStream = $('source').value === 'system'
      ? await navigator.mediaDevices.getDisplayMedia({ video: true, audio: true })
      : await navigator.mediaDevices.getUserMedia({ audio: true });
    if (generation !== sessionId) { sourceStream.getTracks().forEach(track => track.stop()); return; }
    const tracks = sourceStream.getAudioTracks();
    if (!tracks.length) throw new Error('Không thu được âm thanh. Với âm thanh hệ thống, hãy dùng Windows 10/11 và bật phát âm thanh.');
    for (const track of sourceStream.getTracks()) {
      track.addEventListener('ended', () => { if (recording) stopListening(); }, { once: true });
    }
    audioStream = new MediaStream(tracks);
    savedSegments = [];
    nextSegmentId = 0;
    manualCommitPending = false;
    for (const lane of Object.values(lanes)) { lane.cursor = 0; lane.queue = []; lane.pending = ''; lane.pendingPieces = 0; }
    recording = true;
    lastVoiceAt = performance.now();
    await startMeter();
    if (generation !== sessionId) return;
    beginRecorderSegment();
    $('start').textContent = '■ Dừng nghe';
    $('source').disabled = true;
    setLaneLive('auto', $('autoEnabled').checked ? 'Đang nghe câu hỏi tiếp theo…' : 'AUTO đang tạm dừng.');
    setLaneLive('manual', 'Đang nghe đến khi bạn bấm Space…');
    setStatus('Đang nghe…');
  } catch (error) {
    if (generation !== sessionId) return;
    if (sourceStream) sourceStream.getTracks().forEach(track => track.stop());
    sourceStream = null; audioStream = null; recording = false;
    $('start').textContent = '▶ Bắt đầu nghe';
    $('source').disabled = false;
    setStatus(error.message, true);
  } finally { if (generation === sessionId) starting = false; }
}

function stopListening() {
  sessionId += 1;
  if (autoFlushTimer) { clearTimeout(autoFlushTimer); autoFlushTimer = null; }
  starting = false;
  manualCommitPending = false;
  recording = false;
  clearTimeout(segmentTimer);
  if (meterFrame) cancelAnimationFrame(meterFrame);
  if (recorder?.state === 'recording') { recorder._stopReason = 'stop'; recorder.stop(); }
  if (manualRecorder?.state === 'recording') { manualRecorder._submit = false; manualRecorder.stop(); }
  for (const pending of pendingSpaceCuts.values()) {
    clearTimeout(pending.timeout);
    pending.reject(new Error('Phiên nghe đã dừng.'));
  }
  pendingSpaceCuts.clear();
  spaceCaptureNode?.port.close();
  spaceCaptureNode?.disconnect();
  spaceSilentGain?.disconnect();
  audioSourceNode?.disconnect();
  sourceStream?.getTracks().forEach(track => track.stop());
  audioContext?.close().catch(() => {});
  sourceStream = null; audioStream = null; analyser = null; audioContext = null;
  audioSourceNode = null; spaceCaptureNode = null; spaceSilentGain = null; spaceCaptureMode = 'none';
  spacePcmChunks = []; spacePcmSamples = 0;
  $('start').textContent = '▶ Bắt đầu nghe';
  $('source').disabled = false;
  $('level').textContent = 'Âm thanh: đã dừng';
  setLaneLive('auto', 'Đã dừng nghe.');
  setLaneLive('manual', 'Đã dừng nghe.');
  setStatus('Đã dừng');
}

function commitManualQuestion() {
  if (!recording) { setStatus('Hãy bấm Bắt đầu nghe trước.', true); return; }
  if (manualCommitPending) return;
  manualCommitPending = true;
  setStatus('SPACE đã chốt • đang nhận nốt chữ cuối…');
  setLaneLive('manual', 'Đã chốt • đang nhận nốt chữ cuối…');
  const generation = sessionId;
  setTimeout(async () => {
    if (!manualCommitPending) return;
    if (spaceCaptureMode === 'pcm') {
      try {
        const inputRate = audioContext?.sampleRate || 48000;
        const captured = await requestSpaceCut(generation);
        if (generation !== sessionId) return;
        const speech = trimAndDownsample(captured, inputRate);
        if (speech.length < 1600) return setStatus('SPACE chưa nghe được câu hỏi.', true);
        enqueueManualTranscription(encodeWav(speech), generation);
      } catch (error) {
        if (generation === sessionId) setStatus(error.message, true);
      } finally {
        if (generation === sessionId) manualCommitPending = false;
      }
      return;
    }
    if (manualRecorder?.state === 'recording') {
      manualRecorder._submit = true;
      manualRecorder.stop();
    } else {
      manualCommitPending = false;
      setStatus('SPACE recorder chưa sẵn sàng. Hãy thử lại.', true);
    }
  }, SPACE_TAIL_MS);
}

function clearLane(kind) {
  const lane = lanes[kind];
  lane.records = []; lane.pending = ''; lane.pendingPieces = 0; lane.lastAnswered = '';
  lane.live = recording
    ? (kind === 'auto' && !$('autoEnabled').checked ? 'AUTO đang tạm dừng.' : kind === 'auto' ? 'Đang nghe câu hỏi tiếp theo…' : 'Đang nghe đến khi bạn bấm Space…')
    : 'Đã dừng nghe.';
  renderLane(kind);
}

async function copyLane(kind) {
  const lane = lanes[kind];
  const text = lane.records.slice().reverse().map(record => `${record.question}\n${record.answer}`).join('\n\n');
  if (!text) return setStatus(`Chưa có nội dung ${kind === 'auto' ? 'AUTO' : 'SPACE'} để sao chép.`, true);
  try { await window.saCook.copyText(text); setStatus(`Đã sao chép ${kind === 'auto' ? 'AUTO' : 'SPACE'}.`); }
  catch (_) { setStatus('Windows không cho phép ghi clipboard.', true); }
}

function retryLane(kind) {
  const record = lanes[kind].records[lanes[kind].records.length - 1];
  if (!record) return;
  answerRecord(kind, record, true);
}

$('start').onclick = () => recording ? stopListening() : startListening();
$('commit').onclick = commitManualQuestion;
$('autoEnabled').onchange = () => {
  const enabled = $('autoEnabled').checked;
  if (autoFlushTimer) { clearTimeout(autoFlushTimer); autoFlushTimer = null; }
  lanes.auto.pending = '';
  lanes.auto.pendingPieces = 0;
  if (!enabled) lanes.auto.queue = [];
  setLaneLive('auto', enabled ? (recording ? 'Đang nghe câu hỏi tiếp theo…' : 'AUTO sẵn sàng.') : 'AUTO đang tạm dừng.');
};
$('retryAuto').onclick = () => retryLane('auto');
$('retryManual').onclick = () => retryLane('manual');
$('copyAuto').onclick = () => copyLane('auto');
$('copyManual').onclick = () => copyLane('manual');
$('clearAuto').onclick = () => clearLane('auto');
$('clearManual').onclick = () => clearLane('manual');
$('clearAll').onclick = () => { clearLane('auto'); clearLane('manual'); setStatus(recording ? 'Đang nghe…' : 'Sẵn sàng'); };
$('minimizeWindow').onclick = () => window.saCook.minimizeWindow();
$('closeWindow').onclick = () => window.saCook.closeWindow();
$('settings').onclick = async () => { $('apiKey').value = await window.saCook.getKey(); $('keyStatus').textContent = ''; $('keyDialog').showModal(); };
$('saveKey').onclick = async event => {
  event.preventDefault();
  const key = $('apiKey').value.trim();
  if (!key.startsWith('sk-')) { $('keyStatus').textContent = 'Key chưa đúng định dạng.'; return; }
  const previousKey = await window.saCook.getKey();
  try {
    $('keyStatus').textContent = 'Đang kiểm tra…';
    await window.saCook.setKey(key);
    await api('responses', { model: 'gpt-4.1-mini', input: 'Reply only OK.', max_output_tokens: 8, store: false });
    $('keyDialog').close();
    setStatus('OpenAI key hợp lệ và đã lưu.');
  } catch (error) {
    await window.saCook.setKey(previousKey).catch(() => {});
    $('keyStatus').textContent = error.message;
  }
};

window.addEventListener('keydown', event => {
  if (event.code !== 'Space' || event.repeat || event.ctrlKey || event.altKey || event.metaKey) return;
  const target = event.target;
  if ($('keyDialog').open || target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement || target?.isContentEditable) return;
  event.preventDefault();
  commitManualQuestion();
});

window.addEventListener('beforeunload', () => { if (recording) stopListening(); });

const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));

function setReadingFont(value) {
  const size = clamp(Number(value) || 20, 20, 40);
  document.documentElement.style.setProperty('--answer-size', `${size}px`);
  $('fontValue').textContent = String(size);
  try { localStorage.setItem('saCook.readingFont.v1', String(size)); } catch (_) {}
}

function setBackdrop(value) {
  const strength = clamp(Number(value) || 0, 0, 2);
  document.body.dataset.backdrop = String(strength);
  document.querySelectorAll('[data-backdrop-value]').forEach(button => button.classList.toggle('active', Number(button.dataset.backdropValue) === strength));
  try { localStorage.setItem('saCook.backdrop.v1', String(strength)); } catch (_) {}
}

$('fontDown').onclick = () => setReadingFont(Number($('fontValue').textContent) - 2);
$('fontUp').onclick = () => setReadingFont(Number($('fontValue').textContent) + 2);
document.querySelectorAll('[data-backdrop-value]').forEach(button => { button.onclick = () => setBackdrop(button.dataset.backdropValue); });
document.addEventListener('pointerdown', event => {
  if ($('moreMenu').open && !$('moreMenu').contains(event.target)) $('moreMenu').open = false;
});

let savedFont = 20;
let savedBackdrop = 1;
try {
  savedFont = Number(localStorage.getItem('saCook.readingFont.v1')) || 20;
  const storedBackdrop = localStorage.getItem('saCook.backdrop.v1');
  if (storedBackdrop !== null) savedBackdrop = Number(storedBackdrop);
  if (!Number.isFinite(savedBackdrop)) savedBackdrop = 1;
} catch (_) {}
setReadingFont(savedFont);
setBackdrop(savedBackdrop);

window.saCook.loadResources().then(({ localQA, internetQA, hints, answerPolicy: sharedPolicy, knowledge, handbook }) => {
  qa = [...(Array.isArray(localQA) ? localQA : []), ...(Array.isArray(internetQA) ? internetQA : [])];
  speechHints = hints.split(/\r?\n/).map(value => value.trim()).filter(Boolean);
  if (String(sharedPolicy || '').trim()) answerPolicy = String(sharedPolicy).replace(/\s+/g, ' ').trim();
  buildStudyChunks([['SA Cook Study', knowledge], ['SA Cook Handbook', handbook]]);
  setStatus(`Sẵn sàng • ${qa.length} câu hỏi • ${speechHints.length} thuật ngữ`);
}).catch(error => setStatus(error.message || 'Không đọc được dữ liệu SA Cook.', true));

renderLane('auto');
renderLane('manual');
