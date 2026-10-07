import path from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {MongoClient} from 'mongodb';

export async function openStore(config) {
  if(config.storage==='mongo') {
    const client=new MongoClient(config.mongoUri);await client.connect();const db=client.db(config.mongoDb);
    await db.collection('users').createIndex({email:1},{unique:true});
    await db.collection('users').createIndex({username:1},{unique:true});
    return {
      kind:'mongo',
      async get(c,id){const d=await db.collection(c).findOne({_id:id});if(!d)return null;const {_id,_v,...value}=d;return value;},
      async list(c,filter=()=>true){return (await db.collection(c).find({}).limit(10000).toArray()).map(({_id,_v,...d})=>d).filter(filter);},
      async entries(c){return (await db.collection(c).find({}).toArray()).map(({_id,_v,...value})=>({id:_id,value}));},
      async create(c,id,value){await db.collection(c).insertOne({_id:id,_v:0,...value});return value;},
      async put(c,id,value){await db.collection(c).replaceOne({_id:id},{_id:id,_v:0,...value},{upsert:true});return value;},
      async remove(c,id){await db.collection(c).deleteOne({_id:id});},
      async update(c,id,fn){for(let n=0;n<10;n++){const original=await db.collection(c).findOne({_id:id});const {_id,_v=0,...value}=original||{};const next=await fn(original?value:null);if(next===undefined)return value;if(!original){try{await db.collection(c).insertOne({_id:id,_v:0,...next});return next;}catch(err){if(err.code!==11000)throw err;continue;}}const result=await db.collection(c).replaceOne({_id:id,_v},{_id:id,_v:_v+1,...next});if(result.modifiedCount)return next;}throw new Error('Concurrent update failed');},
      async close(){await client.close();},
    };
  }
  const db=new DatabaseSync(path.join(config.dataDir,'glukwave.sqlite'));
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; CREATE TABLE IF NOT EXISTS documents (collection TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(collection,id)); CREATE UNIQUE INDEX IF NOT EXISTS unique_email ON documents(json_extract(body,'$.email')) WHERE collection='users'; CREATE UNIQUE INDEX IF NOT EXISTS unique_username ON documents(json_extract(body,'$.username')) WHERE collection='users';`);
  const get=db.prepare('SELECT body FROM documents WHERE collection=? AND id=?');
  const list=db.prepare('SELECT body FROM documents WHERE collection=?');
  const put=db.prepare('INSERT INTO documents(collection,id,body) VALUES(?,?,?) ON CONFLICT(collection,id) DO UPDATE SET body=excluded.body');
  const create=db.prepare('INSERT INTO documents(collection,id,body) VALUES(?,?,?)');
  const remove=db.prepare('DELETE FROM documents WHERE collection=? AND id=?');
  let tail=Promise.resolve();
  const lock=async fn=>{const next=tail.then(fn,fn);tail=next.catch(()=>{});return next;};
  return {
    kind:'sqlite',
    async get(c,id){const r=get.get(c,id);return r?JSON.parse(r.body):null;},
    async list(c,filter=()=>true){return list.all(c).map(r=>JSON.parse(r.body)).filter(filter);},
    async entries(c){return db.prepare('SELECT id,body FROM documents WHERE collection=?').all(c).map(r=>({id:r.id,value:JSON.parse(r.body)}));},
    async create(c,id,value){create.run(c,id,JSON.stringify(value));return value;},
    async put(c,id,value){return lock(()=>{put.run(c,id,JSON.stringify(value));return value;});},
    async remove(c,id){return lock(()=>remove.run(c,id));},
    async update(c,id,fn){return lock(async()=>{const r=get.get(c,id);const next=await fn(r?JSON.parse(r.body):null);if(next!==undefined)put.run(c,id,JSON.stringify(next));return next;});},
    async close(){await tail;db.close();},
  };
}
