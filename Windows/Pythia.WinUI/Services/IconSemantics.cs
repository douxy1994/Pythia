using Microsoft.UI.Xaml.Controls;

namespace Pythia.Services;

public sealed record IconSemantic(Symbol Symbol, string AccessibleName);

public static class IconSemantics
{
    public static IReadOnlyDictionary<string, IconSemantic> Actions { get; } =
        new Dictionary<string, IconSemantic>(StringComparer.Ordinal)
        {
            ["navigation.translate"] = new(Symbol.Character, "翻译"),
            ["navigation.history"] = new(Symbol.Clock, "历史记录"),
            ["navigation.plugins"] = new(Symbol.Repair, "插件"),
            ["navigation.about"] = new(Symbol.ContactInfo, "关于 Pythia"),
            ["home.services"] = new(Symbol.Sort, "选择并排序翻译服务"),
            ["home.pin"] = new(Symbol.Pin, "切换窗口置顶"),
            ["home.swapLanguages"] = new(Symbol.Switch, "交换源语言和目标语言"),
            ["home.translate"] = new(Symbol.Send, "开始翻译"),
            ["home.copySource"] = new(Symbol.Copy, "复制原文"),
            ["home.paste"] = new(Symbol.Paste, "粘贴原文"),
            ["home.removeLineBreaks"] = new(Symbol.AlignLeft, "合并原文为单行"),
            ["home.clear"] = new(Symbol.Delete, "清空原文和翻译结果"),
            ["home.selection"] = new(Symbol.TouchPointer, "划词翻译"),
            ["home.screenshot"] = new(Symbol.Camera, "截图翻译"),
            ["home.ocrImage"] = new(Symbol.Pictures, "图片文字识别"),
            ["home.copyAll"] = new(Symbol.Copy, "复制全部译文"),
            ["home.favorite"] = new(Symbol.OutlineStar, "收藏本次翻译"),
            ["home.speak"] = new(Symbol.Volume, "朗读首条译文"),
            ["result.retry"] = new(Symbol.Refresh, "重试插件翻译"),
            ["result.copy"] = new(Symbol.Copy, "复制翻译结果"),
            ["plugin.install"] = new(Symbol.Add, "安装插件包"),
            ["plugin.configure"] = new(Symbol.Setting, "配置插件"),
            ["plugin.test"] = new(Symbol.Play, "测试插件连通性"),
            ["plugin.toggle"] = new(Symbol.Switch, "启用或停用插件"),
            ["plugin.remove"] = new(Symbol.Delete, "卸载插件"),
            ["history.export"] = new(Symbol.SaveLocal, "导出历史记录"),
            ["history.load"] = new(Symbol.Forward, "载入历史记录继续翻译"),
            ["history.favorite"] = new(Symbol.OutlineStar, "收藏历史记录"),
            ["history.copy"] = new(Symbol.Copy, "复制历史译文"),
            ["history.delete"] = new(Symbol.Delete, "删除历史记录"),
            ["settings.save"] = new(Symbol.Save, "保存全部设置"),
            ["settings.webdavTest"] = new(Symbol.Link, "测试 WebDAV 连接"),
            ["settings.webdavSync"] = new(Symbol.Sync, "立即同步历史"),
            ["settings.webdavUpload"] = new(Symbol.Upload, "上传便携备份"),
            ["settings.webdavRestore"] = new(Symbol.Download, "恢复远程备份"),
            ["settings.localExport"] = new(Symbol.SaveLocal, "导出本地备份"),
            ["settings.localImport"] = new(Symbol.OpenFile, "导入本地备份"),
            ["settings.update"] = new(Symbol.Download, "检查应用更新"),
        };
}
