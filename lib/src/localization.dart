import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import 'plural_rules.dart';
import 'translations.dart';

class Localization {
  Map<Locale, Translations>? _translations;

  Translations? _fallbackTranslations;

  late Locale _locale;

  final RegExp _replaceArgRegex = RegExp('{}');

  final RegExp _linkKeyMatcher =
      RegExp(r'(?:@(?:\.[a-z]+)?:(?:[\w\-_|.]+|\([\w\-_|.]+\)))');

  final RegExp _linkKeyPrefixMatcher = RegExp(r'^@(?:\.([a-z]+))?:');
  final RegExp _bracketsMatcher = RegExp('[()]');

  final _modifiers = <String, String Function(String?)>{
    'upper': (String? val) => val!.toUpperCase(),
    'lower': (String? val) => val!.toLowerCase(),
    'capitalize': (String? val) => '${val![0].toUpperCase()}${val.substring(1)}'
  };

  Localization();

  static Localization? _instance;

  static Localization get instance => _instance ??= Localization();

  static Localization? of(BuildContext context) =>
      Localizations.of<Localization>(context, Localization);

  static bool load(
    Locale locale, {
    Map<Locale, Translations>? translations,
    Translations? fallbackTranslations,
  }) {
    instance._locale = locale;
    instance._translations = translations;
    instance._fallbackTranslations = fallbackTranslations;

    return translations != null;
  }

  String tr(
    String key, {
    List<String>? args,
    Map<String, String>? namedArgs,
    String? gender,
    Locale? locale,
  }) {
    late String res = gender == null
        ? _resolve(key, locale: locale)
        : _gender(
            key,
            gender: gender,
            locale: locale,
          );

    res = _replaceLinks(res);

    res = _replaceNamedArgs(res, namedArgs);

    return _replaceArgs(res, args);
  }

  String _replaceLinks(String result, {bool logging = true}) {
    // TODO: add recursion detection and a resolve stack.
    final matches = _linkKeyMatcher.allMatches(result);

    for (final match in matches) {
      final link = match[0]!;
      final linkPrefixMatches = _linkKeyPrefixMatcher.allMatches(link);
      final linkPrefix = linkPrefixMatches.first[0]!;
      final formatterName = linkPrefixMatches.first[1];

      // Remove the leading @:, @.case: and the brackets
      final linkPlaceholder =
          link.replaceAll(linkPrefix, '').replaceAll(_bracketsMatcher, '');

      String translated = _resolve(linkPlaceholder);

      if (formatterName != null) {
        if (_modifiers.containsKey(formatterName)) {
          translated = _modifiers[formatterName]!(translated);
        } else {
          if (logging) {
            EasyLocalization.logger.warning(
                'Undefined modifier $formatterName, available modifiers: ${_modifiers.keys.toString()}');
          }
        }
      }

      result =
          translated.isEmpty ? result : result.replaceAll(link, translated);
    }

    return result;
  }

  String _replaceArgs(String result, List<String>? args) {
    if (args == null || args.isEmpty) return result;

    for (final str in args) {
      result = result.replaceFirst(_replaceArgRegex, str);
    }

    return result;
  }

  String _replaceNamedArgs(String result, Map<String, String>? args) {
    if (args == null || args.isEmpty) return result;

    args.forEach((String key, String value) =>
        result = result.replaceAll(RegExp('{$key}'), value));

    return result;
  }

  static PluralRule? _pluralRule(String? locale, num howMany) {
    startRuleEvaluation(howMany);
    return pluralRules[locale];
  }

  static PluralCase _pluralCaseFallback(num value) {
    return switch (value) {
      0 => PluralCase.ZERO,
      1 => PluralCase.ONE,
      2 => PluralCase.TWO,
      _ => PluralCase.OTHER,
    };
  }

  String plural(
    String key,
    num value, {
    List<String>? args,
    Map<String, String>? namedArgs,
    String? name,
    NumberFormat? format,
    Locale? locale,
  }) {
    Locale keyLocale = locale ?? _locale;

    final pluralRule = _pluralRule(keyLocale.languageCode, value);
    final pluralCase =
        pluralRule != null ? pluralRule() : _pluralCaseFallback(value);

    late String result = switch (pluralCase) {
      PluralCase.ZERO => _resolvePlural(
          key: key,
          subKey: 'zero',
          locale: keyLocale,
        ),
      PluralCase.ONE => _resolvePlural(
          key: key,
          subKey: 'one',
          locale: keyLocale,
        ),
      PluralCase.TWO => _resolvePlural(
          key: key,
          subKey: 'two',
          locale: keyLocale,
        ),
      PluralCase.FEW => _resolvePlural(
          key: key,
          subKey: 'few',
          locale: keyLocale,
        ),
      PluralCase.MANY => _resolvePlural(
          key: key,
          subKey: 'many',
          locale: keyLocale,
        ),
      PluralCase.OTHER => _resolvePlural(
          key: key,
          subKey: 'other',
          locale: keyLocale,
        ),
    };

    final formattedValue = format == null ? '$value' : format.format(value);

    if (name != null) {
      namedArgs = {...?namedArgs, name: formattedValue};
    }

    result = _replaceNamedArgs(result, namedArgs);

    return _replaceArgs(result, args ?? [formattedValue]);
  }

  String _gender(
    String key, {
    required String gender,
    Locale? locale,
  }) =>
      _resolve('$key.$gender', locale: locale);

  String _resolvePlural({
    required String key,
    required String subKey,
    Locale? locale,
  }) {
    if (subKey == 'other') return _resolve('$key.other', locale: locale);

    String tag = '$key.$subKey';
    String resource = _resolve(
      tag,
      logging: false,
      fallback: _fallbackTranslations != null,
      locale: locale,
    );

    if (resource == tag) {
      resource = _resolve('$key.other', locale: locale);
    }

    return resource;
  }

  String _resolve(
    String key, {
    Locale? locale,
    bool logging = true,
    bool fallback = true,
  }) {
    String? resource = _getTranslation(locale)?.get(key);

    if (resource == null) {
      if (logging) {
        EasyLocalization.logger.warning('Localization key [$key] not found');
      }

      if (_fallbackTranslations == null || !fallback) {
        return key;
      }

      resource = _fallbackTranslations?.get(key);

      if (resource == null) {
        if (logging) {
          EasyLocalization.logger
              .warning('Fallback localization key [$key] not found');
        }
        return key;
      }
    }

    return resource;
  }

  bool exists(String key, [Locale? locale]) =>
      _getTranslation(locale)?.get(key) != null;

  Translations? _getTranslation([Locale? locale]) {
    Locale keyLocale = locale ?? _locale;

    return _translations![keyLocale];
  }
}
