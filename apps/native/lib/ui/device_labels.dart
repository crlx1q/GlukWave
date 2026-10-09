import 'package:flutter/material.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';

String deviceKindLabel(Json device, {BuildContext? context}) =>
    wt(switch (device['kind'] ?? device['clientKind']) {
      'web' => 'devices.web',
      'windows' => 'devices.windows',
      'android' => 'devices.android',
      'ios' => 'devices.ios',
      _ => 'devices.desktop',
    }, context: context);

IconData deviceKindIcon(Json device) =>
    switch (device['kind'] ?? device['clientKind']) {
      'web' => Icons.language_rounded,
      'android' || 'ios' => Icons.smartphone_rounded,
      _ => Icons.desktop_windows_outlined,
    };

String activityDate(dynamic value, BuildContext context) {
  final date = value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal()
      : value is String
      ? DateTime.tryParse(value)?.toLocal()
      : null;
  if (date == null) return '';
  final material = MaterialLocalizations.of(context);
  return '${material.formatCompactDate(date)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}
