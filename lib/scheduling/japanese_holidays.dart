/// Dates published by the Cabinet Office for 2026 and 2027, including
/// substitute and citizens' holidays. Update after the next official release.
/// Source: https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html
class JapaneseHolidays {
  const JapaneseHolidays();

  static const _dates = <int>{
    20260101,
    20260112,
    20260211,
    20260223,
    20260320,
    20260429,
    20260503,
    20260504,
    20260505,
    20260506,
    20260720,
    20260811,
    20260921,
    20260922,
    20260923,
    20261012,
    20261103,
    20261123,
    20270101,
    20270111,
    20270211,
    20270223,
    20270321,
    20270322,
    20270429,
    20270503,
    20270504,
    20270505,
    20270719,
    20270811,
    20270920,
    20270923,
    20271011,
    20271103,
    20271123,
  };

  bool isHoliday(DateTime civilDate) {
    if (civilDate.year < 2026 || civilDate.year > 2027) {
      throw RangeError('Japanese holiday data is published only through 2027');
    }
    return _dates.contains(
      civilDate.year * 10000 + civilDate.month * 100 + civilDate.day,
    );
  }
}
