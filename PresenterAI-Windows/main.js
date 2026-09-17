const { app, BrowserWindow, clipboard, ipcMain, desktopCapturer, session, safeStorage, net } = require('electron');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { Readable, Transform } = require('stream');
const { pipeline } = require('stream/promises');
const { fileURLToPath } = require('url');

const KEY_FILE = '.openai-key.v2';
const PORTABLE_DIR_NAME = 'SA Cook Assistant-win32-x64';
const PORTABLE_EXE_NAME = 'SA Cook Assistant.exe';
const PORTABLE_MARKER = '.sa-cook-portable-root';
const PORTABLE_MARKER_VALUE = 'SA Cook Assistant portable root\n';
const UPDATE_HEALTH_ARG = '--sa-cook-update-health=';
const RELEASES_API = 'https://api.github.com/repos/belong0205-cmyk/sacook/releases?per_page=30';
const MAX_UPDATE_BYTES = 600 * 1024 * 1024;
const TRUSTED_DOWNLOAD_HOSTS = new Set([
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
  'github-releases.githubusercontent.com'
]);
let mainWindow = null;
let updateInProgress = false;
const hasSingleInstanceLock = app.requestSingleInstanceLock();

if (!hasSingleInstanceLock) app.quit();

function isLocalAppUrl(value) {
  try {
    const url = new URL(value || '');
    return url.protocol === 'file:' && path.resolve(fileURLToPath(url)) === path.resolve(__dirname, 'index.html');
  } catch (_) { return false; }
}

function isTrustedWebContents(contents) {
  return Boolean(mainWindow && !mainWindow.isDestroyed() && contents && contents.id === mainWindow.webContents.id && isLocalAppUrl(contents.getURL()));
}

function isTrustedFrame(frame) {
  if (!frame || !mainWindow || mainWindow.isDestroyed()) return false;
  return frame.processId === mainWindow.webContents.mainFrame.processId && isLocalAppUrl(frame.url);
}

function isTrustedIpc(event) {
  return Boolean(event && isTrustedWebContents(event.sender) && isLocalAppUrl(event.senderFrame && event.senderFrame.url));
}

function keyPath() { return path.join(app.getPath('userData'), KEY_FILE); }

function readResource(name, fallback = '') {
  try { return fs.readFileSync(path.join(__dirname, 'resources', name), 'utf8'); }
  catch (_) { return fallback; }
}

function compareVersions(left, right) {
  const parts = value => {
    const match = String(value || '').match(/(?:^|[^0-9])(\d+)\.(\d+)(?:\.(\d+))?/);
    return match ? [Number(match[1]), Number(match[2]), Number(match[3] || 0)] : null;
  };
  const a = parts(left);
  const b = parts(right);
  if (!a || !b) return 0;
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] > b[index] ? 1 : -1;
  }
  return 0;
}

function windowsReleaseMetadata(release) {
  if (!release || release.draft) return null;
  const tag = String(release.tag_name || '');
  const preview = tag.match(/^v(\d+)\.(\d+)(?:\.(\d+))?-windows-preview(?:\.(\d+))?$/i);
  const stable = tag.match(/^v(\d+)\.(\d+)\.(\d+)$/i);
  const match = preview || stable;
  if (!match || (preview && !release.prerelease) || (stable && release.prerelease)) return null;
  const version = `${Number(match[1])}.${Number(match[2])}.${Number(match[3] || 0)}`;
  const expectedName = preview
    ? `SA-Cook-Assistant-Windows-x64-v${version}-preview.zip`
    : `SA-Cook-Assistant-Windows-x64-v${version}.zip`;
  const asset = Array.isArray(release.assets)
    ? release.assets.find(item => item && String(item.name || '') === expectedName)
    : null;
  return asset ? { version, release, asset } : null;
}

function isTrustedDownloadUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && TRUSTED_DOWNLOAD_HOSTS.has(url.hostname.toLowerCase());
  } catch (_) { return false; }
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 20000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await net.fetch(url, { ...options, signal: controller.signal, redirect: 'follow' });
  } finally { clearTimeout(timeout); }
}

