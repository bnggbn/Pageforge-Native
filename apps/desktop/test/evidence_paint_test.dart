import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/evidence/evidence_card_drag.dart';
import 'package:pageforge/features/evidence/evidence_connections.dart';

void main() {
  test('moving link repaints without laying out unchanged labels', () {
    final drag = EvidenceCardDrag(), pointer = ValueNotifier<Offset?>(null);
    final cards = [
      {'noteId': 'a', 'x': 40, 'y': 40},
      {'noteId': 'b', 'x': 400, 'y': 40},
    ];
    final edges = [
      {'from': 'a', 'to': 'b', 'label': 'because'},
    ];
    final labels = EvidenceLabels()..sync(edges, Colors.red);
    final painter = EvidenceConnections(
      cards: cards,
      edges: edges,
      color: Colors.red,
      drag: drag,
      pointer: pointer,
      source: 'a',
      labels: labels,
      visible: const Rect.fromLTWH(0, 0, 900, 700),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(900, 700));
    final text = labels.get('because', Colors.red);
    for (var i = 0; i < 20; i++) {
      pointer.value = Offset(500 + i.toDouble(), 300);
      painter.paint(canvas, const Size(900, 700));
    }
    expect(labels.layouts, 1);
    expect(labels.get('because', Colors.red), same(text));
    recorder.endRecording().dispose();
    labels.sync([], Colors.red);
    labels.get('because', Colors.red);
    expect(labels.layouts, 2);
    labels.dispose();
    drag.dispose();
    pointer.dispose();
  });
}
