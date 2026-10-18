/* ES5: this screen works before a legacy bundle loads. */
(function () {
  var shell = document.getElementById('gw-boot');
  if (!shell) return;
  var language = (navigator.language || 'en').split('-')[0];
  try {
    var account = JSON.parse(localStorage.getItem('gw-user') || 'null');
    var pending = account && JSON.parse(localStorage.getItem('gw-settings-pending:' + account.id) || 'null');
    var settings = account && JSON.parse(localStorage.getItem('gw-settings:' + account.id) || 'null');
    var choice = (pending && pending.language) || (settings && settings.language) || localStorage.getItem('gw-language-choice');
    if (choice && choice !== 'auto') language = choice;
  } catch (ignored) {}
  if ((!choice || choice === 'auto') && language === 'kk') language = 'ru';
  var tv = /Tizen|SMART-TV|SmartTV/i.test(navigator.userAgent || '');
  var messages = {
    en: ['Opening your music', 'One moment…', 'GlukWave could not load', 'Check the connection and try again.', 'Try again', 'An old TV browser may need an update.'],
    ru: ['Открываем твою музыку', 'Ещё немного…', 'Не удалось открыть GlukWave', 'Проверь соединение и попробуй снова.', 'Попробовать снова', 'Старому браузеру ТВ может понадобиться обновление.'],
    kk: ['Музыкаңды ашып жатырмыз', 'Сәл күте тұр…', 'GlukWave ашылмады', 'Байланысты тексеріп, қайта көр.', 'Қайта көру', 'Ескі ТВ браузерін жаңарту қажет болуы мүмкін.'],
    uk: ['Відкриваємо твою музику', 'Ще трохи…', 'Не вдалося відкрити GlukWave', 'Перевір з’єднання та спробуй ще раз.', 'Спробувати ще', 'Старий браузер ТВ може потребувати оновлення.'],
    de: ['Deine Musik wird geöffnet', 'Einen Moment…', 'GlukWave konnte nicht laden', 'Prüfe die Verbindung und versuche es erneut.', 'Erneut versuchen', 'Ein älterer TV-Browser benötigt eventuell ein Update.'],
    es: ['Abriendo tu música', 'Un momento…', 'No se pudo abrir GlukWave', 'Comprueba la conexión e inténtalo de nuevo.', 'Reintentar', 'El navegador antiguo del televisor puede necesitar una actualización.']
  };
  var text = messages[language] || messages.en;
  document.documentElement.lang = messages[language] ? language : 'en';
  var title = shell.querySelector('h1'), detail = shell.querySelector('p'), retry = shell.querySelector('button');
  title.textContent = ''; detail.textContent = ''; retry.textContent = text[4];
  retry.onclick = function () { location.reload(); };
  function fail() {
    if (!document.getElementById('gw-boot')) return;
    shell.setAttribute('data-failed', 'true');
    title.textContent = text[2]; detail.textContent = text[3] + (tv ? ' ' + text[5] : '');
  }
  var pendingFailure = 0;
  function scriptError(event) {
    var target = event.target;
    // Image/font/API failures do not imply that the application failed to boot.
    // Allow a failed modern branch to recover through the legacy loader before
    // replacing the initial screen. Runtime failures retain the watchdog below.
    if (!target || target.tagName !== 'SCRIPT' || !target.src) return;
    if (!/\/(?:assets\/(?:main|polyfills)-[^/]+\.js|src\/main\.tsx)(?:[?#]|$)/.test(target.src)) return;
    if (pendingFailure) return;
    pendingFailure = setTimeout(fail, 1500);
  }
  var timer = setTimeout(fail, 15000);
  window.addEventListener('error', scriptError, true);
  if (window.MutationObserver) {
    var observer = new MutationObserver(function () {
      if (document.getElementById('gw-boot')) return;
      clearTimeout(timer);
      clearTimeout(pendingFailure);
      window.removeEventListener('error', scriptError, true);
      observer.disconnect();
    });
    observer.observe(document.getElementById('root'), { childList: true });
  }
}());