function githubHeaders() {
  return {
    Accept: 'application/vnd.github+json',
    'User-Agent': `SA-Cook-Assistant-Windows/${app.getVersion()}`,
    'X-GitHub-Api-Version': '2022-11-28'
  };
}

async function findWindowsUpdate() {
  const response = await fetchWithTimeout(RELEASES_API, { headers: githubHeaders() });
  if (!response.ok) throw new Error(`Không kiểm tra được bản cập nhật (GitHub HTTP ${response.status}).`);
  const releases = await response.json();
  if (!Array.isArray(releases)) throw new Error('GitHub trả về danh sách cập nhật không hợp lệ.');
  const currentVersion = app.getVersion();
  const candidates = [];
  for (const release of releases) {
    const candidate = windowsReleaseMetadata(release);
    if (!candidate || compareVersions(candidate.version, currentVersion) <= 0) continue;
    if (!isTrustedDownloadUrl(candidate.asset.browser_download_url)) continue;
    candidates.push(candidate);
  }
  candidates.sort((a, b) => {
    const versionOrder = compareVersions(b.version, a.version);
    if (versionOrder) return versionOrder;
    return String(b.release.published_at || '').localeCompare(String(a.release.published_at || ''));
  });
  return candidates[0] || null;
}

function isPortableRoot(targetDir, requireMarker = true) {
  if (!app.isPackaged || process.platform !== 'win32') return false;
  const resolved = path.resolve(targetDir);
  if (resolved.startsWith('\\\\') || path.parse(resolved).root === resolved) return false;
  if (path.basename(resolved) !== PORTABLE_DIR_NAME || path.basename(process.execPath) !== PORTABLE_EXE_NAME) return false;
  if (!fs.existsSync(path.join(resolved, 'resources', 'app.asar'))) return false;
  if (!requireMarker) return true;
  try { return fs.readFileSync(path.join(resolved, PORTABLE_MARKER), 'utf8') === PORTABLE_MARKER_VALUE; }
  catch (_) { return false; }
}

function ensurePortableMarker() {
  const targetDir = path.dirname(process.execPath);
  if (!isPortableRoot(targetDir, false)) return;
  try { fs.writeFileSync(path.join(targetDir, PORTABLE_MARKER), PORTABLE_MARKER_VALUE, { encoding: 'utf8', mode: 0o600 }); }
  catch (_) {}
}

function requestedUpdateHealthPath() {
  const argument = process.argv.find(value => String(value).startsWith(UPDATE_HEALTH_ARG));
  if (!argument) return '';
  try {
    const decoded = Buffer.from(String(argument).slice(UPDATE_HEALTH_ARG.length), 'base64').toString('utf8');
    const healthPath = path.resolve(decoded);
    const updateDir = path.dirname(healthPath);
    const tempDir = path.resolve(app.getPath('temp'));
    if (path.basename(healthPath) !== 'ready' || !path.basename(updateDir).startsWith('sa-cook-update-')) return '';
    if (path.resolve(path.dirname(updateDir)).toLowerCase() !== tempDir.toLowerCase()) return '';
    return healthPath;
  } catch (_) { return ''; }
}

async function expectedAssetDigest(release, asset) {
  const direct = String(asset.digest || '').match(/^sha256:([a-f0-9]{64})$/i);
  if (direct) return direct[1].toLowerCase();
  const sidecarNames = new Set([`${asset.name}.sha256`, String(asset.name).replace(/\.zip$/i, '.sha256')]);
  const sidecar = (release.assets || []).find(item => item && sidecarNames.has(String(item.name || '')) && isTrustedDownloadUrl(item.browser_download_url));
  if (!sidecar || Number(sidecar.size || 0) > 64 * 1024) throw new Error('Bản cập nhật chưa có mã SHA-256 để xác minh an toàn.');
  const response = await fetchWithTimeout(sidecar.browser_download_url, { headers: githubHeaders() });
  if (!response.ok || !isTrustedDownloadUrl(response.url)) throw new Error('Không tải được mã xác minh của bản cập nhật.');
  const match = (await response.text()).match(/\b([a-f0-9]{64})\b/i);
  if (!match) throw new Error('Mã xác minh SHA-256 không hợp lệ.');
  return match[1].toLowerCase();
}

