class LifestyleSettings {
  const LifestyleSettings({
    this.commuteStartMinute = 18 * 60,
    this.afterHomeMinute = 19 * 60,
    this.weekendsAreHolidays = true,
    this.japaneseHolidays = true,
    this.initialSetupComplete = false,
  }) : assert(commuteStartMinute >= 0 && commuteStartMinute < 1440),
       assert(afterHomeMinute >= 0 && afterHomeMinute < 1440);

  final int commuteStartMinute;
  final int afterHomeMinute;
  final bool weekendsAreHolidays;
  final bool japaneseHolidays;
  final bool initialSetupComplete;

  Map<String, Object?> toJson() => {
    'commute_start_minute': commuteStartMinute,
    'after_home_minute': afterHomeMinute,
    'weekends_are_holidays': weekendsAreHolidays,
    'japanese_holidays': japaneseHolidays,
    'initial_setup_complete': initialSetupComplete,
  };

  factory LifestyleSettings.fromJson(Map<String, dynamic> json) =>
      LifestyleSettings(
        commuteStartMinute: json['commute_start_minute'] as int? ?? 18 * 60,
        afterHomeMinute: json['after_home_minute'] as int? ?? 19 * 60,
        weekendsAreHolidays: json['weekends_are_holidays'] as bool? ?? true,
        japaneseHolidays: json['japanese_holidays'] as bool? ?? true,
        initialSetupComplete: json['initial_setup_complete'] as bool? ?? false,
      );
}
