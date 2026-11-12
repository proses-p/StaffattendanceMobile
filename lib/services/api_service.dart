import 'dart:convert';
import 'dart:async';
import 'dart:io' show File, SocketException;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/config/api_config.dart';
import 'package:staff_attendance_mobile/models/attendance_history_model.dart';
import 'package:staff_attendance_mobile/models/leave_request_model.dart';
import 'package:staff_attendance_mobile/models/profile_model.dart';
import 'package:staff_attendance_mobile/models/user_status_model.dart';
import 'package:staff_attendance_mobile/services/device_security_service.dart';
import 'package:staff_attendance_mobile/services/trusted_clock.dart';

class ApiRequestException implements Exception {
  const ApiRequestException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null || token.isEmpty) {
      throw Exception('Authentication token is missing. Please sign in again.');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': ['Bearer', token.trim()].join(' '),
    };
  }

  Future<Map<String, dynamic>> fetchDeviceStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/devices/status'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(data, 'Unable to check device approval.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> syncBatch(
    List<Map<String, dynamic>> events,
  ) async {
    final headers = await _getHeaders();
    final challengeResponse = await http
        .post(
          Uri.parse('$baseUrl/sync/challenge'),
          headers: headers,
          body: json.encode({}),
        )
        .timeout(const Duration(seconds: 15));
    final challenge = _decodeResponse(challengeResponse);
    if (challengeResponse.statusCode != 201) {
      throw ApiRequestException(
        challengeResponse.statusCode,
        _responseMessage(challenge, 'Unable to authorize field event sync.'),
      );
    }

    final challengeId = challenge['challenge_id'];
    final deviceId = challenge['device_id'];
    final nonce = challenge['nonce'];
    final userId = challenge['user_id'];
    if (challengeId is! int ||
        deviceId is! int ||
        nonce is! String ||
        userId is! int) {
      throw Exception('The field sync challenge is incomplete.');
    }
    final eventsJson = json.encode(events);
    final payloadHash = sha256.convert(utf8.encode(eventsJson)).toString();
    final signature = await DeviceSecurityService().sign(
      'field-sync-v1\n$challengeId\n$nonce\n$userId\n$deviceId\n$payloadHash',
    );
    final response = await http
        .post(
          Uri.parse('$baseUrl/sync/batch'),
          headers: headers,
          body: json.encode({
            'events': events,
            'events_json': eventsJson,
            'challenge_id': challengeId,
            'device_id': deviceId,
            'payload_hash': payloadHash,
            'signature': signature,
          }),
        )
        .timeout(const Duration(seconds: 25));
    final data = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Field event sync failed.'),
      );
    }
    return data;
  }

  Future<void> recoverSyncSigningKey(String currentPassword) async {
    final security = DeviceSecurityService();
    final deviceUuid = await security.deviceUuid();
    final publicKey = await security.generateNewKeyPairString();
    final response = await http
        .post(
          Uri.parse('$baseUrl/device/sync-recovered-key'),
          headers: await _getHeaders(),
          body: json.encode({
            'device_uuid': deviceUuid,
            'new_public_key': publicKey,
            'current_password': currentPassword,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to recover the device signing key.'),
      );
    }
  }

  Future<void> fetchTrustedTime() async {
    final configured = Uri.parse(baseUrl);
    final timeUri = configured.replace(
      path: configured.path.replaceFirst(RegExp(r'/v1$'), '/time'),
    );
    final response = await http
        .get(timeUri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to synchronize the trusted clock.'),
      );
    }
    final value = data['now'];
    if (value is! String || DateTime.tryParse(value) == null) {
      throw Exception('The trusted time response is incomplete.');
    }
    await TrustedClock.instance.anchor(DateTime.parse(value));
  }

    // Method ya kuvuta notifications ambazo hazijasomwa kutoka Laravel
    Future<List<dynamic>> fetchUnreadNotifications() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/notifications/unread'),
          headers: await _getHeaders(),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      return data['notifications'] as List<dynamic>? ?? [];
    }
    return [];
  }



  Future<Map<String, dynamic>> fetchFieldStats({
    bool allowCached = true,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final userId = preferences.getInt('auth_user_id');
    if (userId == null) {
      throw StateError('The signed-in user could not be identified.');
    }
    final cacheKey = 'field_dashboard_stats_$userId';
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/dashboard/employee'),
        headers: await _getHeaders(),
      );
      final data = _decodeResponse(response);
      if (response.statusCode != 200) {
        throw ApiRequestException(
          response.statusCode,
          _responseMessage(data, 'Unable to load field statistics.'),
        );
      }
      await preferences.setString(cacheKey, json.encode(data));
      return data;
    } on SocketException {
      return _cachedFieldStats(preferences, cacheKey, allowCached);
    } on http.ClientException {
      return _cachedFieldStats(preferences, cacheKey, allowCached);
    } on TimeoutException {
      return _cachedFieldStats(preferences, cacheKey, allowCached);
    } on ApiRequestException catch (error) {
      if (error.statusCode < 500) rethrow;
      return _cachedFieldStats(preferences, cacheKey, allowCached);
    }
  }

  Map<String, dynamic> _cachedFieldStats(
    SharedPreferences preferences,
    String cacheKey,
    bool allowCached,
  ) {
    final cached = preferences.getString(cacheKey);
    if (!allowCached || cached == null) {
      throw Exception('Field statistics are unavailable.');
    }
    return Map<String, dynamic>.from(json.decode(cached) as Map);
  }

  Future<Map<String, dynamic>> fetchAdminFieldStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/dashboard'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load admin field statistics.'),
      );
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> fetchOnField() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/field/on-field'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load staff currently in the field.'),
      );
    }
    final rows = data['on_field'];
    if (rows is! List) throw Exception('The on-field response is incomplete.');
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> fetchActiveField() async {
    final response = await http.get(
      Uri.parse('$baseUrl/field/active'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to restore the active field session.'),
      );
    }
    final assignment = data['assignment'];
    return assignment is Map ? Map<String, dynamic>.from(assignment) : null;
  }

  Future<List<Map<String, dynamic>>> fetchMyFieldExpenses() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/field/expenses'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load expenses.'),
      );
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('The expense response is incomplete.');
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> submitFieldExpense({
    required int fieldAssignmentId,
    required String category,
    required String amount,
    required String currency,
    required String clientUuid,
    required bool isOffline,
    String? description,
    String? receiptPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/field/expenses'),
    );
    request.headers.addAll(await _getHeaders());
    request.headers.remove('Content-Type');
    request.fields.addAll({
      'field_assignment_id': fieldAssignmentId.toString(),
      'category': category,
      'amount': amount,
      'currency': currency,
      'client_uuid': clientUuid,
      'is_offline': isOffline ? '1' : '0',
      if (description?.trim().isNotEmpty == true)
        'description': description!.trim(),
    });
    if (receiptPath != null) {
      final file = File(receiptPath);
      final extension = receiptPath.toLowerCase().split('.').last;
      final mime = switch (extension) {
        'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
        'png' => MediaType('image', 'png'),
        'webp' => MediaType('image', 'webp'),
        _ => throw ArgumentError.value(receiptPath, 'receiptPath'),
      };
      request.files.add(
        await http.MultipartFile.fromPath(
          'receipt',
          receiptPath,
          filename: file.uri.pathSegments.last,
          contentType: mime,
        ),
      );
    }

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamedResponse);
    final data = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Expense submission failed.'),
      );
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> fetchFlaggedAssignments() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/field/flagged'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load flagged field assignments.'),
      );
    }
    final rows = data['data'];
    if (rows is! List) {
      throw Exception('The flagged assignment response is incomplete.');
    }
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> reviewFieldAssignment(int assignmentId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/field/$assignmentId/review'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to review this assignment.'),
      );
    }
  }

  Future<Map<String, dynamic>> enrollCurrentDevice({
    bool replaceExistingKey = false,
  }) async {
    final security = DeviceSecurityService();
    if (!await security.canSign()) {
      throw Exception(
        'Strong fingerprint or face biometrics are not currently available. '
        'Set up strong biometrics in Android Settings and try again. '
        'If this device does not support them, contact your administrator.',
      );
    }

    final deviceUuid = await security.deviceUuid();
    final headers = await _getHeaders();
    final challengeResponse = await http.post(
      Uri.parse('$baseUrl/devices/enrollment-challenge'),
      headers: headers,
      body: json.encode({}),
    );
    final challenge = _decodeResponse(challengeResponse);
    if (challengeResponse.statusCode != 201) {
      throw Exception(
        _responseMessage(challenge, 'Unable to start device registration.'),
      );
    }

    final publicKey = await security.createKey(
      replaceExisting: replaceExistingKey,
    );
    final challengeId = challenge['challenge_id'];
    final nonce = challenge['nonce'];
    final userId = challenge['user_id'];
    if (challengeId is! int || nonce is! String || userId is! int) {
      throw Exception('The device registration challenge is incomplete.');
    }
    final signature = await security.sign(
      'staff-device-enroll-v1\n$challengeId\n$nonce\n$userId',
    );
    final response = await http.post(
      Uri.parse('$baseUrl/devices/enroll'),
      headers: headers,
      body: json.encode({
        'device_name': 'Android device',
        'platform': 'android',
        'device_uuid': deviceUuid,
        'public_key': publicKey,
        'challenge_id': challengeId,
        'signature': signature,
      }),
    );
    final responseData = _decodeResponse(response);
    if (response.statusCode != 201) {
      throw Exception(
        _responseMessage(responseData, 'Unable to register this device.'),
      );
    }
    return responseData;
  }

  Future<Map<String, dynamic>> submitAttendance({
    required String endpoint,
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime locationTimestamp,
  }) async {
    final headers = await _getHeaders();
    final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/'), '');
    final operation = normalizedEndpoint.endsWith('check-in')
        ? 'check-in'
        : 'check-out';
    final challengeResponse = await http.post(
      Uri.parse('$baseUrl/attendance/challenges'),
      headers: headers,
      body: json.encode({'operation': operation}),
    );
    final challenge = _decodeResponse(challengeResponse);
    if (challengeResponse.statusCode != 201) {
      throw Exception(
        _responseMessage(
          challenge,
          'Unable to authorize this attendance action.',
        ),
      );
    }

    final challengeId = challenge['challenge_id'];
    final deviceId = challenge['device_id'];
    final nonce = challenge['nonce'];
    final userId = challenge['user_id'];
    if (challengeId is! int ||
        deviceId is! int ||
        nonce is! String ||
        userId is! int) {
      throw Exception('The attendance challenge is incomplete.');
    }
    final latitudeText = latitude.toStringAsFixed(7);
    final longitudeText = longitude.toStringAsFixed(7);
    final accuracyText = accuracy.toStringAsFixed(2);
    final timestampText = _formatUtcTimestamp(locationTimestamp);
    final canonicalPayload = [
      'attendance-v1',
      '$challengeId',
      nonce,
      '$userId',
      '$deviceId',
      operation,
      latitudeText,
      longitudeText,
      accuracyText,
      timestampText,
    ].join('\n');
    final signature = await DeviceSecurityService().sign(canonicalPayload);
    final response = await http.post(
      Uri.parse('$baseUrl/$normalizedEndpoint'),
      headers: headers,
      body: json.encode({
        'latitude': latitudeText,
        'longitude': longitudeText,
        'accuracy': accuracyText,
        'challenge_id': challengeId,
        'device_id': deviceId,
        'location_timestamp': timestampText,
        'signature': signature,
      }),
    );
    final responseData = _decodeResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return responseData;
    }

    throw Exception(
      responseData['message'] ??
          'Attendance request failed (${response.statusCode}).',
    );
  }

  String _formatUtcTimestamp(DateTime timestamp) {
    final value = timestamp.toUtc();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    String threeDigits(int number) => number.toString().padLeft(3, '0');

    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}'
        'T${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}'
        '.${threeDigits(value.millisecond)}Z';
  }

  Future<UserStatusModel> fetchDashboardData() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/dashboard'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      final responseData = _decodeResponse(response);
      throw Exception(
        responseData['message'] ??
            'Dashboard request failed (${response.statusCode}).',
      );
    }

    final responseData = _decodeResponse(response);
    final payload = _asJsonMap(responseData['data']) ?? responseData;
    final attendance = _asJsonMap(payload['attendance']);
    final values = {...payload, ...?attendance};
    final user = _asJsonMap(payload['user']);

    return UserStatusModel.fromJson({
      ...values,
      'user_name': values['user_name'] ?? user?['name'],
      'current_date': values['current_date'] ?? values['date'],
      'worked_hours': values['worked_hours'] ?? values['work_duration'],
      'check_in_time': values['check_in_time'] ?? values['arrival_time'],
    });
  }

  Future<AttendanceHistoryPage> fetchAttendanceHistory({
    required int page,
  }) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/history?page=$page'),
      headers: headers,
    );
    final responseData = _decodeResponse(response);

    if (response.statusCode != 200) {
      throw Exception(
        responseData['message'] ??
            'Attendance history request failed (${response.statusCode}).',
      );
    }

    final payload = _asJsonMap(responseData['data']);
    if (payload == null) {
      throw Exception('The attendance history response is incomplete.');
    }

    return AttendanceHistoryPage.fromJson(payload);
  }

  Future<List<LeaveRequest>> fetchLeaveRequests() async {
    final response = await http.get(
      Uri.parse('$baseUrl/leave-requests'),
      headers: await _getHeaders(),
    );
    final responseData = _decodeResponse(response);

    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(responseData, 'Unable to load your leave requests.'),
      );
    }

    final requests = responseData['leave_requests'];
    if (requests is! List) {
      throw Exception('The leave request response is incomplete.');
    }
    return requests
        .map((request) {
          final data = _asJsonMap(request);
          if (data == null) {
            throw Exception('A leave request in the response is invalid.');
          }
          return LeaveRequest.fromJson(data);
        })
        .toList(growable: false);
  }

  Future<LeaveRequest> submitLeaveRequest({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    String dateOnly(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    final response = await http.post(
      Uri.parse('$baseUrl/leave-requests'),
      headers: await _getHeaders(),
      body: json.encode({
        'leave_type': leaveType,
        'start_date': dateOnly(startDate),
        'end_date': dateOnly(endDate),
        'reason': reason.trim(),
      }),
    );
    final responseData = _decodeResponse(response);

    if (response.statusCode != 201) {
      throw Exception(
        _responseMessage(responseData, 'Unable to submit your leave request.'),
      );
    }

    final request = _asJsonMap(responseData['leave_request']);
    if (request == null) {
      throw Exception('The saved leave request response is incomplete.');
    }
    return LeaveRequest.fromJson(request);
  }

  Future<Map<String, dynamic>> checkInOrOut(String type) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/toggle'),
      headers: headers,
      body: json.encode({'type': type}),
    );
    final responseData = _decodeResponse(response);

    if (response.statusCode == 200) {
      return responseData;
    }

    throw Exception(
      responseData['message'] ??
          'Attendance request failed (${response.statusCode}).',
    );
  }

  Future<StaffProfile> fetchProfile() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/user'),
      headers: headers,
    );
    final responseData = _decodeResponse(response);

    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(responseData, 'Unable to load your profile.'),
      );
    }

    final user = _asJsonMap(responseData['user']);
    if (user == null) {
      throw Exception('The profile response is incomplete.');
    }
    return StaffProfile.fromJson(user);
  }

  Future<StaffProfile> updateProfile({
    required String name,
    required String? phone,
  }) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/user'),
      headers: headers,
      body: json.encode({'name': name, 'phone': phone}),
    );
    final responseData = _decodeResponse(response);

    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(responseData, 'Unable to save your profile.'),
      );
    }

    final user = _asJsonMap(responseData['user']);
    if (user == null) {
      throw Exception('The updated profile response is incomplete.');
    }
    return StaffProfile.fromJson(user);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/user/password'),
      headers: headers,
      body: json.encode({
        'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': newPassword,
      }),
    );
    final responseData = _decodeResponse(response);

    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(responseData, 'Unable to change your password.'),
      );
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    unawaited(
      TrustedClock.instance.observeDateHeader(response.headers['date']),
    );
    final dynamic decoded;
    try {
      decoded = json.decode(response.body);
    } on FormatException {
      throw Exception(
        'The server returned an invalid response (${response.statusCode}).',
      );
    }

    final data = _asJsonMap(decoded);
    if (data == null) {
      throw Exception('The server response was not a JSON object.');
    }

    return data;
  }

  Map<String, dynamic>? _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String _responseMessage(Map<String, dynamic> responseData, String fallback) {
    final message = responseData['message']?.toString();
    final errors = _asJsonMap(responseData['errors']);
    final details = errors?.values
        .expand((value) => value is List ? value : [value])
        .where((value) => value != null)
        .map((value) => value.toString())
        .join(' ');

    if (message != null &&
        message.isNotEmpty &&
        details != null &&
        details.isNotEmpty) {
      return '$message $details';
    }
    if (message != null && message.isNotEmpty) {
      return message;
    }
    if (details != null && details.isNotEmpty) {
      return details;
    }
    return fallback;
  }
}