function sendUpdateStatus(sender, detail) {
  if (sender && !sender.isDestroyed()) sender.send('update:status', detail);
}

async function downloadVerifiedUpdate(sender, release, asset) {
  const declaredSize = Number(asset.size || 0);
  if (declaredSize < 1024 * 1024 || declaredSize > MAX_UPDATE_BYTES) throw new Error('Kích thước bản cập nhật không hợp lệ.');
  const expectedDigest = await expectedAssetDigest(release, asset);
  const updateDir = await fs.promises.mkdtemp(path.join(app.getPath('temp'), 'sa-cook-update-'));
  const zipPath = path.join(updateDir, 'update.zip');
  const controller = new AbortController();
  const downloadTimeout = setTimeout(() => controller.abort(), 10 * 60 * 1000);
  const hash = crypto.createHash('sha256');
  let received = 0;
  let lastPercent = -1;
  const meter = new Transform({
    transform(chunk, _encoding, callback) {
      received += chunk.length;
      if (received > MAX_UPDATE_BYTES || (declaredSize && received > declaredSize + 1024)) return callback(new Error('Gói cập nhật vượt quá kích thước đã công bố.'));
      hash.update(chunk);
      const percent = Math.min(99, Math.floor((received / declaredSize) * 100));
      if (percent !== lastPercent) {
        lastPercent = percent;
        sendUpdateStatus(sender, { phase: 'download', percent });
      }
      callback(null, chunk);
    }
  });
  try {
    const response = await net.fetch(asset.browser_download_url, { headers: githubHeaders(), signal: controller.signal, redirect: 'follow' });
    if (!response.ok || !isTrustedDownloadUrl(response.url)) throw new Error(`Không tải được bản cập nhật (HTTP ${response.status}).`);
    if (response.body) {
      await pipeline(Readable.fromWeb(response.body), meter, fs.createWriteStream(zipPath, { flags: 'wx', mode: 0o600 }));
    } else {
      const buffer = Buffer.from(await response.arrayBuffer());
      received = buffer.length;
      if (received > MAX_UPDATE_BYTES || (declaredSize && received > declaredSize + 1024)) throw new Error('Gói cập nhật vượt quá kích thước đã công bố.');
      hash.update(buffer);
      sendUpdateStatus(sender, { phase: 'download', percent: 99 });
      await fs.promises.writeFile(zipPath, buffer, { flag: 'wx', mode: 0o600 });
    }
    if (received !== declaredSize) throw new Error('Gói cập nhật tải về chưa đầy đủ.');
    const actualDigest = hash.digest('hex');
    if (!crypto.timingSafeEqual(Buffer.from(actualDigest, 'hex'), Buffer.from(expectedDigest, 'hex'))) throw new Error('Gói cập nhật không vượt qua kiểm tra SHA-256.');
    return { updateDir, zipPath };
  } catch (error) {
    await fs.promises.rm(updateDir, { recursive: true, force: true }).catch(() => {});
    throw error;
  } finally { clearTimeout(downloadTimeout); }
}

