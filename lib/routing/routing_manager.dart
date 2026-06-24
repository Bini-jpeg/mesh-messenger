// FILE: lib/routing/routing_manager.dart
import 'package:flutter/foundation.dart';
import 'routing_strategy.dart';
import '../core/storage_service.dart';
import '../main.dart';

/// Holds the active routing strategy and allows hot-swapping at runtime.
/// Hot-swapping is a thesis feature: it lets the researcher change algorithm
/// during a live test session without restarting the app.
class RoutingManager {
  RoutingStrategy _strategy;

  RoutingManager(this._strategy);

  RoutingStrategy get strategy => _strategy;
  String get currentStrategyName => _strategy.name;

  /// Switches to [newStrategy] and pre-seeds its seen set from the full union
  /// of persisted IDs (from Hive) AND the current in-memory seen set of the
  /// outgoing strategy.
  ///
  /// Fix 12 — previously only persisted IDs were used, which meant any
  /// message IDs that were in the old strategy's in-memory set but had not
  /// yet been written to Hive (e.g. messages received as the final
  /// destination, which were never persisted) would be forgotten on swap,
  /// causing the new strategy to aggressively re-forward them.
  void setStrategy(RoutingStrategy newStrategy) {
    final persistedIds = sl<StorageService>().getPersistedSeenIds();
    final inMemoryIds  = _strategy.getSeenIds(); // Fix 12: include in-memory IDs

    // Union of both sets — duplicates are harmless in seedSeen.
    newStrategy.seedSeen({...persistedIds, ...inMemoryIds});

    _strategy = newStrategy;
    debugPrint('RoutingManager: switched to "${newStrategy.name}"');
  }
}
