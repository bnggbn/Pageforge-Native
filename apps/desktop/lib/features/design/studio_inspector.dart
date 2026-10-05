import 'package:flutter/material.dart';
import 'design_document.dart';
import 'studio_view_model.dart';
import 'studio_fields.dart';
import 'studio_presets.dart';

class StudioInspector extends StatelessWidget {
  const StudioInspector({required this.model, super.key});
  final StudioViewModel model;
  @override
  Widget build(BuildContext context) {
    final doc = model.document;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: switch (model.scene) {
        DesignScene.theme => [
          const Text('色彩與字體', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          StudioPresets(onSelect: model.preset),
          const SizedBox(height: 16),
          for (final entry in {
            'paper': '紙張',
            'ink': '文字',
            'accent': '重點',
            'forest': '森林',
            'muted': '次要文字',
          }.entries)
            StudioColorField(
              name: entry.value,
              value: doc.get<String>('theme', entry.key),
              onChanged: (value) => model.change('theme', entry.key, value),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(doc.get<String>('theme', 'headingFont')),
            initialValue: doc.get<String>('theme', 'headingFont'),
            decoration: const InputDecoration(labelText: '標題字體'),
            items: [
              for (final font in DesignDocument.fonts)
                DropdownMenuItem(value: font, child: Text(font)),
            ],
            onChanged: (value) {
              if (value != null) model.change('theme', 'headingFont', value);
            },
          ),
          const SizedBox(height: 12),
          const Text('使用本機字體，缺字時使用系統備援。'),
        ],
        DesignScene.library => [
          const Text('書架場景', style: TextStyle(fontSize: 20)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('閱讀引導'),
            value: doc.get<bool>('library', 'showInvitation'),
            onChanged: (value) =>
                model.change('library', 'showInvitation', value),
          ),
          StudioNumberField(
            model: model,
            group: 'library',
            field: 'cardWidth',
            label: '書卡最大寬度',
            min: 220,
            max: 340,
          ),
          StudioNumberField(
            model: model,
            group: 'library',
            field: 'gap',
            label: '書卡間距',
            min: 12,
            max: 48,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(doc.get<String>('library', 'coverArt')),
            initialValue: doc.get<String>('library', 'coverArt'),
            decoration: const InputDecoration(labelText: '封面線稿'),
            items: [
              for (final entry in {
                'auto': '依文件自動選擇',
                'rings': '環線',
                'frames': '畫框',
                'waves': '波紋',
                'leaf': '葉片',
                'arch': '拱門',
              }.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) model.change('library', 'coverArt', value);
            },
          ),
        ],
        DesignScene.reader => [
          const Text('文字閱讀場景', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 16),
          StudioNumberField(
            model: model,
            group: 'reader',
            field: 'pageWidth',
            label: '文章最大寬度',
            min: 480,
            max: 1000,
          ),
          StudioNumberField(
            model: model,
            group: 'reader',
            field: 'lineHeight',
            label: '內文行高',
            min: 1.3,
            max: 2.4,
            decimals: 2,
          ),
          const SizedBox(height: 16),
          const Text('字級仍可在閱讀工具列調整。這些版面設定套用於 Markdown、TXT 與 EPUB 文字。'),
        ],
      },
    );
  }
}
