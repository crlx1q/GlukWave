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
 // Height and current angle deliberately do not affect artwork size. Short screens scroll.
 void height;void x;void y;
 if(!width)return 0;
 return Math.floor(Math.min(340,Math.max(0,width-24)/(threeD?1.62:1))*100)/100;
}

/** Reserve actual projected height without changing the artwork dimensions. */
export function coverSceneHeight(size:number,bounds?:ReturnType<typeof coverBounds>){return Math.ceil(Math.max(size+36,bounds?bounds.bottom-bounds.top+60:0));}
