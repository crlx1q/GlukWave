import re,json,hashlib
from pathlib import Path
root=Path('apps/native/lib')
files=list((root/'ui').glob('*.dart'))+[root/'core'/'controller.dart',root/'core'/'api.dart',root/'core'/'models.dart',root/'core'/'appearance.dart',root/'services'/'audio.dart',root/'services'/'cache.dart',root/'services'/'desktop.dart',root/'services'/'push.dart',root/'services'/'ambience.dart',root/'main.dart']

def string_end(s,i):
 q=s[i]; j=i+1; parts=[]; exprs=[]; start=j
 while j<len(s):
  if s[j]=='\\':j+=2;continue
  if s[j]==q:
   parts.append(s[start:j]);return j+1,parts,exprs
  if s[j]=='$':
   if j+1<len(s) and s[j+1]=='{':
    k=j+2;level=1
    while k<len(s) and level:
     if s[k] in "'\"":k=string_end(s,k)[0];continue
     if s[k]=='{':level+=1
     if s[k]=='}':level-=1
     k+=1
    parts.append(s[start:j]);exprs.append(s[j+2:k-1]);j=k;start=j;continue
   m=re.match(r'\$([A-Za-z_][\w]*)',s[j:])
   if m:
    parts.append(s[start:j]);exprs.append(m.group(1));j+=len(m.group(0));start=j;continue
  j+=1
 return j,parts,exprs

def tokens(s):
 i=0
 while i<len(s):
  if s.startswith('//',i):
   n=s.find('\n',i);i=len(s) if n<0 else n+1;continue
  if s.startswith('/*',i):
   n=s.find('*/',i+2);i=len(s) if n<0 else n+2;continue
  if s[i] in "'\"":
   end,parts,exprs=string_end(s,i)
   yield i,end,parts,exprs
   i=end;continue
  i+=1

def phrase(parts,exprs):
 return ''.join(part+(('{p'+str(i)+'}') if i<len(exprs) else '') for i,part in enumerate(parts)).replace('\\n','\n').replace("\\'", "'").replace('\\"','"')

def all_phrases(s):
 for st,end,parts,exprs in tokens(s):
  p=phrase(parts,exprs)
  if re.search('[А-Яа-яёІіӘәҒғҚқҢңӨөҰұҮү]',p):
   yield p
  for expression in exprs:
   yield from all_phrases(expression)

if __name__=='__main__':
 out=Path('apps/native/tool/catalog_source.json')
 catalog=json.loads(out.read_text(encoding='utf-8')) if out.exists() else {}
 for f in files:
  s=f.read_text(encoding='utf-8-sig')
  for p in all_phrases(s):
   key='native.'+hashlib.sha1(p.encode()).hexdigest()[:10]
   path=str(f.relative_to(root))
   entries=catalog.setdefault(key,{'ru':p,'files':[]})['files']
   if path not in entries:entries.append(path)
 out.write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
 print(len(catalog))
 for i,(key,v) in enumerate(catalog.items()):print(f'{i:03}|{key}|'+v['ru'].replace('\n',' / '))
