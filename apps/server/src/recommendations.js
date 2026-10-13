import {z} from 'zod';
import {asyncRoute,parse,fail} from './util.js';
import {searchText} from './search.js';

export const waveModes=['personal','favorites','discovery','popular'];
export const waveMoods=['personal','energy','happy','calm','sad','focus','dream'];
const aliases={relax:'calm',night:'dream'};
const genreAliases=[
 ['hip hop',/^(hip[ -]?hop(?:.*)?|rap|русски[йи] рэп|рэп)$/],
 ['electronic',/^(electro(?:nic|nika)?|электронная|электроника|электро)$/],
 ['pop',/^(pop|поп|поп музыка)$/],['rock',/^(rock|рок)$/],
 ['ambient',/^(ambient|эмбиент)$/],['jazz',/^(jazz|джаз)$/],
 ['classical',/^(classic(?:al)?|классика|классическая)$/],
 ['lofi',/^(lo[ -]?fi(?:.*)?|лоуфай)$/],['dance',/^(dance(?:.*)?|танцевальная|танцы)$/]
];
export const genreKey=value=>{const key=searchText(value);return genreAliases.find(([,regex])=>regex.test(key))?.[0]||key;};
const features=track=>{
 const values=new Set([track.genre,...track.tags||[]].filter(value=>typeof value==='string').map(genreKey).filter(value=>value&&value.length<60));
 for(const value of [...values])for(const [genre,pattern] of [['rock',/rock|рок|metal|метал/],['pop',/\bpop\b|поп/],['indie',/indie|инди/],['electronic',/electronic|techno|trance|house|drum.*bass|техно|транс|хаус/],['ambient',/ambient|эмбиент/]])if(pattern.test(value))values.add(genre);
 return values;
};
const artists=track=>(track.artists?.length?track.artists:[{name:track.artist||''}]).map(value=>searchText(value.name)).filter(Boolean);
const overlap=(left,right)=>left.size&&right.size?[...left].filter(key=>right.has(key)).length/Math.sqrt(left.size*right.size):0;
const moods={
 energy:/dance|electronic|rock|hip hop|energetic|бодр|энерг|танц/i,
 happy:/pop|dance|funk|disco|happy|uplift|joy|весел|радост|позитив/i,
 calm:/ambient|chill|lofi|jazz|calm|relax|acoustic|споко[йи]|отдых/i,
 sad:/sad|melanchol|blues|emo|piano|груст|печаль/i,
 focus:/instrumental|piano|classical|focus|ambient|инструмент/i,
 dream:/dream|shoegaze|ambient|indie|night|мечт/i
};
const songKey=track=>artists(track).sort().join('|')+':'+searchText(track.title||'').replace(/\b(official|audio|video|lyrics)\b/g,'').replace(/\s+/g,' ').trim();
const rowSignal=(row,track)=>{
 const plays=Math.max(1,row.plays||0),average=(row.seconds||0)/plays;
 const completion=track.duration>0?Math.min(1,average/track.duration):Math.min(1,average/120);
 return Math.min(12,Math.log1p(row.seconds||0)*.8+completion*5)-Math.min(24,(row.skips||0)*6);
};
const hash=value=>{let number=2166136261;for(const char of value)number=Math.imul(number^char.charCodeAt(0),16777619);return (number>>>0)/4294967296;};

