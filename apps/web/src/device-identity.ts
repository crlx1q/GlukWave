const key='glukwave-installation';
function installation(){
  try {const saved=localStorage.getItem(key);if(saved&&/^[\w-]{1,100}$/.test(saved))return saved;
    const value=crypto.randomUUID();localStorage.setItem(key,value);return value;
  }catch{return crypto.randomUUID();}
}
// Tabs share an installation but keep their own output ownership.
export const deviceId=installation();
export const surfaceId=crypto.randomUUID();
export const browserName=navigator.userAgent.includes('Firefox')?'Firefox':navigator.userAgent.includes('Edg')?'Edge':navigator.userAgent.includes('Chrome')?'Chrome':navigator.userAgent.includes('Safari')?'Safari':'Browser';
export const browserDeviceName=`${browserName} · ${navigator.userAgent.includes('Android')?'Android':/iPhone|iPad/.test(navigator.userAgent)?'iOS':navigator.userAgent.includes('Windows')?'Windows':navigator.userAgent.includes('Mac')?'macOS':'Web'}`;
