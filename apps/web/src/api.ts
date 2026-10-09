import { t, getLanguage } from './locale';
import {reportError} from './diagnostics';
import {deviceId,surfaceId,browserDeviceName} from './device-identity';
export class ApiError extends Error { constructor(public code: string, message: string, public details?: unknown) { super(message); } }
export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set('Accept-Language',getLanguage());
  headers.set('X-GlukWave-Device',deviceId);
  headers.set('X-GlukWave-Surface',surfaceId);
  headers.set('X-GlukWave-Kind','web');
  headers.set('X-GlukWave-Device-Name',browserDeviceName);
  if (init.body && !(init.body instanceof FormData)) headers.set('Content-Type','application/json');
  let response: Response;
  try { response = await fetch(`/api${path}`, { ...init, headers, credentials: 'include' }); }
  catch (error) { if ((error as Error).name === 'AbortError') throw error;reportError(error,'network',{code:'FETCH_FAILED'}); throw new ApiError('NETWORK',t('copy.166')); }
  const body = await response.json().catch(() => ({}));
  if (!response.ok){const error=new ApiError(body.error?.code || `HTTP_${response.status}`, body.error?.message || t('copy.167'), body.error?.details);if(response.status>=500)reportError(error,'network',{code:error.code,status:response.status});throw error;}
  return body as T;
}
export const post = <T>(path: string, data: unknown = {}) => api<T>(path,{method:'POST',body:JSON.stringify(data)});
export const patch = <T>(path: string, data: unknown = {}) => api<T>(path,{method:'PATCH',body:JSON.stringify(data)});
export function errorText(error: unknown) { if(error instanceof ApiError){const labels:Record<string,string>={PLAN_LIMIT:'parity.planLimit',REGISTRATION_CLOSED:'parity.registrationClosed',FRIEND_REQUESTS_DISABLED:'parity.friendRequestsDisabled',JAM_FULL:'parity.jamUnavailable',JAM_NOT_FOUND:'parity.jamUnavailable',PRIVATE_TRACK:'parity.publicAudioOnly',PRIVATE_TRACKS:'parity.publicAudioOnly',PLAYLIST_PRIVATE_TRACKS:'parity.publicAudioOnly',OWNER_ONLY:'parity.ownerOnly'};if(labels[error.code])return t(labels[error.code]);}const message=error instanceof Error?error.message:t('copy.168');return /(?:API|OAuth|RPC|Turnstile|VAPID|\.env|SMTP|credentials|provider.*key|ключ.*(?:сервис|сервер)|настро.{0,25}(?:сервер|разработ))/i.test(message)?t('copy.169'):message; }

