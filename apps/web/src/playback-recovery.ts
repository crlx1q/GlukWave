// Authentication, connectivity and autoplay require user recovery, not skipping.
export function unavailableAudio(error:unknown){
  const code=(error as {code?:string})?.code;
  return !!code&&['AUDIO_UNAVAILABLE',
    'DIRECT_AUDIO_UNAVAILABLE',
    'AUDIO_MATCH_REJECTED'].includes(code);
}
