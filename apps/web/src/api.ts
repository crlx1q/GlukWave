import { t, getLanguage } from './locale';
import {reportError} from './diagnostics';
export class ApiError extends Error { constructor(public code: string, message: string, public details?: unknown) { super(message); } }
export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set('Accept-Language',getLanguage());
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
export function errorText(error: unknown) { const message=error instanceof Error?error.message:t('copy.168');return /(?:API|OAuth|RPC|Turnstile|VAPID|\.env|SMTP|credentials|provider.*key|ключ.*(?:сервис|сервер)|настро.{0,25}(?:сервер|разработ))/i.test(message)?t('copy.169'):message; }

