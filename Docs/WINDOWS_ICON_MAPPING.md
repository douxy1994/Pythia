# Pythia Windows 图标语义映射

Windows 客户端使用 WinUI `SymbolIcon` 和插件包自己的图标。图标必须与动作一致，并由文字、Tooltip 或 `AutomationProperties.Name` 提供可访问名称。

| 区域 | 动作 | Fluent Symbol | 可访问名称 |
| --- | --- | --- | --- |
| 主导航 | 翻译 / 历史 / 插件 / 关于 | `Character` / `Clock` / `Repair` / `ContactInfo` | 与导航标题一致 |
| 首页 | 服务选择与排序 | `Sort` | 选择并排序翻译服务 |
| 首页 | 交换语言 | `Switch` | 交换源语言和目标语言 |
| 首页 | 开始翻译 | `Send` | 开始翻译 |
| 首页 | 复制 / 粘贴 / 合并为单行 / 清空 | `Copy` / `Paste` / `AlignLeft` / `Delete` | 描述实际文本动作 |
| 首页 | 划词 / 截图翻译 / 图片 OCR | `TouchPointer` / `Camera` / `Pictures` | 划词翻译 / 截图翻译 / 图片文字识别 |
| 首页 | 置顶 / 复制全部 / 收藏 / 朗读 | `Pin` / `Copy` / `OutlineStar` / `Volume` | 描述对应首页动作 |
| 结果卡 | 插件重试 / 复制 | `Refresh` / `Copy` | 重试插件翻译 / 复制翻译结果 |
| 插件 | 安装 / 配置 / 测试 / 启停 / 卸载 | `Add` / `Setting` / `Play` / `Switch` / `Delete` | 描述对应插件动作 |
| 历史 | 导出 / 载入 / 收藏 / 复制 / 删除 | `SaveLocal` / `Forward` / `OutlineStar` 或 `SolidStar` / `Copy` / `Delete` | 描述对应历史动作 |
| 设置 | 保存 / WebDAV 测试 / 同步 | `Save` / `Link` / `Sync` | 保存全部设置 / 测试 WebDAV 连接 / 立即同步历史 |
| 设置 | 上传 / 恢复 / 本地导出 / 本地导入 | `Upload` / `Download` / `SaveLocal` / `OpenFile` | 描述对应备份动作 |
| 设置 | 检查应用更新 | `Download` | 检查应用更新 |

插件卡优先显示插件包根目录中的 SVG、PNG、JPEG 或 ICO；没有插件图标时显示 Pythia 默认插件图标。应用 EXE、标题栏、任务栏、托盘、开始菜单、卸载项和安装程序统一使用 `Assets/AppIcon.ico` 或同源 PNG 资产。
