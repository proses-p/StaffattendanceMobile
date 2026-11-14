import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/screens/attendance_history_screen.dart';
import 'package:staff_attendance_mobile/screens/ai_assistant_screen.dart';
import 'package:staff_attendance_mobile/screens/daily_work_submission_screen.dart';
import 'package:staff_attendance_mobile/screens/field_mode_screen.dart';
import 'package:staff_attendance_mobile/screens/leave_management_screen.dart';
import 'package:staff_attendance_mobile/screens/my_payslip_screen.dart';
import 'package:staff_attendance_mobile/screens/notice_board_screen.dart';
import 'package:staff_attendance_mobile/screens/profile_screen.dart';
import 'package:staff_attendance_mobile/screens/team_chat_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({this.onSelectTab, super.key});

  final ValueChanged<int>? onSelectTab;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  static const _primaryColor = Color(0xFFFB923C);
  int _unreadAnnouncements = 0;
  String? _announcementError;

  @override
  void initState() {
    super.initState();
    _loadAnnouncementCount();
  }

  Future<void> _loadAnnouncementCount() async {
    try {
      final response = await ApiService().fetchAnnouncements();
      if (!mounted) return;
      setState(() {
        _unreadAnnouncements = response['unread_count'] as int? ?? 0;
        _announcementError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _unreadAnnouncements = 0;
        _announcementError = error.toString();
      });
    }
  }

  void _navigateToTab(BuildContext context, int index) {
    final navigator = Navigator.of(context);
    if (index == 0) {
      widget.onSelectTab?.call(index);
      navigator.pop();
    } else if (index == 1) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const AttendanceHistoryScreen(),
        ),
      );
    } else if (index == 2) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => LeaveManagementScreen(apiService: ApiService()),
        ),
      );
    } else if (index == 4) {
      widget.onSelectTab?.call(index);
      navigator.pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(onSelectTab: widget.onSelectTab),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'More',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFFFF7ED),
            child: ListTile(
              leading: const Icon(Icons.auto_awesome, color: _primaryColor),
              title: const Text(
                'AI Work Assistant',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Personal work, schedule, and earnings help.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => AiAssistantScreen(apiService: ApiService()),
                ),
              ),
            ),
          ),
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_outlined,
                color: _primaryColor,
              ),
              title: const Text('My Payslip & Earnings'),
              subtitle: const Text('View monthly earnings and performance.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => MyPayslipScreen(apiService: ApiService()),
                ),
              ),
            ),
          ),
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(
                Icons.campaign_outlined,
                color: _primaryColor,
              ),
              title: const Text('Notice Board'),
              subtitle: Text(
                _announcementError ?? 'Company announcements and updates.',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_unreadAnnouncements > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _unreadAnnouncements > 99
                            ? '99+'
                            : '$_unreadAnnouncements',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const NoticeBoardScreen(),
                  ),
                );
                await _loadAnnouncementCount();
              },
            ),
          ),
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.forum_outlined, color: _primaryColor),
              title: const Text('Team Chat'),
              subtitle: const Text(
                'Chat with your organization and colleagues.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const TeamChatScreen()),
              ),
            ),
          ),
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(
                Icons.location_on_outlined,
                color: _primaryColor,
              ),
              title: const Text('Field Mode'),
              subtitle: const Text('Record field sessions and client visits.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const FieldModeScreen(),
                ),
              ),
            ),
          ),
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(
                Icons.assignment_turned_in_outlined,
                color: _primaryColor,
              ),
              title: const Text('Daily Work Submission'),
              subtitle: const Text('Submit today’s work and review feedback.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DailyWorkSubmissionScreen(apiService: ApiService()),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 3,
        type: BottomNavigationBarType.fixed,
        backgroundColor: _primaryColor,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        onTap: (index) => _navigateToTab(context, index),
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
}
