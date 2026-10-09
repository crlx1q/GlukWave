import { useEffect, useRef, useState } from 'react';
import { ArrowUpRight, Check, Headphones, Link, LockKeyhole, Music2, RefreshCw, Unlink, Waves } from 'lucide-react';
import { api, errorText, patch, post } from './api';
import { t, useLocale } from './locale';
import { usePlayer } from './player';
import { useStore } from './store';
import { time, type Room } from './types';
import { Loading, Modal, Toggle } from './ui';
import { DiscordStatusController, discordInvitation, restoredDiscordInvitation, discordOAuthUrl, discordPosition, type DiscordStatus } from './discord-model';
import './discord.css';

function DiscordMark() {
  return <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M19.7 5.1a18 18 0 0 0-4.4-1.4l-.6 1.2a16 16 0 0 0-5.4 0l-.6-1.2a18 18 0 0 0-4.4 1.4C1.6 9.1.9 13 1.3 16.9a18 18 0 0 0 5.4 2.7l1.1-1.8-1.6-.8.4-.3a12.4 12.4 0 0 0 10.8 0l.4.3-1.6.8 1.1 1.8a18 18 0 0 0 5.4-2.7c.5-4.5-.7-8.4-3-11.8ZM8.3 14.5c-1.1 0-1.9-1-1.9-2.2s.8-2.2 1.9-2.2 1.9 1 1.9 2.2-.8 2.2-1.9 2.2Zm7.4 0c-1.1 0-1.9-1-1.9-2.2s.8-2.2 1.9-2.2 1.9 1 1.9 2.2-.8 2.2-1.9 2.2Z"/></svg>;
}

