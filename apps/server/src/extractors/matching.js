import {searchText} from '../search.js';

const variants=/\b(live|remix|cover|karaoke|instrumental|sped|slowed|acoustic)\b/g;

export function overlap(a,b){
  const left=new Set(searchText(a).split(' ').filter(Boolean)),right=new Set(searchText(b).split(' ').filter(Boolean));
  if(!left.size||!right.size)return 0;
  return [...left].filter(word=>right.has(word)).length/Math.max(left.size,right.size);
}

export function cleanCandidateTitle(raw,trackArtist='',candArtist=''){
  let cleaned=String(raw||'').trim();
  cleaned=cleaned.replace(/\s*[\(\[](?:official\s*(?:music\s*|lyric\s*|hd\s*|4k\s*|video\s*)?(?:video|audio|clip|visualizer)|visualizer|lyric\s*video|lyrics?|audio|video|music\s*video|clip\s*officiel|clip|4k(?:\s*remaster(?:ed)?)?|hd|remaster(?:ed)?(?:\s*\d{4})?|hq)[\)\]]/gi,'');
  cleaned=cleaned.replace(/\s*[-–—|/]\s*(?:official\s*(?:video|audio|music\s*video)|visualizer|lyrics?|audio|video)$/gi,'');
  const split=cleaned.match(/^(.+?)\s*[-–—:]\s*(.+)$/);
  if(split){
    const art=trackArtist||candArtist||'';
    const prefixOv=overlap(art,split[1]);
    const normArt=searchText(art),normPrefix=searchText(split[1]);
    if(prefixOv>=0.6||(normArt&&(normPrefix.includes(normArt)||normArt.includes(normPrefix)))){
      cleaned=split[2];
    }
  }
  return cleaned.trim()||String(raw||'');
}

export function cleanCandidateArtist(candArtist,rawTitle='',trackArtist=''){
  let cleaned=String(candArtist||'').trim().replace(/\s*-\s*Topic$/i,'').replace(/vevo$/i,'');
  const split=String(rawTitle||'').match(/^(.+?)\s*[-–—:]\s*(.+)$/);
  if(split){
    const prefixOv=overlap(trackArtist,split[1]);
    if(prefixOv>=0.7){
      cleaned=split[1].trim();
    }
  }
  return cleaned||String(candArtist||'');
}

export function audioMatch(track,candidate){
  const rawCandTitle=candidate.title||'';
  const candTitle=cleanCandidateTitle(rawCandTitle,track.artist,candidate.artist);
  const candArtist=cleanCandidateArtist(candidate.artist,rawCandTitle,track.artist);

  const titleScore=Math.max(overlap(track.title,candidate.title),overlap(track.title,candTitle));
  const artistScore=Math.max(overlap(track.artist,candidate.artist),overlap(track.artist,candArtist));
  const trackDur=Number(track.duration)||0;
  const candDur=Number(candidate.duration)||0;
  const difference=Math.abs(trackDur-candDur);
  const hasBothDur=trackDur>0&&candDur>0;
  const durationScore=hasBothDur?Math.max(0,1-difference/Math.max(5,trackDur*0.05)):(trackDur===0&&candDur>0?1:0);
  const versionMismatch=JSON.stringify([...searchText(track.title).matchAll(variants)].map(m=>m[0]).sort())!==JSON.stringify([...searchText(candidate.title).matchAll(variants)].map(m=>m[0]).sort());
  const score=hasBothDur?(titleScore*.45+artistScore*.4+durationScore*.15):(titleScore*.5+artistScore*.5);

  const durationAccepted=hasBothDur
    ?(difference<=Math.max(8,trackDur*0.04)&&durationScore>0)
    :(trackDur===0&&candDur>0);

  return {
    score:Number(score.toFixed(4)),
    titleScore,
    artistScore,
    durationDifference:difference,
    accepted:!versionMismatch&&titleScore>=.85&&artistScore>=.85&&durationAccepted&&(trackDur>0?durationScore>0:candDur>0),
    versionMismatch
  };
}
