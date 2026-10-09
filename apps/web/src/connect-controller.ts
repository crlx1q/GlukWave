import type {ConnectState, PlayerState} from './types';

// A browser installation can own many tabs, but only one is the audio surface.
export function ownsOutput(connect:ConnectState,device:string,surface:string):boolean{
  if(connect.roomId&&!connect.activeDeviceId)return false;
  return connect.independent&&!connect.roomId||!connect.activeDeviceId||connect.activeDeviceId===device&&connect.activeSurfaceId===surface;
}
export function snapshotPosition(state:PlayerState,serverTime:number,networkDelay=0):number{
  const elapsed=state.playing?Math.max(0,(serverTime-state.updatedAt+networkDelay)/1000):0;
  return Math.max(0,state.position+elapsed);
}
