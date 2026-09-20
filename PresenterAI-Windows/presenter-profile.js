(function (root) {
  'use strict';
  const limits = { name: 200, restaurant: 300, address: 500, menu: 10000, experience: 5000, details: 5000, warnings: 2000, sourceText: 40000 };
  function sanitizeProfile(value) {
    const result = {};
    for (const [key, limit] of Object.entries(limits)) result[key] = typeof value?.[key] === 'string' ? value[key].trim().slice(0, limit) : '';
    return result;
  }
  function needsPersonalAnswer(question, profile) {
    if (!Object.values(profile || {}).some(Boolean)) return false;
    if (/\b(you|your|yours|restaurant|menu|workplace|employer|address|live|experience)\b/i.test(question)) return true;
    const terms = [profile.menu, profile.details].join(' ').toLowerCase().match(/[a-zà-ÿ]{4,}/g) || [];
    const words = new Set(String(question).toLowerCase().match(/[a-zà-ÿ]{4,}/g) || []);
    return terms.some(word => words.has(word));
  }
  function answerFacts(profile) {
    const {sourceText, ...facts} = sanitizeProfile(profile);
    return facts;
  }
  function sourceForEditor(profile) {
    if (profile?.sourceText) return profile.sourceText;
    const labels = {name: 'Name', restaurant: 'Restaurant', address: 'Address', menu: 'Menu', experience: 'Experience', details: 'Other facts'};
    return Object.entries(labels).filter(([key]) => profile?.[key]).map(([key, label]) => `${label}: ${profile[key]}`).join('\n\n');
  }
  function validateExtraction(value, sourceText) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('AI trả về hồ sơ không hợp lệ. Hồ sơ cũ được giữ nguyên.');
    const keys = Object.keys(limits).filter(key => key !== 'sourceText');
    if (Object.keys(value).some(key => !keys.includes(key)) || keys.some(key => typeof value[key] !== 'string' || value[key].length > limits[key])) throw new Error('AI chưa trích xuất đủ/đúng cấu trúc. Hồ sơ cũ được giữ nguyên; hãy thử lại hoặc rút gọn nội dung.');
    if (!keys.filter(key => key !== 'warnings').some(key => value[key].trim())) throw new Error(value.warnings || 'Không tìm thấy thông tin cá nhân hoặc menu để lưu. Hồ sơ cũ được giữ nguyên.');
    if (typeof sourceText !== 'string' || sourceText.length > limits.sourceText) throw new Error('Nội dung vượt quá 40.000 ký tự.');
    return sanitizeProfile({...value, sourceText});
  }
  const api = { sanitizeProfile, needsPersonalAnswer, answerFacts, sourceForEditor, validateExtraction };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.SACookProfile = api;
})(typeof window === 'object' ? window : globalThis);
