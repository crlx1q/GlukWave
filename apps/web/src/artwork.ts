/** Rewrite only image hosts whose size conventions are known. Always retain the original as fallback. */
export function artworkSize(value:string|undefined,large=false){
 if(!value)return value;
 try{
  const url=new URL(value),host=url.hostname.toLowerCase();
  if(host==='sndcdn.com'||host.endsWith('.sndcdn.com'))url.pathname=url.pathname.replace(/-(?:large|small|t\d+x\d+)\.(jpg|jpeg|png|webp)$/i,large?'-t500x500.$1':'-t100x100.$1');
  if(host==='ytimg.com'||host.endsWith('.ytimg.com'))url.pathname=url.pathname.replace(/\/(?:default|mqdefault|hqdefault|sddefault|maxresdefault)\.(jpg|jpeg|webp)$/i,large?'/hqdefault.$1':'/mqdefault.$1');
  return url.href;
 }catch{return value;}
}
