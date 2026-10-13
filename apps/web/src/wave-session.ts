export type WaveMode='personal'|'favorites'|'discovery'|'popular';
export type WaveMood='personal'|'energy'|'happy'|'calm'|'sad'|'focus'|'dream';
export type WaveOptions={mode?:WaveMode;mood?:WaveMood;seedTrackId?:string};
export type WaveSelection={mode:WaveMode;mood:WaveMood};
export const defaultWave:WaveSelection={mode:'personal',mood:'personal'};
export function recommendationQuery(options:WaveOptions,exclude:string[]=[],nonce=''){
 const query=new URLSearchParams({mode:options.mode||'personal',mood:options.mood||'personal',limit:'20',nonce});
 if(options.seedTrackId)query.set('seedTrackId',options.seedTrackId);
 if(exclude.length)query.set('exclude',[...new Set(exclude)].slice(-100).join(','));
 return query.toString();
}
/** Explicit repeat-all owns a finite queue. Other queues continue only at their tail. */
export const needsWaveTail=(ids:string[],current:string|null,repeat:'off'|'all'|'one',manualNext=false)=>repeat!=='all'&&(manualNext||repeat!=='one')&&!!current&&ids.includes(current)&&ids.indexOf(current)===ids.length-1;
