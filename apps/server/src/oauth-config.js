const paths = {google:'/api/auth/google/callback',youtube:'/api/integrations/youtube/callback',spotify:'/api/integrations/spotify/callback',soundcloud:'/api/integrations/soundcloud/callback',discord:'/api/integrations/discord/callback'};

export function oauthCredentials(config, provider) {
  if (provider === 'youtube') return {...(config.youtubeOAuth?.id ? config.youtubeOAuth : config.google),redirectUri:config.youtubeOAuth?.redirectUri||''};
  return config[provider];
}

export function oauthReturnBase(config, request) {
  const candidates=[request.headers?.origin,request.headers?.referer];
  for(const value of candidates)try{const url=new URL(value);if(config.origins?.includes(url.origin)&&!url.username&&!url.password)return url.origin;}catch{}
  return config.appUrl;
}

/** Redirects are server configuration, never a request's Host or return URL. */
export function oauthSettings(config, provider) {
  const credentials = oauthCredentials(config, provider), issues = [];
  if (!paths[provider]) return {id:provider,loginAvailable:false,redirectUri:null,issues:['UNSUPPORTED_PROVIDER']};
  if (!credentials?.id || !credentials?.secret) issues.push('CLIENT_CREDENTIALS_MISSING');
  let redirectUri = null;
  try {
    const raw = credentials?.redirectUri || new URL(paths[provider], config.oauthBaseUrl || config.appUrl).href;
    const uri = new URL(raw);
    // Spotify compares the exact string. Do not normalize an explicit override.
    redirectUri = raw;
    if (uri.username || uri.password || uri.search || uri.hash || uri.pathname !== paths[provider]) issues.push('CALLBACK_INVALID');
    const loopback = uri.hostname === '127.0.0.1' || uri.hostname === '[::1]';
    if (uri.protocol !== 'https:' && !(uri.protocol === 'http:' && !config.production && (provider !== 'spotify' || loopback))) issues.push('CALLBACK_REQUIRES_HTTPS');
    if (provider === 'spotify' && uri.hostname === 'localhost') issues.push('SPOTIFY_LOCALHOST_NOT_ALLOWED');
  } catch { issues.push('CALLBACK_INVALID'); }
  return {id:provider,loginAvailable:issues.length===0,redirectUri,issues:[...new Set(issues)]};
}
