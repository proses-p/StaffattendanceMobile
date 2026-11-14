import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:staff_attendance_mobile/screens/notification_service.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:staff_attendance_mobile/services/app_theme_manager.dart';
import 'package:staff_attendance_mobile/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({this.apiService, super.key});

  final ApiService? apiService;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late final ApiService _apiService = widget.apiService ?? ApiService();
  final TextEditingController _recoveryPasswordController =
      TextEditingController();
  PackageInfo? _packageInfo;
  bool _packageInfoUnavailable = false;
  bool _isRecoveringKey = false;
  bool _dailyRemindersEnabled = true;
  bool _adminUpdatesEnabled = true;
  bool _isLoadingNotificationSettings = true;
  String? _keyRecoveryError;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dailyRemindersEnabled =
          preferences.getBool('daily_attendance_reminders_enabled') ?? true;
      _adminUpdatesEnabled =
          preferences.getBool('admin_updates_enabled') ?? true;
      _isLoadingNotificationSettings = false;
    });
  }

  Future<void> _setDailyReminders(bool enabled) async {
    setState(() => _dailyRemindersEnabled = enabled);
    try {
      await NotificationService().setDailyRemindersEnabled(enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Attendance reminders enabled.'
                : 'Attendance reminders disabled.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _dailyRemindersEnabled = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update reminders: $error')),
      );
    }
  }

  Future<void> _setAdminUpdates(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('admin_updates_enabled', enabled);
    if (mounted) setState(() => _adminUpdatesEnabled = enabled);
  }

  Future<void> _contactSupport() async {
    const email = 'support@wadudu.co.tz';
    const emailUri =
        'mailto:support@wadudu.co.tz'
        '?subject=Staff%20Attendance%20App%20Support';
    try {
      if (await canLaunchUrl(Uri.parse(emailUri)) &&
          await launchUrl(
            Uri.parse(emailUri),
            mode: LaunchMode.externalApplication,
          )) {
        return;
      }
    } catch (_) {
      // Copy the support address when no email application can be opened.
    }

    await Clipboard.setData(const ClipboardData(text: email));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support email copied to clipboard.')),
    );
  }

  Future<void> _openWhatsAppSupport() async {
    const whatsappUri =
        'https://wa.me/?text='
        'Hello%2C%20I%20need%20support%20with%20the%20Staff%20Attendance%20app.';
    try {
      if (await canLaunchUrl(Uri.parse(whatsappUri)) &&
          await launchUrl(
            Uri.parse(whatsappUri),
            mode: LaunchMode.externalApplication,
          )) {
        return;
      }
    } catch (_) {
      // Show the available support contact if WhatsApp cannot be opened.
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contact support',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Email HR / Admin Support: support@wadudu.co.tz'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: 'support@wadudu.co.tz'),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy support email'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickGuide() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick user guide',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              const Text(
                'GPS accuracy: Check in and out near your work location. '
                'The reported GPS accuracy must be 30 metres or better; move '
                'to an open area if accuracy is lower.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Screen lock and biometrics: Set up a device screen lock '
                '(PIN, pattern, password, fingerprint, or face unlock). '
                'Attendance signing requires device security to be enabled.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Daily Work Submissions: Submit your completed work and at '
                'least one photo each day. Admin feedback may ask you to '
                'revise and resubmit a report.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recoveryPasswordController.dispose();
    super.dispose();
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

  Future<void> _recoverSigningKey() async {
    if (_isRecoveringKey || _recoveryPasswordController.text.isEmpty) return;
    setState(() {
      _isRecoveringKey = true;
      _keyRecoveryError = null;
    });
    try {
      await SyncService.instance.recoverSigningKeyAndFlush(
        _recoveryPasswordController.text,
        apiService: _apiService,
      );
      if (!mounted) return;
      _recoveryPasswordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device signing key recovered.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _keyRecoveryError = error.toString().replaceFirst(
          RegExp(r'^(Exception|StateError): '),
          '',
        );
      });
    } finally {
      if (mounted) setState(() => _isRecoveringKey = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packageInfo = _packageInfo;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
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
              _SettingsTile(
                icon: Icons.fingerprint,
                title: 'Device Security',
                subtitle:
                    'View device registration and administrator approval.',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        DeviceSecurityScreen(apiService: _apiService),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recover Device Signing Key',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Enter your current account password to restore secure attendance and field sync.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _recoveryPasswordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _recoverSigningKey(),
                      decoration: const InputDecoration(
                        labelText: 'Current account password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_keyRecoveryError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _keyRecoveryError!,
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            _isRecoveringKey ||
                                _recoveryPasswordController.text.isEmpty
                            ? null
                            : _recoverSigningKey,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFB923C),
                          foregroundColor: Colors.white,
                        ),
                        child: _isRecoveringKey
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Recover key'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Appearance / Theme'),
          _SettingsCard(
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: AppThemeManager.instance.themeMode,
                builder: (context, themeMode, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose how Staff Attendance looks on this device.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (mode, label, icon) in [
                            (
                              ThemeMode.light,
                              'Light',
                              Icons.light_mode_outlined,
                            ),
                            (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                            (
                              ThemeMode.system,
                              'System Default',
                              Icons.settings_brightness_outlined,
                            ),
                          ])
                            ChoiceChip(
                              avatar: Icon(icon, size: 18),
                              label: Text(label),
                              selected: themeMode == mode,
                              onSelected: (_) =>
                                  AppThemeManager.instance.setThemeMode(mode),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Notifications'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(
                  Icons.access_alarm_outlined,
                  color: Color(0xFFFB923C),
                ),
                title: const Text('Daily Check-In & Check-Out Reminders'),
                subtitle: const Text('Receive scheduled attendance reminders.'),
                value: _dailyRemindersEnabled,
                onChanged: _isLoadingNotificationSettings
                    ? null
                    : _setDailyReminders,
              ),
              SwitchListTile(
                secondary: const Icon(
                  Icons.campaign_outlined,
                  color: Color(0xFFFB923C),
                ),
                title: const Text('Admin Updates'),
                subtitle: const Text(
                  'Show local alerts for leave and daily work updates.',
                ),
                value: _adminUpdatesEnabled,
                onChanged: _isLoadingNotificationSettings
                    ? null
                    : _setAdminUpdates,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Help & Support'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.email_outlined,
                title: 'Contact HR / Admin Support',
                subtitle: 'Email support@wadudu.co.tz',
                onTap: _contactSupport,
              ),
              _SettingsTile(
                icon: Icons.chat_outlined,
                title: 'WhatsApp / Phone Support',
                subtitle: 'Open WhatsApp or view available support contact.',
                onTap: _openWhatsAppSupport,
              ),
              _SettingsTile(
                icon: Icons.menu_book_outlined,
                title: 'Quick User Guide / FAQ',
                subtitle: 'GPS accuracy, device security, and work reports.',
                onTap: _showQuickGuide,
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
        ],
      ),
    );
  }
}

