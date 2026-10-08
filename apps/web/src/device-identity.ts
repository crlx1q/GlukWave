const key='glukwave-installation';
function installation(){
  try {const saved=localStorage.getItem(key);if(saved&&/^[\w-]{1,100}$/.test(saved))return saved;
    const value=crypto.randomUUID();localStorage.setItem(key,value);return value;
  }catch{return crypto.randomUUID();}
}
// Tabs share an installation but keep their own output ownership.
export const deviceId=installation();
export const surfaceId=crypto.randomUUID();
