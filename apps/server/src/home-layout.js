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

// Sizes are logical spans. Each client resolves them against its available
// columns so the same account layout remains usable on a phone and desktop.
const widgetBase={
  ...base,
  size:z.enum(['small','medium','large']),
  view:z.enum(['cards','list','compact']),
};
export const homeWidgetTypes=['wave','playlists','recent','recommendations','discovery','popular','daily','likes','playlist','mix'];
const singletonTypes=new Set(homeWidgetTypes.slice(0,7));
export const homeLayoutSchema=z.object({
  version:z.literal(1),
  widgets:z.array(z.discriminatedUnion('type',[
    ...[...singletonTypes,'likes'].map(type=>z.object({...widgetBase,type:z.literal(type)}).strict()),
    z.object({...widgetBase,type:z.literal('playlist'),playlistId:z.string().min(1).max(200)}).strict(),
    z.object({...widgetBase,type:z.literal('mix'),genre:z.string().trim().min(1).max(40).transform(genreKey),mood:z.enum(['personal','energy','happy','calm','sad','focus','dream']).default('personal')}).strict(),
  ])).max(20).superRefine((widgets,ctx)=>{
    const identities=new Set(),singletons=new Set();
    widgets.forEach((widget,index)=>{
      if(identities.has(widget.id))ctx.addIssue({code:'custom',path:[index,'id'],message:'Duplicate widget identity'});
      identities.add(widget.id);
      if(singletonTypes.has(widget.type)){
        if(singletons.has(widget.type))ctx.addIssue({code:'custom',path:[index,'type'],message:'Duplicate home section'});
        singletons.add(widget.type);
      }
    });
  }),
}).strict().nullable();

export async function validateHomeLayout(store,uid,layout){
  if(!layout)return;
  for(const widget of layout.widgets){
    if(widget.type!=='playlist')continue;
    const playlist=await store.get('playlists',widget.playlistId);
    if(!playlist||playlist.ownerId!==uid)fail(403,'PLAYLIST_FORBIDDEN','Добавляй на главную свои плейлисты.');
  }
}
