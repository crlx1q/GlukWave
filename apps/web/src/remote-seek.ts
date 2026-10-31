import {progressPosition,type ProgressSample} from './progress-clock.ts';

export type DeviceSeekIntent={position:number;revision:number;scope:string;sourceAt:number;at:number;deadline:number;playing:boolean;ackAt?:number};
export type DeviceSeekSnapshot=ProgressSample&{updatedAt:number;online:boolean;loading?:boolean};
/** ACK confirms dispatch only. A later output packet must also reflect the target. */
export function deviceSeekStatus(intent:DeviceSeekIntent,scope:string,snapshot:DeviceSeekSnapshot,now:number):'pending'|'confirmed'|'cancelled'{
 if(scope!==intent.scope||now>=intent.deadline||!snapshot.online||snapshot.loading||snapshot.playing!==intent.playing)return 'cancelled';
 if(intent.ackAt===undefined||snapshot.updatedAt<=intent.sourceAt)return 'pending';
 const position=progressPosition(snapshot,now);
 if(!intent.playing)return Math.abs(position-intent.position)<=.025?'confirmed':'pending';
 // The output executes between dispatch and ACK. Match that projected interval.
 const earliest=intent.position+Math.max(0,now-intent.ackAt)/1000-.025;
 const latest=intent.position+Math.max(0,now-intent.at)/1000+.025;
 return position>=earliest&&position<=latest?'confirmed':'pending';
}
export function deviceSeekSample(intent:DeviceSeekIntent,duration:number):ProgressSample{return {position:intent.position,duration,playing:intent.playing,at:intent.at,horizon:Math.max(0,intent.deadline-intent.at)};}
