import 'package:flutter/material.dart';

/// Batch status is determined by the outcome, not whether a request is running.
class BatchMatchSummary extends StatelessWidget {
  final String phase;
  final int total;
  final int completed;
  final int success;
  final int failed;

  const BatchMatchSummary({
    super.key,
    required this.phase,
    required this.total,
    required this.completed,
    required this.success,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = switch (phase) {
      'done' => '批量匹配完成',
      'error' => '客户端未收到完整结果',
      _ => '正在匹配 $completed/$total',
    };
    return Card(
      margin: EdgeInsets.zero,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (phase == 'error') ...[
              const SizedBox(height: 8),
              const Text('服务端可能仍在处理，请先核对结果，避免重复提交。'),
            ],
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: total == 0 ? 1 : completed / total,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statChip(theme, '总数', total),
                _statChip(theme, '成功', success),
                _statChip(theme, '失败', failed),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(ThemeData theme, String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        children: [
          Text(
            '$value',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: label == '失败' && value > 0
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
