import fs from 'node:fs/promises';
import { click,evaluate,fill,open,snapshot,wait } from './browser.mjs';
const [email='qa@example.test',language='en']=process.argv.slice(2);
if(!email.endsWith('@example.test'))throw new Error('Use isolated QA accounts only.');
open('http://127.0.0.1:4100/app/#library');wait(`!!document.querySelector('main h1')`);
if(!evaluate(`!!localStorage.getItem('gw-user')`)){
 const locale=evaluate(`document.documentElement.lang`),copy=JSON.parse(await fs.readFile(`apps/web/src/locales/${locale}.json`,'utf8'));
 click(copy['copy.204']);fill('textbox',copy['copy.249'],email);fill('textbox',copy['copy.250'],'Local-qa-passphrase-2026');click(copy['copy.254']);wait(`!!localStorage.getItem('gw-user')&&!document.querySelector('.auth-form')`);
}
wait(`document.documentElement.lang==='${language}'`);console.log(snapshot().snapshot);
