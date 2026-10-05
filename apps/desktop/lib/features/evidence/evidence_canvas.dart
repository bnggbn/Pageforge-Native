import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../ui/design_theme.dart';
import 'evidence_card.dart';
import 'evidence_connections.dart';
import 'evidence_edge_dialog.dart';
import 'evidence_geometry.dart';
import 'evidence_wall_view_model.dart';

class EvidenceCanvas extends StatefulWidget {
  const EvidenceCanvas({
    required this.model,
    required this.onOpen,
    required this.onReveal,
    super.key,
  });
  final EvidenceWallViewModel model;
  final ValueChanged<Json> onOpen, onReveal;
  @override
  State<EvidenceCanvas> createState() => _EvidenceCanvasState();
}

class _EvidenceCanvasState extends State<EvidenceCanvas> {
  final transform = TransformationController(), viewport = GlobalKey();
  Offset? pointer;
  int focusRequest = -1;
  @override
  void initState() {
    super.initState();
    transform.addListener(redraw);
  }

  void redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    transform.removeListener(redraw);
    transform.dispose();
    super.dispose();
  }

  Offset scenePoint(Offset global) {
    final box = viewport.currentContext!.findRenderObject() as RenderBox;
    return transform.toScene(box.globalToLocal(global));
  }

  void finishLink() {
    final point = pointer;
    pointer = null;
    if (point == null) {
      widget.model.cancelLink();
      return;
    }
    final targets = widget.model.cards.where(
      (card) => evidenceCardRect(card).contains(point),
    );
    if (targets.isEmpty) {
      widget.model.cancelLink();
      return;
    }
    widget.model.connect(targets.first['noteId'] as String);
  }

  void tapBackground(Offset global) {
    final point = scenePoint(global), model = widget.model;
    for (final edge in model.edges) {
      final from = model.card(edge['from'] as String),
          to = model.card(edge['to'] as String);
      if (from != null &&
          to != null &&
          nearEvidenceLine(point, evidencePin(from), evidencePin(to))) {
        editEvidenceEdge(context, model, edge);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final model = widget.model;
      if (focusRequest != model.focusRequest && model.focusNote != null) {
        focusRequest = model.focusRequest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final card = model.card(model.focusNote!);
          if (card == null) return;
          final center = evidenceCardRect(card).center;
          transform.value = Matrix4.translationValues(
            bounds.maxWidth / 2 - center.dx,
            bounds.maxHeight / 2 - center.dy,
            0,
          );
        });
      }
      final visible = Rect.fromPoints(
        transform.toScene(Offset.zero),
        transform.toScene(Offset(bounds.maxWidth, bounds.maxHeight)),
      ).inflate(280);
      final cards = model.cards,
          indices = {
            for (var i = 0; i < cards.length; i++) cards[i]['noteId']: i + 1,
          };
      return ClipRect(
        child: Stack(
          key: viewport,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: EvidenceGrid(context.design.ink)),
              ),
            ),
            InteractiveViewer(
              key: const ValueKey('evidence-viewport'),
              transformationController: transform,
              constrained: false,
              minScale: .25,
              maxScale: 2,
              boundaryMargin: const EdgeInsets.all(600),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => tapBackground(details.globalPosition),
                child: SizedBox(
                  width: model.width,
                  height: model.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: EvidenceConnections(
                              cards: cards,
                              edges: model.edges,
                              color: const Color(0xffa83b35),
                              source: model.linkSource,
                              pointer: pointer,
                            ),
                          ),
                        ),
                      ),
                      for (final card in cards)
                        if (evidenceCardRect(card).overlaps(visible))
                          Positioned(
                            left: (card['x'] as num).toDouble(),
                            top: (card['y'] as num).toDouble(),
                            width: 280,
                            height: 240,
                            child: EvidenceCard(
                              key: ValueKey('evidence-card-${card['noteId']}'),
                              note: model.notes[card['noteId']]!,
                              number: indices[card['noteId']]!,
                              selected: model.linkSource == card['noteId'],
                              onTap: () => model.linkSource == null
                                  ? widget.onOpen(model.notes[card['noteId']]!)
                                  : model.connect(card['noteId'] as String),
                              onReveal: () =>
                                  widget.onReveal(model.notes[card['noteId']]!),
                              onDrag: (delta) => model.move(
                                card['noteId'] as String,
                                (card['x'] as num).toDouble() + delta.dx,
                                (card['y'] as num).toDouble() + delta.dy,
                              ),
                              onPinTap: () => model.linkSource == null
                                  ? model.beginLink(card['noteId'] as String)
                                  : model.connect(card['noteId'] as String),
                              onPinStart: () =>
                                  model.beginLink(card['noteId'] as String),
                              onPinUpdate: (global) =>
                                  setState(() => pointer = scenePoint(global)),
                              onPinEnd: finishLink,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
