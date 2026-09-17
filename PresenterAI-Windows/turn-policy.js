(function (root, factory) {
  const policy = factory();
  if (typeof module === 'object' && module.exports) module.exports = policy;
  if (root) root.SACookTurnPolicy = policy;
})(typeof window !== 'undefined' ? window : globalThis, function () {
  'use strict';

  const stopWords = new Set('what when where which would could should please your you about tell have with that this from they them think important does into are the and for um uh ah yeah okay'.split(' '));
  const normalise = text => String(text || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
  const contentWords = text => new Set(normalise(text).split(/\s+/).filter(word => word.length > 2 && !stopWords.has(word)));

  function needsConversationContext(question) {
    const clean = normalise(question);
    return /\b(?:it|this|that|these|those|they|them|former|latter)\b/.test(clean)
      || /^(?:okay |so |and )*(?:what are the ingredients|what do you have in (?:it|that)|what about (?:it|that))$/.test(clean)
      || (/^(?:okay |so |and )*(?:what|which|how) (?:are |is |about |do you (?:have|use|put) )?(?:the )?(?:ingredients?|sauce|dressing|method|temperature|time)\b/.test(clean) && contentWords(clean).size <= 1);
  }

  function questionParts(question) {
    return String(question || '').split(/\n+|\?\s+/).map(part => part.trim()).filter(Boolean);
  }

  function questionPartsAreLinked(parts) {
    if (parts.length < 2) return false;
    for (let index = 1; index < parts.length; index += 1) {
      const current = normalise(parts[index]);
      const previous = normalise(parts[index - 1]);
      if (!current || current === previous || needsConversationContext(parts[index])) return true;
      const currentTerms = contentWords(parts[index]);
      const previousTerms = contentWords(parts[index - 1]);
      let common = 0;
      for (const term of currentTerms) if (previousTerms.has(term)) common += 1;
      const shorter = Math.min(currentTerms.size, previousTerms.size);
      if (common >= 2 && shorter && common / shorter >= 0.7) return true;
      if (/\b(?:ingredients?|sauce|dressing|method|temperature|time)\b/.test(current) && currentTerms.size <= 3 && common >= 1) return true;
    }
    return false;
  }

  return Object.freeze({ normalise, contentWords, needsConversationContext, questionParts, questionPartsAreLinked });
});
