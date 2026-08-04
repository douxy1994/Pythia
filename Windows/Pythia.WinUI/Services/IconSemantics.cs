namespace Pythia.Services;

public sealed record IconSemantic(string Resource, string AccessibleName);

public static class IconSemantics
{
    public static IReadOnlyDictionary<string, IconSemantic> Actions { get; } =
        new Dictionary<string, IconSemantic>(StringComparer.Ordinal)
        {
            ["navigation.translate"] = new("translate", "翻译"),
            ["navigation.history"] = new("history", "历史记录"),
            ["navigation.plugins"] = new("puzzle", "插件"),
            ["home.services"] = new("sort", "选择并排序翻译服务"),
            ["home.pin"] = new("pin", "切换窗口置顶"),
            ["home.swapLanguages"] = new("swap", "交换源语言和目标语言"),
            ["home.translate"] = new("send", "开始翻译"),
            ["home.copySource"] = new("copy", "复制原文"),
            ["home.paste"] = new("paste", "粘贴原文"),
            ["home.removeLineBreaks"] = new("text-align-left", "合并原文为单行"),
            ["home.clear"] = new("delete", "清空原文和翻译结果"),
            ["home.selection"] = new("text-select", "划词翻译"),
            ["home.screenshot"] = new("crop", "截图翻译"),
            ["home.ocrImage"] = new("image", "图片文字识别"),
            ["home.copyAll"] = new("copy", "复制全部译文"),
            ["home.favorite"] = new("star", "收藏本次翻译"),
            ["home.speak"] = new("speaker", "朗读首条译文"),
            ["result.retry"] = new("arrow-sync", "重试插件翻译"),
            ["result.copy"] = new("copy", "复制翻译结果"),
            ["plugin.install"] = new("add", "安装插件包"),
            ["plugin.configure"] = new("settings", "配置插件"),
            ["plugin.test"] = new("play", "测试插件连通性"),
            ["plugin.toggle"] = new("checkmark", "启用或停用插件"),
            ["plugin.remove"] = new("delete", "卸载插件"),
            ["history.export"] = new("save", "导出历史记录"),
            ["history.load"] = new("arrow-right", "载入历史记录继续翻译"),
            ["history.favorite"] = new("star", "收藏历史记录"),
            ["history.copy"] = new("copy", "复制历史译文"),
            ["history.delete"] = new("delete", "删除历史记录"),
            ["settings.webdavTest"] = new("link", "测试 WebDAV 连接"),
            ["settings.webdavSync"] = new("arrow-sync", "立即同步历史"),
            ["settings.webdavUpload"] = new("arrow-upload", "上传便携备份"),
            ["settings.webdavRestore"] = new("arrow-download", "恢复远程备份"),
            ["settings.localExport"] = new("save", "导出本地备份"),
            ["settings.localImport"] = new("folder-open", "导入本地备份"),
            ["settings.update"] = new("arrow-download", "检查应用更新"),
        };
}
