import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'core/history_record.dart';
import 'core/history_change_sync_scheduler.dart';
import 'core/hotkey_accelerator.dart';
import 'core/local_storage.dart';
import 'core/portable_backup.dart';
import 'core/settings_model.dart';
import 'core/translation_service.dart';
import 'core/update_checker.dart';
import 'core/update_installer.dart';
import 'core/webdav_sync.dart';
import 'core/webdav_sync_retry.dart';
import 'core/webdav_portable_backup.dart';
import 'core/webdav_auto_sync_scheduler.dart';
import 'core/webdav_sync_schedule.dart';
import 'platform/credential_store.dart';
import 'platform/platform_services.dart';
import 'platform/tray_action_dispatcher.dart';
import 'ui/hotkey_recorder_field.dart';

const webdavPasswordSecretKey = 'webdav.password';
const openAICompatibleApiKeySecretKey = 'provider.openai-compatible.apiKey';
const deepLApiKeySecretKey = 'provider.deepl.apiKey';
const libreTranslateApiKeySecretKey = 'provider.libretranslate.apiKey';
const baiduAppIdSecretKey = 'provider.baidu.appId';
const baiduSecretKey = 'provider.baidu.secret';
const youdaoAppKeySecretKey = 'provider.youdao.appKey';
const youdaoSecretKey = 'provider.youdao.secret';

void main() {
  runApp(const PythiaWindowsApp());
}

class PythiaWindowsApp extends StatefulWidget {
  const PythiaWindowsApp({super.key});

  @override
  State<PythiaWindowsApp> createState() => _PythiaWindowsAppState();
}

