export type DiscordActivity = {
  trackId: string; title: string; artist: string; album: string; cover: string;
  position: number; duration: number; playing: boolean; trackUrl: string; joinUrl: string | null;
};
export type DiscordStatus = {
  eligible: boolean; configured: boolean; connected: boolean; needsReconnect: boolean;
  identity: null | { id: string; username: string; displayName: string; avatarUrl: string };
  enabled: boolean; allowJoin: boolean;
  status: 'unavailable' | 'disconnected' | 'reconnect_required' | 'disabled' | 'idle' | 'publishing' | 'active' | 'retrying' | 'unsupported' | 'locked';
  lastPublishedAt: string | null; lastError: string | null;
  device: null | { name: string; kind: string }; activity: DiscordActivity | null;
};

export function discordPosition(activity: DiscordActivity, elapsed: number): number {
  const duration = Number.isFinite(activity.duration) ? Math.max(0, activity.duration) : 0;
  const initial = Number.isFinite(activity.position) ? Math.max(0, activity.position) : 0;
  const position = initial + (activity.playing ? Math.max(0, elapsed) : 0);
  return duration ? Math.min(duration, position) : position;
}

export function discordOAuthUrl(value: string): string {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.hostname !== 'discord.com' || url.username || url.password || !['/oauth2/authorize', '/api/oauth2/authorize'].includes(url.pathname)) throw new Error('Invalid Discord authorization URL');
  return url.href;
}

export type DiscordInvitation = { kind: 'listen' | 'jam'; id: string };
export function discordInvitation(search: string): DiscordInvitation | null {
  const params = new URLSearchParams(search);
  for (const kind of ['listen', 'jam'] as const) {
    const id = params.get(kind);
    if (id && /^[a-zA-Z0-9_-]{1,128}$/.test(id)) return { kind, id };
  }
  return null;
}

export function restoredDiscordInvitation(search: string, saved: string | null, now = Date.now()): DiscordInvitation | null {
  const direct = discordInvitation(search); if (direct) return direct;
  try {
    const value = JSON.parse(saved || 'null');
    if (!value || !['listen', 'jam'].includes(value.kind) || typeof value.id !== 'string' || !Number.isFinite(value.expiresAt) || value.expiresAt <= now || value.expiresAt > now + 30 * 60 * 1000) return null;
    return discordInvitation(`?${value.kind}=${encodeURIComponent(value.id)}`);
  } catch { return null; }
}

// Each mounted account panel owns one request lane. Old account results never cross its lifetime.
export class DiscordStatusController {
  private active = true;
  private request: AbortController | null = null;
  private pending = false;
  private read: (signal: AbortSignal) => Promise<DiscordStatus>;
  private changed: (status: DiscordStatus) => void;
  private failed: (reason: unknown) => void;
  constructor(read: (signal: AbortSignal) => Promise<DiscordStatus>, changed: (status: DiscordStatus) => void, failed: (reason: unknown) => void) { this.read = read; this.changed = changed; this.failed = failed; }
  refresh(): void {
    if (!this.active) return;
    if (this.request) { this.pending = true; return; }
    const request = new AbortController(); this.request = request;
    void this.read(request.signal).then(status => { if (this.active && !request.signal.aborted) this.changed(status); }).catch(reason => { if (this.active && !request.signal.aborted) this.failed(reason); }).finally(() => {
      if (this.request === request) this.request = null;
      if (this.active && this.pending) { this.pending = false; this.refresh(); }
    });
  }
  stop(): void { this.active = false; this.pending = false; this.request?.abort(); this.request = null; }
}
