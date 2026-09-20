// Package only production dependencies, including their licenses. No install
// scripts or downloads run while building the application bundle.
const fs = require('fs');
const path = require('path');
const destination = process.argv[2];
if (!destination || !fs.statSync(destination).isDirectory()) throw new Error('Existing staging directory required');
const copied = new Map();
function copy(name, from) {
  const metadata = require.resolve(`${name}/package.json`, {paths: [from]});
  const root = path.dirname(metadata);
  const pkg = JSON.parse(fs.readFileSync(metadata, 'utf8'));
  if (copied.has(name)) { if (copied.get(name) !== pkg.version) throw new Error(`Conflicting runtime dependency: ${name}`); return; }
  copied.set(name, pkg.version);
  fs.cpSync(root, path.join(destination, 'node_modules', name), {recursive: true, dereference: true});
  for (const dependency of Object.keys(pkg.dependencies || {})) copy(dependency, root);
}
for (const name of Object.keys(require('./package.json').dependencies || {})) copy(name, __dirname);
console.log(`Packaged ${copied.size} runtime dependencies.`);
