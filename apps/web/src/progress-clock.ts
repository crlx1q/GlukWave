/** A presentation sample. Reading/painting it never changes playback authority. */
export type ProgressSample={position:number;duration:number;playing:boolean;rate?:number;at:number;horizon?:number};
export type ProgressReader=()=>ProgressSample;
// Server account snapshots checkpoint every10s; socket disconnect/pause freezes sooner.
export const REMOTE_PROGRESS_HORIZON=12000;
export function progressPosition(sample:ProgressSample,now:number){
 const position=Number.isFinite(sample.position)?sample.position:0,total=Number.isFinite(sample.duration)?Math.max(0,sample.duration):0;
 const elapsed=sample.playing?Math.min(Math.max(0,now-sample.at),Math.max(0,sample.horizon??2000))/1000:0;
 return Math.max(0,Math.min(total,position+elapsed*Math.max(0,Number.isFinite(sample.rate)?sample.rate!:1)));
}
export function progressAdvancing(sample:ProgressSample,now:number){return sample.playing&&progressPosition(sample,now)<sample.duration&&(sample.horizon===undefined||now-sample.at<sample.horizon);}

/** Smooth packet corrections only. Explicit transport revisions change scope and reset immediately. */
export class PacketProgressClock {
 private scope:unknown;private lastAt=0;private painted=0;private source:ProgressSample|null=null;
 read(sample:ProgressSample,scope:unknown,now:number):ProgressSample{
  const target=progressPosition(sample,now),rate=sample.rate??1,advancing=progressAdvancing(sample,now);
  const jump=this.source&&this.source!==sample?Math.abs(sample.position-progressPosition(this.source,sample.at)):0;
  if(this.scope!==scope||!sample.playing||!this.source?.playing||this.source.rate!==sample.rate||now<this.lastAt||jump>Math.max(1.1,rate*1.1))this.painted=target;
  else if(advancing){
   const elapsed=Math.max(0,now-this.lastAt)/1000,next=this.painted+elapsed*rate;
   // Correct at up to 25% of playback speed, never a backwards packet step.
   this.painted=Math.min(sample.duration,Math.max(this.painted,next+Math.max(-elapsed*rate*.25,Math.min(elapsed*rate*.25,target-next))));
  }
  this.scope=scope;this.lastAt=now;this.source=sample;
  return {...sample,position:this.painted,playing:advancing,at:now,horizon:Math.max(0,(sample.horizon??2000)-(now-sample.at))};
 }
}

/** Smooth coarse browser media clocks without advancing playback authority.
 * A healthy coarse source is extrapolated for at most 1500ms; seeks/pause reset it. */
export class LocalMediaClock {
 private scope:unknown;private observed=0;private changedAt=0;private lastAt=0;
 private painted=0;private playing=false;private rate=1;
 reset(){this.playing=false;}
 read(sample:ProgressSample,scope:unknown):ProgressSample{
  const now=sample.at,position=Math.max(0,sample.position),rate=sample.rate??1;
  if(this.scope!==scope||!sample.playing||!this.playing||this.rate!==rate||now<this.lastAt){
   this.scope=scope;this.observed=position;this.painted=position;this.changedAt=now;
  }else{
   const elapsed=Math.max(0,now-this.lastAt)/1000;
   let next=this.painted+elapsed*rate;
   if(Math.abs(position-this.observed)>.00001){
    const delta=position-next;
    const sourceDelta=position-this.observed,sourceElapsed=Math.max(0,now-this.changedAt)/1000;
    if(sourceDelta<-.05||sourceDelta>Math.max(rate*1.1,sourceElapsed*rate+.25))next=position;
    else next+=Math.max(-elapsed*rate*.25,Math.min(elapsed*rate*.25,delta*.15));
    this.observed=position;this.changedAt=now;
   }
   this.painted=Math.max(0,Math.min(sample.duration,position+1.5*rate,next));
  }
  this.lastAt=now;this.playing=sample.playing;this.rate=rate;
  return {...sample,position:this.painted,playing:sample.playing&&now-this.changedAt<1500,at:now,horizon:Math.max(0,1500-(now-this.changedAt))};
 }
}
