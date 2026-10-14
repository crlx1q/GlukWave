import {seal,unseal,digest} from './util.js';

// Opaque, authenticated capabilities survive cache eviction and another worker.
// Resource URLs stay encrypted; a live session and current media permission are
// still checked by the streaming route before any upstream request.
export function audioCapabilities(key,purpose){
  function open(token,kind){
    if(typeof token!=='string'||token.length>8192)return null;
    try{const value=unseal(token,key);return value.purpose===purpose+':'+kind&&Number.isFinite(value.expiresAt)&&value.expiresAt>Date.now()?value:null;}catch{return null;}
  }
  return {
    issueRoot(value){return seal({...value,purpose:purpose+':root'},key);},
    root(token){const value=open(token,'root');return value&&['trackId','userId','sessionId'].every(k=>typeof value[k]==='string')?value:null;},
    issuePart(token,resource,expiresAt){return seal({purpose:purpose+':part',root:digest(token),resource,expiresAt},key);},
    part(token,part){const value=open(part,'part');return value?.root===digest(token)&&typeof value.resource==='string'&&value.resource.length<=4096?value.resource:null;},
  };
}
