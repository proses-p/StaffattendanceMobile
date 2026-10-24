
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
   static const String baseUrl = 'http://192.168.1.12:8000/api/v1';
  // static const String baseUrl = 'http://127.0.0.01/api/v1';

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },

      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'The server returned an invalid response (${response.statusCode}).',
      );
    }
    if (decoded is! Map) {
      throw Exception('The server response was not a JSON object.');
    }
    final data = Map<String, dynamic>.from(decoded);

    if (response.statusCode != 200) {
      throw Exception(
        'Status: ${response.statusCode} | '
        '${data['message'] ?? response.body}',
      );
    }

    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw Exception('The server did not return an authentication token.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
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

    await prefs.remove('auth_token');
    return serverSessionRevoked;
  }
}