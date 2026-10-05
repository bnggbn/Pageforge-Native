import 'package:flutter/material.dart';
import '../../../ui/design_theme.dart';

class NoteCloud extends StatelessWidget {
  const NoteCloud({required this.count, required this.onTap, super.key});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Tooltip(
      message: '這一段有 $count 則筆記',
      child: Semantics(
        button: true,
        label: '查看段落筆記，$count 則',
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: onTap,
            radius: 23,
            child: SizedBox(
              width: 42,
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.cloud,
                    size: 40,
                    color: context.design.forest.withValues(alpha: .1),
                  ),
                  Icon(
                    Icons.cloud_outlined,
                    size: 40,
                    color: context.design.forest,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.design.forest,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
