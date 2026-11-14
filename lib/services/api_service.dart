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
  ApiRequestException(
    this.statusCode,
    String message, {
    this.code,
    this.remainingQuota,
  }) : message = _cleanApiError(message);

  final int statusCode;
  final String message;

  final String? code;
  final int? remainingQuota;
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

  Future<Map<String, dynamic>> fetchDailyWorkStatus() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/daily-work/status'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load daily work reports.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> askStaffAiAssistant(String message) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/ai/staff-assistant'),
      headers: await _getHeaders(),
      body: json.encode({'message': message}),
    );
    final data = _decodeResponse(response);
    await _saveAiQuota(data);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to reach the AI work assistant.'),
        remainingQuota: _quotaValue(data['remaining_quota']),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> draftDailyWorkReport({
    required String roughNotes,
    String? assignedTaskTitle,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/ai/draft-work-report'),
      headers: await _getHeaders(),
      body: json.encode({
        'rough_notes': roughNotes,
        if (assignedTaskTitle?.trim().isNotEmpty == true)
          'assigned_task_title': assignedTaskTitle!.trim(),
      }),
    );
    final data = _decodeResponse(response);
    await _saveAiQuota(data);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to draft the daily work report.'),
        remainingQuota: _quotaValue(data['remaining_quota']),
      );
    }
    return data;
  }

  Future<void> _saveAiQuota(Map<String, dynamic> data) async {
    final remaining = data['remaining_quota'];
    if (remaining is! num) return;
    final preferences = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await preferences.setInt(
      'ai_remaining_quota',
      remaining.toInt().clamp(0, 15).toInt(),
    );
    await preferences.setString('ai_quota_day', today);
    final userId = preferences.getInt('auth_user_id');
    if (userId != null) {
      await preferences.setInt('ai_quota_user_id', userId);
    }
  }

  int? _quotaValue(Object? value) {
    if (value is num) return value.toInt().clamp(0, 15).toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<Map<String, dynamic>> submitDailyWork({
    required String completedPart,
    required String description,
    required String workStatus,
    required List<String> photoPaths,
    int? assignedTaskId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/daily-work/submit'),
    );
    request.headers.addAll(await _getHeaders());
    request.headers.remove('Content-Type');
    request.fields.addAll({
      'completed_part': completedPart,
      'description': description,
      'work_status': workStatus,
      if (assignedTaskId != null) 'assigned_task_id': '$assignedTaskId',
    });
    for (final path in photoPaths) {
      final extension = path.toLowerCase().split('.').last;
      final mime = switch (extension) {
        'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
        'png' => MediaType('image', 'png'),
        'webp' => MediaType('image', 'webp'),
        'heic' || 'heif' => MediaType('image', extension),
        _ => throw ArgumentError.value(path, 'photoPaths'),
      };
      request.files.add(
        await http.MultipartFile.fromPath(
          'photos[]',
          path,
          filename: File(path).uri.pathSegments.last,
          contentType: mime,
        ),
      );
    }

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamedResponse);
    final data = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Daily work submission failed.'),
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
        code: data['code']?.toString(),
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

  Future<Map<String, dynamic>> fetchFieldStatus() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/field/status'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load field visit status.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> startFieldVisit({
    required String clientOrServiceName,
    required String purpose,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/field/start'),
      headers: await _getHeaders(),
      body: json.encode({
        'client_or_service_name': clientOrServiceName,
        'purpose': purpose,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 201) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to start the field visit.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> endFieldVisit({
    int? visitId,
    required double latitude,
    required double longitude,
    String? completionNotes,
    String expenseAmount = '0',
    String? expenseDescription,
    String? receiptPhotoPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/field/end'),
    );
    request.headers.addAll(await _getHeaders());
    request.headers.remove('Content-Type');
    request.fields.addAll({
      if (visitId != null) 'visit_id': visitId.toString(),
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'expense_amount': expenseAmount.trim().isEmpty
          ? '0'
          : expenseAmount.trim(),
      if (completionNotes?.trim().isNotEmpty == true)
        'completion_notes': completionNotes!.trim(),
      if (expenseDescription?.trim().isNotEmpty == true)
        'expense_description': expenseDescription!.trim(),
    });
    if (receiptPhotoPath != null) {
      final extension = receiptPhotoPath.toLowerCase().split('.').last;
      final mime = switch (extension) {
        'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
        'png' => MediaType('image', 'png'),
        'webp' => MediaType('image', 'webp'),
        _ => throw ArgumentError.value(receiptPhotoPath, 'receiptPhotoPath'),
      };
      request.files.add(
        await http.MultipartFile.fromPath(
          'receipt_photo',
          receiptPhotoPath,
          filename: File(receiptPhotoPath).uri.pathSegments.last,
          contentType: mime,
        ),
      );
    }

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamedResponse);
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to complete the field visit.'),
      );
    }
    return data;
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

    throw ApiRequestException(
      response.statusCode,
      _responseMessage(responseData, 'Attendance request failed.'),
      code: responseData['code']?.toString(),
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
      throw Exception(responseData['message'] ?? 'Dashboard request failed.');
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

  Future<Map<String, dynamic>> fetchMyPayslip({String? month}) async {
    final uri = Uri.parse('$baseUrl/my-payslip')
        .replace(queryParameters: month == null ? null : {'month': month});
    final response = await _client.get(uri, headers: await _getHeaders());
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load your payslip.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> submitSalaryAdvanceRequest({
    required double amount,
    required String reason,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/salary-advances'),
      headers: await _getHeaders(),
      body: json.encode({'amount': amount, 'reason': reason}),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 201) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to submit your salary advance request.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> fetchAnnouncements() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/announcements'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load company announcements.'),
      );
    }

    final announcements = data['announcements'];
    return {
      'announcements': announcements is List
          ? announcements
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[],
      'unread_count': data['unread_count'] is num
          ? (data['unread_count'] as num).toInt()
          : 0,
    };
  }

  Future<void> markAnnouncementRead(int announcementId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/announcements/$announcementId/read'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to mark this announcement as read.'),
      );
    }
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
        responseData['message'] ?? 'Attendance history request failed.',
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

    throw Exception(responseData['message'] ?? 'Attendance request failed.');
  }

  Future<Map<String, dynamic>> fetchGroupChat({int? afterId}) async {
    final uri = Uri.parse('$baseUrl/chat/group').replace(
      queryParameters: afterId == null ? null : {'after_id': '$afterId'},
    );
    final response = await _client.get(uri, headers: await _getHeaders());
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load team chat.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> sendGroupChatMessage(String message) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/group'),
      headers: await _getHeaders(),
      body: json.encode({'message': message}),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 201) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to send your message.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> updateGroupChatMessage({
    required int messageId,
    required String message,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/chat/group/$messageId'),
      headers: await _getHeaders(),
      body: json.encode({'message': message}),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to edit this message.'),
      );
    }
    return data;
  }

  Future<void> deleteGroupChatMessage(int messageId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/chat/group/$messageId'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to delete this message.'),
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchPrivateConversations() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/chat/private/conversations'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load private conversations.'),
      );
    }
    final conversations = data['conversations'];
    if (conversations is! List) return const [];
    return conversations
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> fetchPrivateChat(int colleagueId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/chat/private/$colleagueId'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to load this conversation.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> sendPrivateChatMessage({
    required int colleagueId,
    required String message,
    String? quotedMessage,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/private/$colleagueId'),
      headers: await _getHeaders(),
      body: json.encode({
        'message': message,
        if (quotedMessage != null && quotedMessage.isNotEmpty)
          'quoted_message': quotedMessage,
      }),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 201) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to send your private message.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> updatePrivateChatMessage({
    required int messageId,
    required String message,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/chat/private/message/$messageId'),
      headers: await _getHeaders(),
      body: json.encode({'message': message}),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to edit this message.'),
      );
    }
    return data;
  }

  Future<void> deletePrivateChatMessage(int messageId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/chat/private/message/$messageId'),
      headers: await _getHeaders(),
    );
    final data = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        _responseMessage(data, 'Unable to delete this message.'),
      );
    }
  }

  Future<StaffProfile> fetchProfile() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/profile'),
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
      Uri.parse('$baseUrl/profile'),
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

  Future<void> requestPasswordResetCode({required String email}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: json.encode({'email': email.trim()}),
    );
    final responseData = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(responseData, 'Unable to send the reset code.'),
      );
    }
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'email': email.trim(),
        'code': code.trim(),
        'password': password,
        'password_confirmation': passwordConfirmation,
      }),
    );
    final responseData = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(responseData, 'Unable to reset your password.'),
      );
    }
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
      throw Exception('The server returned an invalid response.');
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

    final responseMessage = message != null && message.isNotEmpty
        ? [
            message,
            if (details != null && details.isNotEmpty) details,
          ].join(' ')
        : details != null && details.isNotEmpty
        ? details
        : fallback;
    return _cleanApiError(responseMessage);
  }
}

String _cleanApiError(String value) {
  var message = value.trim();
  message = message.replaceAll(
    RegExp(r'\s*\((?:HTTP\s*)?\d{3}\)', caseSensitive: false),
    '',
  );
  final prefix = RegExp(
    r'^(?:(?:[A-Za-z]*Exception|StateError)\s*:\s*|Error\s+\d{3}\s*:\s*|Error\s*:\s*|Status(?:\s+code)?\s*:\s*\d{3}\s*\|\s*|HTTP\s+\d{3}\s*:\s*|\d{3}\s*:\s*)',
    caseSensitive: false,
  );
  while (prefix.hasMatch(message)) {
    message = message.replaceFirst(prefix, '').trim();
  }
  return message;
}
