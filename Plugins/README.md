# Pythia Plugin Downloads / Pythia 插件下载

[English](#english) | [简体中文](#简体中文)

## English

This directory contains separately downloadable `.pythia` translation plugins for Pythia 1.0.0. They are not bundled with the Pythia application or installer. Version 1.1.1 translates long documents in bounded semantic chunks, keeps decimal numbers, dates, times, versions, and scientific notation intact at chunk boundaries, and retries transient network, timeout, rate-limit, and provider 5xx failures without changing plugin IDs or configuration keys.

Each package was rebuilt from a locally converted compatibility plugin and contains only:

- `manifest.json`
- `main.js`
- the plugin icon when available
- the repository's GPL-3.0 `LICENSE`

The packages do **not** contain API keys, passwords, WebDAV credentials, user history, `plugin-configs.json`, legacy backups, conversion logs, local paths, or test fixtures.

### Install

1. Download the required `.pythia` file.
2. Open Pythia.
3. Go to **Settings > Plugins**.
4. Select **Install Plugin**.
5. Choose the downloaded file.
6. Configure your own API key and service settings inside Pythia.
7. Enable and order the service from the main window's service panel.

### Packages

| Plugin | Package | SHA-256 | Source attribution |
| --- | --- | --- | --- |
| Alibaba Cloud Qwen3.5-35B-A3B | [Download](aliyun-qwen3.5-35b-a3b-1.1.1.pythia) | `6d741a87726be5a0357146399d1ad02b88c4894d105c555ebd5654e574a9fda1` | Legacy metadata: `pot-app` |
| DeepSeek | [Download](deepseek-1.1.1.pythia) | `84bb00d0b97bcdbae504d30cc3cee751681d5aa915bb8bfe84b8ef65080d539c` | [Tzulao55](https://github.com/Tzulao55/pot-app-translate-plugin-deepseek) |
| Qiniu GLM 4.5 Air (free) | [Download](qiniu-glm-4.5-air-free-1.1.1.pythia) | `2ea5cf4a6a6424458d3a0b1e83816fc361fed6dd070d8c21b45540c1f58728f9` | Legacy metadata: `pot-app` |
| SenseNova | [Download](sensenova-1.1.1.pythia) | `bd1a34b5fed474a0105fd9a7308c23ffa43791cde6b9d84747c9f8e41de0472c` | [SenseNova Platform](https://platform.sensenova.cn) |
| SiliconFlow | [Download](siliconflow-1.1.1.pythia) | `a06fd5af3bb6e63866d1a28fd3fa613c84f8493f536517ab21f7172528f353af` | [xubai2001](https://github.com/xubai2001/pot-app-translate-plugin-siliconflow) |
| Xiaomi MiMo | [Download](xiaomi-mimo-1.1.1.pythia) | `0aaa058dddb81f230bdc49a19a32712b4ceb2928c31e126b72ff4d219b741a5a` | [Xiaomi MiMo API](https://platform.xiaomimimo.com/docs/zh-CN/api/chat/openai-api) |

The machine-readable catalog is [`catalog.json`](catalog.json).

### Verify a Download

PowerShell:

```powershell
(Get-FileHash -Algorithm SHA256 .\deepseek-1.1.1.pythia).Hash.ToLowerInvariant()
```

macOS:

```sh
shasum -a 256 deepseek-1.1.1.pythia
```

### Scope and Support

- Every package declares both `macos` and `windows` support.
- Users must supply their own provider credentials.
- Provider endpoints, models, quotas, and availability are controlled by the respective provider and can change independently of Pythia.
- These are converted compatibility packages. New plugin development should use the native Pythia contract directly.
- Auditable package sources and the shared long-text adapter are under [`Sources`](Sources/); `../script/build_public_plugins.mjs` rebuilds deterministic packages and catalog checksums.
- See the [complete plugin development guide](../Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md).
- Source and converted code are distributed under the repository's [GPL-3.0 license](../LICENSE). Original author and service rights remain with their respective owners.

## 简体中文

本目录提供可单独下载的 Pythia 1.0.0 `.pythia` 翻译插件。它们不会捆绑在 Pythia 应用或安装程序中。1.1.1 版会把长文按语义边界分成受控片段顺序翻译，确保小数、日期、时间、版本号和科学计数法不会在片段边界被拆开，并自动重试瞬时网络错误、超时、限流和服务端 5xx；插件 ID 与配置字段保持不变。

每个包都从本机已经转换的兼容插件重新整理，只包含：

- `manifest.json`
- `main.js`
- 存在时附带插件图标
- 仓库的 GPL-3.0 `LICENSE`

插件包不包含 API Key、密码、WebDAV 凭据、用户历史、`plugin-configs.json`、旧插件备份、迁移日志、本机路径或测试 Fixture。

### 安装方法

1. 下载需要的 `.pythia` 文件。
2. 打开 Pythia。
3. 进入 **设置 > 插件**。
4. 点击 **安装插件**。
5. 选择下载的文件。
6. 在 Pythia 中填写自己的 API Key 和服务配置。
7. 在主窗口服务面板中启用并调整顺序。

### 插件列表

| 插件 | 下载 | SHA-256 | 来源说明 |
| --- | --- | --- | --- |
| 阿里云 Qwen3.5-35B-A3B | [下载](aliyun-qwen3.5-35b-a3b-1.1.1.pythia) | `6d741a87726be5a0357146399d1ad02b88c4894d105c555ebd5654e574a9fda1` | 旧插件元数据：`pot-app` |
| DeepSeek | [下载](deepseek-1.1.1.pythia) | `84bb00d0b97bcdbae504d30cc3cee751681d5aa915bb8bfe84b8ef65080d539c` | [Tzulao55](https://github.com/Tzulao55/pot-app-translate-plugin-deepseek) |
| 七牛 GLM 4.5 Air（free） | [下载](qiniu-glm-4.5-air-free-1.1.1.pythia) | `2ea5cf4a6a6424458d3a0b1e83816fc361fed6dd070d8c21b45540c1f58728f9` | 旧插件元数据：`pot-app` |
| SenseNova | [下载](sensenova-1.1.1.pythia) | `bd1a34b5fed474a0105fd9a7308c23ffa43791cde6b9d84747c9f8e41de0472c` | [SenseNova 平台](https://platform.sensenova.cn) |
| SiliconFlow | [下载](siliconflow-1.1.1.pythia) | `a06fd5af3bb6e63866d1a28fd3fa613c84f8493f536517ab21f7172528f353af` | [xubai2001](https://github.com/xubai2001/pot-app-translate-plugin-siliconflow) |
| Xiaomi MiMo | [下载](xiaomi-mimo-1.1.1.pythia) | `0aaa058dddb81f230bdc49a19a32712b4ceb2928c31e126b72ff4d219b741a5a` | [Xiaomi MiMo API](https://platform.xiaomimimo.com/docs/zh-CN/api/chat/openai-api) |

机器可读目录是 [`catalog.json`](catalog.json)。

### 校验下载

PowerShell：

```powershell
(Get-FileHash -Algorithm SHA256 .\deepseek-1.1.1.pythia).Hash.ToLowerInvariant()
```

macOS：

```sh
shasum -a 256 deepseek-1.1.1.pythia
```

### 范围与说明

- 每个插件都声明支持 `macos` 和 `windows`。
- 用户必须使用自己的服务凭据。
- 服务端点、模型、额度和可用性由对应服务商控制，可能独立变化。
- 这些是已经转换的兼容插件。新插件应直接使用 Pythia 原生契约开发。
- 可审计的插件源文件和共享长文适配器位于 [`Sources`](Sources/)；运行 `../script/build_public_plugins.mjs` 可确定性重建插件包并刷新目录校验值。
- 完整规范见 [Pythia 插件开发指南](../Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)。
- 源码和转换代码按仓库 [GPL-3.0 许可证](../LICENSE)发布；原作者和服务商的相关权利归各自所有者。
