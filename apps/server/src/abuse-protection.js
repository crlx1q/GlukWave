import {digest,HttpError} from './util.js';

const policies={
  authNetwork:{capacity:80,perSecond:1},authAttempt:{capacity:12,perSecond:.2},
  message:{capacity:14,perSecond:.75,duplicateWindow:30000},
  comment:{capacity:10,perSecond:.2,duplicateWindow:60000},
  creation:{capacity:40,perSecond:.5},social:{capacity:40,perSecond:.5},
  upload:{capacity:30,perSecond:.5},search:{capacity:60,perSecond:2},
  state:{capacity:120,perSecond:40},control:{capacity:80,perSecond:20},
};
export const normalizedContent=value=>String(value).normalize('NFKC').replace(/[\u200b-\u200d\ufeff]/g,'').replace(/\s+/g,' ').trim().toLowerCase();

/** Per action token budgets allow normal bursts and recover continuously.
 * Store only hashes, never message text, passwords or raw account identifiers.
 * This is a process guard; edge/network limits remain the deployment's job.
 */
export function createAbuseProtection({clock=Date.now,maxEntries=10000}={}){
  const buckets=new Map();let rejected=0;
  function check(action,actor,{content,cost=1}={}){
    const policy=policies[action];if(!policy)throw new Error('Unknown abuse policy');
    const time=clock(),key=digest(action+':'+actor);
    let entry=buckets.get(key)||{tokens:policy.capacity,at:time,duplicates:new Map()};
    entry.tokens=Math.min(policy.capacity,entry.tokens+Math.max(0,time-entry.at)/1000*policy.perSecond);entry.at=time;
    let fingerprint,duplicate,weight=cost;
    if(content!==undefined&&policy.duplicateWindow){
      const text=normalizedContent(content);fingerprint=digest(text);
      for(const [hash,row] of entry.duplicates)if(time-row.at>=policy.duplicateWindow)entry.duplicates.delete(hash);
      duplicate=entry.duplicates.get(fingerprint);
      // Short conversational replies can repeat; pasted paragraphs and links
      // across rooms/tracks are a much stronger abuse signal.
      const limit=text.length<24&&!/https?:\/\//.test(text)?5:2;
      if(duplicate?.count>=limit){
        rejected++;throw new HttpError(429,'DUPLICATE_CONTENT','Это сообщение уже отправлено. Не повторяй его несколько раз.',{action,retryAfter:Math.max(1,Math.ceil((policy.duplicateWindow-(time-duplicate.at))/1000))});
      }
      weight+=Math.min(3,(text.match(/https?:\/\//g)||[]).length);
    }
    if(entry.tokens<weight){rejected++;throw new HttpError(429,'ABUSE_LIMIT','Слишком много одинаковых действий. Попробуй чуть позже.',{action,retryAfter:Math.max(1,Math.ceil((weight-entry.tokens)/policy.perSecond))});}
    entry.tokens-=weight;
    if(fingerprint)entry.duplicates.set(fingerprint,{count:(duplicate?.count||0)+1,at:duplicate?.at??time});
    buckets.delete(key);buckets.set(key,entry);
    if(buckets.size>maxEntries){for(const [hash,row] of buckets){if(time-row.at>300000)buckets.delete(hash);if(buckets.size<=maxEntries)break;}while(buckets.size>maxEntries)buckets.delete(buckets.keys().next().value);}
  }
  const middleware=action=>(req,res,next)=>{try{check(action,req.auth?.user.id||'ip:'+req.ip);next();}catch(error){res.set('Retry-After',String(error.details.retryAfter));next(error);}};
  const auth=(req,res,next)=>{try{
    check('authNetwork','ip:'+req.ip);
    const identity=String(req.body?.email||req.body?.username||req.auth?.user.id||'challenge').trim().toLowerCase();
    check('authAttempt',req.ip+':'+req.path+':'+digest(identity));next();
  }catch(error){res.set('Retry-After',String(error.details.retryAfter));next(error);}};
  return {check,middleware,auth,stats:()=>({tracked:buckets.size,rejected,maxEntries}),close:()=>buckets.clear()};
}
