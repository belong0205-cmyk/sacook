'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const policy = require('../b1-policy.js');

const root = path.resolve(__dirname, '..');
const sharedPolicy = fs.readFileSync(path.resolve(root, '..', 'Shared', 'answer-policy.txt'), 'utf8').trim();
const windowsPolicy = fs.readFileSync(path.resolve(root, 'resources', 'answer-policy.txt'), 'utf8').trim();
assert.equal(policy.DEFAULT_POLICY, sharedPolicy, 'Windows fallback policy must exactly match Shared/answer-policy.txt');
assert.equal(windowsPolicy, sharedPolicy, 'Windows development resource must exactly match Shared/answer-policy.txt');
assert.match(policy.DEFAULT_POLICY, /clear, natural CEFR B2 English/);
assert.match(policy.DEFAULT_POLICY, /Short is normally under 28 words/);
assert.match(policy.DEFAULT_POLICY, /Full is normally under 85 words/);

const count = policy.wordCount;

assert.equal(
  policy.simplifyAnswer('I subsequently utilise approximately two additional containers prior to service.'),
  'I then use approximately two additional containers before service.',
  'the B2 policy keeps useful precise vocabulary while removing overly formal wording'
);

assert.equal(
  policy.simplifyAnswer(
    'Always wash hands, use separate boards, and sanitise food-contact surfaces after cleaning.',
    'How do you work safely?'
  ),
  'I always wash my hands, use separate boards, and sanitise food-contact surfaces after cleaning.',
  'frequency adverbs must follow the first-person subject'
);

const decimal = policy.simplifyAnswer(
  'The target percentage is 29.3%. I record it on the food-safety sheet. I also check the weekly trend. The fourth extra sentence must be omitted.',
  'What percentage do you record?'
);
assert.match(decimal, /29\.3%/);
assert.match(decimal, /food-safety sheet/);
assert.match(decimal, /weekly trend/);
assert.doesNotMatch(decimal, /fourth extra sentence/);
assert.ok(count(decimal) <= 45, `decimal answer exceeds 45 words: ${decimal}`);

const fish = policy.simplifyAnswer(
  'Three fish: Atlantic salmon (rich, oily, versatile), barramundi (mild, firm, ideal for pan-frying), and snapper (lean, delicate, good whole-roasted). Three shellfish: king prawns, Moreton Bay bugs, and Sydney rock oysters.',
  'List three types of fish.'
);
assert.match(fish, /Atlantic salmon/i);
assert.match(fish, /barramundi/i);
assert.match(fish, /snapper/i);
assert.doesNotMatch(fish, /king prawns/i);
assert.ok(count(fish) <= 45, `three-fish answer exceeds 45 words: ${fish}`);

const fishAndShellfish = policy.simplifyAnswer(
  'Three fish: Atlantic salmon (rich and oily), barramundi (mild and firm), and snapper (lean and delicate). Three shellfish: king prawns (sweet and firm), Moreton Bay bugs (sweet), and Sydney rock oysters (briny).',
  'List three types of fish and three types of shellfish.'
);
for (const name of ['Atlantic salmon', 'barramundi', 'snapper', 'king prawns', 'Moreton Bay bugs', 'Sydney rock oysters']) assert.match(fishAndShellfish, new RegExp(name, 'i'));
assert.ok(count(fishAndShellfish) <= 45, `fish and shellfish answer exceeds 45 words: ${fishAndShellfish}`);

const soups = policy.simplifyAnswer(
  'Thin soups: clear soup (consommé), broth soup. Thick soups: cream soup, puree soup, chowder, bisque soup (shellfish stock). Cold soups: gazpacho.',
  'Name six soups.'
);
for (const soup of ['clear soup', 'broth soup', 'cream soup', 'puree soup', 'chowder', 'bisque soup']) assert.match(soups, new RegExp(soup, 'i'));
assert.doesNotMatch(soups, /gazpacho/i);
assert.ok(count(soups) <= 45, `six-soup answer exceeds 45 words: ${soups}`);

const indicators = policy.simplifyAnswer(
  'Eyes: clear, bright, slightly protruding. Gills: bright red or pink and moist. Flesh: firm and springs back when pressed. Smell: mild and clean.',
  'Give three indicators for quality fresh whole fish.'
);
for (const label of ['Eyes:', 'Gills:', 'Flesh:']) assert.match(indicators, new RegExp(label, 'i'));
assert.doesNotMatch(indicators, /Smell:/i);
assert.match(indicators, /; Gills:/i);
assert.ok(count(indicators) <= 45, `indicator answer exceeds 45 words: ${indicators}`);

