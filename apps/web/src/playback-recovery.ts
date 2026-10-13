// Authentication, connectivity and autoplay require user recovery, not skipping.
export function unavailableAudio(error:unknown){
  const code=(error as {code?:string})?.code;
  return !!code&&['AUDIO_UNAVAILABLE','AUDIO_FORMAT_UNAVAILABLE',
    'DIRECT_AUDIO_UNAVAILABLE','EXTRACTOR_UPSTREAM','EXTRACTOR_URL',
    'AUDIO_MATCH_REJECTED'].includes(code);
}
