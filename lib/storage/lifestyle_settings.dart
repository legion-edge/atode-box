enum OverdueRecoveryPolicy { nextRegularSlot, notifyOnRecovery }

class LifestyleSettings {
  const LifestyleSettings({
    this.commuteStartMinute = 18 * 60,
    this.afterHomeMinute = 19 * 60,
    this.weekendsAreHolidays = true,
    this.japaneseHolidays = true,
    this.initialSetupComplete = false,
    this.overdueRecoveryPolicy = OverdueRecoveryPolicy.nextRegularSlot,
  }) : assert(commuteStartMinute >= 0 && commuteStartMinute < 1440),
       assert(afterHomeMinute >= 0 && afterHomeMinute < 1440);

  final int commuteStartMinute;
  final int afterHomeMinute;
  final bool weekendsAreHolidays;
  final bool japaneseHolidays;
  final bool initialSetupComplete;
  final OverdueRecoveryPolicy overdueRecoveryPolicy;

  LifestyleSettings copyWith({
    int? commuteStartMinute,
    int? afterHomeMinute,
    bool? weekendsAreHolidays,
    bool? japaneseHolidays,
    bool? initialSetupComplete,
    OverdueRecoveryPolicy? overdueRecoveryPolicy,
  }) => LifestyleSettings(
    commuteStartMinute: commuteStartMinute ?? this.commuteStartMinute,
    afterHomeMinute: afterHomeMinute ?? this.afterHomeMinute,
    weekendsAreHolidays: weekendsAreHolidays ?? this.weekendsAreHolidays,
    japaneseHolidays: japaneseHolidays ?? this.japaneseHolidays,
    initialSetupComplete: initialSetupComplete ?? this.initialSetupComplete,
    overdueRecoveryPolicy: overdueRecoveryPolicy ?? this.overdueRecoveryPolicy,
  );

  bool hasSameScheduleAs(LifestyleSettings other) =>
      commuteStartMinute == other.commuteStartMinute &&
      afterHomeMinute == other.afterHomeMinute &&
      weekendsAreHolidays == other.weekendsAreHolidays &&
      japaneseHolidays == other.japaneseHolidays;

  Map<String, Object?> toJson() => {
    'commute_start_minute': commuteStartMinute,
    'after_home_minute': afterHomeMinute,
    'weekends_are_holidays': weekendsAreHolidays,
    'japanese_holidays': japaneseHolidays,
    'initial_setup_complete': initialSetupComplete,
    'overdue_recovery_policy': switch (overdueRecoveryPolicy) {
      OverdueRecoveryPolicy.nextRegularSlot => 'next_regular_slot',
      OverdueRecoveryPolicy.notifyOnRecovery => 'notify_on_recovery',
    },
  };

  factory LifestyleSettings.fromJson(Map<String, dynamic> json) =>
      LifestyleSettings(
        commuteStartMinute: json['commute_start_minute'] as int? ?? 18 * 60,
        afterHomeMinute: json['after_home_minute'] as int? ?? 19 * 60,
        weekendsAreHolidays: json['weekends_are_holidays'] as bool? ?? true,
        japaneseHolidays: json['japanese_holidays'] as bool? ?? true,
        initialSetupComplete: json['initial_setup_complete'] as bool? ?? false,
        overdueRecoveryPolicy: switch (json['overdue_recovery_policy']) {
          null || 'next_regular_slot' => OverdueRecoveryPolicy.nextRegularSlot,
          'notify_on_recovery' => OverdueRecoveryPolicy.notifyOnRecovery,
          _ => throw const FormatException('Unknown overdue recovery policy'),
        },
      );
}
