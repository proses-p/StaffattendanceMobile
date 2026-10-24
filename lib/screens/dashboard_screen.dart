// dashboard_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/models/dashboard_statistics_model.dart';
import 'package:staff_attendance_mobile/models/user_status_model.dart';
import 'package:staff_attendance_mobile/custom/attendance_card.dart';
import 'package:staff_attendance_mobile/screens/attendance_history_screen.dart';
import 'package:staff_attendance_mobile/screens/profile_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  int _selectedIndex = 2; // Inafanya icon ya 'Home' iwe active mwanzo

  UserStatusModel? _currentStatus;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  DateTime _clockNow = DateTime.now();
  Timer? _workedHoursTimer;
  String _buttonState = 'CHECK_IN';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // function to load dashboard data
  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.fetchDashboardData();
      if (!mounted) return;
      _clockNow = DateTime.now();
      _syncWorkedHoursTimer(data);
      setState(() {
        _currentStatus = data;
        _loadError = null;
        _buttonState = data.hasCheckedOut
            ? 'COMPLETED'
            : data.hasCheckedIn
            ? 'CHECK_OUT'
            : 'CHECK_IN';
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
        if (_currentStatus != null) {
          _showFeedbackSnackBar(e.toString());
        }
      }
    }
  }

  void _syncWorkedHoursTimer(UserStatusModel status) {
    if (status.isCheckedIn && status.checkInAt != null) {
      _workedHoursTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) {
          setState(() => _clockNow = DateTime.now());
        }
      });
    } else {
      _workedHoursTimer?.cancel();
      _workedHoursTimer = null;
    }
  }

  @override
  void dispose() {
    _workedHoursTimer?.cancel();
    super.dispose();
  }

  // function to handle check and check out
  Future<void> _handleAttendanceAction() async {
    if (_isSubmitting || _buttonState == 'COMPLETED') return;

    setState(() => _isSubmitting = true);
    var dialogOpen = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final String? token = prefs.getString('auth_token');
      if (token == null) {
        throw Exception('Tafadhali login upya.');
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      dialogOpen = true;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Tafadhali washa GPS ya simu yako.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Ruhusa ya GPS imekataliwa.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Ruhusa ya GPS imezimwa. Iruhusu kupitia mipangilio ya simu yako.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final endpoint = _buttonState == 'CHECK_IN'
          ? 'attendance/check-in'
          : 'attendance/check-out';

      final result = await _apiService.submitAttendance(
        endpoint: endpoint,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        token: token,
      );

      if (result['success'] != true) {
        throw Exception(
          result['message']?.toString() ?? 'Attendance request failed.',
        );
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;
      _showFeedbackSnackBar(
        result['message']?.toString() ?? 'Attendance recorded successfully.',
        isSuccess: true,
      );
      setState(() => _isSubmitting = false);
      await _loadDashboardData();
    } catch (errorMessage) {
      if (mounted) {
        if (dialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _showFeedbackSnackBar(errorMessage.toString());
      }
    } finally {
      if (mounted && _isSubmitting) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showFeedbackSnackBar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFB923C);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: _isLoading && _currentStatus == null
            ? const Center(child: CircularProgressIndicator())
            : _currentStatus == null
            ? _buildLoadError()
            : RefreshIndicator(
                onRefresh: _loadDashboardData,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    _buildHeader(_currentStatus!.userName),
                    const SizedBox(height: 18),
                    if (_loadError != null) ...[
                      _buildInlineError(),
                      const SizedBox(height: 14),
                    ],
                    AttendanceCard(
                      status: _currentStatus!,
                      now: _clockNow,
                      buttonState: _buttonState,
                      onAttendanceAction: _handleAttendanceAction,
                      isSubmitting: _isSubmitting,
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Your statistics',
                          style: TextStyle(
                            color: Color(0xFF172033),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_currentStatus!
                                .statistics
                                ?.reportingPeriod
                                .isNotEmpty ==
                            true)
                          Text(
                            _currentStatus!.statistics!.reportingPeriod,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_currentStatus!.statistics == null)
                      _buildStatisticsUnavailable()
                    else ...[
                      if (!_currentStatus!.statistics!.hasAttendanceHistory)
                        _buildNoAttendanceNotice(),
                      _buildStatisticsGrid(_currentStatus!.statistics!),
                    ],
                  ],
                ),
              ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 4) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProfileScreen(
                  onSelectTab: (selectedIndex) {
                    setState(() => _selectedIndex = selectedIndex);
                  },
                ),
              ),
            );
            return;
          }
          if (index == 1) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AttendanceHistoryScreen(),
              ),
            );
            return;
          }
          setState(() => _selectedIndex = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String userName) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 22,
          backgroundColor: Color(0xFFE2E8F0),
          child: Icon(Icons.person, color: Color(0xFF64748B)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good Morning, $userName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF172033),
                ),
              ),
              const Text(
                'Have a productive day',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.black),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Unable to load your dashboard',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadDashboardData,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: Color(0xFFB45309), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not refresh your latest attendance data.',
              style: TextStyle(color: Color(0xFF92400E), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsUnavailable() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'Statistics are unavailable right now. Pull down to try again.',
        style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
      ),
    );
  }

  Widget _buildNoAttendanceNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'No attendance records for this reporting period yet.',
        style: TextStyle(color: Color(0xFF9A3412), fontSize: 12),
      ),
    );
  }

  Widget _buildStatisticsGrid(DashboardStatistics statistics) {
    final totalHours =
        '${statistics.totalWorkedMinutes ~/ 60}h '
        '${(statistics.totalWorkedMinutes % 60).toString().padLeft(2, '0')}m';
    final onTimeRate = statistics.onTimeRatePercent;
    final attendanceRate = statistics.attendanceRatePercent;
    final leaveDays = statistics.approvedLeaveDays;
    final incompleteDays = statistics.incompleteDays;

    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      children: [
        _DashboardStatCard(
          title: 'Overtime Hours',
          icon: Icons.more_time,
          accent: const Color(0xFF7C3AED),
          value: statistics.formatMinutes(statistics.overtimeMinutes),
          detail:
              statistics.unavailableReasons['overtime'] ??
              'Based on completed shifts',
        ),
        _DashboardStatCard(
          title: 'On-Time Rate & Hours',
          icon: Icons.schedule,
          accent: const Color(0xFF0284C7),
          value: onTimeRate == null
              ? _unavailableRateLabel(
                  statistics.unavailableReasons['on_time_rate'],
                )
              : '${onTimeRate.toStringAsFixed(1)}%',
          detail: '$totalHours worked',
          reason: onTimeRate == null
              ? statistics.unavailableReasons['on_time_rate']
              : null,
        ),
        _DashboardStatCard(
          title: 'Attendance Rate',
          icon: Icons.fact_check_outlined,
          accent: const Color(0xFF16A34A),
          value: attendanceRate == null
              ? _unavailableRateLabel(
                  statistics.unavailableReasons['attendance_rate'],
                )
              : '${attendanceRate.toStringAsFixed(1)}%',
          detail:
              statistics.unavailableReasons['attendance_rate'] ??
              'Eligible working days attended',
        ),
        _DashboardStatCard(
          title: 'Leave / Incomplete Days',
          icon: Icons.event_busy_outlined,
          accent: const Color(0xFFEA580C),
          value: 'Breakdown',
          detail: null,
          breakdown: [
            (
              'Leave',
              leaveDays == null ? 'Not configured' : _formatDays(leaveDays),
            ),
            (
              'Incomplete',
              incompleteDays == null
                  ? 'Not configured'
                  : '$incompleteDays day${incompleteDays == 1 ? '' : 's'}',
            ),
            (
              'Absent',
              statistics.absentDays == null
                  ? 'Not configured'
                  : '${statistics.absentDays} day${statistics.absentDays == 1 ? '' : 's'}',
            ),
          ],
          reason:
              statistics.unavailableReasons['approved_leave_days'] ??
              statistics.unavailableReasons['incomplete_days'],
        ),
      ],
    );
  }

  String _formatDays(double days) {
    final number = days == days.roundToDouble()
        ? days.toStringAsFixed(0)
        : days.toStringAsFixed(1);
    return '$number day${days == 1 ? '' : 's'}';
  }

  String _unavailableRateLabel(String? reason) {
    return reason?.startsWith('There are no eligible scheduled working days') ==
            true
        ? 'No eligible days'
        : 'Not configured';
  }

  // Sehemu ya Menu ya chini (Bottom Navigation Bar)
}

class _DashboardStatCard extends StatelessWidget {
  const _DashboardStatCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.value,
    required this.detail,
    this.reason,
    this.breakdown = const [],
  });

  final String title;
  final IconData icon;
  final Color accent;
  final String value;
  final String? detail;
  final String? reason;
  final List<(String, String)> breakdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE8EDF4)),
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
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          if (breakdown.isEmpty) ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: value == 'Not configured'
                      ? const Color(0xFF64748B)
                      : const Color(0xFF172033),
                  fontSize: value == 'Not configured' ? 16 : 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  height: 1.25,
                ),
              ),
            ],
            if (reason != null && value == 'Not configured') ...[
              const SizedBox(height: 3),
              Text(
                reason!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 9,
                  height: 1.2,
                ),
              ),
            ],
          ] else ...[
            for (final item in breakdown) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF172033),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (reason != null) ...[
              const SizedBox(height: 3),
              Text(
                reason!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 9,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
