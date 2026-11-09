import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/services/auth_service.dart';

import 'login_screen.dart';

class StaffRegistrationScreen extends StatefulWidget {
  final String token;
  final String email;

  const StaffRegistrationScreen({
    super.key,
    required this.token,
    required this.email,
  });

  @override
  State<StaffRegistrationScreen> createState() =>
      _StaffRegistrationScreenState();
}

class _StaffRegistrationScreenState extends State<StaffRegistrationScreen> {
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _orange = Color(0xFFFB923C);
  static const _border = Color(0xFFE2E8F0);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _errorMessage;

  bool get _hasValidToken =>
      RegExp(r'^[A-Za-z0-9]{64}$').hasMatch(widget.token);

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_hasValidToken || !_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.registerStaff(
        token: widget.token,
        name: _nameController.text,
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
      );

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: _muted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _orange, width: 1.5),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Staff registration'),
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: _ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _hasValidToken
                  ? _registrationForm()
                  : _invalidInvitation(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _registrationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: _orange,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _orange.withOpacity(0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Complete your registration',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink,
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Set up your staff account to access your attendance workspace.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: Color(0xFFC2410C),
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You have been invited to join Staff Attendance.',
                          style: TextStyle(
                            color: Color(0xFF9A3412),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.email.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _fieldLabel('Invited email'),
                  TextFormField(
                    initialValue: widget.email,
                    readOnly: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _inputDecoration(
                      hint: '',
                      icon: Icons.email_outlined,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _fieldLabel('Full name'),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: _inputDecoration(
                    hint: 'Enter your full name',
                    icon: Icons.person_outline_rounded,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your full name.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                _fieldLabel('Password'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: _inputDecoration(
                    hint: 'Create a password',
                    icon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) {
                      return 'Password must be at least 8 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                _fieldLabel('Confirm password'),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmation,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: _inputDecoration(
                    hint: 'Enter your password again',
                    icon: Icons.lock_reset_outlined,
                    suffixIcon: IconButton(
                      tooltip: _obscureConfirmation
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () => setState(
                        () => _obscureConfirmation = !_obscureConfirmation,
                      ),
                      icon: Icon(
                        _obscureConfirmation
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      disabledBackgroundColor: const Color(0xFFFDBA74),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Create account',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _invalidInvitation() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.link_off_rounded,
            color: Color(0xFFDC2626),
            size: 44,
          ),
          const SizedBox(height: 16),
          const Text(
            'Invalid invitation link',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This registration link is not valid. Contact the person who invited you for a new link.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Return to sign in'),
          ),
        ],
      ),
    );
  }
}