export function DiscordConnection() {
  useLocale();
  const store = useStore(), player = usePlayer();
  const [data, setData] = useState<DiscordStatus | null>(null), [error, setError] = useState(''), [pending, setPending] = useState(false), [unlinkOpen, setUnlinkOpen] = useState(false), [avatarBroken, setAvatarBroken] = useState(false);
  const refreshRef = useRef(() => {}), accountRef = useRef(store.user?.id); accountRef.current = store.user?.id;
  useEffect(() => {
    setData(null); setError(''); setPending(false); setUnlinkOpen(false);
    if (!store.user) return;
    const controller = new DiscordStatusController(signal => api<DiscordStatus>('/discord', { signal }), status => { setData(status); setError(''); }, reason => setError(errorText(reason)));
    const refresh = () => controller.refresh(), visible = () => { if (!document.hidden) refresh(); };
    refreshRef.current = refresh; refresh();
    player.socket?.on('discord:changed', refresh); player.socket?.on('integrations:changed', refresh); player.socket?.on('connect', refresh);
    window.addEventListener('focus', visible); window.addEventListener('online', visible); document.addEventListener('visibilitychange', visible);
    const timer = setInterval(visible, 30000);
    return () => { controller.stop(); refreshRef.current = () => {}; clearInterval(timer); player.socket?.off('discord:changed', refresh); player.socket?.off('integrations:changed', refresh); player.socket?.off('connect', refresh); window.removeEventListener('focus', visible); window.removeEventListener('online', visible); document.removeEventListener('visibilitychange', visible); };
  }, [store.user?.id, player.socket]);
  useEffect(() => setAvatarBroken(false), [data?.identity?.avatarUrl]);
  const mutate = async (operation: () => Promise<unknown>) => {
    const account = store.user?.id; setPending(true); setError('');
    try { await operation(); if (account === accountRef.current) refreshRef.current(); }
    catch (reason) { if (account === accountRef.current) setError(errorText(reason)); }
    finally { if (account === accountRef.current) setPending(false); }
  };
  const connect = () => {
    if (!store.requireAuth()) return;
    void mutate(async () => { const account = accountRef.current, result = await post<{ url: string }>('/integrations/discord/connect'); if (account && account === accountRef.current) location.assign(discordOAuthUrl(result.url)); });
  };
  const update = (value: { enabled?: boolean; allowJoin?: boolean }) => void mutate(async () => { const account = accountRef.current, status = await patch<DiscordStatus>('/discord', value); if (account === accountRef.current) setData(status); });
  const unavailable = data && ['unavailable', 'unsupported'].includes(data.status), eligible = Boolean(data?.eligible), canEdit = eligible && data?.connected && !data.needsReconnect && !unavailable;
  return <section className="wave-discord" aria-labelledby="discord-heading">
    <header className="wave-discord-heading"><span className="wave-discord-mark"><DiscordMark/></span><div><p className="eyebrow">Discord</p><h2 id="discord-heading">{t('discord.title')}</h2><p>{t('discord.caption')}</p></div>{eligible && <span className={`plan-badge ${store.user?.plan}`}>{store.user?.plan === 'beta' ? 'BETA' : 'UNBOUND'}</span>}</header>
    {!store.user ? <div className="wave-discord-empty"><Headphones size={27}/><h3>{t('discord.signInTitle')}</h3><p>{t('discord.signInCaption')}</p><button className="primary-button" onClick={() => store.setAuthOpen(true)}>{t('copy.044')}<ArrowUpRight size={16}/></button></div> : !data && !error ? <div className="wave-discord-loading"><Loading label={t('discord.loading')}/></div> : <>
      {error && <div className="wave-discord-error" role="alert"><p>{error}</p><button className="subtle-button" disabled={pending} onClick={() => refreshRef.current()}><RefreshCw size={15}/>{t('copy.129')}</button></div>}
      {data && !eligible ? <div className="wave-discord-empty locked"><LockKeyhole size={27}/><h3>{t('discord.lockedTitle')}</h3><p>{t('discord.lockedCaption')}</p><button className="primary-button" onClick={() => store.navigate('profile')}>{t('discord.membership')}<ArrowUpRight size={16}/></button>{data.connected && <button className="text-button" disabled={pending} onClick={() => setUnlinkOpen(true)}><Unlink size={15}/>{t('discord.unlink')}</button>}</div> : data && <div className="wave-discord-layout">
        <div className="wave-discord-controls">
          <div className="wave-discord-identity">
            <span className="wave-discord-avatar">{data.identity?.avatarUrl && !avatarBroken ? <img src={data.identity.avatarUrl} alt="" referrerPolicy="no-referrer" onError={() => setAvatarBroken(true)}/> : <DiscordMark/>}</span>
            <div><b>{data.identity?.displayName || t('discord.notConnected')}</b><small>{data.identity ? `@${data.identity.username}` : t('discord.connectCaption')}</small></div>
            {data.connected && !data.needsReconnect && <Check className="wave-discord-check" size={17}/ >}
          </div>
          <div className="wave-discord-account-actions"><button className={data.connected && !data.needsReconnect ? 'subtle-button' : 'primary-button'} disabled={pending || !data.configured || unavailable || !eligible} onClick={connect}><Link size={16}/>{pending ? t('discord.working') : t(data.needsReconnect ? 'discord.reconnect' : data.connected ? 'discord.relink' : 'discord.connect')}<ArrowUpRight size={15}/></button>{data.connected && <button className="text-button" disabled={pending} onClick={() => setUnlinkOpen(true)}><Unlink size={15}/>{t('discord.unlink')}</button>}</div>
          <p className={`wave-discord-status state-${data.status}`} role="status"><i/><span>{t(`discord.status.${data.status}`)}</span></p>
          <Toggle checked={data.enabled} disabled={pending || !canEdit} onChange={enabled => update({ enabled })} label={t('discord.presence')} description={t('discord.presenceCaption')}/>
          <Toggle checked={data.allowJoin} disabled={pending || !canEdit} onChange={allowJoin => update({ allowJoin })} label={t('discord.allowJoin')} description={t('discord.allowJoinCaption')}/>
          <p className="wave-discord-device">{data.device ? <><Music2 size={14}/>{t('discord.device', { device: data.device.name })}</> : <><Waves size={14}/>{t('discord.anyDevice')}</>}</p>
        </div>
        <DiscordPreview data={data}/>
      </div>}
    </>}
    {unlinkOpen && <Modal title={t('discord.unlinkTitle')} onClose={() => setUnlinkOpen(false)}><p className="intro">{t('discord.unlinkCaption')}</p><div className="wave-discord-confirm"><button className="subtle-button" disabled={pending} onClick={() => setUnlinkOpen(false)}>{t('copy.736')}</button><button className="danger-button" disabled={pending} onClick={() => void mutate(async () => { await api('/integrations/discord', { method: 'DELETE' }); setUnlinkOpen(false); })}><Unlink size={16}/>{t('discord.unlink')}</button></div></Modal>}
  </section>;
}

