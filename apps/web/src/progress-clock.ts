/** A presentation sample. Reading/painting it never changes playback authority. */
export type ProgressSample={position:number;duration:number;playing:boolean;rate?:number;at:number;horizon?:number};
export type ProgressReader=()=>ProgressSample;
export function progressPosition(sample:ProgressSample,now:number){
 const position=Number.isFinite(sample.position)?sample.position:0,total=Number.isFinite(sample.duration)?Math.max(0,sample.duration):0;
 const elapsed=sample.playing?Math.min(Math.max(0,now-sample.at),Math.max(0,sample.horizon??2000))/1000:0;
 return Math.max(0,Math.min(total,position+elapsed*Math.max(0,Number.isFinite(sample.rate)?sample.rate!:1)));
}
export function progressAdvancing(sample:ProgressSample,now:number){return sample.playing&&progressPosition(sample,now)<sample.duration&&(sample.horizon===undefined||now-sample.at<sample.horizon);}
