class StaffProfile {
  const StaffProfile({
    required this.name,
    required this.email,
    this.organization,
    this.phone,
    this.employeeId,
    this.role,
    this.isActive,
    this.createdAt,
  });

  final String name;
  final String email;
  final String? organization;
  final String? phone;
  final String? employeeId;
  final String? role;
  final bool? isActive;
  final DateTime? createdAt;

  factory StaffProfile.fromJson(Map<String, dynamic> json) {
    return StaffProfile(
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      organization: _optionalString(json['organization']),
      phone: _optionalString(json['phone']),
      employeeId: _optionalString(json['employee_id']),
      role: _optionalString(json['role']),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  static String? _optionalString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
