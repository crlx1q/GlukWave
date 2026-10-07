import {config} from '../apps/server/src/config.js';
import {openStore} from '../apps/server/src/store.js';
const args=process.argv.slice(2),value=flag=>args[args.indexOf(flag)+1];
const from=value('--from'),to=value('--to'),apply=args.includes('--apply');
if(!['sqlite','mongo'].includes(from)||!['sqlite','mongo'].includes(to)||from===to)throw new Error('Usage: npm run migrate -- --from sqlite --to mongo [--apply]');
if(!config.mongoUri)throw new Error('Set MONGODB_URI in .env first. Keep the same TOKEN_ENCRYPTION_KEY.');
const collections=['users','identities','tracks','assets','libraries','playlists','settings','comments','lyrics','rooms','messages','connections','billing','billingEvents','billingCheckouts','audit'];
const source=await openStore({...config,storage:from}),target=await openStore({...config,storage:to});
let copied=0;try {
  for(const collection of collections){const docs=await source.entries(collection);console.log(`${collection}: ${docs.length} documents`);for(const {id:key,value:document} of docs){const existing=await target.get(collection,key);if(existing){if(JSON.stringify(existing)!==JSON.stringify(document))throw new Error(`Destination has a different ${collection}/${key}; no data overwritten.`);continue;}if(apply)await target.create(collection,key,document);copied++;}}
  console.log(`${apply?'Copied':'Dry run would copy'} ${copied} documents. Sessions and pending authorization challenges are excluded. Media original files must be moved separately. ${apply?'':'Add --apply to perform the copy with the server stopped.'}`);
} finally {await source.close();await target.close();}
