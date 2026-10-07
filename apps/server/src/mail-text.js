const copy={
  en:{verify:'Verify your GlukWave email',reset:'Reset your GlukWave password',verifyAction:'verify your email address',resetAction:'set a new password',expiry:'This link expires in 30 minutes.',sent:'If an account exists, an email has been sent.'},
  ru:{verify:'Подтверди почту GlukWave',reset:'Сброс пароля GlukWave',verifyAction:'подтверди свой адрес',resetAction:'задай новый пароль',expiry:'Ссылка действует 30 минут.',sent:'Если аккаунт существует, письмо отправлено.'},
  kk:{verify:'GlukWave поштаңызды растаңыз',reset:'GlukWave құпиясөзін қалпына келтіру',verifyAction:'поштаңызды растаңыз',resetAction:'жаңа құпиясөз орнатыңыз',expiry:'Сілтеме 30 минут жарамды.',sent:'Аккаунт бар болса, хат жіберілді.'},
  uk:{verify:'Підтвердьте пошту GlukWave',reset:'Скидання пароля GlukWave',verifyAction:'підтвердьте свою адресу',resetAction:'задайте новий пароль',expiry:'Посилання діє 30 хвилин.',sent:'Якщо обліковий запис існує, лист надіслано.'},
  de:{verify:'Bestätige deine GlukWave-E-Mail',reset:'GlukWave-Passwort zurücksetzen',verifyAction:'bestätige deine E-Mail-Adresse',resetAction:'lege ein neues Passwort fest',expiry:'Dieser Link ist 30 Minuten gültig.',sent:'Falls ein Konto vorhanden ist, wurde eine E-Mail gesendet.'},
  es:{verify:'Verifica tu correo de GlukWave',reset:'Restablece tu contraseña de GlukWave',verifyAction:'verifica tu correo',resetAction:'establece una nueva contraseña',expiry:'Este enlace caduca en 30 minutos.',sent:'Si existe una cuenta, se ha enviado un correo.'},
};
export function accountMail(user,type,link,language='en'){const text=copy[language]||copy.en;return {subject:type==='verify'?text.verify:text.reset,text:`${user.displayName}, ${type==='verify'?text.verifyAction:text.resetAction}: ${link}\n${text.expiry}`};}
export const resetConfirmation=language=>(copy[language]||copy.en).sent;