/** Rank metadata and accepted listening, then diversify. Never inspect or extract audio. */
export function rankRecommendations({tracks,taste={},library={},stats=[],popularity=new Map(),seed=null,exclude=[],mode='personal',mood='personal',limit=20,nonce='',at=Date.now()}){
 const liked=new Set(library.likedIds||[]),heard=new Set((library.history||[]).map(value=>value.trackId)),excluded=new Set(exclude),recent=new Map();
 for(const entry of library.history||[])if(!recent.has(entry.trackId))recent.set(entry.trackId,Date.parse(entry.playedAt||''));
 const selectedArtists=new Set((taste.artists||[]).map(value=>searchText(value.name))),selectedGenres=new Set((taste.genres||[]).map(genreKey));
 const rows=new Map(stats.map(row=>[row.trackId,row])),byId=new Map(tracks.map(track=>[track.id,track]));
 for(const row of stats)if(row.plays>0||row.seconds>0)heard.add(row.trackId);
 const heardSongs=new Set([...heard,...liked].map(id=>byId.get(id)).filter(Boolean).map(songKey));
 const artistWeights=new Map(),tagWeights=new Map();
 for(const row of stats){if(row.plays>0||row.seconds>0)heard.add(row.trackId);
  if(taste.automatic===false||taste.learnedResetAt&&row.updatedAt<=taste.learnedResetAt)continue;
  const track=byId.get(row.trackId);if(!track)continue;const signal=rowSignal(row,track);
  for(const name of artists(track))artistWeights.set(name,(artistWeights.get(name)||0)+signal);
  for(const tag of features(track))tagWeights.set(tag,(tagWeights.get(tag)||0)+signal/3);
 }
 for(const id of liked){const track=byId.get(id);if(!track)continue;heard.add(id);for(const tag of features(track))tagWeights.set(tag,(tagWeights.get(tag)||0)+3);}
 const seedTags=seed?features(seed):new Set(),seedArtists=new Set(seed?artists(seed):[]);
 const ranked=[];
 for(const track of tracks){
  if(excluded.has(track.id)||seed?.id===track.id||mode==='favorites'&&!liked.has(track.id)||mode==='discovery'&&(heard.has(track.id)||heardSongs.has(songKey(track))))continue;
  const names=artists(track),tags=features(track),row=rows.get(track.id),popular=popularity.get(track.id)||0;
  let score=names.some(name=>selectedArtists.has(name))?16:0;
  score+=overlap(tags,selectedGenres)*16;
  if(taste.automatic!==false){score+=Math.max(-14,Math.min(14,names.reduce((sum,name)=>sum+(artistWeights.get(name)||0),0)));
   score+=Math.max(-10,Math.min(10,[...tags].reduce((sum,tag)=>sum+(tagWeights.get(tag)||0),0)));
   if(row&&(!taste.learnedResetAt||row.updatedAt>taste.learnedResetAt))score+=rowSignal(row,track);
  }
  if(liked.has(track.id))score+=14;
  if(seed){score+=overlap(tags,seedTags)*24+(names.some(name=>seedArtists.has(name))?18:0);}
  const moodMatch=mood!=='personal'&&moods[mood]?.test([...tags,...track.moods||[]].join(' '));
  if(moodMatch)score+=22;
  if(mode==='popular')score=score*.35+Math.log1p(popular)*14+(moodMatch?14:0);
  else score+=Math.log1p(popular)*2;
  const lastPlayed=recent.get(track.id);
  if(Number.isFinite(lastPlayed)&&at-lastPlayed<24*3600000&&mode!=='favorites')score-=8;
  // Stable per batch: explore without reordering a queue on every renderer tick.
  score+=hash(nonce+':'+track.id)*(mode==='discovery'?6:3);
  ranked.push({track,score,artists:names,key:songKey(track)});
 }
 // Diversity operates on a bounded high-scoring shortlist, not limit × entire catalogue.
 ranked.sort((a,b)=>b.score-a.score);ranked.splice(Math.max(120,limit*12));
 const result=[],usedSongs=new Set(),artistCounts=new Map();
 while(result.length<limit&&ranked.length){
  let winner=-1,best=-Infinity;
  for(let index=0;index<ranked.length;index++){
   const item=ranked[index];if(usedSongs.has(item.key))continue;
   const previous=result.at(-1),consecutive=previous&&item.artists.some(name=>artists(previous).includes(name));
   const penalty=item.artists.reduce((sum,name)=>sum+(artistCounts.get(name)||0)*5,0)+(consecutive?16:0);
   if(item.score-penalty>best){best=item.score-penalty;winner=index;}
  }
  if(winner<0)break;const [item]=ranked.splice(winner,1);usedSongs.add(item.key);result.push(item.track);
  for(const name of item.artists)artistCounts.set(name,(artistCounts.get(name)||0)+1);
 }
 return result;
}

