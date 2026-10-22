class ClassPeriod {
  const ClassPeriod({
    required this.number,
    required this.startMinute,
    required this.endMinute,
  });

  final int number;
  final int startMinute;
  final int endMinute;

  String get range => '${formatMinute(startMinute)}–${formatMinute(endMinute)}';
  String get label => '第$number节 $range';
}

/// The fixed BUPT class periods used by the schedule. Keeping this list in one
/// place means the picker, the weekly view and the API always agree on time.
const classPeriods = <ClassPeriod>[
  ClassPeriod(number: 1, startMinute: 8 * 60, endMinute: 8 * 60 + 45),
  ClassPeriod(number: 2, startMinute: 8 * 60 + 50, endMinute: 9 * 60 + 35),
  ClassPeriod(number: 3, startMinute: 9 * 60 + 50, endMinute: 10 * 60 + 35),
  ClassPeriod(number: 4, startMinute: 10 * 60 + 40, endMinute: 11 * 60 + 25),
  ClassPeriod(number: 5, startMinute: 11 * 60 + 30, endMinute: 12 * 60 + 15),
  ClassPeriod(number: 6, startMinute: 13 * 60, endMinute: 13 * 60 + 45),
  ClassPeriod(number: 7, startMinute: 13 * 60 + 50, endMinute: 14 * 60 + 35),
  ClassPeriod(number: 8, startMinute: 14 * 60 + 45, endMinute: 15 * 60 + 30),
  ClassPeriod(number: 9, startMinute: 15 * 60 + 40, endMinute: 16 * 60 + 25),
  ClassPeriod(number: 10, startMinute: 16 * 60 + 35, endMinute: 17 * 60 + 20),
  ClassPeriod(number: 11, startMinute: 17 * 60 + 25, endMinute: 18 * 60 + 10),
  ClassPeriod(number: 12, startMinute: 18 * 60 + 30, endMinute: 19 * 60 + 15),
  ClassPeriod(number: 13, startMinute: 19 * 60 + 20, endMinute: 20 * 60 + 5),
  ClassPeriod(number: 14, startMinute: 20 * 60 + 10, endMinute: 20 * 60 + 55),
];

String formatMinute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

/// Converts a stored meeting back to the fixed periods it overlaps.
///
/// Older courses may have been entered with free-form times. In that case we
/// choose the closest period so editing still produces a valid fixed-period
/// schedule.
Set<int> periodIndexesForMeeting(int startMinute, int endMinute) {
  final overlaps = <int>{};
  for (var index = 0; index < classPeriods.length; index++) {
    final period = classPeriods[index];
    if (period.startMinute < endMinute && period.endMinute > startMinute) {
      overlaps.add(index);
    }
  }
  if (overlaps.isNotEmpty) return overlaps;

  var closestIndex = 0;
  var closestDistance = 1 << 30;
  for (var index = 0; index < classPeriods.length; index++) {
    final distance = (classPeriods[index].startMinute - startMinute).abs();
    if (distance < closestDistance) {
      closestDistance = distance;
      closestIndex = index;
    }
  }
  return {closestIndex};
}

/// Combines consecutive selected periods into one meeting block.
///
/// A five-to-fifteen minute break is considered part of the same block, while
/// the long lunch break between period 5 and 6 stays split.
List<({int startMinute, int endMinute})> periodBlocks(
  Set<int> selectedIndexes,
) {
  final indexes = selectedIndexes.toList()..sort();
  if (indexes.isEmpty) return const [];

  final blocks = <({int startMinute, int endMinute})>[];
  var start = classPeriods[indexes.first].startMinute;
  var end = classPeriods[indexes.first].endMinute;
  for (final index in indexes.skip(1)) {
    final period = classPeriods[index];
    if (period.startMinute - end <= 15) {
      end = period.endMinute;
    } else {
      blocks.add((startMinute: start, endMinute: end));
      start = period.startMinute;
      end = period.endMinute;
    }
  }
  blocks.add((startMinute: start, endMinute: end));
  return blocks;
}
