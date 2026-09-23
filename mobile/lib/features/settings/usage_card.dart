import 'package:flutter/material.dart';
import 'package:nova_ai/core/api/nova_client.dart';

/// Tokens spent so far — today, this week, all time, and where they went.
class UsageCard extends StatefulWidget {
  const UsageCard({super.key});

  @override
  State<UsageCard> createState() => _UsageCardState();
}

class _UsageCardState extends State<UsageCard> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await NovaClient.instance.usage();
      if (mounted) setState(() { _data = d; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Backend not reachable'; _loading = false; });
    }
  }

  String _n(num? v) {
    final s = (v ?? 0).round().toString();
    // 1,23,456 — Indian grouping, same as the rest of the app's numbers
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _data;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.data_usage, size: 19),
                const SizedBox(width: 8),
                Text('Tokens used', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 19),
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              )
            else if (d != null) ...[
              Row(
                children: [
                  _Stat(label: 'Today', value: _n(d['today_totals']?['total'])),
                  _Stat(label: 'This week', value: _n(d['week_totals']?['total'])),
                  _Stat(label: 'All time', value: _n(d['all_time']?['total'])),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Today: ${_n(d['today_totals']?['input'])} in · '
                '${_n(d['today_totals']?['output'])} out · '
                '${_n(d['today_totals']?['calls'])} calls',
                style: theme.textTheme.bodySmall,
              ),
              if ((d['by_model'] as List?)?.isNotEmpty ?? false) ...[
                const Divider(height: 20),
                for (final m in (d['by_model'] as List).take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(m['model'] ?? '?',
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis)),
                        Text(_n(m['total']), style: theme.textTheme.bodySmall),
                        if (m['cost_usd'] != null)
                          Text('  \$${(m['cost_usd'] as num).toStringAsFixed(3)}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.disabledColor)),
                      ],
                    ),
                  ),
              ],
              if ((d['by_kind'] as List?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final k in (d['by_kind'] as List))
                      Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text('${k['kind']}: ${_n(k['total'])}',
                            style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    await NovaClient.instance.resetUsage();
                    _load();
                  },
                  child: const Text('Reset counter'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600, height: 1.1)),
          Text(label, style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.disabledColor)),
        ],
      ),
    );
  }
}
