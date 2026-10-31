/// A set of half-open byte ranges `[start, end)`, kept merged and sorted.
/// Tracks which parts of a file have arrived so an interrupted transfer can
/// skip them when it resumes.
class RangeSet {
  RangeSet();

  factory RangeSet.fromJson(List<dynamic> json) {
    final set = RangeSet();
    for (final pair in json) {
      final range = pair as List<dynamic>;
      set.add((range[0] as num).toInt(), (range[1] as num).toInt());
    }
    return set;
  }

  final List<(int, int)> _ranges = [];

  List<(int, int)> get ranges => List.unmodifiable(_ranges);

  int get covered => _ranges.fold(0, (sum, r) => sum + (r.$2 - r.$1));

  bool isComplete(int size) =>
      size == 0 || (_ranges.length == 1 && _ranges[0] == (0, size));

  void add(int start, int end) {
    if (end <= start) return;
    var newStart = start;
    var newEnd = end;
    final kept = <(int, int)>[];
    var inserted = false;
    for (final range in _ranges) {
      if (range.$2 < newStart) {
        kept.add(range);
      } else if (range.$1 > newEnd) {
        if (!inserted) {
          kept.add((newStart, newEnd));
          inserted = true;
        }
        kept.add(range);
      } else {
        // Overlapping or touching: merge.
        if (range.$1 < newStart) newStart = range.$1;
        if (range.$2 > newEnd) newEnd = range.$2;
      }
    }
    if (!inserted) kept.add((newStart, newEnd));
    _ranges
      ..clear()
      ..addAll(kept);
  }

  /// The parts of `[0, size)` not yet covered, split into pieces of at most
  /// [maxPiece] bytes.
  List<(int, int)> missing(int size, int maxPiece) {
    final gaps = <(int, int)>[];
    var cursor = 0;
    for (final range in _ranges) {
      if (range.$1 > cursor) gaps.add((cursor, range.$1));
      if (range.$2 > cursor) cursor = range.$2;
    }
    if (cursor < size) gaps.add((cursor, size));

    final pieces = <(int, int)>[];
    for (final gap in gaps) {
      for (var start = gap.$1; start < gap.$2; start += maxPiece) {
        final end = start + maxPiece;
        pieces.add((start, end < gap.$2 ? end : gap.$2));
      }
    }
    return pieces;
  }

  List<List<int>> toJson() => [
    for (final r in _ranges) [r.$1, r.$2],
  ];
}
