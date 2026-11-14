class StaffProfile {
  const StaffProfile({
    required this.name,
    required this.email,
    this.id,
    this.organization,
    this.phone,
    this.shiftName,
    this.role,
    this.isActive,
    this.createdAt,
  });

  final String name;
  final String email;
  final int? id;
  final String? organization;
  final String? phone;
  final String? shiftName;
  final String? role;
  final bool? isActive;
  final DateTime? createdAt;

  factory StaffProfile.fromJson(Map<String, dynamic> json) {
    return StaffProfile(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}'),
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      organization: _optionalString(
        json['company_name'] ?? json['organization'],
      ),
      phone: _optionalString(json['phone']),
      shiftName: _optionalString(json['shift_name']),
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
