/// The election dates the app counts down to, and the arithmetic. All dates
/// are Nigerian calendar dates: the count does not depend on where a phone is
/// or what time zone it is set to.
library;

/// Nigeria keeps West Africa Time all year: UTC+1, with no daylight saving.
const lagosOffset = Duration(hours: 1);

/// An election on INEC's published calendar.
class ScheduledElection {
  const ScheduledElection({
    required this.name,
    required this.year,
    required this.month,
    required this.day,
    required this.source,
    required this.sourceUrl,
  });

  /// "Presidential election".
  final String name;
  final int year;
  final int month;
  final int day;

  /// Who set the date, for showing beside it.
  final String source;
  final String sourceUrl;

  /// The election's date, as a UTC midnight so that whole days subtract
  /// exactly.
  DateTime get date => DateTime.utc(year, month, day);

  /// "Saturday, 16 January 2027".
  String get fullDate {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[date.weekday - 1]}, $day ${months[month - 1]} $year';
  }
}

/// The next presidential election. To move the date, change it here: every
/// countdown in the app reads this.
///
/// INEC's revised timetable under the Electoral Act 2026 replaced the earlier
/// date of 20 February 2027.
const nextPresidentialElection = ScheduledElection(
  name: 'Presidential election',
  year: 2027,
  month: 1,
  day: 16,
  source: "INEC's election calendar",
  sourceUrl: 'https://www.inecnigeria.org/elections/calendar',
);

/// [now]'s calendar date in Nigeria, as a UTC midnight.
DateTime lagosDate(DateTime now) {
  final lagos = now.toUtc().add(lagosOffset);
  return DateTime.utc(lagos.year, lagos.month, lagos.day);
}

/// [now]'s hour on the clock in Nigeria.
int lagosHour(DateTime now) => now.toUtc().add(lagosOffset).hour;

/// The moment the date next changes in Nigeria.
DateTime nextLagosMidnight(DateTime now) =>
    lagosDate(now).add(const Duration(days: 1)).subtract(lagosOffset);

enum ElectionPhase { upcoming, electionDay, completed }

/// Where an election stands on a given day.
class ElectionStatus {
  const ElectionStatus(this.phase, this.daysLeft);

  final ElectionPhase phase;

  /// Calendar days until election day; 0 from election day on, never negative.
  final int daysLeft;

  /// Where [election] stands at [now], counted in Nigerian calendar days.
  factory ElectionStatus.of(ScheduledElection election, DateTime now) {
    final days = election.date.difference(lagosDate(now)).inDays;
    if (days > 0) return ElectionStatus(ElectionPhase.upcoming, days);
    return ElectionStatus(days == 0 ? ElectionPhase.electionDay : ElectionPhase.completed, 0);
  }
}