function updaterPowerShell() {
  return String.raw`param(
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [Parameter(Mandatory=$true)][string]$ZipPath,
  [Parameter(Mandatory=$true)][string]$TargetDir,
  [Parameter(Mandatory=$true)][string]$ExeName,
  [Parameter(Mandatory=$true)][string]$PortableDirName,
  [Parameter(Mandatory=$true)][string]$StageDir,
  [Parameter(Mandatory=$true)][string]$BackupDir,
  [Parameter(Mandatory=$true)][string]$HealthPath
)
$ErrorActionPreference = 'Stop'
# Never keep PowerShell's working directory inside the app folder. Windows can
# refuse to rename a directory while another process is using it as its CWD.
Set-Location -LiteralPath ([IO.Path]::GetTempPath())
function Invoke-WithRetry([scriptblock]$Action) {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { & $Action; return } catch { if ($attempt -eq 39) { throw }; Start-Sleep -Milliseconds 500 }
  }
}
for ($attempt = 0; $attempt -lt 180 -and (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue); $attempt++) { Start-Sleep -Milliseconds 500 }
if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) { exit 10 }
try {
  if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
  New-Item -ItemType Directory -Path $StageDir | Out-Null
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $StageDir -Force
  $payloadDir = Join-Path $StageDir $PortableDirName
  $payloadExe = Join-Path $payloadDir $ExeName
  $payloadAsar = Join-Path $payloadDir 'resources\app.asar'
  if (-not (Test-Path -LiteralPath $payloadDir -PathType Container) -or -not (Test-Path -LiteralPath $payloadExe -PathType Leaf) -or -not (Test-Path -LiteralPath $payloadAsar -PathType Leaf)) { throw 'Updated portable package structure is invalid.' }
  if (Test-Path -LiteralPath $BackupDir) { Remove-Item -LiteralPath $BackupDir -Recurse -Force }
  Invoke-WithRetry { Rename-Item -LiteralPath $TargetDir -NewName ([IO.Path]::GetFileName($BackupDir)) }
  try {
    Move-Item -LiteralPath $payloadDir -Destination $TargetDir
    $newExe = Join-Path $TargetDir $ExeName
    if (-not (Test-Path -LiteralPath $newExe)) { throw 'Replacement executable is missing.' }
    if (Test-Path -LiteralPath $HealthPath) { Remove-Item -LiteralPath $HealthPath -Force }
    $healthArg = '--sa-cook-update-health=' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($HealthPath))
    $newProcess = Start-Process -FilePath $newExe -WorkingDirectory $TargetDir -ArgumentList $healthArg -PassThru
    for ($attempt = 0; $attempt -lt 60 -and -not (Test-Path -LiteralPath $HealthPath) -and -not $newProcess.HasExited; $attempt++) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-Path -LiteralPath $HealthPath)) { throw 'The updated app did not finish starting.' }
    Remove-Item -LiteralPath $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StageDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
  } catch {
    if ($newProcess -and -not $newProcess.HasExited) { Stop-Process -Id $newProcess.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1 }
    if (Test-Path -LiteralPath $TargetDir) { Invoke-WithRetry { Remove-Item -LiteralPath $TargetDir -Recurse -Force } }
    if (Test-Path -LiteralPath $BackupDir) { Invoke-WithRetry { Rename-Item -LiteralPath $BackupDir -NewName ([IO.Path]::GetFileName($TargetDir)) } }
    throw
  }
} catch {
  $_ | Out-File -FilePath ($ZipPath + '.error.log') -Encoding utf8
  $oldExe = Join-Path $TargetDir $ExeName
  if (Test-Path -LiteralPath $oldExe) { Start-Process -FilePath $oldExe -WorkingDirectory $TargetDir }
  exit 1
}`;
}

