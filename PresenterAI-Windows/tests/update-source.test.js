'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, '..', 'main.js'), 'utf8');

assert.match(source, /skipTaskbar:\s*true/, 'open Windows app must stay out of the taskbar');
assert.match(source, /mainWindow\.setSkipTaskbar\(false\);\s*\n\s*mainWindow\.minimize\(\)/, 'a minimized window must remain restorable');
assert.match(source, /app\.requestSingleInstanceLock\(\)/, 'hidden app must prevent duplicate instances');
assert.match(source, /app\.on\('second-instance',[\s\S]*mainWindow\.restore\(\)[\s\S]*mainWindow\.focus\(\)/, 'opening the EXE again must restore and focus the hidden app');
assert.match(source, /cwd:\s*download\.updateDir/, 'updater must start outside the installed app directory');
assert.match(source, /Set-Location -LiteralPath \(\[IO\.Path\]::GetTempPath\(\)\)/, 'PowerShell updater must leave the installed app directory');
assert.doesNotMatch(source, /Wait-Process[^\n]*-Timeout/, 'Windows PowerShell 5.1 does not support Wait-Process -Timeout');
assert.match(source, /\$attempt -lt 180/, 'updater must allow the old app enough time to exit');
assert.match(source, /response\.body[\s\S]*response\.arrayBuffer\(\)/, 'updater must fall back when Electron returns HTTP 200 without a stream body');

console.log('Windows update and taskbar checks passed.');
