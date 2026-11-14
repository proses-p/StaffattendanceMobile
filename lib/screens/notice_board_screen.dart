import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class NoticeBoardScreen extends StatefulWidget {
  const NoticeBoardScreen({this.apiService, super.key});

  final ApiService? apiService;

  @override
  State<NoticeBoardScreen> createState() => _NoticeBoardScreenState();
}

class _NoticeBoardScreenState extends State<NoticeBoardScreen> {
  static const _accent = Color(0xFFFB923C);
  late final ApiService _apiService = widget.apiService ?? ApiService();
  final Set<int> _readRequests = {};
  List<Map<String, dynamic>> _announcements = [];
  int _unreadCount = 0;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    if (!_isLoading || _error != null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final response = await _apiService.fetchAnnouncements();
      if (!mounted) return;
      setState(() {
        _announcements = (response['announcements'] as List)
            .cast<Map<String, dynamic>>();
        _unreadCount = response['unread_count'] as int? ?? 0;
        _isLoading = false;
        _readRequests.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _markReadWhenVisible(int id) {
    if (!_readRequests.add(id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markRead(id);
    });
  }

  Future<void> _markRead(int id) async {
    try {
      await _apiService.markAnnouncementRead(id);
      if (!mounted) return;
      setState(() {
        final index = _announcements.indexWhere(
          (announcement) => _announcementId(announcement) == id,
        );
        if (index >= 0 && _announcements[index]['is_read'] != true) {
          _announcements[index]['is_read'] = true;
          _unreadCount = (_unreadCount - 1)
              .clamp(0, _announcements.length)
              .toInt();
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not mark announcement as read: $error'),
          ),
        );
    }
  }

  int _announcementId(Map<String, dynamic> announcement) {
    final id = announcement['id'];
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '') ?? -1;
  }

  Color _priorityColor(String? priority) {
    return switch (priority?.toLowerCase()) {
      'urgent' => Colors.red.shade700,
      'important' => Colors.deepOrange.shade700,
      _ => Colors.blue.shade700,
    };
  }

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '';
    return DateFormat('d MMM yyyy · h:mm a').format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notice Board'),
        actions: [
          if (_unreadCount > 0)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_unreadCount unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh announcements',
            onPressed: _isLoading ? null : _loadAnnouncements,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading && _announcements.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null && _announcements.isEmpty
          ? _buildError(theme)
          : _announcements.isEmpty
          ? RefreshIndicator(
              onRefresh: _loadAnnouncements,
              color: _accent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Icon(Icons.campaign_outlined, size: 52, color: Colors.grey),
                  SizedBox(height: 12),
                  Center(
                    child: Text(
                      'There are no active announcements.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAnnouncements,
              color: _accent,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _announcements.length,
                itemBuilder: (context, index) {
                  final announcement = _announcements[index];
                  final id = _announcementId(announcement);
                  if (announcement['is_read'] != true && id >= 0) {
                    _markReadWhenVisible(id);
                  }
                  final priority =
                      announcement['priority']?.toString().toLowerCase() ??
                      'normal';
                  final priorityColor = _priorityColor(priority);
                  final pinned = announcement['is_pinned'] == true;
                  final author =
                      announcement['author_name']?.toString() ??
                      'Company Admin';
                  final date = _dateLabel(announcement['created_at']);

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: announcement['is_read'] == true
                            ? theme.colorScheme.outlineVariant
                            : _accent.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(17),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 7,
                            children: [
                              _tag(priority.toUpperCase(), priorityColor),
                              if (pinned) _tag('PINNED', _accent),
                              if (announcement['is_read'] != true)
                                _tag('NEW', Colors.teal.shade700),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            announcement['title']?.toString() ?? '',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            announcement['content']?.toString() ?? '',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  author,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (date.isNotEmpty) ...[
                                Icon(
                                  Icons.schedule,
                                  size: 15,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  date,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 42, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadAnnouncements,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}
