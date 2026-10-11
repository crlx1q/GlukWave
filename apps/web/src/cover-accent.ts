/** A bounded chromatic sample, independent of transport and persisted palettes. */
export function sampleCoverAccent(pixels:ArrayLike<number>):string|null {
 const bins=Array.from({length:12},()=>({weight:0,r:0,g:0,b:0}));
 for(let i=0;i+3<pixels.length;i+=4){const r=pixels[i]/255,g=pixels[i+1]/255,b=pixels[i+2]/255,max=Math.max(r,g,b),min=Math.min(r,g,b),delta=max-min;if(pixels[i+3]<180||max<.12||min>.9||delta<.10)continue;let h=max===r?(g-b)/delta:max===g?(b-r)/delta+2:(r-g)/delta+4;h=((h/6)%1+1)%1;const weight=delta*(.4+max*.6),bin=bins[Math.floor(h*12)%12];bin.weight+=weight;bin.r+=r*weight;bin.g+=g*weight;bin.b+=b*weight;}
 const best=bins.reduce((a,b)=>a.weight>b.weight?a:b);return best.weight<1?null:'#'+[best.r,best.g,best.b].map(value=>Math.round(value/best.weight*255).toString(16).padStart(2,'0')).join('');
}
const rgb=(hex:string)=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255);
const luminance=(c:number[])=>c.map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);
export function readableCoverAccent(sample:string|null,background:string,fallback:string,highContrast=false):string {
 if(!sample)return fallback;const c=rgb(sample),base=luminance(rgb(background)),dark=base<.25,target=highContrast?4.5:3;
 for(let i=0;i<=20;i++){const mix=i/20*.85,tone=c.map(v=>v*(1-mix)+(dark?1:0)*mix),lum=luminance(tone);if((Math.max(base,lum)+.05)/(Math.min(base,lum)+.05)>=target)return '#'+tone.map(v=>Math.round(v*255).toString(16).padStart(2,'0')).join('');}return fallback;
}
const cache=new Map<string,string|null>();
/** Never decode a full image into canvas; provider covers use our authenticated proxy. */
export function readCoverAccent(url:string,key:string,signal:AbortSignal):Promise<string|null> {
 if(cache.has(key))return Promise.resolve(cache.get(key)!);
 return new Promise(resolve=>{const picture=new Image();let done=false;const finish=(tone:string|null)=>{if(done)return;done=true;clearTimeout(timer);picture.onload=null;picture.onerror=null;signal.removeEventListener('abort',abort);picture.src='';if(!signal.aborted){cache.set(key,tone);if(cache.size>32)cache.delete(cache.keys().next().value!);}resolve(tone);};const abort=()=>finish(null),timer=setTimeout(()=>finish(null),5000);signal.addEventListener('abort',abort,{once:true});picture.crossOrigin='anonymous';picture.onload=()=>{try{const canvas=document.createElement('canvas');canvas.width=16;canvas.height=16;const context=canvas.getContext('2d',{willReadFrequently:true});if(!context){finish(null);return;}context.drawImage(picture,0,0,16,16);finish(sampleCoverAccent(context.getImageData(0,0,16,16).data));}catch{finish(null);}};picture.onerror=()=>finish(null);if(signal.aborted)abort();else picture.src=url;});
}
