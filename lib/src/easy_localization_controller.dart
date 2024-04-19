import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl_standalone.dart'
    if (dart.library.html) 'package:intl/intl_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

class EasyLocalizationController extends ChangeNotifier {
  static Locale? _savedLocale;

  static late Locale _deviceLocale;

  late Locale _locale;

  Locale? _fallbackLocale;

  final Function(FlutterError e) onLoadError;

  final AssetLoader assetLoader;

  final String path;

  final List<Locale> supportedLocales;

  final bool useFallbackTranslations;

  final bool saveLocale;

  final bool useOnlyLangCode;

  List<AssetLoader>? extraAssetLoaders;

  final Map<Locale, Translations> _allTranslations = {};

  Map<Locale, Translations> get translations => _allTranslations;

  Translations? _fallbackTranslations;

  Translations? get fallbackTranslations => _fallbackTranslations;

  EasyLocalizationController({
    required this.supportedLocales,
    required this.useFallbackTranslations,
    required this.saveLocale,
    required this.assetLoader,
    required this.path,
    required this.useOnlyLangCode,
    required this.onLoadError,
    this.extraAssetLoaders,
    Locale? startLocale,
    Locale? fallbackLocale,
    Locale? forceLocale, // used for testing
  }) {
    _fallbackLocale = fallbackLocale;
    if (forceLocale != null) {
      _locale = forceLocale;
    } else if (_savedLocale == null && startLocale != null) {
      _locale = _getFallbackLocale(supportedLocales, startLocale);
      EasyLocalization.logger('Start locale loaded ${_locale.toString()}');
    }
    // If saved locale then get
    else if (saveLocale && _savedLocale != null) {
      EasyLocalization.logger('Saved locale loaded ${_savedLocale.toString()}');
      _locale = selectLocaleFrom(
        supportedLocales,
        _savedLocale!,
        fallbackLocale: fallbackLocale,
      );
    } else {
      // From Device Locale
      _locale = selectLocaleFrom(
        supportedLocales,
        _deviceLocale,
        fallbackLocale: fallbackLocale,
      );
    }
  }

  @visibleForTesting
  static Locale selectLocaleFrom(
    List<Locale> supportedLocales,
    Locale deviceLocale, {
    Locale? fallbackLocale,
  }) {
    final selectedLocale = supportedLocales.firstWhere(
      (locale) => locale.supports(deviceLocale),
      orElse: () => _getFallbackLocale(supportedLocales, fallbackLocale),
    );
    return selectedLocale;
  }

  //Get fallback Locale
  static Locale _getFallbackLocale(
    List<Locale> supportedLocales,
    Locale? fallbackLocale,
  ) {
    return fallbackLocale ?? supportedLocales.first;
  }

  Future loadTranslations() async {
    try {
      Map<Locale, Map<String, dynamic>> allTranslationData =
          await loadAllTranslationData();

      allTranslationData.forEach((key, value) {
        _allTranslations.addAll({key: Translations(value)});
      });

      if (useFallbackTranslations && _fallbackLocale != null) {
        Map<String, dynamic>? baseLangData;

        if (_locale.countryCode != null && _locale.countryCode!.isNotEmpty) {
          try {
            baseLangData = allTranslationData[Locale(locale.languageCode)];
          } on FlutterError catch (e) {
            // Disregard asset not found FlutterError when attempting to load base language fallback
            EasyLocalization.logger.warning(e.message);
          }
        }

        Map<String, dynamic> data = allTranslationData[_fallbackLocale]!;

        if (baseLangData != null) {
          try {
            data.addAll(baseLangData);
          } on UnsupportedError {
            data = Map.of(data)..addAll(baseLangData);
          }
        }

        _fallbackTranslations = Translations(data);
      }
    } on FlutterError catch (e) {
      onLoadError(e);
    } catch (e) {
      onLoadError(FlutterError(e.toString()));
    }
  }

  Future<Map<String, dynamic>> loadTranslationData(Locale locale) async =>
      _combineAssetLoaders(
        path: path,
        locale: locale,
        assetLoader: assetLoader,
        useOnlyLangCode: useOnlyLangCode,
        extraAssetLoaders: extraAssetLoaders,
      );

  Future<Map<Locale, Map<String, dynamic>>> loadAllTranslationData() async {
    Map<Locale, Map<String, dynamic>> data = {};

    for (final locale in supportedLocales) {
      data[locale] = await _combineAssetLoaders(
        path: path,
        locale: locale,
        assetLoader: assetLoader,
        useOnlyLangCode: useOnlyLangCode,
        extraAssetLoaders: extraAssetLoaders,
      );
    }

    return data;
  }

  Future<Map<String, dynamic>> _combineAssetLoaders({
    required String path,
    required Locale locale,
    required AssetLoader assetLoader,
    required bool useOnlyLangCode,
    List<AssetLoader>? extraAssetLoaders,
  }) async {
    final Map<String, dynamic> result = {};
    final List<Future<Map<String, dynamic>?>> loaderFutures = [];

    final Locale desiredLocale =
        useOnlyLangCode ? Locale(locale.languageCode) : locale;

    List<AssetLoader> loaders = [
      assetLoader,
      if (extraAssetLoaders != null) ...extraAssetLoaders
    ];

    for (final loader in loaders) {
      loaderFutures.add(loader.load(path, desiredLocale));
    }

    await Future.wait(loaderFutures).then((List<Map<String, dynamic>?> value) {
      for (final Map<String, dynamic>? map in value) {
        if (map != null) {
          result.addAllRecursive(map);
        }
      }
    });

    return result;
  }

  Locale get locale => _locale;

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    await loadTranslations();
    notifyListeners();
    EasyLocalization.logger('Locale $locale changed');
    await _saveLocale(locale);
  }

  Future<void> _saveLocale(Locale? locale) async {
    if (!saveLocale) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('locale', locale.toString());
    EasyLocalization.logger('Locale $locale saved');
  }

  static Future<void> initEasyLocation() async {
    final preferences = await SharedPreferences.getInstance();
    final strLocale = preferences.getString('locale');
    _savedLocale = strLocale?.toLocale();
    final foundPlatformLocale = await findSystemLocale();
    _deviceLocale = foundPlatformLocale.toLocale();
    EasyLocalization.logger.debug('Localization initialized');
  }

  Future<void> deleteSaveLocale() async {
    _savedLocale = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('locale');
    EasyLocalization.logger('Saved locale deleted');
  }

  Locale get deviceLocale => _deviceLocale;

  Future<void> resetLocale() async {
    EasyLocalization.logger('Reset locale to platform locale $_deviceLocale');

    await setLocale(_deviceLocale);
  }
}

@visibleForTesting
extension LocaleExtension on Locale {
  bool supports(Locale locale) {
    if (this == locale) {
      return true;
    }

    if (languageCode != locale.languageCode) {
      return false;
    }

    if (countryCode != null &&
        countryCode!.isNotEmpty &&
        countryCode != locale.countryCode) {
      return false;
    }

    if (scriptCode != null && scriptCode != locale.scriptCode) {
      return false;
    }

    return true;
  }
}
