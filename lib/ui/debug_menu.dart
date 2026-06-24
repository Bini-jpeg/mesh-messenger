// FILE: lib/ui/debug_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/metrics_service.dart';
import '../core/storage_service.dart';
import '../main.dart';
import '../routing/flooding_strategy.dart';
import '../routing/gossip_strategy.dart';
import '../routing/routing_manager.dart';

/// Research / thesis debug menu.
/// Accessible from the HomeScreen app bar.
class DebugMenu extends StatelessWidget {
  const DebugMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final routingManager = sl<RoutingManager>();
    final metrics        = sl<MetricsService>();

    return AlertDialog(
      title: const Text('Debug / Research'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Routing strategy ─────────────────────────────────────────────
            const Text('Routing Strategy',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _StrategyTile(
              label:    'Flooding',
              isActive: routingManager.currentStrategyName == 'Flooding',
              onTap: () {
                routingManager.setStrategy(FloodingStrategy());
                Navigator.pop(context);
              },
            ),
            _StrategyTile(
              label:    'Gossip (fanout: 2)',
              isActive: routingManager.currentStrategyName ==
                  'Gossip (fanout: 2)',
              onTap: () {
                routingManager.setStrategy(GossipStrategy(fanout: 2));
                Navigator.pop(context);
              },
            ),
            _StrategyTile(
              label:    'Gossip (fanout: 3)',
              isActive: routingManager.currentStrategyName ==
                  'Gossip (fanout: 3)',
              onTap: () {
                routingManager.setStrategy(GossipStrategy(fanout: 3));
                Navigator.pop(context);
              },
            ),
            _StrategyTile(
              label:    'Gossip (fanout: 4)',
              isActive: routingManager.currentStrategyName ==
                  'Gossip (fanout: 4)',
              onTap: () {
                routingManager.setStrategy(GossipStrategy(fanout: 4));
                Navigator.pop(context);
              },
            ),

            const Divider(height: 24),

            // ── Metrics ──────────────────────────────────────────────────────
            const Text('Metrics',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),

            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('View Stats'),
              onTap: () => _showStats(context, metrics),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Export CSV (copy to clipboard)'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final csv = metrics.exportToCSV();
                await Clipboard.setData(ClipboardData(text: csv));
                if (context.mounted) {
                  messenger.showSnackBar(const SnackBar(
                      content:
                          Text('CSV copied to clipboard!')));
                  Navigator.pop(context);
                }
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_sweep, color: Colors.orange),
              title: const Text('Clear Metrics Logs'),
              onTap: () async {
                await metrics.clearLogs();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Metrics logs cleared.')),
                  );
                }
              },
            ),

            const Divider(height: 24),

            // ── Danger zone ──────────────────────────────────────────────────
            const Text('Danger Zone',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 4),
            ListTile(
              leading:
                  const Icon(Icons.warning_amber, color: Colors.red),
              title: const Text('Clear ALL Data',
                  style: TextStyle(color: Colors.red)),
              subtitle: const Text(
                  'Deletes all messages, contacts and logs'),
              onTap: () => _confirmClearAll(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _showStats(BuildContext context, MetricsService metrics) {
    final stats = metrics.getStats();
    final avgLatency =
        (stats['avg_latency_ms'] as double).toStringAsFixed(1);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Network Stats'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatRow('Messages sent',      '${stats['total_sent']}'),
            _StatRow('Delivered',          '${stats['total_delivered']}'),
            _StatRow('Failed',             '${stats['total_failed']}'),
            _StatRow('Forwarded (relay)',   '${stats['total_forwarded']}'),
            _StatRow('Avg latency',        '$avgLatency ms'),
            _StatRow('Total log entries',  '${stats['total_log_entries']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Clear All'),
        content: const Text(
            'This will permanently delete ALL messages, contacts, '
            'and metric logs. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await sl<StorageService>().clearAllData();
              await sl<MetricsService>().clearLogs();
              if (context.mounted) {
                Navigator.pop(context); // close confirm dialog
                Navigator.pop(context); // close debug menu
              }
            },
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );
  }
}

class _StrategyTile extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _StrategyTile({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: isActive
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.circle_outlined, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
