import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/models/attendance_history_model.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  static const _primaryColor = Color(0xFFFB923C);

  late final ApiService _apiService = widget.apiService ?? ApiService();
  AttendanceHistoryPage? _history;
  Object? _error;
  bool _isLoading = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    setState(() {
      _page = page;
      _isLoading = true;
      _error = null;
    });

    try {
      final history = await _apiService.fetchAttendanceHistory(page: page);
      if (!mounted) return;
      setState(() {
        _history = history;
        _page = history.currentPage;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'Attendance History',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh history',
            onPressed: _isLoading ? null : () => _loadPage(_page),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading && history == null
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : _error != null && history == null
          ? _buildErrorState()
          : history == null || history.total == 0
          ? _buildEmptyState()
          : RefreshIndicator(
              color: _primaryColor,
              onRefresh: () => _loadPage(_page),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
                          child: Text(
                            '${history.total} ${history.total == 1 ? 'record' : 'records'}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        for (final record in history.records)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AttendanceRecordCard(record: record),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Could not load this page. ${_error.toString()}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _buildPagination(history),
                ],
              ),
            ),
    );
  }

  Widget _buildPagination(AttendanceHistoryPage history) {
    final firstRecord = history.total == 0
        ? 0
        : ((history.currentPage - 1) * history.perPage) + 1;
    final lastRecord = history.total == 0
        ? 0
        : (firstRecord + history.records.length - 1);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            IconButton.outlined(
              tooltip: 'Newer records',
              onPressed: !_isLoading && history.hasPreviousPage
                  ? () => _loadPage(history.currentPage - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
              color: _primaryColor,
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Page ${history.currentPage} of ${history.lastPage}',
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Showing $firstRecord–$lastRecord of ${history.total}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.outlined(
              tooltip: 'Older records',
              onPressed: !_isLoading && history.hasNextPage
                  ? () => _loadPage(history.currentPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
              color: _primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: Color(0xFF94A3B8),
              size: 46,
            ),
            const SizedBox(height: 14),
            const Text(
              'Unable to load attendance history',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _loadPage(_page),
              style: FilledButton.styleFrom(backgroundColor: _primaryColor),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.event_note_outlined, color: Color(0xFF94A3B8), size: 48),
            SizedBox(height: 14),
            Text(
              'No attendance records yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Your recorded work days will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceRecordCard extends StatelessWidget {
  const _AttendanceRecordCard({required this.record});

  final AttendanceHistoryRecord record;

  static const _primaryColor = Color(0xFFFB923C);

  @override
  Widget build(BuildContext context) {
    final checkedOut = record.isCheckedOut;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDF3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                color: _primaryColor,
                size: 17,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _formatDate(record.attendanceDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(isComplete: checkedOut),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DetailCell(
                  icon: Icons.login_rounded,
                  label: 'Sign In',
                  value: record.checkInTime ?? _formatTime(record.checkInAt),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DetailCell(
                  icon: Icons.logout_rounded,
                  label: 'Sign Out',
                  value: checkedOut
                      ? record.checkOutTime ?? _formatTime(record.checkOutAt)
                      : 'Not checked out',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DetailCell(
            icon: Icons.timelapse_rounded,
            label: 'Working Hours',
            value: record.workingHours,
            inline: true,
            valueColor: checkedOut ? const Color(0xFF172033) : _primaryColor,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          _LocationDetail(
            icon: Icons.place_outlined,
            label: 'Sign In Location',
            value: record.signInLocation ?? 'Location unavailable',
          ),
          const SizedBox(height: 9),
          _LocationDetail(
            icon: Icons.place,
            label: 'Sign Out Location',
            value: checkedOut
                ? record.signOutLocation ?? 'Location unavailable'
                : '—',
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'Date unavailable';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }

  static String _formatTime(DateTime? time) {
    if (time == null) return '—';
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isComplete});

  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final color = isComplete
        ? const Color(0xFF15803D)
        : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isComplete ? 'Completed' : 'In progress',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailCell extends StatelessWidget {
  const _DetailCell({
    required this.icon,
    required this.label,
    required this.value,
    this.inline = false,
    this.valueColor = const Color(0xFF172033),
  });

  final IconData icon;
  final String label;
  final String value;
  final bool inline;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (inline) {
      return Row(
        children: [
          Icon(icon, color: _AttendanceRecordCard._primaryColor, size: 17),
          const SizedBox(width: 8),
          Expanded(child: details),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _AttendanceRecordCard._primaryColor, size: 17),
        const SizedBox(width: 8),
        Expanded(child: details),
      ],
    );
  }
}

class _LocationDetail extends StatelessWidget {
  const _LocationDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF94A3B8), size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, height: 1.35),
              children: [
                TextSpan(
                  text: '$label  ',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
