import fs from 'node:fs/promises';
import ts from 'typescript';
const inventory=JSON.parse(await fs.readFile('apps/web/qa/copy-inventory.json','utf8'));
const index=new Map(inventory.strings.map(row=>[row.text,row.key]));
const templates=new Map();
const files=[...new Set(inventory.strings.flatMap(row=>row.locations.map(item=>item.file)))];
const signature=node=>node.head.text+node.templateSpans.map((span,index)=>`{v${index}}${span.literal.text}`).join('');
for(const name of files){const path=`apps/web/src/${name}`,source=await fs.readFile(path,'utf8'),ast=ts.createSourceFile(path,source,ts.ScriptTarget.Latest,true);const walk=node=>{if(ts.isTemplateExpression(node)&&/[А-Яа-яЁё]/.test(node.head.text+node.templateSpans.map(span=>span.literal.text).join(''))){const text=signature(node);if(!templates.has(text))templates.set(text,`template.${String(templates.size+1).padStart(3,'0')}`);}ts.forEachChild(node,walk);};walk(ast);}
await fs.writeFile('apps/web/qa/template-inventory.json',JSON.stringify([...templates].map(([text,key])=>({key,text})),null,2));
if(process.argv.includes('--inspect')){console.log([...templates].map(([text,key])=>`${key}|${text}`).join('\n'));process.exit();}
for(const name of files){const path=`apps/web/src/${name}`,source=await fs.readFile(path,'utf8'),ast=ts.createSourceFile(path,source,ts.ScriptTarget.Latest,true);
 const rewrite=(node)=>{const edits=[];const walk=node=>{
  if(ts.isTemplateExpression(node)&&templates.has(signature(node))){const values=node.templateSpans.map((span,i)=>`v${i}: ${rewrite(span.expression)}`).join(', ');edits.push({start:node.getStart(ast),end:node.end,text:`t('${templates.get(signature(node))}', {${values}})`});return;}
  if(ts.isJsxText(node)){const text=node.text.trim().replace(/\s+/g,' '),key=index.get(text);if(key){const before=/^[ \t]+\S/.test(node.text)?"{' '}" : '',after=/\S[ \t]+$/.test(node.text)?"{' '}" : '';edits.push({start:node.pos,end:node.end,text:`${before}{t('${key}')}${after}`});return;}}
  if((ts.isStringLiteral(node)||ts.isNoSubstitutionTemplateLiteral(node))&&index.has(node.text)){const key=index.get(node.text),call=`t('${key}')`;edits.push({start:node.getStart(ast),end:node.end,text:ts.isJsxAttribute(node.parent)?`{${call}}`:call});return;}
  ts.forEachChild(node,walk);
 };walk(node);let value=source.slice(node.getStart(ast),node.end);const start=node.getStart(ast);for(const edit of edits.sort((a,b)=>b.start-a.start))value=value.slice(0,edit.start-start)+edit.text+value.slice(edit.end-start);return value;};
 let value=rewrite(ast);if(value!==source)value=`import { t${name.endsWith('.tsx')?', useLocale':''} } from './locale';\n${value}`;
 // Every function component subscribes to locale, including leaf controls; providers stay mounted.
 if(name.endsWith('.tsx')){const parsed=ts.createSourceFile(path,value,ts.ScriptTarget.Latest,true),insertions=[];const walk=node=>{if(ts.isFunctionDeclaration(node)&&node.name&&/^[A-Z]/.test(node.name.text)&&node.body)insertions.push(node.body.getStart(parsed)+1);ts.forEachChild(node,walk);};walk(parsed);for(const pos of insertions.sort((a,b)=>b-a))value=value.slice(0,pos)+'useLocale();'+value.slice(pos);}
 await fs.writeFile(path,value);
}
console.log(`Migrated ${files.length} modules and ${templates.size} interpolated messages.`);
