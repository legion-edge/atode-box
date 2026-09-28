import 'package:flutter/material.dart';

import '../storage/inbox_item.dart';

/// Japanese text, icon and color travel together for every category display.
extension CategoryPresentation on ItemCategory {
  String get label => switch (this) {
    ItemCategory.read => '読む',
    ItemCategory.watch => '見る',
    ItemCategory.go => '行く',
    ItemCategory.buy => '買う',
    ItemCategory.doTask => 'やる',
    ItemCategory.idea => 'アイデア',
    ItemCategory.memo => 'メモ',
  };

  IconData get icon => switch (this) {
    ItemCategory.read => Icons.menu_book_outlined,
    ItemCategory.watch => Icons.play_circle_outline,
    ItemCategory.go => Icons.place_outlined,
    ItemCategory.buy => Icons.shopping_bag_outlined,
    ItemCategory.doTask => Icons.check_circle_outline,
    ItemCategory.idea => Icons.lightbulb_outline,
    ItemCategory.memo => Icons.note_outlined,
  };

  Color get color => switch (this) {
    ItemCategory.read => const Color(0xFF345995),
    ItemCategory.watch => const Color(0xFF77549A),
    ItemCategory.go => const Color(0xFF257568),
    ItemCategory.buy => const Color(0xFF98602D),
    ItemCategory.doTask => const Color(0xFF8B405C),
    ItemCategory.idea => const Color(0xFF856A19),
    ItemCategory.memo => const Color(0xFF53616B),
  };
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key});

  final ItemCategory category;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(category.icon, color: category.color, size: 18),
      const SizedBox(width: 4),
      Text(category.label, style: TextStyle(color: category.color)),
    ],
  );
}
