const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('saCook', Object.freeze({
  getKey: () => ipcRenderer.invoke('key:get'),
  setKey: key => ipcRenderer.invoke('key:set', String(key || '').slice(0, 4096)),
  loadResources: () => ipcRenderer.invoke('resources:get'),
  getProfile: () => ipcRenderer.invoke('profile:get'),
  setProfile: profile => ipcRenderer.invoke('profile:set', profile),
  copyText: text => ipcRenderer.invoke('clipboard:write', String(text || '').slice(0, 200000)),
  installUpdate: () => ipcRenderer.invoke('update:run'),
  minimizeWindow: () => ipcRenderer.invoke('window:minimize'),
  closeWindow: () => ipcRenderer.invoke('window:close')
}));

window.addEventListener('DOMContentLoaded', () => {
  const button = document.getElementById('update');
  if (!button) return;
  const reset = (label = 'Update', delay = 2500) => setTimeout(() => {
    button.textContent = label;
    button.disabled = false;
  }, delay);
  ipcRenderer.on('update:status', (_event, detail) => {
    if (!detail || typeof detail !== 'object') return;
    if (detail.phase === 'checking') button.textContent = 'Đang kiểm tra…';
    if (detail.phase === 'preparing') button.textContent = 'Đang chuẩn bị…';
    if (detail.phase === 'download') button.textContent = `Đang tải ${Math.max(0, Math.min(99, Number(detail.percent) || 0))}%`;
    if (detail.phase === 'installing') button.textContent = 'Đang cài…';
    if (detail.phase === 'error') button.title = String(detail.message || 'Không thể cập nhật.').slice(0, 300);
  });
  button.addEventListener('click', async () => {
    if (button.disabled) return;
    button.disabled = true;
    button.title = '';
    button.textContent = 'Đang kiểm tra…';
    try {
      const result = await ipcRenderer.invoke('update:run');
      if (result && result.status === 'up-to-date') {
        button.textContent = 'Đã mới nhất';
        reset();
      } else {
        button.textContent = 'Đang mở lại…';
      }
    } catch (error) {
      button.textContent = 'Update lỗi';
      button.title = String(error && error.message || error).replace(/^Error invoking remote method '[^']+':\s*/, '').slice(0, 300);
      reset('Thử lại Update', 3500);
    }
  });
});
