import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/screens/profile_settings_screen.dart';
import 'package:staff_attendance_mobile/services/sync_service.dart';

class SyncBanner extends StatefulWidget {
  const SyncBanner({super.key});

  @override
  State<SyncBanner> createState() => _SyncBannerState();
}

class _SyncBannerState extends State<SyncBanner> {
  bool _guidanceShown = false;

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_handleSyncChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleSyncChange());
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_handleSyncChange);
    super.dispose();
  }

  void _handleSyncChange() {
    final sync = SyncService.instance;
    if (!sync.keyRecoveryRequired) {
      _guidanceShown = false;
      return;
    }
    if (!mounted || _guidanceShown) return;
    _guidanceShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showKeyRecoveryGuidance();
    });
  }

  Future<void> _showKeyRecoveryGuidance() async {
    final goToSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Signing key recovery required'),
        content: const Text(
          'This device signing key could not be used to verify a secure request. '
          'Recover the key in Settings to resume attendance and field sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Go to Settings'),
          ),
        ],
      ),
    );
    if (goToSettings != true || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ProfileSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SyncService.instance,
      builder: (context, _) {
        final sync = SyncService.instance;
        if (sync.online &&
            !sync.syncing &&
            sync.pendingCount == 0 &&
            sync.failedCount == 0 &&
            !sync.keyRecoveryRequired) {
          return const SizedBox.shrink();
        }

        final Color color;
        final String text;
        if (sync.failedCount > 0) {
          color = const Color(0xFFDC2626);
          text = '${sync.failedCount} record(s) need attention';
        } else if (sync.pendingCount > 0 && sync.lastError != null) {
          color = const Color(0xFFDC2626);
          text = sync.lastError!;
        } else if (sync.syncing) {
          color = const Color(0xFF2563EB);
          text = 'Syncing ${sync.pendingCount} record(s)…';
        } else if (!sync.online) {
          color = const Color(0xFFEA580C);
          text =
              'Offline. Your records are saved and the time is kept '
              '(${sync.pendingCount} waiting)';
        } else {
          color = const Color(0xFF2563EB);
          text = '${sync.pendingCount} record(s) waiting to sync';
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.sync, size: 18, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (sync.failedCount > 0)
                TextButton(
                  onPressed: () async {
                    final events = await sync.failedEvents();
                    if (!context.mounted) return;
                    showModalBottomSheet<void>(
                      context: context,
                      builder: (context) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(16),
                          children: [
                            const Text(
                              'Records needing attention',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            ...events.map(
                              (event) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(event['type']!.toString()),
                                subtitle: Text(
                                  event['last_error']?.toString() ??
                                      'The server rejected this record.',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('Review'),
                ),
            ],
          ),
        );
      },
    );
  }
}
