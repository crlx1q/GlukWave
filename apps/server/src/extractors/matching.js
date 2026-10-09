import {searchText} from '../search.js';

const variants=/\b(live|remix|cover|karaoke|instrumental|sped|slowed|acoustic)\b/g;
function overlap(a,b){const left=new Set(searchText(a).split(' ').filter(Boolean)),right=new Set(searchText(b).split(' ').filter(Boolean));if(!left.size||!right.size)return 0;return [...left].filter(word=>right.has(word)).length/Math.max(left.size,right.size);}
export function audioMatch(track,candidate){
  const title=overlap(track.title,candidate.title),artist=overlap(track.artist,candidate.artist),difference=Math.abs(Number(track.duration)-Number(candidate.duration));
  const duration=Number(track.duration)>0&&Number(candidate.duration)>0?Math.max(0,1-difference/Math.max(5,track.duration*.05)):0;
  const versionMismatch=JSON.stringify([...searchText(track.title).matchAll(variants)].map(m=>m[0]).sort())!==JSON.stringify([...searchText(candidate.title).matchAll(variants)].map(m=>m[0]).sort());
  const score=title*.45+artist*.4+duration*.15;
  return {score:Number(score.toFixed(4)),titleScore:title,artistScore:artist,durationDifference:difference,accepted:!versionMismatch&&title>=.85&&artist>=.85&&difference<=Math.max(5,track.duration*.03)&&duration>0,versionMismatch};
}
