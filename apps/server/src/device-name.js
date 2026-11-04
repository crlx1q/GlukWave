// Older Flutter builds sent a double-decoded UTF-8 middle dot.
export function normalizeDeviceName(name){
  return typeof name==='string'
    ? name.replace(/^GlukWave Р\sвЂ™Р’В· (Windows|Android|iOS)$/u,'GlukWave \u00b7 $1')
    : name;
}
