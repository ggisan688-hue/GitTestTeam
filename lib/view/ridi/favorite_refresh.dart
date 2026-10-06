import 'package:flutter/foundation.dart';

/// A process-local invalidation signal. Server data remains the source of
/// truth; mounted library screens reload their one favorite-list future when
/// a detail screen successfully changes a favorite.
final ValueNotifier<int> favoriteRefresh = ValueNotifier<int>(0);

void notifyFavoriteChanged() => favoriteRefresh.value++;
