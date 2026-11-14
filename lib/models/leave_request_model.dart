class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    required this.submittedAt,
    this.decisionNote,
    this.leaveDays,
  });

  final int id;
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status;
  final DateTime? submittedAt;
  final String? decisionNote;
  final int? leaveDays;

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) {
      throw const FormatException('Leave request ID is missing.');
    }

    return LeaveRequest(
      id: id,
      leaveType: _requiredString(json['leave_type'], 'leave type'),
      startDate: _requiredDate(json['start_date'], 'start date'),
      endDate: _requiredDate(json['end_date'], 'end date'),
      reason: json['reason']?.toString() ?? '',
      status: _requiredString(json['status'], 'status'),
      decisionNote: json['decision_note']?.toString(),
      leaveDays: json['leave_days'] is int ? json['leave_days'] as int : null,
      submittedAt: _optionalDate(json['submitted_at']),
    );
  }

  static String _requiredString(dynamic value, String label) {
    if (value is! String || value.isEmpty) {
      throw FormatException('Leave request $label is missing.');
    }
    return value;
  }

  static DateTime _requiredDate(dynamic value, String label) {
    final date = _optionalDate(value);
    if (date == null) {
      throw FormatException('Leave request $label is invalid.');
    }
    return date;
  }

  static DateTime? _optionalDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
