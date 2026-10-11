function random(index:number){const n=Math.sin(index*127.1+311.7)*43758.5453123;return n-Math.floor(n);}
export function ribbonSeeds(count:number){const values=new Float32Array(count*4);for(let i=0;i<count;i++)values.set([random(i*4),random(i*4+1)*2-1,random(i*4+2)*1000,random(i*4+3)],i*4);return values;}

/** The same sparse detached subset is drawn by GPU, Canvas and Flutter. */
export function ribbonDrift(seed:number,phase:number,energy:number,influence:number){if(seed%13>=1)return {x:0,y:0};const drift=.5+.5*Math.sin(seed*.61+phase*.14);return {x:Math.sin(seed*.37+phase*.11)*(.004+drift*.012),y:(seed%2<1?-1:1)*(.024+drift*.072+energy*.022+influence*.018)};}
