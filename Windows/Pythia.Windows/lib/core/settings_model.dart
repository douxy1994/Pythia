import 'webdav_sync_schedule.dart';

enum PythiaThemeMode { system, light, dark }

class PythiaSettings {
  static const googleServiceId = 'google';
  static const baiduServiceId = 'baidu';
  static const youdaoServiceId = 'youdao';
  static const openAICompatibleServiceId = 'openai-compatible';
  static const deepLServiceId = 'deepl';
  static const libreTranslateServiceId = 'libretranslate';

  final String sourceLanguage;
  final String targetLanguage;
  final List<String> enabledTranslateServices;
  final List<String> translateServiceOrder;
  final bool googleEnabled;
  final bool baiduEnabled;
  final bool youdaoEnabled;
  final bool openAICompatibleEnabled;
  final String openAICompatibleName;
  final String openAICompatibleBaseUrl;
  final String openAICompatibleModel;
  final bool deepLEnabled;
  final String deepLBaseUrl;
  final bool libreTranslateEnabled;
  final String libreTranslateBaseUrl;
  final bool saveHistory;
  final PythiaThemeMode themeMode;
  final bool launchAtStartup;
  final bool closeToTray;
  final bool alwaysOnTop;
  final bool hideOnBlur;
  final bool notificationsEnabled;
  final String showWindowHotkey;
  final String selectionTranslateHotkey;
  final String screenshotTranslateHotkey;
  final String webdavUrl;
  final String webdavUsername;
  final bool webdavHistoryAutoSync;
  final int webdavHistorySyncIntervalValue;
  final String webdavHistorySyncIntervalUnit;
  final String webdavLastSyncAt;
  final String webdavLastSyncStatus;
  final String webdavLastSyncError;

  const PythiaSettings({
    this.sourceLanguage = 'auto',
    this.targetLanguage = 'zh-CN',
    this.enabledTranslateServices = const ['google'],
    this.translateServiceOrder = const ['google'],
    this.googleEnabled = true,
    this.baiduEnabled = false,
    this.youdaoEnabled = false,
    this.openAICompatibleEnabled = false,
    this.openAICompatibleName = 'OpenAI Compatible',
    this.openAICompatibleBaseUrl = 'https://api.openai.com/v1',
    this.openAICompatibleModel = 'gpt-4o-mini',
    this.deepLEnabled = false,
    this.deepLBaseUrl = 'https://api-free.deepl.com/v2',
    this.libreTranslateEnabled = false,
    this.libreTranslateBaseUrl = 'https://libretranslate.com',
    this.saveHistory = true,
    this.themeMode = PythiaThemeMode.system,
    this.launchAtStartup = false,
    this.closeToTray = true,
    this.alwaysOnTop = false,
    this.hideOnBlur = false,
    this.notificationsEnabled = true,
    this.showWindowHotkey = 'Ctrl+Alt+P',
    this.selectionTranslateHotkey = 'Ctrl+Alt+E',
    this.screenshotTranslateHotkey = 'Ctrl+Alt+S',
    this.webdavUrl = '',
    this.webdavUsername = '',
    this.webdavHistoryAutoSync = false,
    this.webdavHistorySyncIntervalValue = 1,
    this.webdavHistorySyncIntervalUnit = 'hour',
    this.webdavLastSyncAt = '',
    this.webdavLastSyncStatus = '',
    this.webdavLastSyncError = '',
  });

