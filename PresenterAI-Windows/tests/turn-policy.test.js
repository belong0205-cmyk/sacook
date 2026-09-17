'use strict';

const assert = require('assert');
const policy = require('../turn-policy');

assert(policy.needsConversationContext('What are the ingredients?'));
assert(policy.needsConversationContext('So what do you have in that?'));
assert(!policy.needsConversationContext('What ingredients are used in a mirepoix?'));
assert(policy.questionPartsAreLinked(policy.questionParts('What are the ingredients?\nSo what do you have in that?\nWhat are the ingredients?')));
assert(policy.questionPartsAreLinked(policy.questionParts('What are the ingredients?\nWhat ingredients do you have?')));
assert(!policy.questionPartsAreLinked(policy.questionParts('Which knife is most versatile?\nWhat is the temperature danger zone?')));
assert(!policy.questionPartsAreLinked(policy.questionParts('Which knife is most versatile?\nWhat knife is best for julienne vegetables?')));

console.log('Windows speaking-turn policy tests passed.');
