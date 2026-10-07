import fs from 'node:fs/promises';
const edit=async(name,fn)=>{const path=`apps/web/src/${name}`;await fs.writeFile(path,fn(await fs.readFile(path,'utf8')));};
await edit('auth.tsx',v=>v.replace("store.setUser(result.user);if(mode==='register'&&getLanguageChoice()!=='auto')await store.saveSettings({language:getLanguageChoice()});store.notify(t('copy.225'));","store.setUser(result.user);store.notify(t('copy.225'));").replace("store.setUser(result.user);store.notify(mode==='register'?","store.setUser(result.user);if(mode==='register'&&getLanguageChoice()!=='auto')await store.saveSettings({language:getLanguageChoice()});store.notify(mode==='register'?"));
await edit('locale.tsx',v=>v.replace("value.split('-')[0]","value.split('-')[0].toLowerCase()"));
await edit('main.tsx',v=>v.replace("location.pathname.startsWith('/app')","(location.pathname==='/app'||location.pathname.startsWith('/app/'))"));