class _PythiaWindowsAppState extends State<PythiaWindowsApp> {
  final store = PythiaLocalStore();
  PythiaSettings settings = const PythiaSettings();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final next = (await store.readSettings()).normalized();
    setState(() {
      settings = next;
      loaded = true;
    });
  }

  Future<void> _save(PythiaSettings next) async {
    final normalized = next.normalized();
    await store.writeSettings(normalized);
    setState(() => settings = normalized);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = switch (settings.themeMode) {
      PythiaThemeMode.light => ThemeMode.light,
      PythiaThemeMode.dark => ThemeMode.dark,
      PythiaThemeMode.system => ThemeMode.system,
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pythia',
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF80B847),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF80B847),
        brightness: Brightness.dark,
      ),
      home: loaded
          ? PythiaHomePage(
              store: store,
              settings: settings,
              onSettingsChanged: _save,
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class PythiaHomePage extends StatefulWidget {
  final PythiaLocalStore store;
  final PythiaSettings settings;
  final Future<void> Function(PythiaSettings) onSettingsChanged;

  const PythiaHomePage({
    super.key,
    required this.store,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<PythiaHomePage> createState() => _PythiaHomePageState();
}

class _PythiaHomePageState extends State<PythiaHomePage> {
  final sourceController = TextEditingController();
  final historySearchController = TextEditingController();
  final sourceFocusNode = FocusNode();
  final historySearchFocusNode = FocusNode();
  final credentialStore = const MethodChannelCredentialStore();
  final platformService = const MethodChannelWindowsPlatformService();
  final translationHttpClient = http.Client();
  late final TrayActionDispatcher trayActionDispatcher;
  List<PythiaTranslationResult> results = const [];
  List<PythiaHistoryRecord> history = const [];
  String status = '就绪';
  bool translating = false;
  bool syncing = false;
  Future<void>? activeSync;
  final webdavAutoSyncScheduler = WebDavAutoSyncScheduler();
  final historyChangeSyncScheduler = HistoryChangeSyncScheduler();
  final webdavSyncRetryPolicy = const WebDavSyncRetryPolicy();

  @override
  void initState() {
    super.initState();
    trayActionDispatcher = TrayActionDispatcher(
      onInputTranslate: _showInputTranslationFromTray,
      onOpenSettings: _openSettingsFromTray,
      onOpenHistory: _openHistoryFromTray,
      onSyncHistory: _syncHistoryFromTray,
      onQuit: _quitFromTray,
    );
    _loadHistory();
    _configureWebDavAutoSync();
    _configurePlatformIntegrations();
    if (widget.settings.webdavHistoryAutoSync &&
        widget.settings.webdavUrl.trim().isNotEmpty) {
      Timer(const Duration(seconds: 3), () {
        if (mounted) _syncHistory(reason: '启动同步', quiet: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant PythiaHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.webdavHistoryAutoSync !=
            widget.settings.webdavHistoryAutoSync ||
        oldWidget.settings.webdavHistorySyncIntervalValue !=
            widget.settings.webdavHistorySyncIntervalValue ||
        oldWidget.settings.webdavHistorySyncIntervalUnit !=
            widget.settings.webdavHistorySyncIntervalUnit ||
        oldWidget.settings.webdavUrl != widget.settings.webdavUrl ||
        oldWidget.settings.webdavUsername != widget.settings.webdavUsername) {
      _configureWebDavAutoSync();
    }
    if (oldWidget.settings.launchAtStartup != widget.settings.launchAtStartup) {
      _applyLaunchAtStartup(widget.settings.launchAtStartup);
    }
    if (oldWidget.settings.alwaysOnTop != widget.settings.alwaysOnTop) {
      _applyAlwaysOnTop(widget.settings.alwaysOnTop);
    }
    if (oldWidget.settings.closeToTray != widget.settings.closeToTray) {
      _applyCloseToTray(widget.settings.closeToTray);
    }
    if (oldWidget.settings.hideOnBlur != widget.settings.hideOnBlur) {
      _applyHideOnBlur(widget.settings.hideOnBlur);
    }
    if (oldWidget.settings.showWindowHotkey !=
            widget.settings.showWindowHotkey ||
        oldWidget.settings.selectionTranslateHotkey !=
            widget.settings.selectionTranslateHotkey ||
        oldWidget.settings.screenshotTranslateHotkey !=
            widget.settings.screenshotTranslateHotkey) {
      _registerHotkeys();
    }
  }

  @override
  void dispose() {
    webdavAutoSyncScheduler.cancel();
    historyChangeSyncScheduler.cancel();
    platformService.setHotkeyHandler(null);
    platformService.setTrayActionHandler(null);
    unawaited(platformService.saveWindowPlacement().catchError((_) {}));
    unawaited(platformService.unregisterAll().catchError((_) {}));
    sourceController.dispose();
    historySearchController.dispose();
    sourceFocusNode.dispose();
    historySearchFocusNode.dispose();
    translationHttpClient.close();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final records = await widget.store.searchVisibleHistory(
      historySearchController.text,
    );
    if (mounted) setState(() => history = records);
  }

  Future<void> _translate() async {
    final text = sourceController.text.trim();
    if (text.isEmpty) {
      setState(() => status = '请输入要翻译的文本');
      return;
    }
    setState(() {
      translating = true;
      status = '翻译中...';
    });
    try {
      final languages = TranslationServiceRegistry.resolvedLanguages(
        text: text,
        sourceLanguage: widget.settings.sourceLanguage,
        targetLanguage: widget.settings.targetLanguage,
      );
      final translated = await _registry().translateAll(
        text: text,
        sourceLanguage: widget.settings.sourceLanguage,
        targetLanguage: widget.settings.targetLanguage,
        serviceIds: widget.settings.enabledTranslateServices,
      );
      if (widget.settings.saveHistory) {
        final now = DateTime.now().toUtc();
        await widget.store.addHistory(PythiaHistoryRecord(
          id: now.microsecondsSinceEpoch.toString(),
          sourceText: text,
          translatedText: translated.map((item) => item.text).join('\n\n'),
          sourceLanguage: languages.source,
          targetLanguage: languages.target,
          service: translated.map((item) => item.serviceName).join(', '),
          createdAt: now,
          updatedAt: now,
          deviceId: await widget.store.deviceId(),
        ));
        historyChangeSyncScheduler.historyChanged();
      }
      await _loadHistory();
      setState(() {
        results = translated;
        status = '翻译完成';
      });
    } catch (error) {
      setState(() => status = '翻译失败：$error');
    } finally {
      if (mounted) setState(() => translating = false);
    }
  }

  Future<void> _translateSelection() async {
    setState(() => status = '正在读取选中文本...');
    try {
      final text = (await platformService.readSelectedText()).trim();
      if (text.isEmpty) {
        setState(() => status = '未读取到选中文本');
        return;
      }
      sourceController.text = text;
      await _translate();
    } catch (error) {
      setState(() => status = '划词翻译不可用：$error');
    }
  }

  Future<void> _screenshotTranslate() async {
    setState(() => status = '正在截图 OCR...');
    try {
      final text = (await platformService.captureAndRecognize(
        translateAfterRecognition: true,
      ))
          .trim();
      if (text.isEmpty) {
        setState(() => status = '截图 OCR 未返回文本');
        return;
      }
      sourceController.text = text;
      await _translate();
    } on PlatformException catch (error) {
      setState(() {
        status = error.code == 'ocr_cancelled'
            ? '已取消截图'
            : '截图 OCR 失败：${error.message ?? error.code}';
      });
    } catch (error) {
      setState(() => status = '截图 OCR 失败：$error');
    }
  }

  Future<void> _applyAlwaysOnTop(bool enabled) async {
    try {
      await platformService.setAlwaysOnTop(enabled);
    } catch (error) {
      if (mounted) setState(() => status = '窗口置顶设置待 Windows 通道接入：$error');
    }
  }

  Future<void> _applyLaunchAtStartup(bool enabled) async {
    try {
      await platformService.setLaunchAtStartup(enabled);
    } catch (error) {
      if (mounted) setState(() => status = '开机启动设置待 Windows 通道接入：$error');
    }
  }

  Future<void> _applyCloseToTray(bool enabled) async {
    try {
      await platformService.setCloseToTray(enabled);
    } catch (error) {
      if (mounted) setState(() => status = '关闭到托盘设置待 Windows 通道接入：$error');
    }
  }

  Future<void> _applyHideOnBlur(bool enabled) async {
    try {
      await platformService.setHideOnBlur(enabled);
    } catch (error) {
      if (mounted) setState(() => status = '失焦隐藏设置失败：$error');
    }
  }

  Future<void> _configurePlatformIntegrations() async {
    platformService.setHotkeyHandler(_handleHotkeyAction);
    platformService.setTrayActionHandler(_handleTrayAction);
    final warnings = <String>[];

    Future<void> attempt(String label, Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        warnings.add('$label：$error');
      }
    }

    await attempt('托盘', platformService.install);
    await attempt('恢复窗口位置', platformService.restoreWindowPlacement);
    await attempt(
      '关闭到托盘',
      () => platformService.setCloseToTray(widget.settings.closeToTray),
    );
    await attempt(
      '失焦隐藏',
      () => platformService.setHideOnBlur(widget.settings.hideOnBlur),
    );
    await attempt(
      '窗口置顶',
      () => platformService.setAlwaysOnTop(widget.settings.alwaysOnTop),
    );
    await attempt(
      '开机启动',
      () => platformService.setLaunchAtStartup(widget.settings.launchAtStartup),
    );
    warnings.addAll(await _registerHotkeys());

    if (warnings.isNotEmpty && mounted) {
      setState(() => status = warnings.join('；'));
    }
  }

  Future<List<String>> _registerHotkeys() async {
    final warnings = <String>[];

    Future<void> attempt(String label, Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        warnings.add('$label：$error');
      }
    }

    await attempt('清理旧热键', platformService.unregisterAll);
    await attempt(
      '显示窗口快捷键',
      () => platformService.register(
        'window.show',
        widget.settings.showWindowHotkey,
      ),
    );
    await attempt(
      '划词翻译快捷键',
      () => platformService.register(
        'selection.translate',
        widget.settings.selectionTranslateHotkey,
      ),
    );
    await attempt(
      '截图翻译快捷键',
      () => platformService.register(
        'screenshot.translate',
        widget.settings.screenshotTranslateHotkey,
      ),
    );
    if (warnings.isNotEmpty && mounted) {
      setState(() => status = warnings.join('；'));
    }
    return warnings;
  }

  Future<void> _handleHotkeyAction(String action) async {
    if (!mounted) return;
    switch (action) {
      case 'window.show':
        try {
          await platformService.showWindow();
          if (mounted) setState(() => status = '已通过快捷键显示窗口');
        } catch (error) {
          if (mounted) setState(() => status = '显示窗口快捷键不可用：$error');
        }
      case 'selection.translate':
        await _translateSelection();
      case 'screenshot.translate':
        await _screenshotTranslate();
      default:
        if (mounted) setState(() => status = '未知快捷键动作：$action');
    }
  }

  Future<void> _handleTrayAction(String action) async {
    if (!mounted) return;
    final handled = await trayActionDispatcher.dispatch(action);
    if (!handled && mounted) setState(() => status = '未知托盘动作：$action');
  }

  Future<void> _showInputTranslationFromTray() async {
    await platformService.showWindow();
    if (!mounted) return;
    sourceController.clear();
    setState(() {
      results = const [];
      status = '请输入文本，按回车翻译';
    });
    sourceFocusNode.requestFocus();
  }

  Future<void> _openSettingsFromTray() async {
    await platformService.showWindow();
    if (!mounted) return;
    await _openSettings(context);
  }

  Future<void> _openHistoryFromTray() async {
    await platformService.showWindow();
    if (!mounted) return;
    historySearchFocusNode.requestFocus();
    setState(() => status = '已打开历史记录');
  }

  Future<void> _syncHistoryFromTray() async {
    await _syncHistory(reason: '托盘同步');
  }

  Future<void> _quitFromTray() async {
    historyChangeSyncScheduler.cancel();
    if (widget.settings.webdavHistoryAutoSync &&
        widget.settings.webdavUrl.trim().isNotEmpty) {
      await _syncHistory(reason: '退出同步', quiet: true);
    }
    await platformService.quitApp();
  }

  void _configureWebDavAutoSync() {
    webdavAutoSyncScheduler.configure(
      enabled: widget.settings.webdavHistoryAutoSync,
      hasWebDavAddress: widget.settings.webdavUrl.trim().isNotEmpty,
      schedule: widget.settings.webdavSyncSchedule,
      synchronize: () => _syncHistory(reason: '自动同步', quiet: true),
    );
    historyChangeSyncScheduler.configure(
      enabled: widget.settings.webdavHistoryAutoSync,
      hasWebDavAddress: widget.settings.webdavUrl.trim().isNotEmpty,
      synchronize: () => _syncHistory(reason: '历史变更同步', quiet: true),
    );
  }

  Future<void> _syncHistory({
    String reason = '手动同步',
    bool quiet = false,
  }) {
    final running = activeSync;
    if (running != null) return running;
    final operation = _performSync(reason: reason, quiet: quiet);
    activeSync = operation;
    return operation.whenComplete(() {
      if (identical(activeSync, operation)) activeSync = null;
    });
  }

  Future<void> _performSync({
    required String reason,
    required bool quiet,
  }) async {
    setState(() {
      syncing = true;
      if (!quiet) status = '$reason：同步历史中...';
    });
    final String? password;
    try {
      password = await credentialStore.readSecret(webdavPasswordSecretKey);
    } catch (error) {
      final errorMessage = 'Windows 凭据读取失败：$error';
      await _recordSyncStatus(
        statusText: '$reason 失败',
        errorText: errorMessage,
      );
      await _notifyBackgroundSync(
        quiet: quiet,
        reason: reason,
        success: false,
        message: errorMessage,
      );
      if (mounted) {
        setState(() {
          status = '同步失败：$errorMessage';
          syncing = false;
        });
      }
      return;
    }
    if (widget.settings.webdavUsername.isNotEmpty &&
        (password == null || password.isEmpty)) {
      await _recordSyncStatus(
        statusText: '$reason 失败',
        errorText: '请先在设置中保存 WebDAV 密码',
      );
      await _notifyBackgroundSync(
        quiet: quiet,
        reason: reason,
        success: false,
        message: '请先在设置中保存 WebDAV 密码',
      );
      if (mounted) {
        setState(() {
          status = '同步失败：请先在设置中保存 WebDAV 密码';
          syncing = false;
        });
      }
      return;
    }
    final client = http.Client();
    final sync = WebDavHistorySyncService(
      client: client,
      historyRepository: widget.store,
    );
    final WebDavHistorySyncResult result;
    try {
      result = await webdavSyncRetryPolicy.run(
        () => sync.sync(WebDavCredentials(
          baseUrl: widget.settings.webdavUrl,
          username: widget.settings.webdavUsername,
          password: password ?? '',
        )),
      );
    } finally {
      client.close();
    }
    await _loadHistory();
    final nextStatus = result.isSuccess
        ? '$reason 成功：远程 ${result.downloadedCount} 条，本机 ${result.visibleCount} 条'
        : '$reason 失败';
    await _recordSyncStatus(
      statusText: nextStatus,
      errorText:
          result.isSuccess ? '' : result.errorMessage ?? '${result.httpCode}',
    );
    await _notifyBackgroundSync(
      quiet: quiet,
      reason: reason,
      success: result.isSuccess,
      message: result.isSuccess
          ? '远程 ${result.downloadedCount} 条，本机 ${result.visibleCount} 条'
          : result.errorMessage ?? 'HTTP ${result.httpCode}',
    );
    if (!mounted) return;
    setState(() {
      status = result.isSuccess
          ? '同步完成：远程 ${result.downloadedCount} 条，本机 ${result.visibleCount} 条'
          : '同步失败：${result.errorMessage ?? result.httpCode}';
      syncing = false;
    });
  }

  Future<void> _notifyBackgroundSync({
    required bool quiet,
    required String reason,
    required bool success,
    required String message,
  }) async {
    if (!quiet || !widget.settings.notificationsEnabled) return;
    try {
      await platformService.showNotification(
        title: 'Pythia $reason${success ? '完成' : '失败'}',
        body: message,
        level: success
            ? WindowsNotificationLevel.info
            : WindowsNotificationLevel.error,
      );
    } catch (_) {
      // Notification failures must never turn a completed history sync into a
      // failed sync or leave the UI in a busy state.
    }
  }

  Future<void> _recordSyncStatus({
    required String statusText,
    required String errorText,
  }) async {
    final next = widget.settings.copyWith(
      webdavLastSyncAt: DateTime.now().toUtc().toIso8601String(),
      webdavLastSyncStatus: statusText,
      webdavLastSyncError: errorText,
    );
    await widget.onSettingsChanged(next);
  }

  TranslationServiceRegistry _registry() {
    final providers = <TranslationProvider>[
      LocalEchoTranslationProvider(),
      if (widget.settings.googleEnabled)
        GoogleTranslationProvider(httpClient: translationHttpClient),
      if (widget.settings.baiduEnabled)
        BaiduTranslationProvider(
          credentialStore: credentialStore,
          httpClient: translationHttpClient,
        ),
      if (widget.settings.youdaoEnabled)
        YoudaoTranslationProvider(
          credentialStore: credentialStore,
          httpClient: translationHttpClient,
        ),
      if (widget.settings.openAICompatibleEnabled)
        OpenAICompatibleTranslationProvider(
          id: PythiaSettings.openAICompatibleServiceId,
          displayName: widget.settings.openAICompatibleName.trim().isEmpty
              ? 'OpenAI Compatible'
              : widget.settings.openAICompatibleName.trim(),
          baseUrl: widget.settings.openAICompatibleBaseUrl,
          model: widget.settings.openAICompatibleModel,
          credentialStore: credentialStore,
          httpClient: translationHttpClient,
        ),
      if (widget.settings.deepLEnabled)
        DeepLTranslationProvider(
          baseUrl: widget.settings.deepLBaseUrl,
          credentialStore: credentialStore,
          httpClient: translationHttpClient,
        ),
      if (widget.settings.libreTranslateEnabled)
        LibreTranslateTranslationProvider(
          baseUrl: widget.settings.libreTranslateBaseUrl,
          credentialStore: credentialStore,
          httpClient: translationHttpClient,
        ),
    ];
    return TranslationServiceRegistry(providers);
  }

  List<(String, String)> _availableTranslateServices() {
    return [
      const ('local', 'Local'),
      if (widget.settings.googleEnabled)
        const (PythiaSettings.googleServiceId, 'Google'),
      if (widget.settings.baiduEnabled)
        const (PythiaSettings.baiduServiceId, '百度翻译'),
      if (widget.settings.youdaoEnabled)
        const (PythiaSettings.youdaoServiceId, '有道翻译'),
      if (widget.settings.openAICompatibleEnabled)
        (
          PythiaSettings.openAICompatibleServiceId,
          widget.settings.openAICompatibleName.trim().isEmpty
              ? 'OpenAI Compatible'
              : widget.settings.openAICompatibleName.trim(),
        ),
      if (widget.settings.deepLEnabled)
        const (PythiaSettings.deepLServiceId, 'DeepL'),
      if (widget.settings.libreTranslateEnabled)
        const (PythiaSettings.libreTranslateServiceId, 'LibreTranslate'),
    ];
  }

  void _toggleTranslateService(String id, bool selected) {
    final enabled = widget.settings.enabledTranslateServices.toList();
    if (selected) {
      enabled.remove(id);
      enabled.insert(0, id);
    } else {
      enabled.remove(id);
    }
    if (enabled.isEmpty) enabled.add('local');
    widget.onSettingsChanged(
      widget.settings.copyWith(enabledTranslateServices: enabled),
    );
  }

  Future<void> _toggleFavorite(PythiaHistoryRecord record) async {
    await widget.store.setFavorite(record.id, !record.isFavorite);
    historyChangeSyncScheduler.historyChanged();
    await _loadHistory();
    setState(() {
      status = record.isFavorite ? '已取消收藏' : '已收藏';
    });
  }

  Future<void> _deleteHistoryRecord(PythiaHistoryRecord record) async {
    await widget.store.markDeleted(record.id);
    historyChangeSyncScheduler.historyChanged();
    await _loadHistory();
    setState(() => status = '已删除历史记录');
  }

  Future<void> _clearHistory() async {
    if (history.isEmpty) return;
    await widget.store.clearVisibleHistory();
    historyChangeSyncScheduler.historyChanged();
    await _loadHistory();
    setState(() => status = '已清空历史记录');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pythia'),
        actions: [
          IconButton(
            tooltip: '历史同步',
            onPressed: syncing ? null : () => _syncHistory(),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      DropdownButton<String>(
                        value: widget.settings.sourceLanguage,
                        items: const [
                          DropdownMenuItem(value: 'auto', child: Text('自动检测')),
                          DropdownMenuItem(value: 'en', child: Text('English')),
                          DropdownMenuItem(value: 'zh-CN', child: Text('简体中文')),
                          DropdownMenuItem(value: 'ja', child: Text('日本語')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          widget.onSettingsChanged(
                            widget.settings.copyWith(sourceLanguage: value),
                          );
                        },
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.arrow_forward),
                      ),
                      DropdownButton<String>(
                        value: widget.settings.targetLanguage,
                        items: const [
                          DropdownMenuItem(value: 'zh-CN', child: Text('简体中文')),
                          DropdownMenuItem(value: 'en', child: Text('English')),
                          DropdownMenuItem(value: 'ja', child: Text('日本語')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          widget.onSettingsChanged(
                            widget.settings.copyWith(targetLanguage: value),
                          );
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '划词翻译',
                        onPressed: translating ? null : _translateSelection,
                        icon: const Icon(Icons.text_fields),
                      ),
                      IconButton(
                        tooltip: '截图翻译',
                        onPressed: translating ? null : _screenshotTranslate,
                        icon: const Icon(Icons.crop_free),
                      ),
                      FilledButton.icon(
                        onPressed: translating ? null : _translate,
                        icon: const Icon(Icons.translate),
                        label: const Text('翻译'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final service in _availableTranslateServices())
                        FilterChip(
                          label: Text(service.$2),
                          selected: widget.settings.enabledTranslateServices
                              .contains(service.$1),
                          onSelected: (selected) =>
                              _toggleTranslateService(service.$1, selected),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TextField(
                      controller: sourceController,
                      focusNode: sourceFocusNode,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: '原文',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _translate(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final result in results)
                            Card(
                              child: ListTile(
                                title: Text(result.serviceName),
                                subtitle: SelectableText(result.text),
                                trailing: IconButton(
                                  tooltip: '复制译文',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () => Clipboard.setData(
                                    ClipboardData(text: result.text),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(status),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          sourceController.clear();
                          setState(() => results = const []);
                        },
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                  if (widget.settings.webdavLastSyncStatus.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        widget.settings.webdavLastSyncStatus,
                        if (widget.settings.webdavLastSyncAt.isNotEmpty)
                          widget.settings.webdavLastSyncAt,
                        if (widget.settings.webdavLastSyncError.isNotEmpty)
                          widget.settings.webdavLastSyncError,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '历史记录',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: history.isEmpty ? null : _clearHistory,
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: historySearchController,
                    focusNode: historySearchFocusNode,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '搜索历史',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _loadHistory(),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    children: [
                      for (final item in history)
                        Card(
                          child: ListTile(
                            leading: IconButton(
                              tooltip: item.isFavorite ? '取消收藏' : '收藏',
                              icon: Icon(
                                item.isFavorite
                                    ? Icons.star
                                    : Icons.star_border,
                              ),
                              onPressed: () => _toggleFavorite(item),
                            ),
                            title: Text(
                              item.sourceText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.translatedText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${item.service} · ${syncStatusToJson(item.syncStatus)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteHistoryRecord(item),
                            ),
                            onTap: () {
                              sourceController.text = item.sourceText;
                              setState(() => results = [
                                    PythiaTranslationResult(
                                      serviceId: item.service,
                                      serviceName: item.service,
                                      text: item.translatedText,
                                      model: item.model,
                                    ),
                                  ]);
                            },
                          ),
                        ),
                      if (history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            historySearchController.text.trim().isEmpty
                                ? '暂无历史记录'
                                : '没有匹配的历史记录',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    final next = await showDialog<PythiaSettings>(
      context: context,
      builder: (context) => SettingsDialog(
        settings: widget.settings,
        credentialStore: credentialStore,
        historyRepository: widget.store,
      ),
    );
    if (next != null) {
      await widget.onSettingsChanged(next);
      await _loadHistory();
      if (mounted) setState(() => status = '设置已保存');
    }
  }
}

class SettingsDialog extends StatefulWidget {
  final PythiaSettings settings;
  final CredentialStore credentialStore;
  final HistoryRepository historyRepository;

  const SettingsDialog({
    super.key,
    required this.settings,
    required this.credentialStore,
    required this.historyRepository,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late bool saveHistory = widget.settings.saveHistory;
  late PythiaThemeMode themeMode = widget.settings.themeMode;
  late bool launchAtStartup = widget.settings.launchAtStartup;
  late bool closeToTray = widget.settings.closeToTray;
  late bool alwaysOnTop = widget.settings.alwaysOnTop;
  late bool hideOnBlur = widget.settings.hideOnBlur;
  late bool notificationsEnabled = widget.settings.notificationsEnabled;
  late bool autoSync = widget.settings.webdavHistoryAutoSync;
  late WebDavSyncIntervalUnit syncIntervalUnit =
      widget.settings.webdavSyncSchedule.unit;
  late bool googleEnabled = widget.settings.googleEnabled;
  late bool baiduEnabled = widget.settings.baiduEnabled;
  late bool youdaoEnabled = widget.settings.youdaoEnabled;
  late bool openAICompatibleEnabled = widget.settings.openAICompatibleEnabled;
  late bool deepLEnabled = widget.settings.deepLEnabled;
  late bool libreTranslateEnabled = widget.settings.libreTranslateEnabled;
  late final showWindowHotkey = TextEditingController(
    text: widget.settings.showWindowHotkey,
  );
  late final selectionTranslateHotkey = TextEditingController(
    text: widget.settings.selectionTranslateHotkey,
  );
  late final screenshotTranslateHotkey = TextEditingController(
    text: widget.settings.screenshotTranslateHotkey,
  );
  late final openAICompatibleName = TextEditingController(
    text: widget.settings.openAICompatibleName,
  );
  late final openAICompatibleBaseUrl = TextEditingController(
    text: widget.settings.openAICompatibleBaseUrl,
  );
  late final openAICompatibleModel = TextEditingController(
    text: widget.settings.openAICompatibleModel,
  );
  late final openAICompatibleApiKey = TextEditingController();
  late final deepLBaseUrl = TextEditingController(
    text: widget.settings.deepLBaseUrl,
  );
  late final deepLApiKey = TextEditingController();
  late final libreTranslateBaseUrl = TextEditingController(
    text: widget.settings.libreTranslateBaseUrl,
  );
  late final libreTranslateApiKey = TextEditingController();
  late final baiduAppId = TextEditingController();
  late final baiduSecret = TextEditingController();
  late final youdaoAppKey = TextEditingController();
  late final youdaoSecret = TextEditingController();
  late final webdavUrl = TextEditingController(text: widget.settings.webdavUrl);
  late final webdavUser =
      TextEditingController(text: widget.settings.webdavUsername);
  late final webdavPassword = TextEditingController();
  late final syncIntervalValue = TextEditingController(
    text: '${widget.settings.webdavSyncSchedule.value}',
  );
  String credentialStatus = '';
  String hotkeyStatus = '';
  String connectionStatus = '';
  String updateStatus = '';
  String backupStatus = '';
  bool testingConnection = false;
  bool checkingUpdate = false;
  bool installingUpdate = false;
  bool backupBusy = false;
  PythiaUpdateInfo? availableUpdate;

  @override
  void dispose() {
    showWindowHotkey.dispose();
    selectionTranslateHotkey.dispose();
    screenshotTranslateHotkey.dispose();
    openAICompatibleName.dispose();
    openAICompatibleBaseUrl.dispose();
    openAICompatibleModel.dispose();
    openAICompatibleApiKey.dispose();
    deepLBaseUrl.dispose();
    deepLApiKey.dispose();
    libreTranslateBaseUrl.dispose();
    libreTranslateApiKey.dispose();
    baiduAppId.dispose();
    baiduSecret.dispose();
    youdaoAppKey.dispose();
    youdaoSecret.dispose();
    webdavUrl.dispose();
    webdavUser.dispose();
    webdavPassword.dispose();
    syncIntervalValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                value: saveHistory,
                title: const Text('保存历史记录'),
                onChanged: (value) => setState(() => saveHistory = value),
              ),
              DropdownButtonFormField<PythiaThemeMode>(
                initialValue: themeMode,
                decoration: const InputDecoration(labelText: '外观'),
                items: const [
                  DropdownMenuItem(
                    value: PythiaThemeMode.system,
                    child: Text('跟随系统'),
                  ),
                  DropdownMenuItem(
                    value: PythiaThemeMode.light,
                    child: Text('浅色'),
                  ),
                  DropdownMenuItem(
                    value: PythiaThemeMode.dark,
                    child: Text('深色'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => themeMode = value);
                },
              ),
              SwitchListTile(
                value: launchAtStartup,
                title: const Text('开机启动'),
                subtitle: const Text('保存后立即注册到当前 Windows 用户的启动项。'),
                onChanged: (value) => setState(() => launchAtStartup = value),
              ),
              SwitchListTile(
                value: closeToTray,
                title: const Text('关闭后最小化到托盘'),
                onChanged: (value) => setState(() => closeToTray = value),
              ),
              SwitchListTile(
                value: alwaysOnTop,
                title: const Text('翻译窗口置顶'),
                onChanged: (value) => setState(() => alwaysOnTop = value),
              ),
              SwitchListTile(
                value: hideOnBlur,
                title: const Text('失焦后隐藏翻译窗口'),
                onChanged: (value) => setState(() => hideOnBlur = value),
              ),
              SwitchListTile(
                value: notificationsEnabled,
                title: const Text('系统通知'),
                subtitle: const Text('后台自动同步完成或失败时显示 Windows 通知。'),
                onChanged: (value) =>
                    setState(() => notificationsEnabled = value),
              ),
              const Divider(),
              HotkeyRecorderField(
                controller: showWindowHotkey,
                label: '显示窗口快捷键',
              ),
              HotkeyRecorderField(
                controller: selectionTranslateHotkey,
                label: '划词翻译快捷键',
              ),
              HotkeyRecorderField(
                controller: screenshotTranslateHotkey,
                label: '截图翻译快捷键',
              ),
              if (hotkeyStatus.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hotkeyStatus,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const Divider(),
              SwitchListTile(
                value: googleEnabled,
                title: const Text('启用 Google 翻译'),
                subtitle: const Text('无需 API Key，可作为默认在线翻译服务。'),
                onChanged: (value) => setState(() => googleEnabled = value),
              ),
              const Divider(),
              SwitchListTile(
                value: baiduEnabled,
                title: const Text('启用百度翻译'),
                subtitle:
                    const Text('AppID 和密钥保存在 Windows Credential Manager。'),
                onChanged: (value) => setState(() => baiduEnabled = value),
              ),
              TextField(
                controller: baiduAppId,
                enabled: baiduEnabled,
                decoration: const InputDecoration(
                  labelText: '百度 AppID',
                  helperText: '留空表示不修改已保存的 Windows 凭据。',
                ),
              ),
              TextField(
                controller: baiduSecret,
                enabled: baiduEnabled,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '百度密钥',
                  helperText: '留空表示不修改已保存的 Windows 凭据。',
                ),
              ),
              const Divider(),
              SwitchListTile(
                value: youdaoEnabled,
                title: const Text('启用有道翻译'),
                subtitle:
                    const Text('AppKey 和密钥保存在 Windows Credential Manager。'),
                onChanged: (value) => setState(() => youdaoEnabled = value),
              ),
              TextField(
                controller: youdaoAppKey,
                enabled: youdaoEnabled,
                decoration: const InputDecoration(
                  labelText: '有道 AppKey',
                  helperText: '留空表示不修改已保存的 Windows 凭据。',
                ),
              ),
              TextField(
                controller: youdaoSecret,
                enabled: youdaoEnabled,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '有道密钥',
                  helperText: '留空表示不修改已保存的 Windows 凭据。',
                ),
              ),
              const Divider(),
              SwitchListTile(
                value: openAICompatibleEnabled,
                title: const Text('启用 OpenAI-compatible 翻译服务'),
                subtitle: const Text(
                  '兼容 OpenAI Chat Completions 的服务会显示在主界面多选服务里。',
                ),
                onChanged: (value) =>
                    setState(() => openAICompatibleEnabled = value),
              ),
              TextField(
                controller: openAICompatibleName,
                decoration: const InputDecoration(labelText: '服务显示名称'),
              ),
              TextField(
                controller: openAICompatibleBaseUrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  helperText:
                      '例如 https://api.openai.com/v1，不要包含 /chat/completions。',
                ),
              ),
              TextField(
                controller: openAICompatibleModel,
                decoration: const InputDecoration(labelText: '模型'),
              ),
              TextField(
                controller: openAICompatibleApiKey,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  helperText: '留空表示不修改已保存的 Windows 凭据。',
                ),
              ),
              const Divider(),
              SwitchListTile(
                value: deepLEnabled,
                title: const Text('启用 DeepL'),
                subtitle: const Text('支持 DeepL Free 与 Pro API。'),
                onChanged: (value) => setState(() => deepLEnabled = value),
              ),
              TextField(
                controller: deepLBaseUrl,
                enabled: deepLEnabled,
                decoration: const InputDecoration(
                  labelText: 'DeepL Base URL',
                  helperText: 'Free 默认 https://api-free.deepl.com/v2',
                ),
              ),
              TextField(
                controller: deepLApiKey,
                enabled: deepLEnabled,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'DeepL API Key',
                  helperText: '留空表示不修改已保存的 Windows 凭据。',
                ),
              ),
              const Divider(),
              SwitchListTile(
                value: libreTranslateEnabled,
                title: const Text('启用 LibreTranslate'),
                subtitle: const Text('可连接公共实例或自托管实例。'),
                onChanged: (value) =>
                    setState(() => libreTranslateEnabled = value),
              ),
              TextField(
                controller: libreTranslateBaseUrl,
                enabled: libreTranslateEnabled,
                decoration: const InputDecoration(
                  labelText: 'LibreTranslate Base URL',
                  helperText: '例如 https://libretranslate.com',
                ),
              ),
              TextField(
                controller: libreTranslateApiKey,
                enabled: libreTranslateEnabled,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'LibreTranslate API Key（可选）',
                  helperText: '留空表示不修改已保存的 Windows 凭据。',
                ),
              ),
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '备份与恢复',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: backupBusy ? null : _exportPortableBackup,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('导出本地备份'),
                    ),
                    OutlinedButton.icon(
                      onPressed: backupBusy ? null : _restorePortableBackup,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('从备份恢复'),
                    ),
                    OutlinedButton.icon(
                      onPressed: backupBusy ? null : _backupToWebDav,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('备份到 WebDAV'),
                    ),
                    OutlinedButton.icon(
                      onPressed: backupBusy ? null : _restoreFromWebDav,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('从 WebDAV 恢复'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '备份包含可移植翻译设置和历史记录，不包含 API Key、WebDAV 凭据、快捷键、启动项或窗口状态。',
                ),
              ),
              if (backupStatus.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(backupStatus),
                ),
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.settings.webdavUrl.isEmpty
                      ? '当前未配置 WebDAV。'
                      : '当前 WebDAV：${widget.settings.webdavUsername.isEmpty ? '匿名' : widget.settings.webdavUsername} · ${widget.settings.webdavUrl}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (widget.settings.webdavLastSyncStatus.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    [
                      widget.settings.webdavLastSyncStatus,
                      if (widget.settings.webdavLastSyncAt.isNotEmpty)
                        widget.settings.webdavLastSyncAt,
                      if (widget.settings.webdavLastSyncError.isNotEmpty)
                        widget.settings.webdavLastSyncError,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: webdavUrl,
                decoration: const InputDecoration(labelText: 'WebDAV 地址'),
              ),
              TextField(
                controller: webdavUser,
                decoration: const InputDecoration(labelText: 'WebDAV 用户名'),
              ),
              TextField(
                controller: webdavPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'WebDAV 密码或令牌',
                  helperText: '留空表示不修改已保存的 Windows 凭据。',
                ),
              ),
              if (credentialStatus.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    credentialStatus,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (connectionStatus.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(connectionStatus),
                ),
              SwitchListTile(
                value: autoSync,
                title: const Text('自动同步历史记录'),
                onChanged: (value) => setState(() => autoSync = value),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: syncIntervalValue,
                      enabled: autoSync,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '自动同步间隔',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<WebDavSyncIntervalUnit>(
                      initialValue: syncIntervalUnit,
                      decoration: const InputDecoration(labelText: '单位'),
                      items: [
                        for (final unit in WebDavSyncIntervalUnit.values)
                          DropdownMenuItem(
                            value: unit,
                            child: Text(unit.label),
                          ),
                      ],
                      onChanged: autoSync
                          ? (value) {
                              if (value != null) {
                                setState(() => syncIntervalUnit = value);
                              }
                            }
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'API Key 与 WebDAV 密码必须通过 Windows Credential Manager/DPAPI 平台通道保存，不写入 settings.json。',
              ),
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前版本：$pythiaCurrentVersion',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (updateStatus.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(updateStatus),
                ),
              if (availableUpdate?.installer != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.icon(
                      onPressed:
                          installingUpdate ? null : _downloadAndInstallUpdate,
                      icon: installingUpdate
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt),
                      label: Text(
                        installingUpdate ? '正在准备更新' : '下载并安装',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: checkingUpdate ? null : _checkForUpdates,
          child: const Text('检查更新'),
        ),
        TextButton(
          onPressed: _clearWebDavConfig,
          child: const Text('清除 WebDAV'),
        ),
        TextButton(
          onPressed: testingConnection ? null : _testWebDavConnection,
          child: const Text('测试连接'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            if (!_validateHotkeys()) return;
            if (autoSync && webdavUrl.text.trim().isEmpty) {
              setState(() {
                connectionStatus = '启用自动同步前，请先填写 WebDAV 地址。';
              });
              return;
            }
            final syncSchedule = WebDavSyncSchedule(
              int.tryParse(syncIntervalValue.text.trim()) ?? 0,
              syncIntervalUnit,
            );
            try {
              syncSchedule.validated();
            } on FormatException catch (error) {
              setState(() => connectionStatus = error.message.toString());
              return;
            }
            final password = webdavPassword.text;
            final providerApiKey = openAICompatibleApiKey.text;
            final credentialValues = <String, String>{
              openAICompatibleApiKeySecretKey: providerApiKey,
              deepLApiKeySecretKey: deepLApiKey.text,
              libreTranslateApiKeySecretKey: libreTranslateApiKey.text,
              baiduAppIdSecretKey: baiduAppId.text,
              baiduSecretKey: baiduSecret.text,
              youdaoAppKeySecretKey: youdaoAppKey.text,
              youdaoSecretKey: youdaoSecret.text,
            };
            try {
              for (final entry in credentialValues.entries) {
                if (entry.value.isNotEmpty) {
                  await widget.credentialStore.writeSecret(
                    entry.key,
                    entry.value,
                  );
                }
              }
            } catch (error) {
              setState(() => credentialStatus = '保存 API Key 失败：$error');
              return;
            }
            if (password.isNotEmpty) {
              try {
                await widget.credentialStore.writeSecret(
                  webdavPasswordSecretKey,
                  password,
                );
              } catch (error) {
                setState(() => credentialStatus = '保存 Windows 凭据失败：$error');
                return;
              }
            }
            if (!context.mounted) return;
            final enabledServices =
                widget.settings.enabledTranslateServices.toList();
            _updateNewProviderSelection(
              enabledServices,
              id: PythiaSettings.googleServiceId,
              enabled: googleEnabled,
              wasEnabled: widget.settings.googleEnabled,
            );
            _updateNewProviderSelection(
              enabledServices,
              id: PythiaSettings.baiduServiceId,
              enabled: baiduEnabled,
              wasEnabled: widget.settings.baiduEnabled,
            );
            _updateNewProviderSelection(
              enabledServices,
              id: PythiaSettings.youdaoServiceId,
              enabled: youdaoEnabled,
              wasEnabled: widget.settings.youdaoEnabled,
            );
            if (openAICompatibleEnabled &&
                !widget.settings.openAICompatibleEnabled) {
              enabledServices.remove(PythiaSettings.openAICompatibleServiceId);
              enabledServices.insert(
                0,
                PythiaSettings.openAICompatibleServiceId,
              );
            } else if (!openAICompatibleEnabled) {
              enabledServices.remove(PythiaSettings.openAICompatibleServiceId);
            }
            _updateNewProviderSelection(
              enabledServices,
              id: PythiaSettings.deepLServiceId,
              enabled: deepLEnabled,
              wasEnabled: widget.settings.deepLEnabled,
            );
            _updateNewProviderSelection(
              enabledServices,
              id: PythiaSettings.libreTranslateServiceId,
              enabled: libreTranslateEnabled,
              wasEnabled: widget.settings.libreTranslateEnabled,
            );
            if (enabledServices.isEmpty) enabledServices.add('local');
            Navigator.pop(
              context,
              widget.settings.copyWith(
                saveHistory: saveHistory,
                themeMode: themeMode,
                launchAtStartup: launchAtStartup,
                closeToTray: closeToTray,
                alwaysOnTop: alwaysOnTop,
                hideOnBlur: hideOnBlur,
                notificationsEnabled: notificationsEnabled,
                showWindowHotkey: showWindowHotkey.text.trim().isEmpty
                    ? 'Ctrl+Alt+P'
                    : showWindowHotkey.text.trim(),
                selectionTranslateHotkey:
                    selectionTranslateHotkey.text.trim().isEmpty
                        ? 'Ctrl+Alt+E'
                        : selectionTranslateHotkey.text.trim(),
                screenshotTranslateHotkey:
                    screenshotTranslateHotkey.text.trim().isEmpty
                        ? 'Ctrl+Alt+S'
                        : screenshotTranslateHotkey.text.trim(),
                enabledTranslateServices: enabledServices,
                googleEnabled: googleEnabled,
                baiduEnabled: baiduEnabled,
                youdaoEnabled: youdaoEnabled,
                openAICompatibleEnabled: openAICompatibleEnabled,
                openAICompatibleName: openAICompatibleName.text.trim().isEmpty
                    ? 'OpenAI Compatible'
                    : openAICompatibleName.text.trim(),
                openAICompatibleBaseUrl:
                    openAICompatibleBaseUrl.text.trim().isEmpty
                        ? 'https://api.openai.com/v1'
                        : openAICompatibleBaseUrl.text.trim(),
                openAICompatibleModel: openAICompatibleModel.text.trim().isEmpty
                    ? 'gpt-4o-mini'
                    : openAICompatibleModel.text.trim(),
                deepLEnabled: deepLEnabled,
                deepLBaseUrl: deepLBaseUrl.text.trim().isEmpty
                    ? 'https://api-free.deepl.com/v2'
                    : deepLBaseUrl.text.trim(),
                libreTranslateEnabled: libreTranslateEnabled,
                libreTranslateBaseUrl: libreTranslateBaseUrl.text.trim().isEmpty
                    ? 'https://libretranslate.com'
                    : libreTranslateBaseUrl.text.trim(),
                webdavUrl: webdavUrl.text.trim(),
                webdavUsername: webdavUser.text.trim(),
                webdavHistoryAutoSync: autoSync,
                webdavHistorySyncIntervalValue: syncSchedule.value,
                webdavHistorySyncIntervalUnit: syncSchedule.unit.storageValue,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  bool _validateHotkeys() {
    final controllers = <String, TextEditingController>{
      '显示窗口': showWindowHotkey,
      '划词翻译': selectionTranslateHotkey,
      '截图翻译': screenshotTranslateHotkey,
    };
    try {
      for (final controller in controllers.values) {
        controller.text = HotkeyAccelerator.parse(controller.text).canonical;
      }
      final duplicates = HotkeyAccelerator.duplicateCanonicalValues({
        for (final entry in controllers.entries) entry.key: entry.value.text,
      });
      if (duplicates.isNotEmpty) {
        final conflict = duplicates.entries.first;
        setState(() {
          hotkeyStatus = '${conflict.value.join('、')}不能使用相同快捷键 ${conflict.key}';
        });
        return false;
      }
      setState(() => hotkeyStatus = '');
      return true;
    } on FormatException catch (error) {
      setState(() => hotkeyStatus = error.message.toString());
      return false;
    }
  }

  Future<void> _exportPortableBackup() async {
    setState(() {
      backupBusy = true;
      backupStatus = '正在准备备份...';
    });
    try {
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final suggestedName =
          'Pythia-backup-${now.year}${two(now.month)}${two(now.day)}.json';
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Pythia JSON backup',
            extensions: ['json'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
      if (location == null) {
        if (mounted) {
          setState(() {
            backupBusy = false;
            backupStatus = '';
          });
        }
        return;
      }
      final encoded = await PortableBackupService(widget.historyRepository)
          .create(widget.settings);
      final path = location.path.toLowerCase().endsWith('.json')
          ? location.path
          : '${location.path}.json';
      await File(path).writeAsString(encoded, flush: true);
      if (mounted) {
        setState(() {
          backupBusy = false;
          backupStatus = '备份已导出：$path';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          backupBusy = false;
          backupStatus = '导出失败：$error';
        });
      }
    }
  }

  Future<void> _restorePortableBackup() async {
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Pythia JSON backup',
          extensions: ['json'],
          mimeTypes: ['application/json'],
        ),
      ],
    );
    if (selected == null || !mounted) return;
    if (await selected.length() > 64 * 1024 * 1024) {
      setState(() => backupStatus = '恢复失败：备份文件不能超过 64 MB。');
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('恢复 Pythia 备份'),
            content: const Text(
              '将合并备份中的历史记录，并恢复可移植翻译设置。API Key、WebDAV 凭据、快捷键、启动项和窗口状态不会被覆盖。继续吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('恢复'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      backupBusy = true;
      backupStatus = '正在验证并恢复备份...';
    });
    try {
      final result = await PortableBackupService(widget.historyRepository)
          .restore(await selected.readAsString(), widget.settings);
      if (!mounted) return;
      Navigator.pop(context, result.settings);
    } catch (error) {
      if (mounted) {
        setState(() {
          backupBusy = false;
          backupStatus = '恢复失败：$error';
        });
      }
    }
  }

  Future<WebDavCredentials> _backupWebDavCredentials() async {
    final url = webdavUrl.text.trim();
    if (url.isEmpty) throw StateError('请先填写 WebDAV 地址。');
    final username = webdavUser.text.trim();
    final typedPassword = webdavPassword.text;
    final password = typedPassword.isNotEmpty
        ? typedPassword
        : await widget.credentialStore.readSecret(webdavPasswordSecretKey) ??
            '';
    if (username.isNotEmpty && password.isEmpty) {
      throw StateError('请先输入或保存 WebDAV 密码。');
    }
    return WebDavCredentials(
      baseUrl: url,
      username: username,
      password: password,
    );
  }

  Future<void> _backupToWebDav() async {
    setState(() {
      backupBusy = true;
      backupStatus = '正在上传 WebDAV 备份...';
    });
    final client = http.Client();
    try {
      final encoded = await PortableBackupService(widget.historyRepository)
          .create(widget.settings);
      await WebDavPortableBackupService(client: client).upload(
        encoded,
        await _backupWebDavCredentials(),
      );
      if (mounted) {
        setState(() {
          backupBusy = false;
          backupStatus = 'WebDAV 备份完成。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          backupBusy = false;
          backupStatus = 'WebDAV 备份失败：$error';
        });
      }
    } finally {
      client.close();
    }
  }

  Future<void> _restoreFromWebDav() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('从 WebDAV 恢复'),
            content: const Text(
              '将下载并验证 Pythia 可移植备份，合并历史记录并恢复翻译设置。凭据、快捷键、启动项和窗口状态不会被覆盖。继续吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('下载并恢复'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      backupBusy = true;
      backupStatus = '正在下载并验证 WebDAV 备份...';
    });
    final client = http.Client();
    try {
      final encoded = await WebDavPortableBackupService(client: client)
          .download(await _backupWebDavCredentials());
      if (utf8.encode(encoded).length > 64 * 1024 * 1024) {
        throw StateError('远程备份不能超过 64 MB。');
      }
      final result = await PortableBackupService(widget.historyRepository)
          .restore(encoded, widget.settings);
      if (!mounted) return;
      Navigator.pop(context, result.settings);
    } catch (error) {
      if (mounted) {
        setState(() {
          backupBusy = false;
          backupStatus = 'WebDAV 恢复失败：$error';
        });
      }
    } finally {
      client.close();
    }
  }

  static void _updateNewProviderSelection(
    List<String> enabledServices, {
    required String id,
    required bool enabled,
    required bool wasEnabled,
  }) {
    if (!enabled) {
      enabledServices.remove(id);
    } else if (!wasEnabled || !enabledServices.contains(id)) {
      enabledServices.remove(id);
      enabledServices.insert(0, id);
    }
  }

  Future<void> _testWebDavConnection() async {
    setState(() {
      testingConnection = true;
      connectionStatus = '正在测试 WebDAV 连接...';
      credentialStatus = '';
    });
    final typedPassword = webdavPassword.text;
    final String? password;
    if (typedPassword.isNotEmpty) {
      password = typedPassword;
    } else {
      try {
        password = await widget.credentialStore.readSecret(
          webdavPasswordSecretKey,
        );
      } catch (error) {
        setState(() {
          testingConnection = false;
          credentialStatus = '读取 WebDAV 凭据失败：$error';
          connectionStatus = '';
        });
        return;
      }
    }

    if (webdavUser.text.trim().isNotEmpty &&
        (password == null || password.isEmpty)) {
      setState(() {
        testingConnection = false;
        connectionStatus = '测试失败：请先输入或保存 WebDAV 密码。';
      });
      return;
    }

    final client = http.Client();
    final service = WebDavHistorySyncService(
      client: client,
      historyRepository: widget.historyRepository,
    );
    final WebDavConnectionTestResult result;
    try {
      result = await service.testConnection(WebDavCredentials(
        baseUrl: webdavUrl.text.trim(),
        username: webdavUser.text.trim(),
        password: password ?? '',
      ));
    } finally {
      client.close();
    }
    if (!mounted) return;
    setState(() {
      testingConnection = false;
      connectionStatus =
          result.isSuccess ? result.message : '测试失败：${result.message}';
    });
  }

  Future<void> _clearWebDavConfig() async {
    try {
      await widget.credentialStore.deleteSecret(webdavPasswordSecretKey);
    } catch (error) {
      setState(() => credentialStatus = '清除 WebDAV 凭据失败：$error');
      return;
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      widget.settings.copyWith(
        webdavUrl: '',
        webdavUsername: '',
        webdavHistoryAutoSync: false,
        webdavLastSyncAt: '',
        webdavLastSyncStatus: '',
        webdavLastSyncError: '',
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      checkingUpdate = true;
      updateStatus = '正在检查更新...';
      availableUpdate = null;
    });
    final client = http.Client();
    try {
      final info = await PythiaUpdateChecker(client: client).check();
      if (!mounted) return;
      setState(() {
        checkingUpdate = false;
        availableUpdate = info.isNewer ? info : null;
        updateStatus = info.isNewer
            ? info.installer == null
                ? '发现新版本 ${info.latestVersion}，但 Release 缺少 Windows x64 安装器或 SHA-256 校验文件：${info.releaseUrl}'
                : '发现新版本 ${info.latestVersion}，可安全下载并安装。'
            : '当前已是最新版本。Release：${info.releaseUrl}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        checkingUpdate = false;
        updateStatus = '检查更新失败：$error';
      });
    } finally {
      client.close();
    }
  }

  Future<void> _downloadAndInstallUpdate() async {
    final info = availableUpdate;
    final asset = info?.installer;
    if (info == null || asset == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('安装 Pythia ${info.latestVersion}'),
            content: const Text(
              'Pythia 将从 GitHub 下载 Windows x64 安装器，验证文件大小和 SHA-256 后启动安装。安装器启动后当前应用会退出。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('下载并安装'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      installingUpdate = true;
      updateStatus = '正在下载 ${asset.name}...';
    });
    final client = http.Client();
    try {
      final temporary = await getTemporaryDirectory();
      final updateDirectory = Directory(
        '${temporary.path}${Platform.pathSeparator}Pythia${Platform.pathSeparator}updates',
      );
      final file =
          await PythiaReleaseInstaller(client: client).downloadVerified(
        asset,
        updateDirectory,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          final percent = (received * 100 / total).clamp(0, 100).round();
          setState(() => updateStatus = '正在下载：$percent%');
        },
      );
      if (!mounted) return;
      setState(() => updateStatus = '校验通过，正在启动安装器...');
      await const MethodChannelWindowsPlatformService()
          .launchUpdateInstaller(file.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        installingUpdate = false;
        updateStatus = '更新安装失败：$error';
      });
    } finally {
      client.close();
    }
  }
}
