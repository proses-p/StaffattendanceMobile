import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/models/profile_model.dart';
import 'package:staff_attendance_mobile/screens/attendance_history_screen.dart';
import 'package:staff_attendance_mobile/screens/edit_profile_screen.dart';
import 'package:staff_attendance_mobile/screens/login_screen.dart';
import 'package:staff_attendance_mobile/screens/profile_settings_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:staff_attendance_mobile/services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    this.apiService,
    this.authService,
    this.onSelectTab,
    super.key,
  });

  final ApiService? apiService;
  final AuthService? authService;
  final ValueChanged<int>? onSelectTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _primaryColor = Color(0xFFFB923C);

  late final ApiService _apiService = widget.apiService ?? ApiService();
  late final AuthService _authService = widget.authService ?? AuthService();
  StaffProfile? _profile;
  Object? _loadError;
  bool _isLoading = true;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final profile = await _apiService.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _editProfile() async {
    final profile = _profile;
    if (profile == null) return;
    final updatedProfile = await Navigator.of(context).push<StaffProfile>(
      MaterialPageRoute<StaffProfile>(
        builder: (_) =>
            EditProfileScreen(profile: profile, apiService: _apiService),
      ),
    );
    if (updatedProfile != null && mounted) {
      setState(() => _profile = updatedProfile);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfileSettingsScreen(apiService: _apiService),
      ),
    );
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access your attendance account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLoggingOut = true);
    try {
      final serverSessionRevoked = await _authService.logout();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      if (!serverSessionRevoked) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Signed out on this device. The server could not confirm session revocation.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to clear the local session: '
            '${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _navigateToTab(int index) async {
    if (index == 1) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const AttendanceHistoryScreen(),
        ),
      );
    } else if (index != 4) {
      widget.onSelectTab?.call(index);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading && profile == null
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : _loadError != null && profile == null
          ? _buildLoadError()
          : RefreshIndicator(
              color: _primaryColor,
              onRefresh: _loadProfile,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      if (profile != null) ...[
                        _ProfileHeader(profile: profile, onEdit: _editProfile),
                        const SizedBox(height: 22),
                        _ProfileSection(
                          title: 'Personal information',
                          trailing: TextButton.icon(
                            onPressed: _editProfile,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit'),
                          ),
                          children: [
                            _ProfileInfoRow(
                              icon: Icons.person_outline,
                              label: 'Full name',
                              value: _displayValue(profile.name),
                            ),
                            _ProfileInfoRow(
                              icon: Icons.email_outlined,
                              label: 'Email address',
                              value: _displayValue(profile.email),
                            ),
                            _ProfileInfoRow(
                              icon: Icons.phone_outlined,
                              label: 'Phone number',
                              value: _displayValue(profile.phone),
                            ),
                            _ProfileInfoRow(
                              icon: Icons.business_outlined,
                              label: 'Organization',
                              value: _displayValue(profile.organization),
                            ),
                            _ProfileInfoRow(
                              icon: Icons.badge_outlined,
                              label: 'Employee ID',
                              value: _displayValue(profile.employeeId),
                            ),
                            if (profile.createdAt != null)
                              _ProfileInfoRow(
                                icon: Icons.calendar_month_outlined,
                                label: 'Member since',
                                value: _formatDate(profile.createdAt!),
                                isLast: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _ProfileSection(
                          title: 'Account',
                          children: [
                            _ProfileInfoRow(
                              icon: Icons.admin_panel_settings_outlined,
                              label: 'Account type',
                              value: _displayValue(profile.role).toUpperCase(),
                            ),
                            if (profile.isActive != null)
                              _ProfileInfoRow(
                                icon: Icons.verified_user_outlined,
                                label: 'Account status',
                                value: profile.isActive!
                                    ? 'Active'
                                    : 'Inactive',
                                isLast: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _ProfileSection(
                          title: 'Account actions',
                          children: [
                            ListTile(
                              minVerticalPadding: 12,
                              leading: const Icon(
                                Icons.logout_rounded,
                                color: Color(0xFFB91C1C),
                              ),
                              title: const Text(
                                'Sign out',
                                style: TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'End your session on this device.',
                              ),
                              trailing: _isLoggingOut
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFB91C1C),
                                      ),
                                    )
                                  : const Icon(Icons.chevron_right),
                              onTap: _isLoggingOut ? null : _logout,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 4,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _primaryColor,
        unselectedItemColor: Colors.grey,
        onTap: _navigateToTab,
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

  Widget _buildLoadError() {
    final message = _loadError.toString().replaceFirst('Exception: ', '');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 48,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            const Text(
              'Profile unavailable',
              style: TextStyle(
                color: Color(0xFF172033),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _displayValue(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? 'Not provided' : trimmed;
}

String _formatDate(DateTime date) {
  final localDate = date.toLocal();
  return '${localDate.day.toString().padLeft(2, '0')}/'
      '${localDate.month.toString().padLeft(2, '0')}/${localDate.year}';
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.onEdit});

  final StaffProfile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFB923C), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white.withValues(alpha: 0.22),
            child: Text(
              _initials(profile.name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayValue(profile.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _displayValue(profile.email),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFF7ED),
                    fontSize: 13,
                  ),
                ),
                if (profile.organization?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    profile.organization!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (profile.employeeId?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${profile.employeeId}',
                    style: const TextStyle(
                      color: Color(0xFFFFF7ED),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit profile',
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final initials = parts.take(2).map((part) => part[0].toUpperCase()).join();
    return initials.isEmpty ? '?' : initials;
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF64748B), size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
