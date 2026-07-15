# Pythia Plugin Downloads / Pythia 插件下载

[English](#english) | [简体中文](#简体中文)

## English

This directory contains separately downloadable `.pythia` translation plugins for Pythia 1.0.0. They are not bundled with the Pythia application or installer.

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
| Alibaba Cloud Qwen3.5-35B-A3B | [Download](aliyun-qwen3.5-35b-a3b-1.0.0.pythia) | `da735708dec4ba75bb4edb28eb239a7ed28d699b68b8a37b32a8bb45ac0199cf` | Legacy metadata: `pot-app` |
| DeepSeek | [Download](deepseek-1.0.0.pythia) | `827ae7c0ddf5621b45a5f9c0e2c35602f286f72fdc8da0c985f8bcfd99a20199` | [Tzulao55](https://github.com/Tzulao55/pot-app-translate-plugin-deepseek) |
| Qiniu GLM 4.5 Air (free) | [Download](qiniu-glm-4.5-air-free-1.0.0.pythia) | `69d05ba2ee21ab2fbc0b059c6b4402d76b4092c647d50bd1c6ca74cb37238b36` | Legacy metadata: `pot-app` |
| SenseNova | [Download](sensenova-1.0.0.pythia) | `18218f923eedf35e66c0c059c8f1e3a9be89ae3af4abaec9bd4d5e9806cad967` | [SenseNova Platform](https://platform.sensenova.cn) |
| SiliconFlow | [Download](siliconflow-1.0.0.pythia) | `390a6cfb469a92a6d2cb6b3e98f0693a114b447926f46c24cd7f70f1db9e9307` | [xubai2001](https://github.com/xubai2001/pot-app-translate-plugin-siliconflow) |
| Xiaomi MiMo | [Download](xiaomi-mimo-1.0.0.pythia) | `21a42d0952ebd800868881fe8712aadbc451623bfbc297f855b8251aa145d193` | [Xiaomi MiMo API](https://platform.xiaomimimo.com/docs/zh-CN/api/chat/openai-api) |

The machine-readable catalog is [`catalog.json`](catalog.json).

### Verify a Download

PowerShell:

```powershell
(Get-FileHash -Algorithm SHA256 .\deepseek-1.0.0.pythia).Hash.ToLowerInvariant()
```

macOS:

```sh
shasum -a 256 deepseek-1.0.0.pythia
```

### Scope and Support

- Every package declares both `macos` and `windows` support.
- Users must supply their own provider credentials.
- Provider endpoints, models, quotas, and availability are controlled by the respective provider and can change independently of Pythia.
- These are converted compatibility packages. New plugin development should use the native Pythia contract directly.
- See the [complete plugin development guide](../Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md).
- Source and converted code are distributed under the repository's [GPL-3.0 license](../LICENSE). Original author and service rights remain with their respective owners.

## 简体中文

本目录提供可单独下载的 Pythia 1.0.0 `.pythia` 翻译插件。它们不会捆绑在 Pythia 应用或安装程序中。

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
| 阿里云 Qwen3.5-35B-A3B | [下载](aliyun-qwen3.5-35b-a3b-1.0.0.pythia) | `da735708dec4ba75bb4edb28eb239a7ed28d699b68b8a37b32a8bb45ac0199cf` | 旧插件元数据：`pot-app` |
| DeepSeek | [下载](deepseek-1.0.0.pythia) | `827ae7c0ddf5621b45a5f9c0e2c35602f286f72fdc8da0c985f8bcfd99a20199` | [Tzulao55](https://github.com/Tzulao55/pot-app-translate-plugin-deepseek) |
| 七牛 GLM 4.5 Air（free） | [下载](qiniu-glm-4.5-air-free-1.0.0.pythia) | `69d05ba2ee21ab2fbc0b059c6b4402d76b4092c647d50bd1c6ca74cb37238b36` | 旧插件元数据：`pot-app` |
| SenseNova | [下载](sensenova-1.0.0.pythia) | `18218f923eedf35e66c0c059c8f1e3a9be89ae3af4abaec9bd4d5e9806cad967` | [SenseNova 平台](https://platform.sensenova.cn) |
| SiliconFlow | [下载](siliconflow-1.0.0.pythia) | `390a6cfb469a92a6d2cb6b3e98f0693a114b447926f46c24cd7f70f1db9e9307` | [xubai2001](https://github.com/xubai2001/pot-app-translate-plugin-siliconflow) |
| Xiaomi MiMo | [下载](xiaomi-mimo-1.0.0.pythia) | `21a42d0952ebd800868881fe8712aadbc451623bfbc297f855b8251aa145d193` | [Xiaomi MiMo API](https://platform.xiaomimimo.com/docs/zh-CN/api/chat/openai-api) |

机器可读目录是 [`catalog.json`](catalog.json)。

### 校验下载

PowerShell：

```powershell
(Get-FileHash -Algorithm SHA256 .\deepseek-1.0.0.pythia).Hash.ToLowerInvariant()
```

macOS：

```sh
shasum -a 256 deepseek-1.0.0.pythia
```

### 范围与说明

- 每个插件都声明支持 `macos` 和 `windows`。
- 用户必须使用自己的服务凭据。
- 服务端点、模型、额度和可用性由对应服务商控制，可能独立变化。
- 这些是已经转换的兼容插件。新插件应直接使用 Pythia 原生契约开发。
- 完整规范见 [Pythia 插件开发指南](../Docs/PYTHIA_PLUGIN_DEVELOPMENT_GUIDE.md)。
- 源码和转换代码按仓库 [GPL-3.0 许可证](../LICENSE)发布；原作者和服务商的相关权利归各自所有者。
