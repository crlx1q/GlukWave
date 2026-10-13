// The 9px thumb travels 125px inside a 134px vertical input. SVG uses 144 units.
export const EQ_EDITOR_GAIN_SCALE=(134-9)/24*144/134;
/** Shape-preserving editor interpolation. Each control stays between its two bands. */
export function equalizerPath(bands:readonly number[],radius:number){
 const points=bands.map((gain,index)=>({x:15+index*30,y:72-Math.max(-12,Math.min(12,gain))*EQ_EDITOR_GAIN_SCALE}));
 if(!points.length)return '';
 const strength=Math.max(0,Math.min(1,radius/24));
 if(!strength)return `M${points.map(point=>`${point.x},${point.y}`).join('L')}`;
 const slopes=points.slice(1).map((point,index)=>(point.y-points[index].y)/30);
 const tangents=points.map((_,index)=>index===0?slopes[0]:index===points.length-1?slopes.at(-1)!:slopes[index-1]*slopes[index]<=0?0:2*slopes[index-1]*slopes[index]/(slopes[index-1]+slopes[index]));
 const round=(value:number)=>Math.round(value*1000)/1000;
 return `M${points[0].x},${points[0].y}`+points.slice(1).map((end,index)=>{
  const start=points[index],difference=end.y-start.y,clamp=(value:number)=>Math.max(Math.min(start.y,end.y),Math.min(Math.max(start.y,end.y),value));
  const first=clamp(start.y+(difference*(1-strength)+tangents[index]*30*strength)/3),second=clamp(end.y-(difference*(1-strength)+tangents[index+1]*30*strength)/3);
  return `C${start.x+10},${round(first)} ${end.x-10},${round(second)} ${end.x},${end.y}`;
 }).join('');
}
