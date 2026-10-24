import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/custom/check_in_button.dart';
import 'package:staff_attendance_mobile/models/user_status_model.dart';

class AttendanceCard extends StatelessWidget {
  const AttendanceCard({
    super.key,
    required this.status,
    required this.now,
    required this.buttonState,
    required this.onAttendanceAction,
    required this.isSubmitting,
  });

  final UserStatusModel status;
  final DateTime now;
  final String buttonState;
  final VoidCallback onAttendanceAction;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFB923C);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.access_time, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.currentTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      status.currentDate,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CheckInButton(
            buttonState: buttonState,
            isSubmitting: isSubmitting,
            onTap: onAttendanceAction,
          ),
          const SizedBox(height: 15),
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _buildStatusItem(
                  'Worked Hrs',
                  status.workedHoursAt(now),
                ),
              ),
              Expanded(child: _buildStatusItem('Check In', status.checkInTime)),
              Expanded(
                child: _buildStatusItem('Check Out', status.checkOutTime),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
