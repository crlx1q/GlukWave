"""One-time migration from the recorded Russian copy to stable catalog keys."""
import hashlib,re
from catalog_extract import files,tokens,phrase

def transform(source, context=True):
    edits=[]
    for start,end,parts,expressions in tokens(source):
        text=phrase(parts,expressions)
        values=[transform(value, context) for value in expressions]
        if re.search('[А-Яа-яёІіӘәҒғҚқҢңӨөҰұҮү]',text):
            key='native.'+hashlib.sha1(text.encode()).hexdigest()[:10]
            args=''
            if values:args=', values: {'+', '.join("'p"+str(i)+"': ("+value+")" for i,value in enumerate(values))+'}'
            if context:args+=', context: context'
            edits.append((start,end,f"wt('{key}'{args})"))
        elif values != expressions:
            # Preserve literals that only interpolate a translated expression.
            quote=source[start]
            replacement=quote+''.join(part+('${'+values[i]+'}' if i<len(values) else '') for i,part in enumerate(parts))+quote
            edits.append((start,end,replacement))
    for start,end,value in reversed(edits):source=source[:start]+value+source[end:]
    return source

def remove_dynamic_consts(source):
    ranges=[]
    for match in re.finditer(r'\bconst\s+(?:[\w.]+(?:<[^;]*?>)?\s*)?(?=[\[\{(])',source):
        opener=match.end(); close={'(':')','[':']','{':'}'}; stack=[]; i=opener
        while i<len(source):
            if source[i] in "'\"":
                from catalog_extract import string_end
                i=string_end(source,i)[0];continue
            c=source[i]
            if c in close:stack.append(close[c])
            elif stack and c==stack[-1]:
                stack.pop()
                if not stack:break
            i+=1
        if 'wt(' in source[opener:i]:ranges.append((match.start(),match.start()+6))
    for start,end in reversed(ranges):source=source[:start]+source[end:]
    return source

for file in files:
    source=file.read_text(encoding='utf-8-sig')
    ui='ui' in file.parts
    # Constructor defaults must remain constant; resolve loading copy in build.
    if file.name=='widgets.dart':
        source=source.replace('final String label;\n  const WaveLoadingList','final String? label;\n  const WaveLoadingList')
        source=source.replace("this.label = 'Загружаем музыку',",'this.label,')
        source=source.replace('label: label,\n    liveRegion: true,',"label: label ?? wt('native.e917ac283f', context: context),\n    liveRegion: true,")
    source=transform(source,context=ui)
    if file.name=='app.dart':
        source=source.replace('const pageLabels =','List<String> get pageLabels =>')
        source=source.replace('static const settingsSections =','Map<String, (String, IconData)> get settingsSections =>')
        # Labels at top level have no BuildContext; normal build reads them live.
        start=source.index('List<String> get pageLabels')
        end=source.index('const pageIcons',start)
        source=source[:start]+source[start:end].replace(', context: context','')+source[end:]
    if file.name=='lofi.dart':
        source=source.replace('const lofiScenes =','List<String> get lofiScenes =>')
        start=source.index('List<String> get lofiScenes')
        end=source.index('class LofiPage',start)
        source=source[:start]+source[start:end].replace(', context: context','')+source[end:]
    source=remove_dynamic_consts(source)
    path="../l10n/wave_localizations.dart" if file.name!='main.dart' else 'l10n/wave_localizations.dart'
    if 'wt(' in source and f"import '{path}';" not in source:
        source=f"import '{path}';\n"+source
    file.write_text(source,encoding='utf-8')
    print(file)
