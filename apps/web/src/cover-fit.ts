/** Project every face and the fully extended disc into the stage's perspective. */
export function coverBounds(size:number,x:number,y:number) {
 const rx=x*Math.PI/180,ry=y*Math.PI/180,cx=Math.cos(rx),sx=Math.sin(rx),cy=Math.cos(ry),sy=Math.sin(ry),points:{x:number;y:number}[]=[];
 for(const [left,right,top,bottom,z] of [[-.5,.5,-.5,.5,5],[-.5,.5,-.5,.5,-5],[-.14,.86,-.5,.5,0]])
  for(const xx of [left*size,right*size])for(const yy of [top*size,bottom*size]){
   const tx=cy*xx+sy*z,tz=-sy*xx+cy*z,ty=cx*yy-sx*tz,depth=sx*yy+cx*tz,projection=1200/(1200-depth);
   points.push({x:tx*projection-.14*size,y:ty*projection});
  }
 return {left:Math.min(...points.map(p=>p.x)),right:Math.max(...points.map(p=>p.x)),top:Math.min(...points.map(p=>p.y)),bottom:Math.max(...points.map(p=>p.y))};
}

export function fitCover(width:number,height:number,threeD:boolean,x:number,y:number) {
 if(!width||!height)return 0;
 const padding=12,limit=Math.max(0,Math.min(340,width-padding*2,height-padding*2));
 if(!threeD)return limit;
 // The existing idle animation adds a small rotation/vertical drift; reserve it.
 const fits=(size:number)=>[-2,0,2].every(dx=>[-5,0,5].every(dy=>{const b=coverBounds(size,x+dx,y+dy);return b.left>=-width/2+padding&&b.right<=width/2-padding&&b.top>=-height/2+padding+4&&b.bottom<=height/2-padding;}));
 let low=0,high=limit;for(let i=0;i<16;i++){const mid=(low+high)/2;if(fits(mid))low=mid;else high=mid;}
 return Math.floor(low*100)/100;
}