  PythiaSettings copyWith({
    String? sourceLanguage,
    String? targetLanguage,
    List<String>? enabledTranslateServices,
    List<String>? translateServiceOrder,
    bool? googleEnabled,
    bool? baiduEnabled,
    bool? youdaoEnabled,
    bool? openAICompatibleEnabled,
    String? openAICompatibleName,
    String? openAICompatibleBaseUrl,
    String? openAICompatibleModel,
    bool? deepLEnabled,
    String? deepLBaseUrl,
    bool? libreTranslateEnabled,
    String? libreTranslateBaseUrl,
    bool? saveHistory,
    PythiaThemeMode? themeMode,
    bool? launchAtStartup,
    bool? closeToTray,
    bool? alwaysOnTop,
    bool? hideOnBlur,
    bool? notificationsEnabled,
    String? showWindowHotkey,
    String? selectionTranslateHotkey,
    String? screenshotTranslateHotkey,
    String? webdavUrl,
    String? webdavUsername,
    bool? webdavHistoryAutoSync,
    int? webdavHistorySyncIntervalValue,
    String? webdavHistorySyncIntervalUnit,
    String? webdavLastSyncAt,
    String? webdavLastSyncStatus,
    String? webdavLastSyncError,
  }) {
    return PythiaSettings(
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      enabledTranslateServices:
          enabledTranslateServices ?? this.enabledTranslateServices,
      translateServiceOrder:
          translateServiceOrder ?? this.translateServiceOrder,
      googleEnabled: googleEnabled ?? this.googleEnabled,
      baiduEnabled: baiduEnabled ?? this.baiduEnabled,
      youdaoEnabled: youdaoEnabled ?? this.youdaoEnabled,
      openAICompatibleEnabled:
          openAICompatibleEnabled ?? this.openAICompatibleEnabled,
      openAICompatibleName: openAICompatibleName ?? this.openAICompatibleName,
      openAICompatibleBaseUrl:
          openAICompatibleBaseUrl ?? this.openAICompatibleBaseUrl,
      openAICompatibleModel:
          openAICompatibleModel ?? this.openAICompatibleModel,
      deepLEnabled: deepLEnabled ?? this.deepLEnabled,
      deepLBaseUrl: deepLBaseUrl ?? this.deepLBaseUrl,
      libreTranslateEnabled:
          libreTranslateEnabled ?? this.libreTranslateEnabled,
      libreTranslateBaseUrl:
          libreTranslateBaseUrl ?? this.libreTranslateBaseUrl,
      saveHistory: saveHistory ?? this.saveHistory,
      themeMode: themeMode ?? this.themeMode,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      closeToTray: closeToTray ?? this.closeToTray,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      hideOnBlur: hideOnBlur ?? this.hideOnBlur,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      showWindowHotkey: showWindowHotkey ?? this.showWindowHotkey,
      selectionTranslateHotkey:
          selectionTranslateHotkey ?? this.selectionTranslateHotkey,
      screenshotTranslateHotkey:
          screenshotTranslateHotkey ?? this.screenshotTranslateHotkey,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      webdavUsername: webdavUsername ?? this.webdavUsername,
      webdavHistoryAutoSync:
          webdavHistoryAutoSync ?? this.webdavHistoryAutoSync,
      webdavHistorySyncIntervalValue:
          webdavHistorySyncIntervalValue ?? this.webdavHistorySyncIntervalValue,
      webdavHistorySyncIntervalUnit:
          webdavHistorySyncIntervalUnit ?? this.webdavHistorySyncIntervalUnit,
      webdavLastSyncAt: webdavLastSyncAt ?? this.webdavLastSyncAt,
      webdavLastSyncStatus: webdavLastSyncStatus ?? this.webdavLastSyncStatus,
      webdavLastSyncError: webdavLastSyncError ?? this.webdavLastSyncError,
    );
  }

