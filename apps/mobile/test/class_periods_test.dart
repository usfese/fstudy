import 'package:flutter_test/flutter_test.dart';
import 'package:fstudy/features/academic/class_periods.dart';
import 'package:fstudy/features/academic/recent_inputs.dart';

void main() {
  test('fixed class periods cover the configured timetable', () {
    expect(classPeriods, hasLength(14));
    expect(classPeriods.first.label, '第1节 08:00–08:45');
    expect(classPeriods[4].range, '11:30–12:15');
    expect(classPeriods[5].range, '13:00–13:45');
    expect(classPeriods.last.label, '第14节 20:10–20:55');
  });

  test('consecutive periods merge but the lunch break stays separate', () {
    expect(periodBlocks({0, 1}), [(startMinute: 480, endMinute: 575)]);
    expect(periodBlocks({4, 5}), [
      (startMinute: 690, endMinute: 735),
      (startMinute: 780, endMinute: 825),
    ]);
  });

  test('a stored free-form meeting maps back to overlapping periods', () {
    expect(periodIndexesForMeeting(480, 570), {0, 1});
    expect(periodIndexesForMeeting(480, 525), {0});
  });

  test('recent inputs are deduplicated and capped', () {
    RecentInputs.clear();
    for (var index = 0; index < 10; index++) {
      RecentInputs.remember('course.name', '课程$index');
    }
    RecentInputs.remember('course.name', '课程9');
    final suggestions = RecentInputs.suggestions('course.name');
    expect(suggestions, hasLength(8));
    expect(suggestions.first, '课程9');
    expect(suggestions.where((value) => value == '课程9'), hasLength(1));
  });
}
