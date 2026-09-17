(function attachB1Policy(root, factory) {
  const policy = factory();
  if (typeof module === 'object' && module.exports) module.exports = policy;
  root.SACookB1 = policy;
}(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  'use strict';

  const DEFAULT_POLICY = 'Use clear, natural CEFR B2 English with varied vocabulary and useful detail. Keep the answer easy to say aloud and focused on the exact question. Keep necessary cooking, food-safety, workplace, legal, and French culinary terms; explain uncommon technical words briefly when helpful. Use I, my, we, or our for actions, choices, experience, and opinions; state factual definitions directly. Provide two versions when the app asks for them: Short is normally under 28 words, and Full is normally under 85 words with the useful details. Do not invent past experience; when no real example is supplied, say what I would do.';

  const NUMBER_VALUES = new Map([
    ['one', 1], ['two', 2], ['three', 3], ['four', 4], ['five', 5],
    ['six', 6], ['seven', 7], ['eight', 8], ['nine', 9], ['ten', 10]
  ]);
  const NUMBER_SOURCE = '(?:one|two|three|four|five|six|seven|eight|nine|ten|[1-9]|10)';
  const LIST_SUBJECT_SOURCE = '(?:fish|shellfish|soups?|stocks?|sauces?|knives?|cuts?|methods?|ways?|examples?|points?|indicators?|signs?|steps?|types?|classifications?|categories?|ingredients?|products?)';

  // Only replacements that preserve grammar in every common inflection are used.
  // Food-safety wording such as HACCP, hazard analysis, critical control point,
  // monitoring, verification, validation and corrective action is left untouched.
  const SAFE_REPLACEMENTS = [
    [/\bdue to the fact that\b/gi, 'because'],
    [/\bin order to\b/gi, 'to'],
    [/\bat this point in time\b/gi, 'now'],
    [/\bsubsequently\b/gi, 'then'],
    [/\bprior to\b/gi, 'before'],
    [/\bsubsequent to\b/gi, 'after'],
    [/\butili[sz]es\b/gi, 'uses'],
    [/\butili[sz]ed\b/gi, 'used'],
    [/\butili[sz]ing\b/gi, 'using'],
    [/\butili[sz]e\b/gi, 'use'],
    [/\bcommences\b/gi, 'starts'],
    [/\bcommenced\b/gi, 'started'],
    [/\bcommencing\b/gi, 'starting'],
    [/\bcommence\b/gi, 'start'],
    [/\bfacilitates\b/gi, 'helps'],
    [/\bfacilitated\b/gi, 'helped'],
    [/\bfacilitating\b/gi, 'helping'],
    [/\bfacilitate\b/gi, 'help']
  ];

  const IMPERATIVE_VERBS = new Set([
    'acknowledge', 'ask', 'avoid', 'check', 'clean', 'communicate', 'confirm', 'cook',
    'cool', 'develop', 'discard', 'explain', 'follow', 'keep', 'label', 'listen',
    'manage', 'measure', 'monitor', 'organise', 'organize', 'participate', 'prepare',
    'promote', 'record', 'report', 'rinse', 'sanitise', 'sanitize', 'separate',
    'serve', 'store', 'tell', 'test', 'train', 'use', 'wash', 'wear'
  ]);

  function cleanText(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  function words(value) {
    return cleanText(value).split(/\s+/).filter(Boolean);
  }

  function wordCount(value) {
    return words(value).length;
  }

  function numberValue(token) {
    const clean = String(token || '').toLowerCase();
    return NUMBER_VALUES.get(clean) || Number(clean) || 0;
  }

  function finishSentence(value) {
    const clean = cleanText(value).replace(/\s+([,.;!?])/g, '$1').replace(/\.{2,}$/g, '.');
    if (!clean) return '';
    const finished = /[.!?]$/.test(clean) ? clean : `${clean}.`;
    return finished.charAt(0).toUpperCase() + finished.slice(1);
  }

  function simplifyVocabulary(value) {
    let clean = cleanText(value).replace(/^(?:answer|suggested answer)\s*:\s*/i, '');
    for (const [pattern, replacement] of SAFE_REPLACEMENTS) clean = clean.replace(pattern, replacement);
    return clean.replace(/\s+([,.;!?])/g, '$1');
  }

  function splitSentences(value) {
    const text = cleanText(value);
    if (!text) return [];
    const result = [];
    let start = 0;
    for (let index = 0; index < text.length; index += 1) {
      const mark = text[index];
      if (mark !== '.' && mark !== '!' && mark !== '?') continue;
      if (mark === '.' && /\d/.test(text[index - 1] || '') && /\d/.test(text[index + 1] || '')) continue;
      const token = text.slice(start, index + 1).match(/(?:^|\s)([A-Za-z.]+)$/)?.[1]?.toLowerCase() || '';
      if (mark === '.' && /^(?:e\.g\.|i\.e\.|mr\.|mrs\.|ms\.|dr\.|vs\.)$/.test(token)) continue;
      let next = index + 1;
      while (next < text.length && /\s/.test(text[next])) next += 1;
      if (next < text.length && mark === '.' && !/[A-Z0-9]/.test(text[next])) continue;
      result.push(text.slice(start, index + 1).trim());
      start = next;
      index = next - 1;
    }
    if (start < text.length) result.push(text.slice(start).trim());
    return result.filter(Boolean);
  }

  function listRequests(question) {
    const clean = cleanText(question);
    if (!/^(?:okay[, ]+|so[, ]+|please\s+)*(?:list|name|give|provide|state|mention|identify)\b|\bwhat are the\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|[1-9]|10)\b/i.test(clean)) return [];
    const specific = new RegExp(`\\b(${NUMBER_SOURCE})\\s+(?:(?:types?|kinds?|examples?|classifications?|categories?)\\s+(?:of|for)\\s+)?(${LIST_SUBJECT_SOURCE})\\b`, 'gi');
    const requests = [];
    for (const match of clean.matchAll(specific)) {
      const count = numberValue(match[1]);
      if (count) requests.push({ count, subject: match[2].toLowerCase().replace(/s$/, '') });
    }
    if (requests.length) return requests;
    const firstNumber = clean.match(new RegExp(`\\b(${NUMBER_SOURCE})\\b`, 'i'));
    return firstNumber ? [{ count: numberValue(firstNumber[1]), subject: '' }] : [];
  }

  function splitTopLevel(value) {
    const text = cleanText(value);
    const items = [];
    let buffer = '';
    let depth = 0;
    const push = () => {
      const item = cleanText(buffer).replace(/^(?:and|or)\s+/i, '').replace(/[.;]+$/, '');
      if (item) items.push(item);
      buffer = '';
    };
    for (let index = 0; index < text.length; index += 1) {
      const character = text[index];
      if (character === '(' || character === '[') depth += 1;
      if (character === ')' || character === ']') depth = Math.max(0, depth - 1);
      const remaining = text.slice(index);
      const andMatch = depth === 0 ? remaining.match(/^\s+(?:and|or)\s+/i) : null;
      if (depth === 0 && (character === ',' || character === ';' || character === '\n')) {
        push();
      } else if (andMatch) {
        push();
        index += andMatch[0].length - 1;
      } else {
        buffer += character;
      }
    }
    push();
    return items;
  }

  function compactName(value) {
    let item = cleanText(value)
      .replace(/^\d+[.)]\s*/, '')
      .replace(/^[-•]\s*/, '')
      .replace(/\s*\([^)]*\)\s*/g, ' ')
      .replace(/\s+(?:which|that)\s+.+$/i, '')
      .replace(/\s+[–—-]\s+.+$/, '')
      .replace(/[.;:,]+$/, '');
    const itemWords = words(item);
    if (itemWords.length > 5) item = itemWords.slice(0, 5).join(' ');
    return cleanText(item);
  }

  function subjectPattern(subject) {
    if (!subject) return '';
    if (subject === 'soup') return '(?:thin\\s+|thick\\s+|cold\\s+|national\\s+)?soups?';
    if (subject === 'fish') return '(?<!shell)fish';
    if (subject === 'shellfish') return 'shellfish';
    return `${subject}s?`;
  }

  function labelledSegments(answer, subject) {
    const source = subjectPattern(subject);
    if (!source) return [];
    const matcher = new RegExp(`\\b(?:${NUMBER_SOURCE}\\s+)?${source}\\s*:\\s*([^.!?]+)`, 'gi');
    return [...answer.matchAll(matcher)].map(match => match[1]);
  }

  function numberedItems(answer) {
    const matches = [...String(answer || '').matchAll(/(?:^|\s)(\d+)[.)]\s+([\s\S]*?)(?=(?:\s+\d+[.)]\s+)|$)/g)];
    return matches.map(match => compactName(match[2])).filter(Boolean);
  }

  function indicatorItems(answer) {
    const matches = [...String(answer || '').matchAll(/(?:^|[.!]\s+)([A-Z][A-Za-z /-]{1,24}):\s*([^.!?]+)/g)];
    return matches.map(match => {
      const descriptor = splitTopLevel(match[2]).slice(0, 2).join(', ');
      const short = words(descriptor).slice(0, 5).join(' ');
      return cleanText(`${match[1]}: ${short}`).replace(/[.;:,]+$/, '');
    }).filter(Boolean);
  }

  function candidatesFor(answer, request) {
    const labelled = labelledSegments(answer, request.subject).flatMap(splitTopLevel).map(compactName).filter(Boolean);
    if (labelled.length >= request.count) return labelled;
    if (/^(?:indicator|point|sign)$/.test(request.subject)) {
      const indicators = indicatorItems(answer);
      if (indicators.length >= request.count) return indicators;
    }
    const numbered = numberedItems(answer);
    if (numbered.length >= request.count) return numbered;
    const afterColon = String(answer || '').includes(':') ? String(answer).slice(String(answer).indexOf(':') + 1) : answer;
    return splitTopLevel(afterColon).map(compactName).filter(Boolean);
  }

  function fitList(groups, maximumWords) {
    const mutable = groups.map(group => ({ label: group.label, items: group.items.slice() }));
    const render = () => mutable.map(group => {
      const separator = group.items.some(item => /[:,]/.test(item)) ? '; ' : ', ';
      return `${group.label ? `${group.label}: ` : ''}${group.items.join(separator)}`;
    }).join('; ');
    let output = render();
    while (wordCount(output) > maximumWords) {
      let target = null;
      for (const group of mutable) {
        for (let index = 0; index < group.items.length; index += 1) {
          const length = words(group.items[index]).length;
          if (length > 1 && (!target || length > target.length)) target = { group, index, length };
        }
      }
      if (!target) break;
      target.group.items[target.index] = words(target.group.items[target.index]).slice(0, -1).join(' ');
      output = render();
    }
    return wordCount(output) <= maximumWords ? finishSentence(output) : '';
  }

  function compactRequestedList(answer, question, maximumWords) {
    const requests = listRequests(question);
    if (!requests.length || requests.reduce((sum, request) => sum + request.count, 0) > maximumWords) return '';
    const groups = [];
    for (const request of requests) {
      const candidates = candidatesFor(answer, request);
      if (candidates.length < request.count) return '';
      const unique = [];
      for (const item of candidates) if (item && !unique.some(existing => existing.toLowerCase() === item.toLowerCase())) unique.push(item);
      if (unique.length < request.count) return '';
      const label = requests.length > 1 && request.subject
        ? request.subject.replace(/^./, letter => letter.toUpperCase()) + (request.subject === 'fish' || request.subject === 'shellfish' ? '' : 's')
        : '';
      groups.push({ label, items: unique.slice(0, request.count) });
    }
    return fitList(groups, maximumWords);
  }

  function shouldUseFirstPerson(question) {
    return /\b(?:how do you|how would you|what do you do|what would you do|how can you|tell (?:me|us) how you|describe how you)\b/i.test(question || '')
      || /\bways can\b[\s\S]*\bbe (?:avoided|handled|managed|prevented|reduced|resolved)\b/i.test(question || '');
  }

  function asksForPastExperience(question) {
    return /\b(?:tell (?:me|us) about|describe|give (?:me|us)?\s*(?:an? )?example of|share)\b[\s\S]*\b(?:a time|situation|occasion|experience)\b/i.test(question || '')
      || /\b(?:tell|describe|share|give)\b[\s\S]*\b(?:you had|you handled|you faced|you solved|your experience)\b/i.test(question || '')
      || /\b(?:have you ever|how did you)\b/i.test(question || '');
  }

  function avoidInventedPast(answer, question) {
    if (!asksForPastExperience(question) || /\bI would\b/i.test(answer)) return answer;
    if (!/\bI\s+(?:once|had|worked|handled|faced|resolved|spoke|noticed|managed|made|was|did)\b/i.test(answer)) return answer;
    const topic = String(question || '').toLowerCase();
    if (/colleague|team member|conflict/.test(topic)) return 'I would speak to the person privately, listen to their view, agree on a fair plan, and follow up to check the result.';
    if (/customer|complaint/.test(topic)) return 'I would listen calmly, confirm the problem, apologise, offer a fair solution, and check that the customer is satisfied.';
    if (/pressure|busy/.test(topic)) return 'I would stay calm, set task priorities, communicate with my team, and check food quality and safety throughout service.';
    if (/mistake|error/.test(topic)) return 'I would report the mistake, fix it safely, explain what happened, and change my process so it does not happen again.';
    return 'I would explain the situation clearly, take practical action, communicate with the people involved, and check the result.';
  }

  function firstPersonWhenSafe(answer, question) {
    if (!shouldUseFirstPerson(question)) return answer;
    const convert = sentence => {
      if (/^(?:I|My|We|Our)\b/i.test(sentence)) return sentence;
      const match = String(sentence || '').match(/^((?:First|Then|Next|Finally),\s*)?((?:Always|Never)\s+)?([A-Za-z]+)\b/);
      if (!match || !IMPERATIVE_VERBS.has(match[3].toLowerCase())) return sentence;
      const prefix = match[1] || '';
      const adverb = match[2] || '';
      const verb = match[3].toLowerCase();
      let rest = sentence.slice(match[0].length);
      if (verb === 'wash') rest = rest.replace(/^\s+(?:the\s+)?hands\b/i, ' my hands');
      if (verb === 'manage') rest = rest.replace(/^\s+(?:the\s+)?station\b/i, ' my station');
      return `${prefix}I ${adverb.toLowerCase()}${verb}${rest}`.replace(/\s+[—–-]\s+([A-Za-z]+)\b/, (whole, nextVerb) => (
        IMPERATIVE_VERBS.has(nextVerb.toLowerCase()) ? `; I ${nextVerb.toLowerCase()}` : whole
      ));
    };
    return splitSentences(answer).map(convert).join(' ');
  }

  function isCriticalFact(value) {
    const negation = new Set(['no', 'not', 'never', 'without', 'cannot', "can't", "don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't", "won't", "wouldn't", "shouldn't", "mustn't"]);
    return words(value).some(token => {
      const lower = token.toLowerCase().replace(/^[^a-z0-9°]+|[^a-z0-9°']+$/g, '');
      return /\d|°/.test(token) || /celsius|fahrenheit|degree/.test(lower) || negation.has(lower);
    });
  }

  function removeOptionalCommaPhrases(value, maximumWords) {
    const parts = String(value || '').split(',').map(part => part.trim()).filter(Boolean);
    if (parts.length < 3) return value;
    while (wordCount(parts.join(', ')) > maximumWords && parts.length > 2) {
      let choice = -1;
      let shortest = Number.POSITIVE_INFINITY;
      for (let index = 1; index + 1 < parts.length; index += 1) {
        if (isCriticalFact(parts[index])) continue;
        const length = wordCount(parts[index]);
        if (length < shortest) {
          shortest = length;
          choice = index;
        }
      }
      if (choice < 0) break;
      parts.splice(choice, 1);
    }
    return parts.join(', ')
      .replace(/,\s*(?:and|or)\s*,/gi, ', ')
      .replace(/,\s*,/g, ', ');
  }

  function keepCompleteSentences(value, maximumWords, maximumSentences = 3) {
    const sentences = splitSentences(value);
    if (sentences.length < 2) return value;
    const chosen = [];
    for (const sentence of sentences) {
      const candidate = [...chosen, sentence].join(' ');
      if (chosen.length < maximumSentences && wordCount(candidate) <= maximumWords) {
        chosen.push(sentence);
      } else if (isCriticalFact(sentence)) {
        while (chosen.length && (chosen.length >= maximumSentences || wordCount([...chosen, sentence].join(' ')) > maximumWords)) chosen.pop();
        if (wordCount(sentence) <= maximumWords) chosen.push(sentence);
      }
    }
    return chosen.length ? chosen.join(' ') : value;
  }

  function trimToWords(value, maximumWords) {
    const tokens = words(value);
    if (tokens.length <= maximumWords) return finishSentence(value);
    let kept = tokens.slice(0, maximumWords);
    const dangling = /^(?:a|an|and|at|before|but|by|during|for|from|in|my|of|on|or|our|the|to|with)$/i;
    while (kept.length > 1 && dangling.test(kept[kept.length - 1].replace(/[^A-Za-z]/g, ''))) kept.pop();
    return finishSentence(kept.join(' ').replace(/[,;:]$/, ''));
  }

  function simplifyAnswer(answer, question = '', maximumWords = 45) {
    let clean = simplifyVocabulary(answer);
    if (!clean) return '';
    clean = avoidInventedPast(clean, question);
    const compactList = compactRequestedList(clean, question, maximumWords);
    if (compactList) return compactList;
    clean = firstPersonWhenSafe(clean, question);
    clean = removeOptionalCommaPhrases(clean, maximumWords);
    clean = keepCompleteSentences(clean, maximumWords);
    return trimToWords(clean, maximumWords);
  }

  function simplifyAnswerOutput(answer, question = '', maximumWords = 45) {
    const questionCount = (String(question || '').match(/\?/g) || []).length;
    if (questionCount < 2) return simplifyAnswer(answer, question, maximumWords);
    const parts = String(answer || '').trim().split(/\s+(?=\d+[.)]\s+)/).filter(Boolean);
    if (parts.length < 2) return simplifyAnswer(answer, question, maximumWords);
    return parts.map(part => {
      const match = part.match(/^(\d+)[.)]\s*([\s\S]*)$/);
      return match ? `${match[1]}. ${simplifyAnswer(match[2], '', maximumWords)}` : simplifyAnswer(part, '', maximumWords);
    }).join('\n');
  }

  return {
    DEFAULT_POLICY,
    compactRequestedList,
    avoidInventedPast,
    firstPersonWhenSafe,
    isCriticalFact,
    keepCompleteSentences,
    removeOptionalCommaPhrases,
    simplifyAnswer,
    simplifyAnswerOutput,
    splitSentences,
    wordCount
  };
}));
