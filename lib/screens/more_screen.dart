import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/screens/attendance_history_screen.dart';
import 'package:staff_attendance_mobile/screens/field_mode_screen.dart';
import 'package:staff_attendance_mobile/screens/leave_management_screen.dart';
import 'package:staff_attendance_mobile/screens/profile_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({this.onSelectTab, super.key});

  static const _primaryColor = Color(0xFFFB923C);
  final ValueChanged<int>? onSelectTab;

  void _navigateToTab(BuildContext context, int index) {
    final navigator = Navigator.of(context);
    if (index == 0) {
      onSelectTab?.call(index);
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
      onSelectTab?.call(index);
      navigator.pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(onSelectTab: onSelectTab),
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
