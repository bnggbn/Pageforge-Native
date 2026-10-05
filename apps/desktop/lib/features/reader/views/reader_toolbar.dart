import 'package:flutter/material.dart';
import '../../../ui/motion.dart';
import '../../../ui/theme.dart';
import '../reader_view_model.dart';

class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({required this.model, super.key});
  final ReaderViewModel model;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final entry in [
        (ReaderTab.read, '閱讀'),
        (ReaderTab.notes, '筆記'),
        if (model.book!.editable) (ReaderTab.edit, '編輯'),
        (ReaderTab.history, '版本'),
      ])
        TextButton(
          onPressed: model.busy ? null : () => model.changeTab(entry.$1),
          style: TextButton.styleFrom(
            foregroundColor: model.tab == entry.$1 ? rust : muted,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          child: AnimatedContainer(
            duration: PageforgeMotion.reduced(context)
                ? Duration.zero
                : PageforgeMotion.quick,
            curve: PageforgeMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: model.tab == entry.$1
                  ? rust.withValues(alpha: .09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border(
                bottom: BorderSide(
                  color: model.tab == entry.$1 ? rust : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(entry.$2),
          ),
        ),
      const SizedBox(width: 16),
      IconButton(
        tooltip: '縮小字級',
        onPressed: model.canDecreaseFont ? model.decreaseFont : null,
        icon: const Icon(Icons.text_decrease, size: 18),
      ),
      IconButton(
        tooltip: '放大字級',
        onPressed: model.canIncreaseFont ? model.increaseFont : null,
        icon: const Icon(Icons.text_increase, size: 18),
      ),
    ],
  );
}
