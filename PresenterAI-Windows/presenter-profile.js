(function (root) {
  'use strict';
  const limits = { name: 200, restaurant: 300, address: 500, menu: 10000, experience: 5000 };
  function sanitizeProfile(value) {
    const result = {};
    for (const [key, limit] of Object.entries(limits)) result[key] = typeof value?.[key] === 'string' ? value[key].trim().slice(0, limit) : '';
    return result;
  }
  function needsPersonalAnswer(question, profile) {
    if (!Object.values(profile || {}).some(Boolean)) return false;
    if (/\b(you|your|yours|restaurant|menu|workplace|employer|address|live|experience)\b/i.test(question)) return true;
    const terms = String(profile.menu || '').toLowerCase().match(/[a-zà-ÿ]{4,}/g) || [];
    const words = new Set(String(question).toLowerCase().match(/[a-zà-ÿ]{4,}/g) || []);
    return terms.some(word => words.has(word));
  }
  const api = { sanitizeProfile, needsPersonalAnswer };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.SACookProfile = api;
})(typeof window === 'object' ? window : globalThis);
