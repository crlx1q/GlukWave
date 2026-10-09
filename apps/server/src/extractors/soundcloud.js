export const soundcloudAdapter=runtime=>({id:'soundcloud',metadata:url=>runtime.execute('soundcloud',{action:'extract',source:'soundcloud',url})});
