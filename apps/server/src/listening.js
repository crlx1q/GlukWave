import {asyncRoute} from './util.js';
// Statistics observe accepted output heartbeats, never renderer ticks or seeks.
export function setupListening(app,ctx){
 const {store}=ctx,baselines=new Map(),pending=new Map();let flushTask=Promise.resolve();
 ctx.observeListening=(uid,output,state,at=Date.now())=>{
  const previous=baselines.get(uid);baselines.delete(uid);baselines.set(uid,{output,trackId:state.trackId,position:state.position,playing:state.playing,at});while(baselines.size>2000)baselines.delete(baselines.keys().next().value);
  if(previous?.output===output&&previous.trackId&&previous.trackId!==state.trackId&&previous.playing&&previous.position>1){const oldKey=uid+':'+previous.trackId,old=pending.get(oldKey)||{id:oldKey,userId:uid,trackId:previous.trackId,plays:0,seconds:0};if(pending.size<4000){old.skippedPositions=[...old.skippedPositions||[],previous.position].slice(-20);old.updatedAt=new Date(at).toISOString();pending.set(oldKey,old);}}
  if(!state.trackId)return;const key=uid+':'+state.trackId;let row=pending.get(key);
  const continuing=previous?.output===output&&previous.trackId===state.trackId,elapsed=continuing?(at-previous.at)/1000:0,advance=continuing?state.position-previous.position:0;
  const seconds=previous?.playing&&state.playing&&continuing&&elapsed>0&&elapsed<=20&&advance>=0&&advance<=elapsed*1.5+2?Math.min(elapsed,advance):0;
  const plays=state.playing&&(!previous||previous.trackId!==state.trackId||!previous.playing&&previous.position<1&&state.position<3)?1:0;
  if(!seconds&&!plays)return;if(!row){if(pending.size>=4000){void ctx.flushListening();}row={id:key,userId:uid,trackId:state.trackId,plays:0,seconds:0};pending.set(key,row);}row.plays+=plays;row.seconds+=seconds;row.updatedAt=new Date(at).toISOString();
 };
 ctx.forgetListening=uid=>{baselines.delete(uid);for(const [key,row] of pending)if(row.userId===uid)pending.delete(key);};
 ctx.flushListening=()=>{const batch=[...pending.values()];pending.clear();flushTask=flushTask.then(async()=>{for(const row of batch){try{const track=await store.get('tracks',row.trackId);if(!track||!await store.get('users',row.userId))continue;const {skippedPositions,...totals}=row,skips=(skippedPositions||[]).filter(position=>track.duration>0&&position<Math.min(30,track.duration-3)).length;await store.update('listeningStats',row.id,previous=>({...totals,artist:track.artist,title:track.title,source:track.source,artwork:track.artwork,plays:(previous?.plays||0)+row.plays,seconds:(previous?.seconds||0)+row.seconds,skips:(previous?.skips||0)+skips,createdAt:previous?.createdAt||row.updatedAt}));}catch(error){if(pending.size<4000){const current=pending.get(row.id);pending.set(row.id,{...row,plays:row.plays+(current?.plays||0),seconds:row.seconds+(current?.seconds||0),skippedPositions:[...row.skippedPositions||[],...current?.skippedPositions||[]].slice(-20)});}ctx.log.warn({message:error.message},'Listening statistics flush deferred');}}});return flushTask;};
 ctx.accountStats=async(userId,viewer)=>{
  await ctx.flushListening();const rows=await store.list('listeningStats',row=>row.userId===userId),topTracks=[],artists=new Map();let plays=0,seconds=0;
  for(const row of rows){plays+=row.plays;seconds+=row.seconds;if(row.artist){const artist=artists.get(row.artist)||{name:row.artist,plays:0,seconds:0};artist.plays+=row.plays;artist.seconds+=row.seconds;artists.set(row.artist,artist);}const track=await store.get('tracks',row.trackId);if(track&&await ctx.canAccessTrack(track,viewer))topTracks.push({track:ctx.publicTrack(track,viewer),plays:row.plays,seconds:Math.round(row.seconds)});}
  return {plays,listeningSeconds:Math.round(seconds),trackCount:rows.length,artistCount:artists.size,topTracks:topTracks.sort((a,b)=>b.seconds-a.seconds||b.plays-a.plays).slice(0,20),topArtists:[...artists.values()].sort((a,b)=>b.seconds-a.seconds||b.plays-a.plays).slice(0,20).map(artist=>({...artist,seconds:Math.round(artist.seconds)}))};
 };
 app.get('/api/account/stats',ctx.requireAuth,asyncRoute(async(req,res)=>res.set('Cache-Control','no-store').json({stats:await ctx.accountStats(req.auth.user.id,req.auth.user)})));
 const timer=setInterval(()=>{void ctx.flushListening();},15000);timer.unref();ctx.closeListening=async()=>{clearInterval(timer);await ctx.flushListening();baselines.clear();};
}
