import {readdirSync,readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {parse} from 'acorn';

const directory=new URL('../dist/assets/',import.meta.url);
const chunks=readdirSync(directory).filter(name=>name.endsWith('.js')&&name.includes('-legacy-'));
if(chunks.length<3)throw Error('Legacy entry/polyfills/shared chunks were not emitted');
const files=chunks.map(name=>{
 const code=readFileSync(new URL(name,directory),'utf8');
 parse(code,{ecmaVersion:5});
 return {name,bytes:Buffer.byteLength(code),sha256:createHash('sha256').update(code).digest('hex')};
});
const html=readFileSync(new URL('../dist/index.html',import.meta.url),'utf8');
if(!html.includes('vite-legacy-entry')||!html.includes('vite-legacy-polyfill')||!html.includes('gw-boot'))throw Error('Startup recovery or legacy loader is missing');
const proof={checkedAt:new Date().toISOString(),passed:true,es5Parsed:true,physicalTvVerified:false,files};
if(process.argv[2])writeFileSync(process.argv[2],JSON.stringify(proof,null,2)+'\n');
console.log(JSON.stringify({passed:true,es5Chunks:files.length}));
