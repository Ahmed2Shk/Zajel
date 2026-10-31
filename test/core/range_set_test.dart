import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/range_set.dart';

void main() {
  test('adds and merges overlapping and touching ranges', () {
    final set = RangeSet()
      ..add(10, 20)
      ..add(30, 40)
      ..add(20, 30);
    expect(set.ranges, [(10, 40)]);
    expect(set.covered, 30);
  });

  test('keeps disjoint ranges sorted', () {
    final set = RangeSet()
      ..add(50, 60)
      ..add(0, 10)
      ..add(20, 30);
    expect(set.ranges, [(0, 10), (20, 30), (50, 60)]);
  });

  test('a repeated range does not double count', () {
    final set = RangeSet()
      ..add(0, 100)
      ..add(0, 100)
      ..add(25, 75);
    expect(set.covered, 100);
    expect(set.ranges, [(0, 100)]);
  });

  test('swallows several ranges at once', () {
    final set = RangeSet()
      ..add(0, 5)
      ..add(10, 15)
      ..add(20, 25)
      ..add(3, 22);
    expect(set.ranges, [(0, 25)]);
  });

  test('ignores empty ranges', () {
    final set = RangeSet()..add(5, 5);
    expect(set.ranges, isEmpty);
  });

  test('isComplete only when one range spans the whole file', () {
    expect((RangeSet()..add(0, 10)).isComplete(10), isTrue);
    expect((RangeSet()..add(0, 9)).isComplete(10), isFalse);
    expect((RangeSet()..add(0, 4)..add(5, 10)).isComplete(10), isFalse);
    expect(RangeSet().isComplete(0), isTrue);
  });

  test('missing splits gaps into pieces of at most the chunk size', () {
    final set = RangeSet()
      ..add(10, 20)
      ..add(50, 60);
    expect(set.missing(100, 25), [
      (0, 10),
      (20, 45),
      (45, 50),
      (60, 85),
      (85, 100),
    ]);
  });

  test('missing of an empty set covers the whole file', () {
    expect(RangeSet().missing(10, 4), [(0, 4), (4, 8), (8, 10)]);
    expect(RangeSet().missing(0, 4), isEmpty);
  });

  test('round-trips through json', () {
    final set = RangeSet()
      ..add(0, 10)
      ..add(20, 30);
    expect(RangeSet.fromJson(set.toJson()).ranges, set.ranges);
  });
}
