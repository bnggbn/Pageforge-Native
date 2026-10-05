import 'package:flutter/material.dart';
import '../../../ui/design_theme.dart';
import '../working_copy.dart';

class WorkingCopyBar extends StatelessWidget {
  const WorkingCopyBar({required this.copy, super.key});
  final WorkingCopy copy;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: copy,
    builder: (context, _) => Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            copy.status == 'error' ? Icons.error_outline : Icons.edit_note,
            size: 16,
            color: context.design.muted,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              copy.error.isNotEmpty
                  ? copy.error
                  : switch (copy.status) {
                      'pending' => '草稿等待保存…',
                      'saving' => '正在保存草稿…',
                      _ => '草稿已暫存 · 正式版本另行保存',
                    },
              style: TextStyle(
                fontSize: 11,
                color: copy.error.isEmpty
                    ? context.design.muted
                    : context.design.rust,
              ),
            ),
          ),
          if (copy.status == 'error')
            TextButton(
              onPressed: () {
                copy.flush().catchError((Object e) {});
              },
              child: Text('重試'),
            ),
        ],
      ),
    ),
  );
}
