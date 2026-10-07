import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'catalogs.dart';

const languageNames = <String, String>{
  'en': 'English',
  'ru': 'Русский',
  'kk': 'Қазақша',
  'uk': 'Українська',
  'de': 'Deutsch',
  'es': 'Español',
};

String supportedLanguage(String? code) {
  final base = (code ?? '').toLowerCase().split(RegExp('[-_]')).first;
  return languageNames.containsKey(base) ? base : 'en';
}

/// Local catalogs ship with the application. Service messages use the active
/// controller language; widgets resolve the normal Flutter inherited locale.
class WaveStrings {
  final String language;
  const WaveStrings(this.language);
  static WaveStrings current = const WaveStrings('en');
  static const supportedLocales = [
    Locale('en'),
    Locale('ru'),
    Locale('kk'),
    Locale('uk'),
    Locale('de'),
    Locale('es'),
  ];
  static const delegates = <LocalizationsDelegate<dynamic>>[
    WaveStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  static WaveStrings of(BuildContext context) =>
      Localizations.of<WaveStrings>(context, WaveStrings) ?? current;

  String text(String key, [Map<String, Object?> values = const {}]) {
    if (values['p0'] is num) {
      final count = (values['p0'] as num).toInt();
      if (key == 'native.dcb57004b9') return plural('count.tracks', count);
      if (key == 'native.bd71178379') {
        return '${plural('count.tracks', count)} · ${values['p1']}';
      }
      if (key == 'native.e352fa0553') return plural('count.liked', count);
    }
    final template =
        waveCatalogs[language]?[key] ?? waveCatalogs['en']?[key] ?? key;
    return template.replaceAllMapped(RegExp(r'\{([a-zA-Z0-9_]+)\}'), (match) {
      final value = values[match[1]];
      if (value is num) return number(value);
      if (value is DateTime) return date(value);
      return value?.toString() ?? match[0]!;
    });
  }

  String number(num value, {int? decimalDigits}) => decimalDigits == null
      ? NumberFormat.decimalPattern(language).format(value)
      : NumberFormat.decimalPatternDigits(
          locale: language,
          decimalDigits: decimalDigits,
        ).format(value);
  String date(DateTime value) => DateFormat.yMMMMd(language).format(value);
  String time(DateTime value) => DateFormat.Hm(language).format(value);

  String plural(String stem, int count) {
    String form(String suffix) => text('$stem.$suffix', {'count': count});
    return Intl.plural(
      count,
      one: form('one'),
      few: form('few'),
      many: form('many'),
      other: form('other'),
      locale: language,
    );
  }
}

class WaveStringsDelegate extends LocalizationsDelegate<WaveStrings> {
  const WaveStringsDelegate();
  @override
  bool isSupported(Locale locale) =>
      languageNames.containsKey(locale.languageCode);
  @override
  Future<WaveStrings> load(Locale locale) async {
    final language = supportedLanguage(locale.languageCode);
    await initializeDateFormatting(language);
    return WaveStrings(language);
  }

  @override
  bool shouldReload(WaveStringsDelegate old) => false;
}

String wt(
  String key, {
  Map<String, Object?> values = const {},
  BuildContext? context,
}) => (context == null ? WaveStrings.current : WaveStrings.of(context)).text(
  key,
  values,
);

String localizedNumber(
  num value, {
  int? decimalDigits,
  BuildContext? context,
}) => (context == null ? WaveStrings.current : WaveStrings.of(context)).number(
  value,
  decimalDigits: decimalDigits,
);
