class AttendanceHistoryRecord {
  const AttendanceHistoryRecord({
    required this.attendanceDate,
    required this.checkInAt,
    required this.checkOutAt,
    required this.checkInTime,
    required this.checkOutTime,
    required this.signInLocation,
    required this.signOutLocation,
  });

  final DateTime? attendanceDate;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final String? checkInTime;
  final String? checkOutTime;
  final String? signInLocation;
  final String? signOutLocation;

  bool get isCheckedOut => checkOutAt != null;

  String get workingHours {
    final start = checkInAt;
    final end = checkOutAt;
    if (start == null || end == null) {
      return end == null ? 'In progress' : '—';
    }

    final elapsed = end.difference(start);
    if (elapsed.isNegative) {
      return '—';
    }

    final minutes = elapsed.inMinutes;
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  factory AttendanceHistoryRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceHistoryRecord(
      attendanceDate: _parseDate(json['attendance_date']),
      checkInAt: _parseDate(json['check_in_at']),
      checkOutAt: _parseDate(json['check_out_at']),
      checkInTime: _nonEmptyString(json['check_in_time']),
      checkOutTime: _nonEmptyString(json['check_out_time']),
      signInLocation: _nonEmptyString(json['sign_in_location']),
      signOutLocation: _nonEmptyString(json['sign_out_location']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static String? _nonEmptyString(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}

class AttendanceHistoryPage {
  AttendanceHistoryPage({
    required List<AttendanceHistoryRecord> records,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  }) : records = List.unmodifiable(records);

  final List<AttendanceHistoryRecord> records;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;

  bool get hasPreviousPage => currentPage > 1;
  bool get hasNextPage => currentPage < lastPage;

  factory AttendanceHistoryPage.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'];
    if (rawRecords is! List) {
      throw const FormatException('Attendance history records are missing.');
    }

    final records =
        rawRecords
            .whereType<Map>()
            .map(
              (record) => AttendanceHistoryRecord.fromJson(
                Map<String, dynamic>.from(record),
              ),
            )
            .toList()
          ..sort((a, b) {
            final aDate = a.attendanceDate;
            final bDate = b.attendanceDate;
            if (aDate == null) return bDate == null ? 0 : 1;
            if (bDate == null) return -1;
            return bDate.compareTo(aDate);
          });

    return AttendanceHistoryPage(
      records: records,
      currentPage: _integer(json['current_page'], fallback: 1),
      lastPage: _integer(json['last_page'], fallback: 1),
      total: _integer(json['total'], fallback: records.length),
      perPage: _integer(json['per_page'], fallback: 6),
    );
  }

  static int _integer(dynamic value, {required int fallback}) {
    if (value is int && value >= 0) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }
}
