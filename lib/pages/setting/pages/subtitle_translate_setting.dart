import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/widgets/switch_item.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/subtitle_translator.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

class SubtitleTranslateSetting extends StatefulWidget {
  const SubtitleTranslateSetting({super.key});

  @override
  State<SubtitleTranslateSetting> createState() =>
      _SubtitleTranslateSettingState();
}

class _SubtitleTranslateSettingState extends State<SubtitleTranslateSetting> {
  late final _baseUrl = TextEditingController(
    text: Pref.subtitleTranslateBaseUrl,
  );
  late final _model = TextEditingController(text: Pref.subtitleTranslateModel);
  late final _apiKey = TextEditingController(text: Pref.subtitleTranslateApiKey);

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _save(String key, String value) {
    GStorage.setting.put(key, value.trim());
  }

  Future<void> _test() async {
    if (Pref.subtitleTranslateApiKey.trim().isEmpty) {
      SmartDialog.showToast('请先填写 API Key');
      return;
    }
    SmartDialog.showLoading(msg: '正在测试');
    final res = await SubtitleTranslator.test();
    SmartDialog.dismiss();
    SmartDialog.showToast(
      res == null ? '翻译失败，请检查接口地址、模型与密钥' : '翻译成功：$res',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );

    return SimpleScaffold(
      appBar: AppBar(title: const Text('字幕翻译')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SetSwitchItem(
            title: '启用字幕翻译',
            subtitle: '播放外语字幕时自动翻译成简体中文，结果缓存在本地',
            setKey: SettingBoxKey.subtitleTranslateEnabled,
            leading: Icon(Icons.translate),
          ),
          ListTile(
            title: const Text('保留原文（双语显示）'),
            subtitle: Text('关闭后只显示中文译文', style: hintStyle),
            trailing: Switch(
              value: Pref.subtitleTranslateMode == 0,
              onChanged: (val) {
                GStorage.setting.put(
                  SettingBoxKey.subtitleTranslateMode,
                  val ? 0 : 1,
                );
                setState(() {});
              },
            ),
          ),
          const Divider(height: 1),
          _buildField(
            label: '接口地址',
            controller: _baseUrl,
            hint: 'https://api.hunyuan.cloud.tencent.com/v1',
            onChanged: (v) => _save(SettingBoxKey.subtitleTranslateBaseUrl, v),
          ),
          _buildField(
            label: '模型',
            controller: _model,
            hint: 'hunyuan-translation',
            onChanged: (v) => _save(SettingBoxKey.subtitleTranslateModel, v),
          ),
          _buildField(
            label: 'API Key',
            controller: _apiKey,
            hint: '在腾讯云 TokenHub 创建，模型权限勾选 hunyuan-translation',
            onChanged: (v) => _save(SettingBoxKey.subtitleTranslateApiKey, v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              '默认使用腾讯混元翻译专用模型 hunyuan-translation（33 种语言互译）：免费、国内直连、不需要代理。'
              '在腾讯云控制台「TokenHub」创建 API Key，模型权限勾选 hunyuan-translation。'
              '字幕按 20 句一批串行翻译，成功一批缓存一批，失败的批次会自动拆半重试；'
              '换模型或换地址会重新翻译。B 站本身已有中文（含 AI）字幕的视频不会走翻译。',
              style: hintStyle,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: const Text('测试接口'),
            subtitle: Text('发送 "Hello, world." 试译一句', style: hintStyle),
            onTap: _test,
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
