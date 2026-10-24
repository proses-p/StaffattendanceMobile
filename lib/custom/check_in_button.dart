import 'package:flutter/material.dart';

class CheckInButton extends StatelessWidget {
  const CheckInButton({
    super.key,
    required this.onTap,
    required this.buttonState,
    this.isSubmitting = false,
  });

  final VoidCallback? onTap;
  final String buttonState;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final isCompleted = buttonState == 'COMPLETED';
    final isCheckOut = buttonState == 'CHECK_OUT';
    final foregroundColor = isCheckOut
        ? const Color(0xFFDC2626)
        : const Color(0xFFEA7A19);

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: isCompleted || isSubmitting ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.82),
          disabledForegroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isSubmitting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isCompleted
                        ? Icons.check_circle_outline
                        : isCheckOut
                        ? Icons.logout
                        : Icons.login,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isCompleted
                        ? 'Completed'
                        : isCheckOut
                        ? 'Check Out'
                        : 'Check In',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