async function launchPortableUpdater(download) {
  if (!app.isPackaged || process.platform !== 'win32') throw new Error('Update trực tiếp chỉ hoạt động trong bản Windows đã đóng gói.');
  const targetDir = path.dirname(process.execPath);
  if (!isPortableRoot(targetDir, true)) throw new Error(`Hãy giữ ứng dụng trong thư mục “${PORTABLE_DIR_NAME}” rồi thử Update lại.`);
  const parentDir = path.dirname(targetDir);
  const suffix = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
  const stageDir = path.join(parentDir, `.sa-cook-stage-${suffix}`);
  const backupDir = path.join(parentDir, `.sa-cook-backup-${suffix}`);
  const writeProbe = path.join(parentDir, `.sa-cook-write-test-${suffix}`);
  await fs.promises.writeFile(writeProbe, 'ok', { flag: 'wx' });
  await fs.promises.unlink(writeProbe);
  const scriptPath = path.join(download.updateDir, 'install-update.ps1');
  const healthPath = path.join(download.updateDir, 'ready');
  await fs.promises.writeFile(scriptPath, updaterPowerShell(), { encoding: 'utf8', mode: 0o600 });
  const systemRoot = process.env.SystemRoot || process.env.WINDIR;
  const powershellPath = systemRoot && path.join(systemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  if (!powershellPath || !path.isAbsolute(powershellPath) || !fs.existsSync(powershellPath)) throw new Error('Không tìm thấy Windows PowerShell an toàn để cài update.');
  const child = spawn(powershellPath, [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', scriptPath,
    '-ProcessId', String(process.pid),
    '-ZipPath', download.zipPath,
    '-TargetDir', targetDir,
    '-ExeName', path.basename(process.execPath),
    '-PortableDirName', PORTABLE_DIR_NAME,
    '-StageDir', stageDir,
    '-BackupDir', backupDir,
    '-HealthPath', healthPath
  ], {
    cwd: download.updateDir,
    detached: true,
    windowsHide: true,
    shell: false,
    stdio: 'ignore'
  });
  await new Promise((resolve, reject) => {
    child.once('spawn', resolve);
    child.once('error', reject);
  });
  child.unref();
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1120, height: 700, minWidth: 780, minHeight: 480,
    transparent: true, frame: false, alwaysOnTop: true, hasShadow: true,
    backgroundColor: '#00000000', title: 'SA Cook Assistant — Windows Preview 5.47', autoHideMenuBar: true,
    skipTaskbar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true, webSecurity: true, allowRunningInsecureContent: false, backgroundThrottling: false }
  });
  mainWindow.setAlwaysOnTop(true, 'floating');
  mainWindow.setContentProtection(true);
  mainWindow.removeMenu();
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  mainWindow.webContents.on('will-navigate', event => event.preventDefault());
  mainWindow.on('restore', () => mainWindow && !mainWindow.isDestroyed() && mainWindow.setSkipTaskbar(true));
  mainWindow.on('show', () => mainWindow && !mainWindow.isDestroyed() && mainWindow.setSkipTaskbar(true));
  mainWindow.on('closed', () => { mainWindow = null; });
  mainWindow.loadFile('index.html');
}

function configureMediaPermissions() {
  const allowed = new Set(['media', 'display-capture']);
  session.defaultSession.setPermissionCheckHandler((contents, permission) => allowed.has(permission) && isTrustedWebContents(contents));
  session.defaultSession.setPermissionRequestHandler((contents, permission, callback) => callback(allowed.has(permission) && isTrustedWebContents(contents)));
  session.defaultSession.setDisplayMediaRequestHandler(async (request, callback) => {
    if (!isTrustedFrame(request && request.frame)) return callback({});
    try {
      const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 }, fetchWindowIcons: false });
      const screen = sources.find(source => source.id.startsWith('screen:')) || sources[0];
      if (!screen) return callback({});
      const selection = { video: screen };
      if (process.platform === 'win32') selection.audio = 'loopback';
      callback(selection);
    } catch (_) { callback({}); }
  });
}

app.on('second-instance', () => {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  if (!mainWindow.isVisible()) mainWindow.show();
  mainWindow.setSkipTaskbar(true);
  mainWindow.focus();
});