export function setupRecommendations(app,ctx){
 const {store}=ctx;let popularity=null,popularityAt=0,popularityJob=null;
 const candidateCache=new Map();let candidateJobs=0;
 async function briefWait(job){let timer;try{await Promise.race([job,new Promise(resolve=>{timer=setTimeout(resolve,6000);timer.unref();})]);}finally{clearTimeout(timer);}}
 async function discover(query,user){
  const provider=ctx.providerConfiguration?.().filter(value=>value.searchAvailable).sort((a,b)=>['soundcloud','spotify','youtube'].indexOf(a.id)-['soundcloud','spotify','youtube'].indexOf(b.id))[0];
  if(!provider||!ctx.searchProvider)return;
  const key=(user?.id||'guest')+':'+provider.id+':'+query;
  let entry=candidateCache.get(key);
  if(entry&&Date.now()-entry.at<300000){if(entry.job)await briefWait(entry.job);return;}
  if(candidateJobs>=2)return;
  entry={at:Date.now(),job:null};candidateCache.set(key,entry);
  while(candidateCache.size>64)candidateCache.delete(candidateCache.keys().next().value);
  candidateJobs++;entry.job=ctx.searchProvider(provider.id,query,user?.id).catch(()=>[]).finally(()=>{candidateJobs--;entry.job=null;});
  await briefWait(entry.job);
 }
 ctx.invalidateRecommendations=()=>{popularityAt=0;};
 async function aggregate(){
  if(popularity&&Date.now()-popularityAt<60000)return popularity;
  popularityJob??=(async()=>{const map=new Map(),[rows,libraries]=await Promise.all([store.list('listeningStats'),store.list('libraries')]);
   for(const row of rows)map.set(row.trackId,(map.get(row.trackId)||0)+Math.min(20,row.plays||0)+Math.min(60,(row.seconds||0)/60));
   for(const library of libraries)for(const id of library.likedIds||[])map.set(id,(map.get(id)||0)+8);
   popularity=map;popularityAt=Date.now();return map;
  })().finally(()=>{popularityJob=null;});return popularityJob;
 }
 app.get('/api/recommendations',asyncRoute(async(req,res)=>{
  const query=parse(z.object({mode:z.enum(waveModes).default('personal'),mood:z.enum([...waveMoods,'relax','night']).default('personal'),seedTrackId:z.string().max(200).optional(),exclude:z.string().max(22000).default(''),limit:z.coerce.number().int().min(1).max(60).default(20),nonce:z.string().max(100).default('')}).strict(),req.query);
  const user=req.auth?.user,uid=user?.id,mood=aliases[query.mood]||query.mood,exclude=query.exclude.split(',').filter(Boolean).slice(-100);
  await ctx.flushListening?.();
  const [taste,library,stats,popular]=await Promise.all([uid?store.get('taste',uid):null,uid?store.get('libraries',uid):null,uid?store.list('listeningStats',row=>row.userId===uid):[],aggregate()]);
  const seed=query.seedTrackId?await ctx.requireTrack(query.seedTrackId,user):null;
  const accessible=track=>track.public&&track.source!=='local'||!!uid&&track.uploadedBy===uid;
  let tracks=await store.list('tracks',accessible);
  const rank=()=>rankRecommendations({tracks,taste:taste||{},library:library||{},stats,popularity:popular,seed,exclude,mode:query.mode,mood,limit:query.limit,nonce:query.nonce||uid||'guest'});
  let ranked=rank();
  if(ranked.length<Math.min(8,query.limit)&&query.mode!=='favorites'){
   const genre=seed?.genre||taste?.genres?.[0]||[...seed?.tags||[]][0]||'';
   const names=seed?.artist||taste?.artists?.[0]?.name||'';
   const terms=[names,genre,mood!=='personal'?mood:''].filter(Boolean).join(' ').slice(0,160)||'indie pop';
   await discover(terms,user);tracks=await store.list('tracks',accessible);ranked=rank();
  }
  if(uid){const [fresh,session]=await Promise.all([store.get('users',uid),store.get('sessions',req.auth.session.id)]);if(!fresh||fresh.blocked||!session||session.expiresAt<Date.now())fail(401,'AUTH_REQUIRED','Сессия завершена.');}
  res.set('Cache-Control','private, no-store').json({tracks:ranked.map(track=>ctx.publicTrack(track,user)),artists:taste?.artists||[],genres:[...new Set(tracks.flatMap(track=>[track.genre,...track.tags||[]]).filter(value=>typeof value==='string'&&value.length<60))].sort().slice(0,100),reason:!ranked.length?'empty':seed?'seed':taste?.artists?.length||taste?.genres?.length?'taste':stats.length||library?.history?.length?'history':'catalogue',mode:query.mode,mood,seedTrackId:seed?.id||null,algorithm:'content-v1',popularityScope:'glukwave'});
 }));
}
