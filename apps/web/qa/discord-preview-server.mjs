// Isolated UI fixtures, never a production provider or proof of genuine Discord publication.
import { createServer } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
let scenario = 'active', revision = 1, settings = { language: 'en', theme: 'light', autoCache: false, fontScale: 1 };
let preferences = { enabled: true, allowJoin: false }, mutations = [];
const user = { id: 'discord-ui-qa', email: 'discord-ui@example.test', username: 'wave_verified', displayName: 'Wave verification', bio: '', tags: [], plan: 'beta', role: 'user', emailVerified: true, createdAt: '2026-10-09T00:00:00.000Z' };
const status = () => ({ eligible: scenario !== 'free', configured: scenario !== 'unavailable', connected: !['disconnected', 'unavailable'].includes(scenario), needsReconnect: scenario === 'reconnect_required', ...preferences, status: scenario === 'free' ? 'locked' : scenario === 'active' && !preferences.enabled ? 'disabled' : scenario, lastPublishedAt: scenario === 'active' ? new Date().toISOString() : null, lastError: null, identity: ['disconnected', 'unavailable', 'free'].includes(scenario) ? null : { id: '1001', username: 'wave_listener', displayName: 'Your Wave friend', avatarUrl: '/assets/asset-1.jpg' }, device: scenario === 'active' ? { name: 'Gluk Wave on Windows', kind: 'windows' } : null, activity: scenario === 'active' ? { trackId: 'verified-music', title: 'A moment on your wavelength', artist: 'Gluk Wave verification', album: 'UI verification fixture', cover: '/assets/asset-1.jpg', position: 25, duration: 178, playing: true, trackUrl: '/app/?track=verified-music', joinUrl: preferences.allowJoin ? '/app/?listen=discord-ui-qa' : null } : null });
const fixture = {
  name: 'discord-ui-fixtures',
  configureServer(server) {
    server.middlewares.use(async (req, res, next) => {
      if (!req.url.startsWith('/api/')) return next();
      let raw = ''; for await (const chunk of req) raw += chunk;
      let body = {}; try { body = JSON.parse(raw || '{}'); } catch {}
      const route = req.url.split('?')[0], method = req.method;
      let result = {};
      if (route === '/api/qa/discord') { scenario = body.scenario || scenario; preferences = { ...preferences, ...body.preferences }; result = { scenario, mutations }; }
      else if (route === '/api/locale') result = { language: 'en', country: null, source: 'default' };
      else if (route === '/api/config') result = { appName: 'Gluk Wave', appUrl: 'http://127.0.0.1:5183', environment: 'test', providers: [], auth: { google: false, turnstileSiteKey: '' }, push: { enabled: false }, plans: [] };
      else if (route === '/api/auth/me') result = { user: scenario === 'signedout' ? null : { ...user, plan: scenario === 'free' ? 'free' : 'beta' } };
      else if (route === '/api/settings') { if (method === 'PATCH') { settings = { ...settings, ...body }; revision++; } result = { settings: { ...settings, revision }, revision }; }
      else if (route === '/api/library') result = { tracks: [], likedIds: [], playlists: [], history: [] };
      else if (route === '/api/integrations') result = { connections: [] };
      else if (route === '/api/discord') {
        if (scenario === 'error') { res.statusCode = 503; result = { error: { code: 'DISCORD_UNAVAILABLE', message: 'This connection is temporarily unavailable.' } }; }
        else { if (method === 'PATCH') { preferences = { ...preferences, ...body }; mutations.push(body); } result = status(); }
      }
      else if (route === '/api/integrations/discord' && method === 'DELETE') { scenario = 'disconnected'; result = { ok: true }; }
      else if (route === '/api/integrations/discord/connect') result = { url: 'https://discord.com/oauth2/authorize?client_id=fixture-only&scope=openid' };
      else if (route === '/api/devices') result = { devices: [] };
      else if (route.startsWith('/api/discord/listen/') || route.startsWith('/api/jams/')) { res.statusCode = 403; result = { error: { code: 'FRIEND_REQUIRED', message: 'Only Wave friends can join this jam.' } }; }
      else if (route === '/api/client-errors') result = { ok: true };
      res.setHeader('Content-Type', 'application/json'); res.setHeader('Cache-Control', 'no-store'); res.end(JSON.stringify(result));
    });
  }
};
const server = await createServer({ root: path.resolve('apps/web'), configFile: false, plugins: [react(), fixture], server: { host: '127.0.0.1', port: 5183, strictPort: true } });
await server.listen(); console.log('Isolated Discord UI fixtures: http://127.0.0.1:5183');
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await server.close(); process.exit(); });
