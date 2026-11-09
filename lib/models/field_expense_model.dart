class FieldExpenseModel {
  const FieldExpenseModel({
    required this.category,
    required this.amount,
    required this.currency,
    required this.submittedAt,
    required this.status,
    required this.fieldAssignmentId,
    this.description,
    this.adminNotes,
    this.syncStatus,
    this.syncError,
    this.localId,
  });

  static const categories = <String, String>{
    'transport_fuel': 'Transport / Fuel',
    'meals_refreshments': 'Meals / Refreshments',
    'client_entertainment': 'Client Entertainment',
    'other_emergency': 'Other / Emergency',
  };

  final String category;
  final String amount;
  final String currency;
  final DateTime? submittedAt;
  final String status;
  final int? fieldAssignmentId;
  final String? description;
  final String? adminNotes;
  final String? syncStatus;
  final String? syncError;
  final int? localId;

  factory FieldExpenseModel.fromApi(Map<String, dynamic> json) {
    final id = json['field_assignment_id'];
    final submitted = json['submitted_at'];
    return FieldExpenseModel(
      category: json['category']?.toString() ?? 'other_emergency',
      amount: json['amount']?.toString() ?? '0.00',
      currency: json['currency']?.toString() ?? 'TZS',
      submittedAt: submitted is String ? DateTime.tryParse(submitted) : null,
      status: json['status']?.toString() ?? 'pending',
      fieldAssignmentId: id is int ? id : int.tryParse(id?.toString() ?? ''),
      description: json['description']?.toString(),
      adminNotes: json['admin_notes']?.toString(),
    );
  }

  factory FieldExpenseModel.fromLocal(Map<String, Object?> row) {
    final id = row['field_assignment_id'];
    final createdAt = row['created_at']?.toString();
    final syncStatus = row['sync_status']?.toString() ?? 'pending';
    return FieldExpenseModel(
      category: row['category']?.toString() ?? 'other_emergency',
      amount: row['amount']?.toString() ?? '0.00',
      currency: row['currency']?.toString() ?? 'TZS',
      submittedAt: createdAt == null ? null : DateTime.tryParse(createdAt),
      status: syncStatus == 'synced' ? 'pending' : syncStatus,
      fieldAssignmentId: id is int ? id : int.tryParse(id?.toString() ?? ''),
      description: row['description']?.toString(),
      syncStatus: syncStatus,
      syncError: row['last_error']?.toString(),
      localId: row['local_id'] is int ? row['local_id']! as int : null,
    );
  }

  static String? validateAmount(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) {
      return 'Enter a valid amount with up to two decimal places.';
    }
    final amount = num.tryParse(normalized);
    if (amount == null || amount <= 0) {
      return 'Amount must be greater than zero.';
    }
    if (amount > 99999999.99) return 'Amount exceeds the allowed limit.';
    return null;
  }
}