function DiscordPreview({ data }: { data: DiscordStatus }) {
  const [elapsed, setElapsed] = useState(0), [coverBroken, setCoverBroken] = useState(false);
  const activity = data.activity;
  useEffect(() => { setElapsed(0); if (!activity?.playing) return; const start = performance.now(), tick = () => { if (!document.hidden) setElapsed((performance.now() - start) / 1000); }; const timer = setInterval(tick, 1000); document.addEventListener('visibilitychange', tick); return () => { clearInterval(timer); document.removeEventListener('visibilitychange', tick); }; }, [activity]);
  useEffect(() => setCoverBroken(false), [activity?.cover]);
  const position = activity ? discordPosition(activity, elapsed) : 0;
  return <aside className="wave-discord-preview"><header><span>{t('discord.preview')}</span><span className="wave-discord-preview-brand">∿ Gluk Wave</span></header><article className={`wave-discord-activity ${activity ? '' : 'empty'}`}>
    <p className="wave-discord-listening"><span className={`wave-discord-bars ${activity?.playing ? 'playing' : ''}`} aria-hidden="true"><i/><i/><i/></span>{t(activity && !activity.playing ? 'discord.paused' : 'discord.listening')}</p>
    <div className="wave-discord-song"><div className="wave-discord-cover">{activity?.cover && !coverBroken ? <img src={activity.cover} alt={activity.album || activity.title} onError={() => setCoverBroken(true)}/> : <Waves size={30}/ >}<span className="wave-discord-logo">∿</span></div><div className="wave-discord-song-info"><b>{activity?.title || t('discord.emptyTitle')}</b><span>{activity?.artist || t('discord.emptyCaption')}</span>{activity?.album && <small>{activity.album}</small>}<div className="wave-discord-progress"><time>{time(position)}</time><div role="progressbar" aria-label={t('discord.progress')} aria-valuemin={0} aria-valuemax={activity?.duration ? activity.duration : undefined} aria-valuenow={activity?.duration ? position : undefined}><i style={{ width: `${activity?.duration ? Math.min(100, position / activity.duration * 100) : 0}%` }}/></div><time>{time(activity?.duration || 0)}</time></div></div></div>
    <div className="wave-discord-preview-actions">{activity?.joinUrl && data.allowJoin ? <a href={activity.joinUrl}><Headphones size={14}/>{t('discord.listenTogether')}</a> : <button disabled title={t(data.allowJoin ? 'discord.joinUnavailable' : 'discord.joinDisabled')}><Headphones size={14}/>{t('discord.listenTogether')}</button>}{activity?.trackUrl ? <a href={activity.trackUrl}>{t('discord.openWave')}<ArrowUpRight size={14}/></a> : <button disabled>{t('discord.openWave')}<ArrowUpRight size={14}/></button>}</div>
  </article><p className="wave-discord-preview-note">{t('discord.previewNote')}</p></aside>;
}

export function DiscordInvitationHandler() {
  useLocale(); const store = useStore(), player = usePlayer();
  const [invite, setInvite] = useState(() => { try { return restoredDiscordInvitation(location.search, sessionStorage.getItem('gw-discord-invitation')); } catch { return discordInvitation(location.search); } }), [pending, setPending] = useState(false), [error, setError] = useState('');
  const accountRef = useRef(store.user?.id); accountRef.current = store.user?.id;
  const dismiss = () => { try { sessionStorage.removeItem('gw-discord-invitation'); } catch {} const url = new URL(location.href); url.searchParams.delete('listen'); url.searchParams.delete('jam'); history.replaceState(null, '', url); setInvite(null); };
  const accept = () => {
    if (!invite) return;
    if (!store.user) { try { sessionStorage.setItem('gw-discord-invitation', JSON.stringify({ ...invite, expiresAt: Date.now() + 30 * 60 * 1000 })); } catch {} store.requireAuth(); return; }
    const account = store.user?.id; setPending(true); setError('');
    void post<{ room: Room }>(invite.kind === 'listen' ? `/discord/listen/${encodeURIComponent(invite.id)}` : `/jams/${encodeURIComponent(invite.id)}/join`).then(async result => { if (account !== accountRef.current) return; await player.joinRoom(result.room); dismiss(); store.navigate('rooms'); }).catch(reason => setError(errorText(reason))).finally(() => setPending(false));
  };
  if (!invite || store.loading || store.authOpen) return null;
  return <Modal title={t('discord.listenTogether')} onClose={dismiss}><div className="wave-discord-invitation"><span className="wave-discord-mark"><Headphones size={27}/></span><h3>{t('discord.inviteTitle')}</h3><p>{t('discord.inviteCaption')}</p>{error && <p className="error-banner" role="alert">{error}</p>}<button className="primary-button" disabled={pending || Boolean(store.user && player.connectionStatus !== 'online')} onClick={accept}><Headphones size={17}/>{pending ? t('discord.working') : !store.user ? t('discord.signInJoin') : t('discord.join')}</button><button className="text-button" onClick={dismiss}>{t('copy.736')}</button></div></Modal>;
}
