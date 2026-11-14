import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:staff_attendance_mobile/services/location_service.dart';

class FieldModeScreen extends StatefulWidget {
  const FieldModeScreen({
    super.key,
    this.apiService,
    this.locationService,
    this.captureFromCamera,
  });

  final ApiService? apiService;
  final LocationService? locationService;
  final Future<XFile?> Function()? captureFromCamera;

  @override
  State<FieldModeScreen> createState() => _FieldModeScreenState();
}

class _FieldModeScreenState extends State<FieldModeScreen> {
  static const _accent = Color(0xFFFB923C);
  late final ApiService _api = widget.apiService ?? ApiService();
  late final LocationService _location =
      widget.locationService ?? LocationService();
  final _formKey = GlobalKey<FormState>();
  final _clientController = TextEditingController();
  final _purposeController = TextEditingController();
  final _completionController = TextEditingController();
  final _expenseAmountController = TextEditingController();
  final _expenseDescriptionController = TextEditingController();
  Map<String, dynamic> _status = {};
  XFile? _receiptPhoto;
  Timer? _elapsedTimer;
  DateTime _now = DateTime.now();
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  Map<String, dynamic>? get _activeVisit {
    final visit = _status['active_visit'];
    return visit is Map ? Map<String, dynamic>.from(visit) : null;
  }

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _clientController.dispose();
    _purposeController.dispose();
    _completionController.dispose();
    _expenseAmountController.dispose();
    _expenseDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final result = await _api.fetchFieldStatus();
      if (!mounted) return;
      setState(() {
        _status = result;
        _isLoading = false;
        _error = null;
      });
      _syncElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _syncElapsedTimer() {
    if (_activeVisit == null) {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      return;
    }
    _elapsedTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _startVisit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final location = await _location.current();
      await _api.startFieldVisit(
        clientOrServiceName: _clientController.text.trim(),
        purpose: _purposeController.text.trim(),
        latitude: (location['latitude'] as num).toDouble(),
        longitude: (location['longitude'] as num).toDouble(),
      );
      _clientController.clear();
      _purposeController.clear();
      await _loadStatus(showLoading: false);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _endVisit() async {
    if (_isSubmitting) return;
    final amount = _expenseAmountController.text.trim();
    if (amount.isNotEmpty && double.tryParse(amount) == null) {
      _showError('Enter a valid expense amount.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final location = await _location.current();
      await _api.endFieldVisit(
        visitId: _visitId(_activeVisit?['id']),
        latitude: (location['latitude'] as num).toDouble(),
        longitude: (location['longitude'] as num).toDouble(),
        completionNotes: _completionController.text,
        expenseAmount: amount.isEmpty ? '0' : amount,
        expenseDescription: _expenseDescriptionController.text,
        receiptPhotoPath: _receiptPhoto?.path,
      );
      _completionController.clear();
      _expenseAmountController.clear();
      _expenseDescriptionController.clear();
      setState(() => _receiptPhoto = null);
      await _loadStatus(showLoading: false);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _captureReceipt() async {
    try {
      final photo = await (widget.captureFromCamera ??
          () => ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
          ))();
      if (photo == null || !mounted) return;
      final extension = photo.path.toLowerCase().split('.').last;
      if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
        _showError('Use a JPEG, PNG, or WEBP receipt photo.');
        return;
      }
      final size = await File(photo.path).length();
      if (size == 0 || size > 5 * 1024 * 1024) {
        _showError('Receipt photos must be between 1 byte and 5 MB.');
        return;
      }
      setState(() => _receiptPhoto = photo);
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showError(
        error.code == 'camera_access_denied'
            ? 'Camera access is denied. Enable camera permission in Settings.'
            : 'Unable to open the camera.',
      );
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    final message = error.toString().replaceFirst(
      RegExp(r'^(Exception|StateError|ArgumentError): '),
      '',
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  int? _visitId(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  double _stat(String key) {
    final stats = _status['stats'];
    if (stats is! Map) return 0;
    final value = stats[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _elapsedLabel(Map<String, dynamic> visit) {
    final start = DateTime.tryParse(visit['clock_in_at']?.toString() ?? '');
    if (start == null) return '00:00:00';
    final seconds = _now
        .difference(start.toLocal())
        .inSeconds
        .clamp(0, 999999)
        .toInt();
    final hours = (seconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$remainingSeconds';
  }

  String _dateLabel(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? 'Date unavailable' : DateFormat('d MMM yyyy').format(date.toLocal());
  }

  String _durationLabel(Map<String, dynamic> visit) {
    final supplied = visit['duration_minutes'];
    int minutes;
    if (supplied is num) {
      minutes = supplied.toInt();
    } else {
      final start = DateTime.tryParse(visit['clock_in_at']?.toString() ?? '');
      final end = DateTime.tryParse(visit['clock_out_at']?.toString() ?? '');
      if (start == null || end == null) return 'Duration unavailable';
      minutes = end.difference(start).inMinutes.clamp(0, 100000).toInt();
    }
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final activeVisit = _activeVisit;
    final recentVisits = _status['recent_visits'] is List
        ? (_status['recent_visits'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'Field Mode',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _status.isEmpty
          ? _errorView()
          : RefreshIndicator(
              onRefresh: _loadStatus,
              color: _accent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  _buildStats(),
                  const SizedBox(height: 16),
                  if (activeVisit == null)
                    _buildStartCard()
                  else
                    _buildActiveVisitCard(activeVisit),
                  const SizedBox(height: 22),
                  Text(
                    'Recent Field Visits',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (recentVisits.isEmpty)
                    _emptyVisits()
                  else
                    ...recentVisits.map(_buildRecentVisitCard),
                ],
              ),
            ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadStatus, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _FieldStatCard(
            title: 'Field Hours',
            value: _stat('total_field_hours').toStringAsFixed(2),
            icon: Icons.work_history_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FieldStatCard(
            title: 'Avg Daily Hrs',
            value: _stat('avg_daily_hours').toStringAsFixed(2),
            icon: Icons.schedule_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FieldStatCard(
            title: 'Field Visits',
            value: _stat('total_visits').toStringAsFixed(0),
            icon: Icons.location_on_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildStartCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start a Field Visit',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _clientController,
                textCapitalization: TextCapitalization.words,
                validator: (value) => value?.trim().isNotEmpty == true
                    ? null
                    : 'Enter a client or service name.',
                decoration: const InputDecoration(
                  labelText: 'Client Name / Service Name',
                  hintText: 'Mikocheni Site / Fiber Installation',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _purposeController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                validator: (value) =>
                    value?.trim().isNotEmpty == true ? null : 'Enter the purpose of this visit.',
                decoration: const InputDecoration(
                  labelText: 'Purpose of Visit',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _startVisit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Field Visit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveVisitCard(Map<String, dynamic> visit) {
    final start = DateTime.tryParse(visit['clock_in_at']?.toString() ?? '');
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.radio_button_checked, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Visit in progress',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailLabel(
              'Client / Service',
              visit['client_or_service_name']?.toString() ?? 'Field Visit',
            ),
            _detailLabel('Purpose', visit['purpose']?.toString() ?? ''),
            _detailLabel(
              'Started',
              start == null
                  ? 'Time unavailable'
                  : DateFormat('d MMM yyyy · h:mm a').format(start.toLocal()),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _elapsedLabel(visit),
                style: const TextStyle(
                  color: Color(0xFF172033),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Expenses & Receipt Photo',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _completionController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Completion Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expenseAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Expense Amount (TZS)',
                hintText: 'e.g., transport or site costs',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expenseDescriptionController,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Expense Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _captureReceipt,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(
                _receiptPhoto == null
                    ? 'Take Receipt / Site Photo'
                    : 'Retake Receipt / Site Photo',
              ),
            ),
            if (_receiptPhoto != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_receiptPhoto!.path),
                  height: 150,
                  width: 180,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _endVisit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.stop_circle_outlined),
                label: const Text('End Field Visit & Submit'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailLabel(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _emptyVisits() {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Your completed field visits will appear here.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      ),
    );
  }

  Widget _buildRecentVisitCard(Map<String, dynamic> visit) {
    final expense = double.tryParse(visit['expense_amount']?.toString() ?? '') ?? 0;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              visit['client_or_service_name']?.toString() ?? 'Field Visit',
              style: const TextStyle(
                color: Color(0xFF172033),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${_dateLabel(visit['clock_in_at'])} · ${_durationLabel(visit)}',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            if (expense > 0 || visit['receipt_photo_url'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (expense > 0)
                    Text(
                      'TZS ${NumberFormat('#,##0.##', 'en_US').format(expense)}',
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (visit['receipt_photo_url'] != null) ...[
                    if (expense > 0) const SizedBox(width: 12),
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 17,
                      color: _accent,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Receipt attached',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldStatCard extends StatelessWidget {
  const _FieldStatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EDF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFFFB923C)),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF172033),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
