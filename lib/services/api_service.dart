import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/models/attendance_history_model.dart';
import 'package:staff_attendance_mobile/models/profile_model.dart';
import 'package:staff_attendance_mobile/models/user_status_model.dart';
import 'package:staff_attendance_mobile/services/auth_service.dart';

class ApiService {
  static const String baseUrl = AuthService.baseUrl;

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

  Future<Map<String, dynamic>> submitAttendance({
    required String endpoint,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String token,
  }) async {
    final headers = await _getHeaders();
    final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/'), '');
    final response = await http.post(
      Uri.parse('$baseUrl/$normalizedEndpoint'),
      headers: headers,
      body: json.encode({
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
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

    if (message != null && message.isNotEmpty && details != null && details.isNotEmpty) {
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
