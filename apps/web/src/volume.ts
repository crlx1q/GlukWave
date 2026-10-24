const key = 'gw-device-volume';
/** Wheel ticks use a five-percent lattice even after a fine slider adjustment. */
export function wheelVolume(value:number,deltaY:number):number {
  const current=Math.max(0,Math.min(1,value));
  if(!deltaY||!Number.isFinite(deltaY))return current;
  const ticks=current*20;
  return Math.max(0,Math.min(20,deltaY<0?Math.floor(ticks+1e-7)+1:Math.ceil(ticks-1e-7)-1))/20;
}
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
