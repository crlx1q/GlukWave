/** A successful HTTP response can still be a manifest/error page, not a file.
 * Inspect only the prefix; keep unknown binary formats for the real decoder. */
export async function isAudioFile(blob:Blob):Promise<boolean>{
 if(!blob.size)return false;
 const type=blob.type.toLowerCase().split(';')[0].trim();
 if(type.startsWith('text/')||/json|html|xml|mpegurl/.test(type))return false;
 const prefix=(await blob.slice(0,256).text()).replace(/^\uFEFF/,'').trimStart();
 return !/^(?:#EXTM3U|<!doctype\b|<html\b|<\?xml\b|[\[{])/i.test(prefix);
}

export function canRetryCachedAudio(error:unknown,cached:boolean,online:boolean):boolean{
 if(!cached||!online||!error||typeof error!=='object')return false;
 return ('name' in error&&error.name==='NotSupportedError')||('code' in error&&error.code==='AUDIO_FORMAT_UNAVAILABLE');
}
