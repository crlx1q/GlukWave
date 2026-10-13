// Prime the same media element only during an explicit playback gesture.
// This is silent PCM, not an autoplay bypass or a second hidden player.
export class AudioGesture {
 private marker='';
 get active(){return this.marker!=='';}
 owns(audio:HTMLMediaElement){return this.active&&audio.getAttribute('src')===this.marker;}
 prime(audio:HTMLMediaElement){
  if(!navigator.userActivation?.isActive||audio.getAttribute('src'))return;
  const buffer=new ArrayBuffer(46),view=new DataView(buffer);
  const text=(offset:number,value:string)=>[...value].forEach((char,index)=>view.setUint8(offset+index,char.charCodeAt(0)));
  text(0,'RIFF');view.setUint32(4,38,true);text(8,'WAVE');text(12,'fmt ');view.setUint32(16,16,true);view.setUint16(20,1,true);view.setUint16(22,1,true);view.setUint32(24,8000,true);view.setUint32(28,16000,true);view.setUint16(32,2,true);view.setUint16(34,16,true);text(36,'data');view.setUint32(40,2,true);
  const marker=URL.createObjectURL(new Blob([buffer],{type:'audio/wav'}));this.marker=marker;audio.src=marker;
  void audio.play().then(()=>{if(this.owns(audio))audio.pause();}).catch(()=>{}).finally(()=>URL.revokeObjectURL(marker));
 }
}
