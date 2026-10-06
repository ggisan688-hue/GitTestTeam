import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RecentDocument {
  const RecentDocument({
    required this.documentId,
    required this.title,
    required this.author,
    this.coverAsset,
    required this.lastReadAt,
    required this.progressPercent,
    required this.lastReadPosition,
  });
  final String documentId;
  final String title;
  final String author;
  final String? coverAsset;
  final DateTime lastReadAt;
  final int progressPercent;
  final int lastReadPosition;
  Map<String, Object?> toJson() => {
    'documentId': documentId,
    'title': title,
    'author': author,
    'coverAsset': coverAsset,
    'lastReadAt': lastReadAt.toIso8601String(),
    'progressPercent': progressPercent,
    'lastReadPosition': lastReadPosition,
  };
  factory RecentDocument.fromJson(Map<String, dynamic> json) => RecentDocument(
    documentId: json['documentId'] as String,
    title: json['title'] as String,
    author: json['author'] as String? ?? '',
    coverAsset: json['coverAsset'] as String?,
    lastReadAt: DateTime.parse(json['lastReadAt'] as String),
    progressPercent: (json['progressPercent'] as num?)?.toInt() ?? 0,
    lastReadPosition: (json['lastReadPosition'] as num?)?.toInt() ?? 0,
  );
}

class RecentDocumentsRepository {
  static const _storageKey = 'recent_documents_v1';
  static const maxDocuments = 10;
  Future<List<RecentDocument>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final documents =
          decoded
              .whereType<Map<String, dynamic>>()
              .map(RecentDocument.fromJson)
              .toList()
            ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
      return documents.take(maxDocuments).toList(growable: false);
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> save(List<RecentDocument> documents) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(
        documents
            .take(maxDocuments)
            .map((document) => document.toJson())
            .toList(growable: false),
      ),
    );
  }
}
