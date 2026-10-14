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
  var messages = {
    en: ['Opening your music', 'One moment…', 'GlukWave could not load', 'Check the connection and try again. An old TV browser may need an update.', 'Try again'],
    ru: ['Открываем твою музыку', 'Ещё немного…', 'Не удалось открыть GlukWave', 'Проверь соединение и попробуй снова. Старому браузеру ТВ может понадобиться обновление.', 'Попробовать снова'],
    kk: ['Музыкаңды ашып жатырмыз', 'Сәл күте тұр…', 'GlukWave ашылмады', 'Байланысты тексеріп, қайта көр. Ескі ТВ браузерін жаңарту қажет болуы мүмкін.', 'Қайта көру'],
    uk: ['Відкриваємо твою музику', 'Ще трохи…', 'Не вдалося відкрити GlukWave', 'Перевір з’єднання та спробуй ще раз. Старий браузер ТВ може потребувати оновлення.', 'Спробувати ще'],
    de: ['Deine Musik wird geöffnet', 'Einen Moment…', 'GlukWave konnte nicht laden', 'Prüfe die Verbindung und versuche es erneut. Ein älterer TV-Browser benötigt eventuell ein Update.', 'Erneut versuchen'],
    es: ['Abriendo tu música', 'Un momento…', 'No se pudo abrir GlukWave', 'Comprueba la conexión e inténtalo de nuevo. El navegador antiguo del televisor puede necesitar una actualización.', 'Reintentar']
  };
  var text = messages[language] || messages.en;
  document.documentElement.lang = messages[language] ? language : 'en';
  var title = shell.querySelector('h1'), detail = shell.querySelector('p'), retry = shell.querySelector('button');
  title.textContent = text[0]; detail.textContent = text[1]; retry.textContent = text[4];
  retry.onclick = function () { location.reload(); };
  function fail() {
    if (!document.getElementById('gw-boot')) return;
    shell.setAttribute('data-failed', 'true');
    title.textContent = text[2]; detail.textContent = text[3];
  }
  var timer = setTimeout(fail, 15000);
  window.addEventListener('error', fail, true);
  window.addEventListener('unhandledrejection', fail);
  if (window.MutationObserver) {
    var observer = new MutationObserver(function () {
      if (document.getElementById('gw-boot')) return;
      clearTimeout(timer);
      window.removeEventListener('error', fail, true);
      window.removeEventListener('unhandledrejection', fail);
      observer.disconnect();
    });
    observer.observe(document.getElementById('root'), { childList: true });
  }
}());
