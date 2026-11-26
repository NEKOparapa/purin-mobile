import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'english.dart';

enum AppLanguage {
  chinese(Locale('zh', 'CN'), '简体中文'),
  english(Locale('en'), 'English');

  const AppLanguage(this.locale, this.label);
  final Locale locale;
  final String label;

  static AppLanguage fromTag(String? tag) => tag == 'en' ? english : chinese;

  String text(String source, [List<Object?> values = const []]) {
    final message = this == english
        ? englishMessages[source] ?? source
        : source;
    if (values.isEmpty) return message;
    return message.replaceAllMapped(
      RegExp(r'\{(\d+)\}'),
      (match) => values[int.parse(match[1]!)].toString(),
    );
  }

  String date(DateTime date) => this == chinese
      ? '${date.year}年${date.month}月${date.day}日'
      : DateFormat.yMMMd('en').format(date);
}

class LocalizedFormatException extends FormatException {
  LocalizedFormatException(this.template, this.values)
    : super(AppLanguage.chinese.text(template, values));

  final String template;
  final List<Object?> values;
}

class AppLanguageDelegate extends LocalizationsDelegate<AppLanguage> {
  const AppLanguageDelegate();

  @override
  bool isSupported(Locale locale) => AppLanguage.values.any(
    (value) => value.locale.languageCode == locale.languageCode,
  );

  @override
  Future<AppLanguage> load(Locale locale) =>
      SynchronousFuture(AppLanguage.fromTag(locale.toLanguageTag()));

  @override
  bool shouldReload(AppLanguageDelegate old) => false;
}

extension AppTranslations on BuildContext {
  AppLanguage get appLanguage =>
      Localizations.of<AppLanguage>(this, AppLanguage) ?? AppLanguage.chinese;

  String tr(String source, [List<Object?> values = const []]) =>
      appLanguage.text(source, values);
}
