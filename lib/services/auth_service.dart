import 'dart:async';
import 'dart:convert';
import 'dart:io';

// import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/config/api_config.dart';
import 'package:staff_attendance_mobile/services/notification_storage.dart';

class AuthService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },

      body: jsonEncode({'email': email, 'password': password}),
    );

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception('The server returned an invalid response.');
    }
    if (decoded is! Map) {
      throw Exception('The server response was not a JSON object.');
    }
    final data = Map<String, dynamic>.from(decoded);

    if (response.statusCode != 200) {
      if (response.statusCode == 401) {
        throw Exception('Email or password is incorrect.');
      }
      throw Exception(data['message']?.toString() ?? 'Unable to sign in.');
    }

    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw Exception('The server did not return an authentication token.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setInt(
      'last_active_at',
      DateTime.now().millisecondsSinceEpoch,
    );
    final user = data['user'];
    if (user is Map && user['id'] != null) {
      await prefs.setInt('auth_user_id', int.parse(user['id'].toString()));
      final role = user['role']?.toString();
      if (role != null) await prefs.setString('auth_role', role);
    }
    return data;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<bool> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    var serverSessionRevoked = token == null || token.isEmpty;

    if (!serverSessionRevoked) {
      try {
        final response = await http
            .post(
              Uri.parse('$baseUrl/logout'),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer ${token.trim()}',
              },
            )
            .timeout(const Duration(seconds: 15));
        serverSessionRevoked =
            response.statusCode == 200 || response.statusCode == 401;
      } on http.ClientException {
        serverSessionRevoked = false;
      } on SocketException {
        serverSessionRevoked = false;
      } on TimeoutException {
        serverSessionRevoked = false;
      }
    }

    await clearLocalSession();
    return serverSessionRevoked;
  }

  static Future<void> clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('auth_user_id');
    if (userId != null) {
      await NotificationStorage.clearForUser(userId);
    } else {
      await NotificationStorage.clearLegacyNotifications();
    }
    await prefs.remove('auth_token');
    await prefs.remove('auth_user_id');
    await prefs.remove('auth_role');
    await prefs.remove('last_active_at');
  }

  // register method
  Future<Map<String, dynamic>> registerStaff({
    required String token,
    required String name,
    String? phone,
    required String password,
    required String confirmPassword,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/staff/register'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },

          body: jsonEncode({
            // converts the dart map into raw json string
            'token': token,
            'name': name.trim(),
            if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
            'password': password,
            'password_confirmation': confirmPassword,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final dynamic decoded;

    try {
      decoded = jsonDecode(
        response.body,
      ); // converts raw json string to dart map
    } on FormatException {
      throw Exception('Invalid response (${response.statusCode}).');
    }

    if (decoded is! Map) {
      throw Exception('Invalid server response');
    }

    final data = Map<String, dynamic>.from(decoded);

    if (response.statusCode != 201 || data['success'] != true) {
      final errors = data['errors'] ?? data['error'];

      if (errors is Map) {
        final messages = errors.values
            .expand((value) => value is List ? value : [value])
            .map((value) => value.toString())
            .join('\n');
        throw Exception(
          messages.isNotEmpty
              ? messages
              : data['message'] ?? 'Registration failed.',
        );
      }

      throw Exception(data['message'] ?? 'Registration failed');
    }
    return data;
  }
}
