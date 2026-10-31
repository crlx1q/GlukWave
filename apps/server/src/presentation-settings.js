import {z} from 'zod';
import {fail} from './util.js';

const color=z.string().regex(/^#[0-9a-f]{6}$/i).transform(value=>value.toLowerCase());
const colors=z.object({bg:color,surface:color,ink:color,accent:color}).strict();
export const wallpaperSchema=z.object({url:z.string().max(200).regex(/^(?:|\/api\/profile-assets\/[\w-]+)$/).optional(),dim:z.number().finite().min(0).max(.9).optional(),blur:z.number().finite().min(0).max(24).optional()}).strict();
export const savedThemesSchema=z.array(z.object({id:z.string().regex(/^[\w-]{1,80}$/),name:z.string().trim().min(1).max(40),mode:z.enum(['light','dark']),colors}).strict()).max(12).superRefine((rows,ctx)=>{if(new Set(rows.map(row=>row.id)).size!==rows.length)ctx.addIssue({code:'custom',message:'Theme identifiers must be unique'});});

export async function validateWallpaper(store,userId,wallpaper){
  if(!wallpaper?.url)return;
  const asset=await store.get('assets',wallpaper.url.split('/').at(-1));
  if(!asset||asset.ownerId!==userId||asset.kind!=='wallpaper')fail(403,'WALLPAPER_FORBIDDEN','Выбери свои загруженные обои.');
}
