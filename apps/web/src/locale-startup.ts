const codes=['en','ru','kk','uk','de','es'];
export function preferenceStorage():Pick<Storage,'getItem'>{try{return localStorage;}catch{return {getItem:()=>null};}}
export function startupAccountId(storage:Pick<Storage,'getItem'>):string|null{
 try{const value=JSON.parse(storage.getItem('gw-user')||'null')?.id;return typeof value==='string'&&value.length>0&&value.length<=200?value:null;}catch{return null;}
}
/** Cached identity selects preferences only; it never authenticates a user or grants access. */
export function startupLanguageChoice(storage:Pick<Storage,'getItem'>):string{
 try{
  const id=startupAccountId(storage);
  const choice=(value:unknown)=>value==='auto'||codes.includes(String(value));
  if(id){for(const key of [`gw-settings-pending:${id}`,`gw-settings:${id}`]){const language=JSON.parse(storage.getItem(key)||'null')?.language;if(choice(language))return language;}}
  const saved=storage.getItem('gw-language-choice');return choice(saved)?saved!:'auto';
 }catch{return 'auto';}
}
export function startupAutomaticLanguage(storage:Pick<Storage,'getItem'>,fallback:string):{language:string;country:string|null;source:'ip'|'browser'|'default'}{
 try{const value=JSON.parse(storage.getItem('gw-language-auto')||'null');if(codes.includes(value?.language)&&['ip','browser','default'].includes(value.source)&&Date.now()-value.savedAt<7*86400000&&value.savedAt<=Date.now())return {language:value.language,country:/^[A-Z]{2}$/.test(value.country)?value.country:null,source:value.source};}catch{/* Browser language remains available. */}
 return {language:fallback,country:null,source:'browser'};
}
