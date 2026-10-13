/** Media metadata survives pause and the real loading interval between queue items. */
export function mediaSessionState(track:{title:string;artist:string}|null,playing:boolean,loading:boolean,intendsToPlay:boolean,pending:boolean){
 return {title:track?`${track.title} — ${track.artist} · GlukWave`:null,playbackState:(track?(playing||(loading||pending)&&intendsToPlay?'playing':'paused'):'none') as MediaSessionPlaybackState};
}
