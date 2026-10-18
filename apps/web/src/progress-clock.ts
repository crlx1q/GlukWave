/** A presentation sample. Reading/painting it never changes playback authority. */
export type ProgressSample={position:number;duration:number;playing:boolean;rate?:number;at:number;horizon?:number};
export type ProgressReader=()=>ProgressSample;
export function progressPosition(sample:ProgressSample,now:number){
 const position=Number.isFinite(sample.position)?sample.position:0,total=Number.isFinite(sample.duration)?Math.max(0,sample.duration):0;
 const elapsed=sample.playing?Math.min(Math.max(0,now-sample.at),Math.max(0,sample.horizon??2000))/1000:0;
 return Math.max(0,Math.min(total,position+elapsed*Math.max(0,Number.isFinite(sample.rate)?sample.rate!:1)));
}
export function progressAdvancing(sample:ProgressSample,now:number){return sample.playing&&progressPosition(sample,now)<sample.duration&&(sample.horizon===undefined||now-sample.at<sample.horizon);}

/** Smooth coarse browser media clocks without advancing playback authority.
 * A stalled source is extrapolated for at most 250ms; seeks/pause reset it. */
export class LocalMediaClock {
 private scope:unknown;private observed=0;private changedAt=0;private lastAt=0;
 private painted=0;private playing=false;private rate=1;
 read(sample:ProgressSample,scope:unknown):ProgressSample{
  const now=sample.at,position=Math.max(0,sample.position),rate=sample.rate??1;
  if(this.scope!==scope||!sample.playing||!this.playing||this.rate!==rate||now<this.lastAt){
   this.scope=scope;this.observed=position;this.painted=position;this.changedAt=now;
  }else{
   const elapsed=Math.max(0,now-this.lastAt)/1000;
   let next=this.painted+elapsed*rate;
   if(Math.abs(position-this.observed)>.00001){
    const delta=position-next;
    if(Math.abs(delta)>.25)next=position;
    else next+=Math.max(-elapsed*rate*.25,Math.min(elapsed*rate*.25,delta*.15));
    this.observed=position;this.changedAt=now;
   }
   this.painted=Math.max(0,Math.min(sample.duration,position+.25*rate,next));
  }
  this.lastAt=now;this.playing=sample.playing;this.rate=rate;
  return {...sample,position:this.painted,playing:sample.playing&&now-this.changedAt<250,at:now,horizon:250};
 }
}
