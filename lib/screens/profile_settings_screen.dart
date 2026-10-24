import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({this.apiService, super.key});

  final ApiService? apiService;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late final ApiService _apiService = widget.apiService ?? ApiService();
  PackageInfo? _packageInfo;
  bool _packageInfoUnavailable = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _packageInfo = packageInfo);
    } on PlatformException {
      if (mounted) setState(() => _packageInfoUnavailable = true);
    } on MissingPluginException {
      if (mounted) setState(() => _packageInfoUnavailable = true);
    }
  }

  Future<void> _openAppSettings() async {
    final bool opened;
    try {
      opened = await Geolocator.openAppSettings();
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open app settings.')),
      );
      return;
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open app settings.')),
      );
      return;
    }
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open app settings.')),
    );
  }

  Future<void> _openPasswordChange() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangePasswordScreen(apiService: _apiService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packageInfo = _packageInfo;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const _SectionTitle(title: 'Security'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Change password',
                subtitle: 'Verify your current password before updating it.',
                onTap: _openPasswordChange,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Privacy'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.location_on_outlined,
                title: 'Location permission',
                subtitle: 'Location is used to verify attendance check-in and check-out.',
                onTap: _openAppSettings,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'About'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.access_time_rounded,
                title: 'Staff Attendance',
                subtitle: packageInfo == null
                    ? _packageInfoUnavailable
                          ? 'Version information unavailable'
                          : 'Loading version information…'
                    : 'Version ${packageInfo.version} '
                          '(build ${packageInfo.buildNumber})',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Theme selection, notification controls, and support links are not '
              'shown because this app does not currently provide those settings.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({required this.apiService, super.key});

  final ApiService apiService;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _primaryColor = Color(0xFFFB923C);
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSaving = false;
  bool _obscurePasswords = true;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.apiService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
          'Change password',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                const Text(
                  'Choose a strong password of at least 8 characters.',
                  style: TextStyle(color: Color(0xFF64748B), height: 1.45),
                ),
                const SizedBox(height: 22),
                _passwordField(
                  controller: _currentPasswordController,
                  label: 'Current password',
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your current password.'
                      : null,
                ),
                const SizedBox(height: 16),
                _passwordField(
                  controller: _newPasswordController,
                  label: 'New password',
                  validator: (value) {
                    if (value == null || value.length < 8) {
                      return 'Password must be at least 8 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _passwordField(
                  controller: _confirmPasswordController,
                  label: 'Confirm new password',
                  validator: (value) => value != _newPasswordController.text
                      ? 'Passwords do not match.'
                      : null,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _changePassword,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Update password'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: _obscurePasswords,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscurePasswords ? 'Show passwords' : 'Hide passwords',
          onPressed: () =>
              setState(() => _obscurePasswords = !_obscurePasswords),
          icon: Icon(
            _obscurePasswords
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF172033),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 14,
      leading: Icon(icon, color: const Color(0xFFFB923C)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle, style: const TextStyle(height: 1.4)),
      ),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
    );
  }
}