if (hasSingleInstanceLock) app.whenReady().then(() => {
  ensurePortableMarker();
  const updateHealthPath = requestedUpdateHealthPath();
  configureMediaPermissions();
  createWindow();
  if (updateHealthPath && mainWindow) {
    mainWindow.webContents.once('did-finish-load', () => {
      fs.promises.writeFile(updateHealthPath, 'ready', { encoding: 'utf8', mode: 0o600 }).catch(() => {});
    });
  }
  app.on('activate', () => { if (!BrowserWindow.getAllWindows().length) createWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });

ipcMain.handle('key:set', (event, key) => {
  if (!isTrustedIpc(event)) throw new Error('Yêu cầu lưu key không hợp lệ.');
  if (!safeStorage.isEncryptionAvailable()) throw new Error('Windows Secure Storage chưa sẵn sàng; key không được lưu để tránh ghi dữ liệu không mã hóa.');
  const clean = String(key || '').trim();
  if (!clean) {
    try { fs.unlinkSync(keyPath()); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    return '';
  }
  if (!clean.startsWith('sk-') || clean.length > 4096) throw new Error('OpenAI API key không hợp lệ.');
  fs.writeFileSync(keyPath(), safeStorage.encryptString(clean).toString('base64'), { encoding: 'utf8', mode: 0o600 });
  return 'ok';
});

ipcMain.handle('key:get', event => {
  if (!isTrustedIpc(event) || !safeStorage.isEncryptionAvailable()) return '';
  try { return safeStorage.decryptString(Buffer.from(fs.readFileSync(keyPath(), 'utf8'), 'base64')); }
  catch (_) { return ''; }
});

ipcMain.handle('resources:get', event => {
  if (!isTrustedIpc(event)) throw new Error('Yêu cầu đọc dữ liệu không hợp lệ.');
  try {
    return {
      localQA: JSON.parse(readResource('sa-cook-qa.json', '[]')),
      internetQA: JSON.parse(readResource('internet-qa.json', '[]')),
      hints: readResource('speech-hints.txt'),
      answerPolicy: readResource('answer-policy.txt'),
      knowledge: readResource('sa-cook-knowledge.txt'),
      handbook: readResource('sa-cook-handbook.txt')
    };
  } catch (_) { throw new Error('Không đọc được dữ liệu SA Cook.'); }
});

ipcMain.handle('clipboard:write', (event, value) => {
  if (!isTrustedIpc(event)) throw new Error('Yêu cầu sao chép không hợp lệ.');
  clipboard.writeText(String(value || '').slice(0, 200000));
  return 'ok';
});

ipcMain.handle('window:minimize', event => {
  if (!isTrustedIpc(event) || !mainWindow || mainWindow.isDestroyed()) throw new Error('Yêu cầu thu nhỏ cửa sổ không hợp lệ.');
  // Make the icon available only while minimized so the user can restore the
  // window. It is hidden again as soon as the app is open.
  mainWindow.setSkipTaskbar(false);
  mainWindow.minimize();
  return 'ok';
});

ipcMain.handle('window:close', event => {
  if (!isTrustedIpc(event) || !mainWindow || mainWindow.isDestroyed()) throw new Error('Yêu cầu đóng cửa sổ không hợp lệ.');
  mainWindow.close();
  return 'ok';
});

ipcMain.handle('update:run', async event => {
  if (!isTrustedIpc(event)) throw new Error('Yêu cầu cập nhật không hợp lệ.');
  if (!app.isPackaged || process.platform !== 'win32') throw new Error('Update trực tiếp chỉ hoạt động trong bản Windows đã đóng gói.');
  if (!isPortableRoot(path.dirname(process.execPath), true)) throw new Error(`Hãy giữ ứng dụng trong thư mục “${PORTABLE_DIR_NAME}” rồi thử Update lại.`);
  if (updateInProgress) throw new Error('Bản cập nhật đang được xử lý.');
  updateInProgress = true;
  const sender = event.sender;
  try {
    sendUpdateStatus(sender, { phase: 'checking' });
    const candidate = await findWindowsUpdate();
    if (!candidate) return { status: 'up-to-date', version: app.getVersion() };
    sendUpdateStatus(sender, { phase: 'preparing', version: candidate.release.tag_name });
    const download = await downloadVerifiedUpdate(sender, candidate.release, candidate.asset);
    sendUpdateStatus(sender, { phase: 'installing', version: candidate.release.tag_name });
    try {
      await launchPortableUpdater(download);
    } catch (error) {
      await fs.promises.rm(download.updateDir, { recursive: true, force: true }).catch(() => {});
      throw error;
    }
    setTimeout(() => app.quit(), 500);
    return { status: 'installing', version: candidate.release.tag_name };
  } catch (error) {
    sendUpdateStatus(sender, { phase: 'error', message: String(error && error.message || error) });
    throw error;
  } finally {
    updateInProgress = false;
  }
});