const haccp = policy.simplifyAnswer(
  'HACCP requires monitoring and verification at each critical control point. Corrective action is required when a critical limit is not met.',
  'How does HACCP control food-safety hazards?'
);
for (const term of ['HACCP', 'monitoring', 'verification', 'critical control point', 'Corrective action', 'critical limit']) assert.match(haccp, new RegExp(term, 'i'));
assert.match(haccp, /is required/, 'do not damage official food-safety grammar by changing “required” to “needed”');
assert.ok(count(haccp) <= 45, `HACCP answer exceeds 45 words: ${haccp}`);

const cultural = policy.simplifyAnswer(
  'Participate in cultural awareness training. Use open, non-judgmental communication — ask politely instead of assuming. Promote anti-discrimination policies.',
  'In what ways can problems or misunderstandings with customers or colleagues from different cultural backgrounds be avoided?'
);
assert.match(cultural, /^I participate\b/);
assert.match(cultural, /\bI use\b/);
assert.ok(count(cultural) <= 45, `first-person answer exceeds 45 words: ${cultural}`);

const hygiene = policy.simplifyAnswer(
  'Wash hands, use separate boards, and sanitise food-contact surfaces after cleaning.',
  'How do you prevent cross-contamination?'
);
assert.match(hygiene, /^I wash my hands\b/);
assert.match(hygiene, /sanitise/);
assert.ok(count(hygiene) <= 45, `hygiene answer exceeds 45 words: ${hygiene}`);

const lateCriticalFacts = policy.simplifyAnswer(
  'I check every item carefully before service and keep the station clean, safe, ready, calm, neat, well stocked, clearly labelled, and easy for my team to use during a busy shift without delay at 75°C.',
  'How do you prepare for service?'
);
assert.ok(count(lateCriticalFacts) <= 45, `critical-fact answer exceeds 45 words: ${lateCriticalFacts}`);
assert.match(lateCriticalFacts, /\bwithout\b/);
assert.match(lateCriticalFacts, /75°C/);
assert.doesNotMatch(lateCriticalFacts, /\bduring\./, 'hard cap must not leave a dangling phrase');
assert.doesNotMatch(lateCriticalFacts, /during without/, 'critical suffix must not be spliced onto an incomplete fragment');
assert.match(lateCriticalFacts, /during a busy shift without delay at 75°C\.$/, 'the retained critical clause must remain contiguous and complete');

const lateCriticalSentence = policy.simplifyAnswer(
  'I organise every delivery and prepare a detailed station plan before service begins. I then review several optional notes with my team. I never serve chicken below 75°C.',
  'How do you keep chicken safe?'
);
assert.ok(count(lateCriticalSentence) <= 45, `critical-sentence answer exceeds 45 words: ${lateCriticalSentence}`);
assert.match(lateCriticalSentence, /I never serve chicken below 75°C\./, 'complete-sentence selection must keep a late critical fact');

const behavioral = policy.simplifyAnswer(
  'I once worked with a colleague who was late finishing prep, so I spoke to them privately and we fixed the problem.',
  'Tell me about a time you handled a difficult colleague or team member.'
);
assert.match(behavioral, /^I would\b/);
assert.doesNotMatch(behavioral, /\bI once\b/);
assert.ok(count(behavioral) <= 45, `behavioral answer exceeds 45 words: ${behavioral}`);

const richerB2 = policy.simplifyAnswer(
  'I maintain an organised mise en place, communicate priorities clearly, monitor food safety throughout service, and adapt quickly when orders change. This helps the team work efficiently while protecting consistency, timing, and presentation quality.',
  'How do you stay effective during a busy service?'
);
assert.ok(count(richerB2) > 30 && count(richerB2) <= 45, `B2 answer should retain useful detail between 31 and 45 words: ${richerB2}`);
for (const word of ['maintain', 'priorities', 'monitor', 'adapt', 'efficiently', 'consistency']) assert.match(richerB2, new RegExp(`\\b${word}\\b`, 'i'));

const source = fs.readFileSync(path.resolve(root, 'app.js'), 'utf8');
assert.match(source, /requiresBehavioralSynthesis\(question\)/, 'local fast path must guard behavioral questions');
assert.match(source, /!requiresBehavioralSynthesis\(question\)/, 'behavioral questions must bypass memorized exact answers');
assert.match(source, /A local reference is not proof that the presenter lived that event/);

console.log('Windows B2 answer policy tests passed.');
