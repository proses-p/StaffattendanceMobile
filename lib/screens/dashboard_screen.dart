import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:staff_attendance_mobile/models/dashboard_statistics_model.dart';
import 'package:staff_attendance_mobile/models/user_status_model.dart';
import 'package:staff_attendance_mobile/custom/attendance_card.dart';
import 'package:staff_attendance_mobile/screens/on_field_screen.dart';
import 'package:staff_attendance_mobile/screens/flagged_assignments_screen.dart';
import 'package:staff_attendance_mobile/screens/attendance_history_screen.dart';
import 'package:staff_attendance_mobile/screens/leave_management_screen.dart';
import 'package:staff_attendance_mobile/screens/more_screen.dart';
import 'package:staff_attendance_mobile/screens/profile_screen.dart';
import 'package:staff_attendance_mobile/screens/profile_settings_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:staff_attendance_mobile/services/device_security_service.dart';
import 'package:staff_attendance_mobile/services/notification_storage.dart';
import 'package:staff_attendance_mobile/screens/notifications_screen.dart';
import 'package:staff_attendance_mobile/screens/notification_service.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  int _selectedIndex = 0; // Inafanya icon ya 'Home' iwe active mwanzo

  UserStatusModel? _currentStatus;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  DateTime _clockNow = DateTime.now();
  Timer? _workedHoursTimer;
  Timer? _notificationTimer;
  String _buttonState = 'CHECK_IN';
  String? _role;
  Map<String, dynamic>? _fieldStats;
  Map<String, dynamic>? _adminStats;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startNotificationSync();
  }

  // function to load dashboard data
  Future<void> _loadDashboardData({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      if (_role == null) {
        final preferences = await SharedPreferences.getInstance();
        _role = preferences.getString('auth_role');
        _role ??= (await _apiService.fetchProfile()).role;
      }
      if (_role == 'admin' || _role == 'manager') {
        await _loadFieldStatistics();
        if (!mounted) return;
        setState(() {
          _loadError = null;
          _isLoading = false;
        });
        return;
      }
      unawaited(_loadFieldStatistics());
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
          _showFeedbackSnackBar(_displayError(e));
        }
      }
    }
  }

  Future<void> _loadFieldStatistics() async {
    try {
      final fieldStats = _role == 'admin' || _role == 'manager'
          ? null
          : await _apiService.fetchFieldStats();
      Map<String, dynamic>? adminStats;
      if (_role == 'admin' || _role == 'manager') {
        adminStats = await _apiService.fetchAdminFieldStats();
      }
      if (!mounted) return;
      setState(() {
        if (fieldStats != null) _fieldStats = fieldStats;
        _adminStats = adminStats;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.toString());
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
    _notificationTimer?.cancel();
    super.dispose();
  }

  void _startNotificationSync() {
    // Kagua mara moja app ikifunguka
    _checkServerNotifications();

    // Endelea kukagua kila baada ya sekunde 20 mtumiaji akiwa ndani ya app
    _notificationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkServerNotifications();
    });
  }

  Future<void> _checkServerNotifications() async {
    try {
      final items = await _apiService.fetchUnreadNotifications();
      if (items.isEmpty) return;

      for (var item in items) {
        final String title = item['title']?.toString() ?? 'Taarifa Mpya';
        final String body = item['body']?.toString() ?? '';
        final int id = item['id'] is int
            ? item['id']
            : DateTime.now().millisecondsSinceEpoch;

        // 1. Hifadhi kwenye kengele ya ndani ya App (Badge itaongezeka!)
        await NotificationStorage.addNotification(title, body);

        // 2. Piga mlio wa notification juu ya screen ya simu
        await NotificationService().showInstantNotification(
          id: id,
          title: title,
          body: body,
        );
      }

      // Onyesha mabadiliko kwenye icon ya kengele (Badge namba ionekane)
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Kama mtandao unasumbua, isilete error kwenye screen; itajaribu tena baada ya sekunde 20
    }
  }


  // function to handle check and check out
  Future<void> _handleAttendanceAction() async {
    if (_isSubmitting || _buttonState == 'COMPLETED') return;

    setState(() => _isSubmitting = true);

    try {
      final deviceStatus = await _apiService.fetchDeviceStatus();
      if (!mounted) return;
      final status = deviceStatus['status']?.toString() ?? 'unknown';
      if (status != 'active') {
        await _showDeviceAccessDialog(status);
        return;
      }
      if (!await DeviceSecurityService().canSign()) {
        throw Exception(
          'Strong biometric authentication is not available. Set up strong '
          'fingerprint or face biometrics in Android Settings, then retry. '
          'Attendance was not submitted.',
        );
      }
      if (!mounted) return;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Please turn on your GPS to track your location.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Refusal of your GPS location.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Your location is turned off. Allow the location permission to your phone settings',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (position.accuracy > 30) {
        throw Exception(
          'Your location accuracy is ${position.accuracy.toStringAsFixed(0)}m. '
          'Move to an open area and try again; 30m or better is required.',
        );
      }
      final endpoint = _buttonState == 'CHECK_IN'
          ? 'attendance/check-in'
          : 'attendance/check-out';

      final result = await _apiService.submitAttendance(
        endpoint: endpoint,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        locationTimestamp: position.timestamp,
      );

      if (result['success'] != true) {
        throw Exception(
          result['message']?.toString() ?? 'Attendance request failed.',
        );
      }

      if (!mounted) return;
      _showFeedbackSnackBar(
        result['message']?.toString() ?? 'Attendance recorded successfully.',
        isSuccess: true,
      );
      setState(() => _isSubmitting = false);
      unawaited(_loadDashboardData(showLoading: false));
    } catch (errorMessage) {
      if (mounted) {
        _showFeedbackSnackBar(_displayError(errorMessage));
      }
    } finally {
      if (mounted && _isSubmitting) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showDeviceAccessDialog(String status) async {
    final title = switch (status) {
      'not_registered' => 'Device Registration Required',
      'pending' => 'Administrator approval pending',
      'revoked' => 'Device access revoked',
      _ => 'Unable to confirm device approval',
    };
    final message = switch (status) {
      'not_registered' =>
        'You need to register this device before you can check in or check out. '
            'Open Profile > Settings > Device Security and follow the registration steps.',
      'pending' =>
        'This device is registered and awaiting administrator approval. Wait for '
            'approval or contact your administrator; do not register it again.',
      'revoked' =>
        'This device is no longer authorized for attendance. Contact your '
            'administrator; if a replacement is needed, open Device Security.',
      _ =>
        'The server could not confirm that this device is approved. Refresh its '
            'status in Device Security before trying attendance again.',
    };
    final canOpenSettings =
        status == 'not_registered' ||
        status == 'pending' ||
        status == 'revoked';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (canOpenSettings)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _openDeviceSecurity();
              },
              child: Text(
                status == 'pending'
                    ? 'View Device Status'
                    : 'Go to Device Settings',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openDeviceSecurity() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeviceSecurityScreen(apiService: _apiService),
      ),
    );
  }

  String _displayError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(Exception|StateError): '), '');

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

    // Set status bar icons to light (white) to match the orange background header
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _role == 'admin' || _role == 'manager'
          ? SafeArea(child: _buildAdminDashboard())
          : _isLoading && _currentStatus == null
          ? const Center(child: CircularProgressIndicator())
          : _currentStatus == null
          ? SafeArea(
              child: _fieldStats == null
                  ? _buildLoadError()
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildLoadError(),
                        const SizedBox(height: 18),
                        _buildEmployeeFieldStats(),
                      ],
                    ),
            )
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  // ===================================================
                  // EXTENDED ORANGE HERO CONTAINER (Top to Attendance Card)
                  // ===================================================
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: primaryColor, // Vibrant Orange
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: 20,
                      right: 20,
                      bottom: 28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroHeader(_currentStatus!.userName),
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
                      ],
                    ),
                  ),

                  // ===================================================
                  // STATISTICS & LOWER SECTIONS (White / Light Background)
                  // ===================================================
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        const SizedBox(height: 22),
                        _buildEmployeeFieldStats(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Color(0xFFFB923C),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        onTap: (index) {
          if (index == 3) {
            setState(() => _selectedIndex = index);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MoreScreen(
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
          if (index == 2) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LeaveManagementScreen(apiService: _apiService),
              ),
            );
            return;
          }
          if (index == 4) {
            setState(() => _selectedIndex = index);
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
          setState(() => _selectedIndex = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.time_to_leave),
            label: 'Leave',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeFieldStats() {
    final stats = _fieldStats;
    if (stats == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Field operations · ${stats['month'] ?? ''}',
          style: const TextStyle(
            color: Color(0xFF172033),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FieldStatCard(
                title: 'Field hours',
                value: '${stats['total_field_hours'] ?? 0}',
                icon: Icons.work_history_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FieldStatCard(
                title: 'Avg daily hrs',
                value: '${stats['avg_daily_hours'] ?? 0}',
                icon: Icons.schedule_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FieldStatCard(
                title: 'Field visits',
                value: '${stats['total_field_visits'] ?? 0}',
                icon: Icons.location_on_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdminDashboard() {
    final stats = _adminStats;
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          _buildHeader('Admin'),
          const SizedBox(height: 20),
          const Text(
            'Field operations',
            style: TextStyle(
              color: Color(0xFF172033),
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (stats == null)
            _loadError == null
                ? const Center(child: CircularProgressIndicator())
                : _buildInlineError()
          else ...[
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const OnFieldScreen()),
              ),
              child: _FieldStatCard(
                title: 'On field',
                value: '${stats['currently_on_field'] ?? 0}',
                icon: Icons.people_alt_outlined,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FieldStatCard(
                    title: 'Missing',
                    value: '${stats['missing_personnel'] ?? 0}',
                    icon: Icons.person_off_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FieldStatCard(
                    title: 'Pending',
                    value:
                        '${(stats['pending_approvals'] as Map?)?['total'] ?? 0}',
                    icon: Icons.pending_actions_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FlaggedAssignmentsScreen(),
                ),
              ),
              child: _FieldStatCard(
                title: 'Flagged for review',
                value: '${stats['flagged_assignments'] ?? 0}',
                icon: Icons.flag_outlined,
              ),
            ),
          ],
          if (_loadError != null && stats != null) ...[
            const SizedBox(height: 10),
            _buildInlineError(),
          ],
        ],
      ),
    );
  }

  // Header styled specifically for the Orange Hero Background (white text & icons)
  Widget _buildHeroHeader(String userName) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.white.withOpacity(0.25),
          child: const Icon(Icons.person, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good Day, $userName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Have a productive day',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: _buildNotificationBell(),
        ),
      ],
    );
  }

  
Widget _buildNotificationBell() {
  return FutureBuilder<int>(
    future: NotificationStorage.getUnreadCount(),
    builder: (context, snapshot) {
      final int unreadCount = snapshot.data ?? 0;

      return IconButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          );
          setState(() {}); // Refresh namba ya kengele ikirudi Home (iwe 0)
        },
        icon: Badge(
          isLabelVisible: unreadCount > 0,
          label: Text('$unreadCount'),
          backgroundColor: Colors.red,
          child: const Icon(Icons.notifications_outlined, size: 28),
        ),
      );
    },
  );
}

  // Standard Header for non-orange sections (e.g. Admin view)
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
                'Good Day, $userName',
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
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not refresh your latest attendance data.',
              style: TextStyle(color: Colors.white, fontSize: 12),
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
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.88,
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
            ('Leave', leaveDays == null ? '-' : _formatDays(leaveDays)),
            (
              'Incomplete',
              incompleteDays == null
                  ? '-'
                  : '$incompleteDays day${incompleteDays == 1 ? '' : 's'}',
            ),
            (
              'Absent',
              statistics.absentDays == null
                  ? '-'
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
        : '-';
  }
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
      padding: const EdgeInsets.all(10),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
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
                  color: value == '-'
                      ? const Color(0xFF64748B)
                      : const Color(0xFF172033),
                  fontSize: value == '-' ? 16 : 26,
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
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
            if (reason != null && value == '-') ...[
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

class _FieldStatCard extends StatelessWidget {
  const _FieldStatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EDF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFFFB923C)),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF172033),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}