  factory PythiaSettings.fromJson(Map<String, Object?> json) {
    return PythiaSettings(
      sourceLanguage: json['sourceLanguage'] as String? ?? 'auto',
      targetLanguage: json['targetLanguage'] as String? ?? 'zh-CN',
      enabledTranslateServices:
          _stringList(json['enabledTranslateServices']) ?? const ['google'],
      translateServiceOrder:
          _stringList(json['translateServiceOrder']) ?? const ['google'],
      googleEnabled: json['googleEnabled'] as bool? ?? true,
      baiduEnabled: json['baiduEnabled'] as bool? ?? false,
      youdaoEnabled: json['youdaoEnabled'] as bool? ?? false,
      openAICompatibleEnabled:
          json['openAICompatibleEnabled'] as bool? ?? false,
      openAICompatibleName:
          json['openAICompatibleName'] as String? ?? 'OpenAI Compatible',
      openAICompatibleBaseUrl: json['openAICompatibleBaseUrl'] as String? ??
          'https://api.openai.com/v1',
      openAICompatibleModel:
          json['openAICompatibleModel'] as String? ?? 'gpt-4o-mini',
      deepLEnabled: json['deepLEnabled'] as bool? ?? false,
      deepLBaseUrl:
          json['deepLBaseUrl'] as String? ?? 'https://api-free.deepl.com/v2',
      libreTranslateEnabled: json['libreTranslateEnabled'] as bool? ?? false,
      libreTranslateBaseUrl: json['libreTranslateBaseUrl'] as String? ??
          'https://libretranslate.com',
      saveHistory: json['saveHistory'] as bool? ?? true,
      themeMode: _themeModeFromJson(json['themeMode'] as String?),
      launchAtStartup: json['launchAtStartup'] as bool? ?? false,
      closeToTray: json['closeToTray'] as bool? ?? true,
      alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
      hideOnBlur: json['hideOnBlur'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      showWindowHotkey: json['showWindowHotkey'] as String? ?? 'Ctrl+Alt+P',
      selectionTranslateHotkey:
          json['selectionTranslateHotkey'] as String? ?? 'Ctrl+Alt+E',
      screenshotTranslateHotkey:
          json['screenshotTranslateHotkey'] as String? ?? 'Ctrl+Alt+S',
      webdavUrl: json['webdavUrl'] as String? ?? '',
      webdavUsername: json['webdavUsername'] as String? ?? '',
      webdavHistoryAutoSync: json['webdavHistoryAutoSync'] as bool? ?? false,
      webdavHistorySyncIntervalValue: _syncScheduleFromJson(json).value,
      webdavHistorySyncIntervalUnit:
          _syncScheduleFromJson(json).unit.storageValue,
      webdavLastSyncAt: json['webdavLastSyncAt'] as String? ?? '',
      webdavLastSyncStatus: json['webdavLastSyncStatus'] as String? ?? '',
      webdavLastSyncError: json['webdavLastSyncError'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'enabledTranslateServices': enabledTranslateServices,
        'translateServiceOrder': translateServiceOrder,
        'googleEnabled': googleEnabled,
        'baiduEnabled': baiduEnabled,
        'youdaoEnabled': youdaoEnabled,
        'openAICompatibleEnabled': openAICompatibleEnabled,
        'openAICompatibleName': openAICompatibleName,
        'openAICompatibleBaseUrl': openAICompatibleBaseUrl,
        'openAICompatibleModel': openAICompatibleModel,
        'deepLEnabled': deepLEnabled,
        'deepLBaseUrl': deepLBaseUrl,
        'libreTranslateEnabled': libreTranslateEnabled,
        'libreTranslateBaseUrl': libreTranslateBaseUrl,
        'saveHistory': saveHistory,
        'themeMode': themeMode.name,
        'launchAtStartup': launchAtStartup,
        'closeToTray': closeToTray,
        'alwaysOnTop': alwaysOnTop,
        'hideOnBlur': hideOnBlur,
        'notificationsEnabled': notificationsEnabled,
        'showWindowHotkey': showWindowHotkey,
        'selectionTranslateHotkey': selectionTranslateHotkey,
        'screenshotTranslateHotkey': screenshotTranslateHotkey,
        'webdavUrl': webdavUrl,
        'webdavUsername': webdavUsername,
        'webdavHistoryAutoSync': webdavHistoryAutoSync,
        'webdavHistorySyncIntervalValue': webdavHistorySyncIntervalValue,
        'webdavHistorySyncIntervalUnit': webdavHistorySyncIntervalUnit,
        'webdavHistorySyncIntervalMinutes': webdavSyncSchedule.legacyMinutes,
        'webdavLastSyncAt': webdavLastSyncAt,
        'webdavLastSyncStatus': webdavLastSyncStatus,
        'webdavLastSyncError': webdavLastSyncError,
      };

  static PythiaThemeMode _themeModeFromJson(String? raw) {
    return switch (raw) {
      'light' => PythiaThemeMode.light,
      'dark' => PythiaThemeMode.dark,
      _ => PythiaThemeMode.system,
    };
  }

  static List<String>? _stringList(Object? raw) {
    if (raw is! List<Object?>) return null;
    return raw.whereType<String>().toList(growable: false);
  }

  PythiaSettings normalized() {
    final services = <String>[
      for (final id in enabledTranslateServices)
        if ((googleEnabled || id != googleServiceId) &&
            (baiduEnabled || id != baiduServiceId) &&
            (youdaoEnabled || id != youdaoServiceId) &&
            (openAICompatibleEnabled || id != openAICompatibleServiceId) &&
            (deepLEnabled || id != deepLServiceId) &&
            (libreTranslateEnabled || id != libreTranslateServiceId))
          id,
    ];
    if (services.isEmpty) {
      services.add(googleEnabled ? googleServiceId : 'local');
    }

    final order = <String>[
      for (final id in translateServiceOrder)
        if (services.contains(id)) id,
      for (final id in services)
        if (!translateServiceOrder.contains(id)) id,
    ];

    return copyWith(
      enabledTranslateServices: services,
      translateServiceOrder: order,
      webdavHistorySyncIntervalValue: webdavSyncSchedule.value,
      webdavHistorySyncIntervalUnit: webdavSyncSchedule.unit.storageValue,
    );
  }

  WebDavSyncSchedule get webdavSyncSchedule {
    final schedule = WebDavSyncSchedule(
      webdavHistorySyncIntervalValue,
      WebDavSyncIntervalUnit.fromStorage(webdavHistorySyncIntervalUnit),
    );
    try {
      return schedule.validated();
    } on FormatException {
      return const WebDavSyncSchedule(1, WebDavSyncIntervalUnit.hour);
    }
  }

  static WebDavSyncSchedule _syncScheduleFromJson(Map<String, Object?> json) {
    final value = json['webdavHistorySyncIntervalValue'] as int?;
    final unit = json['webdavHistorySyncIntervalUnit'] as String?;
    if (value != null && unit != null) {
      final schedule = WebDavSyncSchedule(
        value,
        WebDavSyncIntervalUnit.fromStorage(unit),
      );
      try {
        return schedule.validated();
      } on FormatException {
        return const WebDavSyncSchedule(1, WebDavSyncIntervalUnit.hour);
      }
    }
    return WebDavSyncSchedule.fromLegacyMinutes(
      json['webdavHistorySyncIntervalMinutes'] as int? ?? 60,
    );
  }
}
