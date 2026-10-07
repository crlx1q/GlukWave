const catalogs={
  en:{likedTracks:'Liked tracks',likedVideos:'Liked videos',importedTracks:'Imported tracks',importedMusic:'Imported music',roomJoined:'{name} joined the room'},
  ru:{likedTracks:'Любимые треки',likedVideos:'Понравившиеся видео',importedTracks:'Импортированные треки',importedMusic:'Импортированная музыка',roomJoined:'{name} присоединился к комнате'},
  kk:{likedTracks:'Ұнаған тректер',likedVideos:'Ұнаған бейнелер',importedTracks:'Импортталған тректер',importedMusic:'Импортталған музыка',roomJoined:'{name} бөлмеге қосылды'},
  uk:{likedTracks:'Улюблені треки',likedVideos:'Вподобані відео',importedTracks:'Імпортовані треки',importedMusic:'Імпортована музика',roomJoined:'{name} приєднався до кімнати'},
  de:{likedTracks:'Lieblingstitel',likedVideos:'Videos mit „Gefällt mir“',importedTracks:'Importierte Titel',importedMusic:'Importierte Musik',roomJoined:'{name} ist dem Raum beigetreten'},
  es:{likedTracks:'Pistas favoritas',likedVideos:'Vídeos que te gustan',importedTracks:'Pistas importadas',importedMusic:'Música importada',roomJoined:'{name} se ha unido a la sala'},
};

export function systemText(key,language='en',values={}){
  const template=catalogs[language]?.[key]??catalogs.en[key]??key;
  return template.replace(/\{(\w+)\}/g,(_,name)=>String(values[name]??`{${name}}`));
}

export function notificationFor(message,language){
  const {kind,values,...payload}=message;
  return kind==='room.join'?{...payload,body:systemText('roomJoined',language,values)}:payload;
}
