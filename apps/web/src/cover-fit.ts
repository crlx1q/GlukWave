/** Project every face and the fully extended disc into the stage's perspective. */
export function coverBounds(size:number,x:number,y:number) {
 const rx=x*Math.PI/180,ry=y*Math.PI/180,cx=Math.cos(rx),sx=Math.sin(rx),cy=Math.cos(ry),sy=Math.sin(ry),points:{x:number;y:number}[]=[];
 const geometry:[number,number,number][]=[];
 for(const z of [9,-9])for(const xx of [-.5,.5])for(const yy of [-.5,.5])geometry.push([xx*size,yy*size,z]);
 // A round record has no square corners. Sampling its true circular edge avoids
 // reserving imaginary corners that made the original front needlessly small.
 for(let a=0;a<Math.PI*2;a+=Math.PI/24)geometry.push([(.56+.47*Math.cos(a))*size,.47*Math.sin(a)*size,0]);
 for(const [xx,yy,z]of geometry){
   const tx=cy*xx+sy*z,tz=-sy*xx+cy*z,ty=cx*yy-sx*tz,depth=sx*yy+cx*tz,projection=1100/(1100-depth);
   points.push({x:tx*projection-.12*size*cy,y:ty*projection});
  }
 return {left:Math.min(...points.map(p=>p.x)),right:Math.max(...points.map(p=>p.x)),top:Math.min(...points.map(p=>p.y)),bottom:Math.max(...points.map(p=>p.y))};
}

export function fitCover(width:number,height:number,threeD:boolean,x:number,y:number) {
 // Size follows the available viewport once. Angle never changes the stage or the artwork.
 void x;void y;
 if(!width)return 0;
 const widthLimit=Math.min(340,Math.max(0,width-24)/(threeD?1.5:1));
 if(height<=0)return Math.floor(widthLimit*100)/100;
 if(!threeD)return Math.max(0,Math.min(widthLimit,height-36));
 let low=0,high=widthLimit;
 for(let i=0;i<11;i++){const middle=(low+high)/2;if(coverEnvelopeHeight(middle)<=height)low=middle;else high=middle;}
 return Math.floor(low*100)/100;
}

const envelopes=new Map<number,number>();
/** One constant envelope for a complete turn, including the extended disc and tilted cover. */
export function coverEnvelopeHeight(size:number){
 const key=Math.ceil(size),cached=envelopes.get(key);if(cached!==undefined)return cached;
 let extent=size;
 for(let x=-38;x<=38;x+=2)for(let y=-180;y<=180;y+=5){const bounds=coverBounds(key,x,y);extent=Math.max(extent,2*Math.max(Math.abs(bounds.top),Math.abs(bounds.bottom)));}
 const height=Math.ceil(extent+24);envelopes.set(key,height);if(envelopes.size>64)envelopes.delete(envelopes.keys().next().value!);return height;
}

/** Reserve actual projected height without changing the artwork dimensions. */
export function coverSceneHeight(size:number,bounds?:ReturnType<typeof coverBounds>){return Math.ceil(Math.max(size+36,bounds?2*Math.max(Math.abs(bounds.top),Math.abs(bounds.bottom))+60:0));}
