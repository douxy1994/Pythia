import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/plugin_system.dart';
import '../core/translation_service.dart';

class PluginSettingsPanel extends StatefulWidget {
  final PythiaPluginManager? manager;
  final Future<void> Function(String? selectedServiceId) onChanged;

  const PluginSettingsPanel({
    super.key,
    required this.manager,
    required this.onChanged,
  });

  @override
  State<PluginSettingsPanel> createState() => _PluginSettingsPanelState();
}

class _PluginSettingsPanelState extends State<PluginSettingsPanel> {
  List<InstalledPythiaPlugin> plugins = const [];
  bool busy = false;
  String status = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PluginSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) _reload();
  }

  Future<void> _reload() async {
    final manager = widget.manager;
    if (manager == null) return;
    try {
      final next = await manager.listInstalled();
      if (mounted) setState(() => plugins = next);
    } catch (error) {
      if (mounted) setState(() => status = '读取插件失败：$error');
    }
  }

  Future<void> _install() async {
    final manager = widget.manager;
    if (manager == null) return;
    final chooseFile = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('安装插件'),
        content: const Text('可安装打包后的插件文件，也可选择以 .pythia 或 .potext 结尾的开发目录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('选择开发目录'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择插件文件'),
          ),
        ],
      ),
    );
    if (chooseFile == null) return;
    const types = XTypeGroup(
      label: 'Pythia 插件',
      extensions: ['pythia', 'potext'],
    );
    final FileSystemEntity? selected;
    if (chooseFile) {
      final file = await openFile(acceptedTypeGroups: const [types]);
      selected = file == null ? null : File(file.path);
    } else {
      final directory = await getDirectoryPath(
        confirmButtonText: '安装插件',
      );
      selected = directory == null ? null : Directory(directory);
    }
    if (selected == null) return;
    await _run(() async {
      final result = await manager.install(selected!);
      await _reload();
      await widget.onChanged(result.plugin.serviceId);
      return result.message;
    });
  }

  Future<void> _openDirectory() async {
    final manager = widget.manager;
    if (manager == null) return;
    await manager.rootDirectory.create(recursive: true);
    await _openWithExplorer(manager.rootDirectory.path);
  }

  Future<void> _openGuide() => _openWithExplorer(PythiaPluginManager.guideUrl);

  Future<void> _openWithExplorer(String target) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [target]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [target]);
      } else {
        await Process.start('xdg-open', [target]);
      }
    } catch (error) {
      if (mounted) setState(() => status = '无法打开：$error');
    }
  }

  Future<void> _toggle(InstalledPythiaPlugin plugin, bool enabled) async {
    final manager = widget.manager;
    if (manager == null) return;
    await _run(() async {
      await manager.setEnabled(plugin.manifest.id, enabled);
      await _reload();
      await widget.onChanged(enabled ? plugin.serviceId : null);
      return enabled
          ? '已启用 ${plugin.manifest.name}'
          : '已禁用 ${plugin.manifest.name}';
    });
  }

  Future<void> _delete(InstalledPythiaPlugin plugin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${plugin.manifest.name}？'),
        content: const Text('插件文件、本机配置和安全存储中的插件密钥都会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除插件'),
          ),
        ],
      ),
    );
    if (confirmed != true || widget.manager == null) return;
    await _run(() async {
      await widget.manager!.deletePlugin(plugin);
      await _reload();
      await widget.onChanged(null);
      return '已删除 ${plugin.manifest.name}';
    });
  }

  Future<void> _reconvert(InstalledPythiaPlugin plugin) async {
    final manager = widget.manager;
    if (manager == null) return;
    await _run(() async {
      final converted = await manager.reconvert(plugin);
      await _reload();
      await widget.onChanged(converted.serviceId);
      return '已重新转换 ${converted.manifest.name}';
    });
  }

  Future<void> _test(InstalledPythiaPlugin plugin) async {
    final manager = widget.manager;
    if (manager == null) return;
    await _run(() async {
      final translated = await manager.translate(
        plugin,
        PythiaTranslationRequest(
          text: 'Pythia plugin test',
          sourceLanguage: 'en',
          targetLanguage: 'zh-CN',
          serviceId: plugin.serviceId,
        ),
      );
      await _reload();
      final preview = translated.replaceAll(RegExp(r'\s+'), ' ').trim();
      return '测试成功：${preview.length > 80 ? '${preview.substring(0, 80)}...' : preview}';
    });
  }

  Future<void> _configure(InstalledPythiaPlugin plugin) async {
    final manager = widget.manager;
    if (manager == null) return;
    final current = await manager.configurationFor(plugin.manifest);
    if (!mounted) return;
    final controllers = <String, TextEditingController>{};
    final selected = <String, String>{};
    for (final field in plugin.manifest.configuration) {
      if (field.type == 'select') {
        selected[field.key] = current[field.key] ??
            field.defaultValue ??
            field.options?.keys.firstOrNull ??
            '';
      } else {
        controllers[field.key] = TextEditingController(
          text: current[field.key] ?? field.defaultValue ?? '',
        );
      }
    }
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('配置 ${plugin.manifest.name}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (plugin.manifest.configuration.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('该插件没有可配置项。'),
                    ),
                  for (final field in plugin.manifest.configuration)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: field.type == 'select'
                          ? DropdownButtonFormField<String>(
                              initialValue: selected[field.key],
                              decoration: InputDecoration(
                                labelText: field.label,
                              ),
                              items: [
                                for (final option
                                    in (field.options ?? const {}).entries)
                                  DropdownMenuItem(
                                    value: option.key,
                                    child: Text(option.value),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(
                                    () => selected[field.key] = value,
                                  );
                                }
                              },
                            )
                          : TextField(
                              controller: controllers[field.key],
                              obscureText: field.type == 'secret',
                              decoration: InputDecoration(
                                labelText: field.label,
                                helperText: field.type == 'secret'
                                    ? '保存在 Windows Credential Manager，不写入普通配置。'
                                    : null,
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, {
                  ...selected,
                  for (final entry in controllers.entries)
                    entry.key: entry.value.text,
                });
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (values == null) return;
    await _run(() async {
      await manager.saveConfiguration(plugin.manifest, values);
      return '已保存 ${plugin.manifest.name} 的配置';
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = '';
    });
    try {
      final message = await action();
      if (mounted) setState(() => status = message);
    } catch (error) {
      if (mounted) setState(() => status = '操作失败：$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('插件', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '安装新插件',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                '支持 .pythia 和 .potext 格式，优先推荐 .pythia。.potext 会先自动转换，失败时再进入兼容模式。',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: manager == null || busy ? null : _install,
                    icon: const Icon(Icons.add),
                    label: const Text('安装插件'),
                  ),
                  OutlinedButton.icon(
                    onPressed: manager == null ? null : _openDirectory,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('打开插件目录'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openGuide,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('插件开发指南'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (manager == null)
          const Text('插件运行时正在初始化。')
        else if (plugins.isEmpty)
          const Text('尚未安装插件。发布包不会预装或默认启用第三方插件。')
        else
          for (final plugin in plugins)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plugin.manifest.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: plugin.enabled,
                          onChanged:
                              busy ? null : (value) => _toggle(plugin, value),
                        ),
                      ],
                    ),
                    Text(
                      '${plugin.format.name} · ${plugin.conversionStatus} · v${plugin.manifest.version} · ${plugin.manifest.author}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '权限：${plugin.manifest.permissions.isEmpty ? '无' : plugin.manifest.permissions.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (plugin.conversionWarnings.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        plugin.conversionWarnings.join('\n'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (plugin.lastError.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        '最近错误：${plugin.lastError}',
                        style: TextStyle(color: colors.error),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: busy ? null : () => _configure(plugin),
                          child: const Text('配置'),
                        ),
                        OutlinedButton(
                          onPressed: busy || !plugin.enabled
                              ? null
                              : () => _test(plugin),
                          child: const Text('测试连通性'),
                        ),
                        if (plugin.conversionStatus != 'native')
                          OutlinedButton(
                            onPressed: busy ? null : () => _reconvert(plugin),
                            child: const Text('重新转换'),
                          ),
                        TextButton(
                          onPressed: busy ? null : () => _delete(plugin),
                          child: const Text('删除插件'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText(status),
          ),
        if (busy) const LinearProgressIndicator(),
      ],
    );
  }
}
