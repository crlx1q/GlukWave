const key = 'gw-device-volume';
export function restoredVolume(): number {
  try {
    const raw = localStorage.getItem(key);
    if (raw === null || !raw.trim()) return .8;
    const value = Number(raw);
    return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : .8;
  } catch { return .8; }
}
export function saveVolume(value: number): void {
  if (!Number.isFinite(value)) return;
  try { localStorage.setItem(key, String(Math.max(0, Math.min(1, value)))); }
  catch { /* Playback remains available when storage is restricted. */ }
}
