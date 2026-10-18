import {z} from 'zod';
import {fail} from './util.js';
import {genreKey} from './recommendations.js';

const base={id:z.string().regex(/^[\w-]{1,80}$/)};
export const homePinsSchema=z.array(z.discriminatedUnion('type',[
  z.object({...base,type:z.literal('likes')}).strict(),
  z.object({...base,type:z.literal('playlist'),playlistId:z.string().min(1).max(200)}).strict(),
  z.object({...base,type:z.literal('mix'),genre:z.string().trim().min(1).max(40).transform(genreKey),mood:z.enum(['personal','energy','happy','calm','sad','focus','dream']).default('personal')}).strict(),
])).max(12).refine(values=>new Set(values.map(x=>x.id)).size===values.length,'Duplicate pin identity');
export async function validateHomePins(store,uid,pins){
  for(const pin of pins||[]){
    if(pin.type!=='playlist')continue;
    const playlist=await store.get('playlists',pin.playlistId);
    if(!playlist||playlist.ownerId!==uid)fail(403,'PLAYLIST_FORBIDDEN','Закрепляй свои плейлисты.');
  }
}
