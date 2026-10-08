import { t, countLabel, number, type LanguageChoice, type LocaleResponse } from './locale';
export type Source = 'local' | 'youtube' | 'spotify' | 'soundcloud' | 'yandex';
export type User = { id: string; email: string; username: string; displayName: string; avatarUrl?: string; bannerUrl?: string; bio: string; tags: string[]; plan: 'free'|'beta'|'unbound'; role: 'user'|'admin'; emailVerified: boolean; createdAt: string };
export type Playback = { kind: Source|'audio'; url?: string; embedUrl?: string; offline: boolean };
export type Track = { id: string; title: string; artist: string; album: string; artwork: string; duration: number; source: Source; sourceId: string; sourceUrl: string; playback: Playback; createdAt: string; liked?: boolean };
export type Playlist = { id: string; name: string; description: string; artwork: string; trackIds: string[]; ownerId: string; createdAt: string; updatedAt: string };
export type HistoryEntry = { trackId: string; position?: number; playedAt?: string; createdAt?: string };
export type Library = { tracks: Track[]; likedIds: string[]; playlists: Playlist[]; history: HistoryEntry[] };
export type PaletteColors = { bg:string; surface:string; ink:string; accent:string };
export type PaletteMode = 'light'|'dark'|'amoled';
export type Appearance = { light:PaletteColors; dark:PaletteColors; amoled:PaletteColors; radius:number; speed:number; compact:boolean; blur:boolean; waveStyle:'silk'|'particles'|'bloom'; cover3d:boolean; coverKind:'vinyl'|'cd' };
export type AppearancePatch = Partial<Omit<Appearance,PaletteMode>> & { light?:Partial<PaletteColors>; dark?:Partial<PaletteColors>; amoled?:Partial<PaletteColors> };
export type Equalizer = {enabled:boolean;preamp:number;bands:number[]};
export type Settings = { language:LanguageChoice; autoCache: boolean; cacheLimitMB: number; lyrics: boolean; discordPresence: boolean; notifications: boolean; theme:PaletteMode|'system'; reducedMotion:boolean; appearance:Appearance; equalizer:Equalizer; playbackRate:number };
export type SettingsPatch = Omit<Partial<Settings>,'appearance'|'equalizer'> & { appearance?:AppearancePatch; equalizer?:Partial<Equalizer> };
export type Provider = { id: string; name: string; configured: boolean; searchAvailable?:boolean; capabilities: string[]; reason?: string };
export type Config = { localization?:LocaleResponse; appName: string; appUrl: string; environment: string; providers: Provider[]; auth: { google: boolean; turnstileSiteKey: string; requireEmailVerification?:boolean }; push: { enabled: boolean; vapidPublicKey?: string; fcmEnabled?:boolean }; discord?:{clientId:string;bridgeOrigin:string}; billing?:{configured:boolean;provider:string}; plans: { id?: string; name?: string; price?: number }[] };
export type PlayerState = { trackId: string|null; position: number; playing: boolean; volume: number; queue: string[]; updatedAt: number; revision: number };
export type RoomMember = { userId: string; displayName: string; avatarUrl?: string; canControl: boolean; role: string };
export type Room = { id: string; name: string; ownerId: string; members: RoomMember[]; state: PlayerState; createdAt: string; inviteCode: string };
export type Message = { id: string; userId: string; displayName: string; text: string; createdAt: string };
export type Comment = Message & { avatarUrl?: string; position: number };
export type Device = { id: string; name: string; kind: string; online: boolean; lastSeen: string; state: PlayerState };
export type Connection = { provider: string; connected: boolean; displayName?: string; configured: boolean; reason?: string };
export const sourceNames: Record<Source, string> = { get local(){return t('copy.191')}, youtube: 'YouTube Music', spotify: 'Spotify', soundcloud: 'SoundCloud', get yandex(){return t('copy.187')} };
export const defaultAppearance:Appearance={light:{bg:'#efede3',surface:'#f8f7f1',ink:'#302f2c',accent:'#a08369'},dark:{bg:'#141517',surface:'#202225',ink:'#eeeae3',accent:'#b1a2de'},amoled:{bg:'#000000',surface:'#0b0b0b',ink:'#f4f1f7',accent:'#b1a2de'},radius:24,speed:1,compact:false,blur:true,waveStyle:'silk',cover3d:true,coverKind:'vinyl'};
export const defaultEqualizer:Equalizer={enabled:false,preamp:0,bands:Array(10).fill(0)};
export const defaultSettings:Settings={language:'auto',autoCache:true,cacheLimitMB:1024,lyrics:true,discordPresence:true,notifications:false,theme:'light',reducedMotion:false,appearance:defaultAppearance,equalizer:defaultEqualizer,playbackRate:1};
export function time(seconds = 0) { const value = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0)), minutes=Math.floor(value/60), tail=String(value%60).padStart(2,'0'); return value<3600?`${minutes}:${tail}`:`${Math.floor(value/3600)}:${String(minutes%60).padStart(2,'0')}:${tail}`; }
export function bytes(value: number) { return value >= 1024*1024 ? t('template.002', {v0: number(value/1024/1024,{maximumFractionDigits:1})}) : t('template.018', {v0: number(Math.round(value/1024))}); }


export function plural(count:number,one:string,few:string,many:string){const value=Math.abs(count)%100,unit=value%10;return value>10&&value<20?many:unit===1?one:unit>=2&&unit<=4?few:many;}
export function trackCount(count:number){return countLabel(count,'tracks');}