class DeviceSecurityScreen extends StatefulWidget {
  const DeviceSecurityScreen({required this.apiService, super.key});

  final ApiService apiService;

  @override
  State<DeviceSecurityScreen> createState() => _DeviceSecurityScreenState();
}

class _DeviceSecurityScreenState extends State<DeviceSecurityScreen> {
  Map<String, dynamic>? _deviceStatus;
  Object? _loadError;
  bool _isLoading = true;
  bool _isRegistering = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceStatus();
  }

  Future<void> _loadDeviceStatus() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final status = await widget.apiService.fetchDeviceStatus();
      if (!mounted) return;
      setState(() {
        _deviceStatus = status;
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

  Future<void> _registerDevice() async {
    if (_isRegistering) return;
    final status = _deviceStatus?['status']?.toString();
    if (status != 'not_registered' && status != 'revoked') return;

    setState(() => _isRegistering = true);
    try {
      final response = await widget.apiService.enrollCurrentDevice(
        replaceExistingKey: status == 'revoked',
      );
      final device = response['device'];
      if (mounted && device is Map) {
        setState(() => _deviceStatus = {'status': device['status']});
      }
      await _loadDeviceStatus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_displayError(error)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  String _displayError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(Exception|StateError): '), '');

  @override
  Widget build(BuildContext context) {
    final status = _deviceStatus?['status']?.toString();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Device Security',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh device status',
            onPressed: _isLoading ? null : _loadDeviceStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDeviceStatus,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (_isLoading && _deviceStatus == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_loadError != null && _deviceStatus == null)
                  _buildStatusCard(
                    icon: Icons.error_outline,
                    title: 'Unable to load device status',
                    description:
                        '${_displayError(_loadError!)} Refresh to try again.',
                    color: const Color(0xFFFFF1F2),
                    borderColor: const Color(0xFFFECDD3),
                  )
                else
                  _buildStatusCard(
                    icon: _statusIcon(status),
                    title: _statusTitle(status),
                    description: _statusDescription(status),
                    color: _statusColor(status),
                    borderColor: _statusBorderColor(status),
                  ),
                if (_loadError != null && _deviceStatus != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Could not refresh device status: '
                    '${_displayError(_loadError!)}',
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      height: 1.4,
                    ),
                  ),
                ],
                if (status == 'not_registered' || status == 'revoked') ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isRegistering ? null : _registerDevice,
                    icon: _isRegistering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fingerprint),
                    label: Text(
                      _isRegistering
                          ? 'Registering…'
                          : status == 'revoked'
                          ? 'Request replacement device'
                          : 'Register Device',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF172033)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(height: 1.45)
                      .apply(bodyColor: Color(0xFF475569)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String? status) => switch (status) {
    'active' => Icons.verified_user_outlined,
    'pending' => Icons.hourglass_top_rounded,
    'revoked' => Icons.gpp_bad_outlined,
    _ => Icons.phonelink_lock_outlined,
  };

  String _statusTitle(String? status) => switch (status) {
    'active' => 'Approved and ready for attendance',
    'pending' => 'Awaiting administrator approval',
    'revoked' => 'Device access revoked',
    'not_registered' => 'Device not registered',
    _ => 'Device status unavailable',
  };

  String _statusDescription(String? status) => switch (status) {
    'active' =>
      'This device is approved and can securely sign attendance actions.',
    'pending' => 'Your device is registered and awaiting administrator approval. Wait for approval or contact your administrator; do not register this device again.',
    'revoked' => 'This device cannot record attendance. Contact your administrator; if a replacement is needed, request a new registration here. Approval is required before attendance is enabled.',
    'not_registered' => 'Register this Android device and wait for administrator approval before checking in or out.',
    _ => 'Refresh to check the registration status. Attendance authorization is confirmed by the server.',
  };

  Color _statusColor(String? status) => switch (status) {
    'active' => const Color(0xFFF0FDF4),
    'pending' => const Color(0xFFFFF7ED),
    'revoked' => const Color(0xFFFFF1F2),
    _ => const Color(0xFFF1F5F9),
  };

  Color _statusBorderColor(String? status) => switch (status) {
    'active' => const Color(0xFFBBF7D0),
    'pending' => const Color(0xFFFED7AA),
    'revoked' => const Color(0xFFFECDD3),
    _ => const Color(0xFFE2E8F0),
  };
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 14,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          style: TextStyle(
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      trailing: onTap == null
          ? null
          : Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
    );
  }
}
