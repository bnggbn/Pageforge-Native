import '../../data/models.dart';

const allEvidenceTopic = '00000000-0000-4000-8000-000000000001';
Json emptyEvidence() => {
  'schemaVersion': 2,
  'revision': '',
  'updatedAt': '',
  'activeTopic': allEvidenceTopic,
  'topics': <Json>[
    {
      'id': allEvidenceTopic,
      'name': '全部線索',
      'cards': <Json>[],
      'edges': <Json>[],
    },
  ],
};
Json normalizeEvidence(Json source) {
  if (source['schemaVersion'] == 2) return source;
  return {
    ...emptyEvidence(),
    'revision': source['revision'],
    'updatedAt': source['updatedAt'],
    'topics': <Json>[
      {
        'id': allEvidenceTopic,
        'name': '全部線索',
        'cards': source['cards'],
        'edges': source['edges'],
      },
    ],
  };
}

List<Json> evidenceTopics(Json wall) => (wall['topics'] as List).cast<Json>();
Json activeEvidenceTopic(Json wall) =>
    evidenceTopics(wall).firstWhere((t) => t['id'] == wall['activeTopic']);
Json replaceEvidenceTopic(Json wall, Json topic) => {
  ...wall,
  'topics': <Json>[
    for (final item in evidenceTopics(wall))
      if (item['id'] == topic['id']) topic else item,
  ],
};

/// Explicit membership in named topics; all notes remain available in the default.
Json reconcileEvidence(
  Json wall,
  Map<String, Json> notes,
  double width,
  double height,
  int maxCards,
) => {
  ...wall,
  'topics': <Json>[
    for (final topic in evidenceTopics(wall))
      reconcileTopic(
        topic,
        notes.keys.toSet(),
        width,
        height,
        maxCards,
        includeAll: topic['id'] == allEvidenceTopic,
      ),
  ],
};
Json reconcileTopic(
  Json topic,
  Set<String> members,
  double width,
  double height,
  int maxCards, {
  bool includeAll = true,
}) {
  final cards = (topic['cards'] as List)
      .cast<Json>()
      .where((c) => members.contains(c['noteId']))
      .take(maxCards)
      .toList();
  final present = cards.map((c) => c['noteId']).toSet();
  if (includeAll) {
    final columns = ((width - 80) / 320).floor();
    final occupied = {
      for (final c in cards) _pointKey(c['x'] as num, c['y'] as num),
    };
    var next = 0;
    for (final id in members) {
      if (cards.length >= maxCards) break;
      if (!present.add(id)) continue;
      double x, y;
      do {
        x = 40.0 + (next % columns) * 320;
        y = (40.0 + (next ~/ columns) * 280).clamp(0.0, height - 240);
        next++;
      } while (occupied.contains(_pointKey(x, y)) && next < maxCards * 2);
      occupied.add(_pointKey(x, y));
      cards.add({'noteId': id, 'x': x, 'y': y});
    }
  }
  return {
    ...topic,
    'cards': cards,
    'edges': (topic['edges'] as List)
        .cast<Json>()
        .where((e) => present.contains(e['from']) && present.contains(e['to']))
        .toList(),
  };
}

String _pointKey(num x, num y) => '${x.toDouble()}:${y.toDouble()}';
