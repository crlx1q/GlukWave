export const canManageRoom = (room,user) => !!user && (user.role==='admin'||room.ownerId===user.id);
export const canControlRoom = (room,user) => !!user && (canManageRoom(room,user)||room.members.some(member=>member.userId===user.id&&member.canControl&&!member.administrative));

/** A directory card contains metadata, never private invitations, device identities or audio URLs. */
export async function roomCard(room,user,ctx,{joined=false}={}) {
  const decorated=ctx.decorateRoom?await ctx.decorateRoom(room):room;
  const members=decorated.members.map(member=>({...member,playing:!!member.devices?.some(device=>device.playing)}));
  const track=room.state.trackId?await ctx.store.get('tracks',room.state.trackId):null;
  const visible=track&&(joined||user.role==='admin'||track.public||track.source!=='local');
  const currentTrack=visible?{
    id:track.id,title:track.title,artist:track.artist,album:track.album||'',
    artwork:ctx.externalCoverUrl?.(track)||track.artwork||'',duration:track.duration||0,
    source:track.source,sourceId:track.sourceId||'',sourceUrl:track.source==='local'?'':track.sourceUrl||'',
    createdAt:track.createdAt,playback:{kind:track.source,offline:false},
  }:null;
  return {
    id:room.id,name:room.name,ownerId:room.ownerId,visibility:room.visibility||'private',type:room.type||'room',
    memberCount:members.length,onlineCount:members.filter(member=>member.online).length,
    listeningCount:members.filter(member=>member.playing).length,currentTrack,
    canManage:canManageRoom(room,user),canControl:canControlRoom(room,user),
    members:joined?members:members.slice(0,3).map(({userId,displayName,avatarUrl,online,playing})=>({userId,displayName,avatarUrl,online:!!online,playing})),
  };
}
