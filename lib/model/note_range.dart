class NoteRange {
  const NoteRange(this.paragraphOrder, this.startOffset, this.endOffset);
  final int paragraphOrder, startOffset, endOffset;
  factory NoteRange.fromJson(Map<String, dynamic> json) => NoteRange(
    (json['paragraphOrder'] as num).toInt(),
    (json['startOffset'] as num).toInt(),
    (json['endOffset'] as num).toInt(),
  );
  Map<String, dynamic> toJson() => {
    'paragraphOrder': paragraphOrder,
    'startOffset': startOffset,
    'endOffset': endOffset,
  };
}
