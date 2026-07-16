# Public plugin sources

Each child directory contains the auditable source and assets for one package in `Plugins/`:

- `provider.js` is the provider-specific translation implementation.
- `manifest.json`, `LICENSE`, and optional icons are copied into the package.
- `shared/long-text-wrapper.js` is appended as the package entry adapter. It preserves whitespace, splits long documents at semantic boundaries, translates chunks sequentially, and retries transient failures.

Rebuild all public packages and refresh `Plugins/catalog.json` from the repository root:

```sh
node script/build_public_plugins.mjs
node script/validate_public_plugins.mjs
node script/test_public_plugin_long_text.mjs
```

The builder creates deterministic ZIP-compatible `.pythia` archives without reading Pythia's application-support directory or any local credential/configuration file.

## 中文

每个子目录对应 `Plugins/` 中的一个公开插件包：

- `provider.js` 是服务商专用的翻译实现。
- `manifest.json`、`LICENSE` 和可选图标会写入插件包。
- `shared/long-text-wrapper.js` 是统一入口适配器，负责保留空白、按语义边界切分长文、顺序翻译各片段，并重试瞬时错误。

上面的三个命令分别用于重建插件包、校验公开内容及执行长文本回归测试。构建器不会读取 Pythia 的应用数据目录、凭据文件或用户配置。
