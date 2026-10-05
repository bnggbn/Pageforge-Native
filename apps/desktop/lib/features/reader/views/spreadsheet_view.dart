import 'package:flutter/material.dart';
import '../reader_view_model.dart';

class SpreadsheetView extends StatelessWidget {
  const SpreadsheetView({required this.model, super.key});
  final ReaderViewModel model;
  @override
  Widget build(BuildContext context) {
    final sheets = model.book!.sheets;
    if (sheets.isEmpty) return const Center(child: Text('此文件沒有可讀取的工作表。'));
    final section = model.section.clamp(0, sheets.length - 1);
    final rows = sheets[section]['rows'] as List;
    final columns = rows.fold<int>(
      1,
      (value, row) => (row as List).length > value ? row.length : value,
    );
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: DropdownButton<int>(
            value: section,
            items: [
              for (var i = 0; i < sheets.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(sheets[i]['name'] as String),
                ),
            ],
            onChanged: model.busy
                ? null
                : (value) {
                    if (value != null) model.selectSection(value);
                  },
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 55 + columns * 160.0,
                height: constraints.maxHeight,
                child: ListView.builder(
                  itemExtent: 44,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final cells = rows[index] as List;
                    return Row(
                      children: [
                        SizedBox(
                          width: 55,
                          child: Center(child: Text('${index + 1}')),
                        ),
                        for (var column = 0; column < columns; column++)
                          SizedBox(
                            width: 160,
                            child: InkWell(
                              onTap:
                                  column >= cells.length ||
                                      '${cells[column]}'.isEmpty
                                  ? null
                                  : () => showDialog<void>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: Text(
                                          '第 ${index + 1} 列 · 第 ${column + 1} 欄',
                                        ),
                                        content: SizedBox(
                                          width: 480,
                                          child: SingleChildScrollView(
                                            child: SelectableText(
                                              '${cells[column]}',
                                            ),
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              model.working!.change({
                                                'quote': '${cells[column]}',
                                                'location':
                                                    '${sheets[section]['name']} · 第 ${index + 1} 列',
                                              });
                                              Navigator.pop(context);
                                            },
                                            child: const Text('引用到筆記'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('關閉'),
                                          ),
                                        ],
                                      ),
                                    ),
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                    width: .5,
                                  ),
                                ),
                                child: Text(
                                  column < cells.length
                                      ? '${cells[column]}'
                                      : '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
