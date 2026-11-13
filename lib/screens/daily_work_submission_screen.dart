import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class DailyWorkSubmissionScreen extends StatefulWidget {
  const DailyWorkSubmissionScreen({required this.apiService, super.key});

  final ApiService apiService;

  @override
  State<DailyWorkSubmissionScreen> createState() =>
      _DailyWorkSubmissionScreenState();
}

class _DailyWorkSubmissionScreenState extends State<DailyWorkSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _completedPartController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  Map<String, dynamic>? _todaySubmission;
  List<Map<String, dynamic>> _history = const [];
  List<Map<String, dynamic>> _tasks = const [];
  final List<XFile> _photos = [];
  int? _assignedTaskId;
  String _workStatus = 'completed';
  Object? _loadError;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _completedPartController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await widget.apiService.fetchDailyWorkStatus();
      if (!mounted) return;
      final today = response['today_submission'];
      final history = response['history'];
      final tasks = response['active_tasks'];
      setState(() {
        _todaySubmission = today is Map
            ? Map<String, dynamic>.from(today)
            : null;
        _history = history is List
            ? history
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList(growable: false)
            : const [];
        _tasks = tasks is List
            ? tasks
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList(growable: false)
            : const [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (photo == null || !mounted) return;
      if (await photo.length() > 5 * 1024 * 1024) {
        _showMessage('Each photo must be 5 MB or smaller.');
        return;
      }
      setState(() => _photos.add(photo));
    } catch (error) {
      if (mounted) _showMessage('Unable to capture photo: $error');
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    if (_photos.isEmpty) {
      _showMessage('Capture at least one photo before submitting.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.apiService.submitDailyWork(
        completedPart: _completedPartController.text.trim(),
        description: _descriptionController.text.trim(),
        workStatus: _workStatus,
        assignedTaskId: _assignedTaskId,
        photoPaths: _photos.map((photo) => photo.path).toList(growable: false),
      );
      if (!mounted) return;
      _completedPartController.clear();
      _descriptionController.clear();
      _photos.clear();
      _assignedTaskId = null;
      _workStatus = 'completed';
      _showMessage('Daily work report submitted for review.');
      await _load();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _reviewStatusLabel(Object? status) => switch (status?.toString()) {
    'accepted' => 'Accepted',
    'revision_requested' => 'Revision Requested',
    _ => 'Pending Review',
  };

  Color _reviewStatusColor(Object? status) => switch (status?.toString()) {
    'accepted' => const Color(0xFF15803D),
    'revision_requested' => const Color(0xFFB45309),
    _ => const Color(0xFF2563EB),
  };

  @override
  Widget build(BuildContext context) {
    final today = _todaySubmission;
    final canRevise = today?['review_status'] == 'revision_requested';
    final isLocked = today != null && !canRevise;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'Daily Work Submission',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && today == null && _loadError == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  if (_loadError != null)
                    _MessageCard(
                      message: 'Unable to load daily work reports: $_loadError',
                      color: const Color(0xFFFFF1F2),
                    ),
                  if (_tasks.isNotEmpty) ...[
                    const _SectionHeading(title: 'Admin assigned tasks'),
                    ..._tasks.map(_taskCard),
                    const SizedBox(height: 8),
                  ],
                  if (canRevise) ...[
                    _MessageCard(
                      message:
                          'Revision requested: ${today?['admin_feedback'] ?? 'Please update your report.'}',
                      color: const Color(0xFFFFF7ED),
                    ),
                    const SizedBox(height: 16),
                    _buildForm(isRevision: true),
                  ] else if (isLocked) ...[
                    const _SectionHeading(title: 'Today’s submission'),
                    _submissionCard(today!),
                  ] else ...[
                    const _SectionHeading(title: 'Today’s work report'),
                    _buildForm(),
                  ],
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionHeading(title: 'Past submissions'),
                    ..._history.map(_historyCard),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final id = task['id'] is int
        ? task['id'] as int
        : int.tryParse(task['id']?.toString() ?? '');
    final selected = id != null && _assignedTaskId == id;
    return Card(
      color: selected ? const Color(0xFFFFF7ED) : Colors.white,
      child: ListTile(
        leading: const Icon(Icons.assignment_outlined, color: Color(0xFFEA580C)),
        title: Text(task['title']?.toString() ?? 'Assigned task'),
        subtitle: Text(
          [
            if (task['instructions']?.toString().isNotEmpty == true)
              task['instructions'].toString(),
            if (task['due_date'] != null) 'Due ${task['due_date']}',
          ].join('\n'),
        ),
        trailing: id == null
            ? null
            : selected
            ? TextButton(
                onPressed: () => setState(() => _assignedTaskId = null),
                child: const Text('Unlink'),
              )
            : TextButton(
                onPressed: () => setState(() => _assignedTaskId = id),
                child: const Text('Link'),
              ),
      ),
    );
  }

  Widget _buildForm({bool isRevision = false}) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_tasks.isNotEmpty) ...[
                DropdownButtonFormField<int?>(
                  initialValue: _assignedTaskId,
                  decoration: const InputDecoration(
                    labelText: 'Link to assigned task (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('No assigned task'),
                    ),
                    ..._tasks.map((task) {
                      final id = task['id'] is int
                          ? task['id'] as int
                          : int.tryParse(task['id']?.toString() ?? '');
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Text(task['title']?.toString() ?? 'Task'),
                      );
                    }),
                  ],
                  onChanged: (value) => setState(() => _assignedTaskId = value),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _completedPartController,
                maxLength: 255,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Completed Part / Milestone',
                  hintText: 'What did you achieve today?',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Describe your key achievement.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 8,
                maxLength: 10000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Work Description',
                  hintText: 'Summarize the work you completed today.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a work description.'
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _workStatus,
                decoration: const InputDecoration(
                  labelText: 'Work Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'completed',
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem(
                    value: 'in_progress',
                    child: Text('In Progress'),
                  ),
                  DropdownMenuItem(value: 'blocked', child: Text('Needs Support / Blocked')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _workStatus = value);
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Photos (camera only)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _capturePhoto,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(_photos.isEmpty ? 'Add Photo' : 'Add New Picture'),
                  ),
                ],
              ),
              if (_photos.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'At least one photo is required. Each photo must be 5 MB or smaller.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                )
              else
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_photos[index].path),
                            width: 100,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: -6,
                          top: -6,
                          child: IconButton.filled(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Remove photo',
                            onPressed: () =>
                                setState(() => _photos.removeAt(index)),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFB923C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(isRevision ? 'Submit Revised Report' : 'Submit Daily Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _submissionCard(Map<String, dynamic> submission) {
    return _ReportCard(
      submission: submission,
      statusLabel: _reviewStatusLabel(submission['review_status']),
      statusColor: _reviewStatusColor(submission['review_status']),
    );
  }

  Widget _historyCard(Map<String, dynamic> submission) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _ReportCard(
        submission: submission,
        statusLabel: _reviewStatusLabel(submission['review_status']),
        statusColor: _reviewStatusColor(submission['review_status']),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: const TextStyle(
        color: Color(0xFF172033),
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: const TextStyle(height: 1.4)),
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.submission,
    required this.statusLabel,
    required this.statusColor,
  });

  final Map<String, dynamic> submission;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final photos = submission['photos'] is List
        ? (submission['photos'] as List)
              .whereType<Map>()
              .map((photo) => Map<String, dynamic>.from(photo))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  submission['submission_date']?.toString() ?? 'Today',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (submission['assigned_task'] is Map) ...[
              const SizedBox(height: 8),
              Text(
                'Task: ${(submission['assigned_task'] as Map)['title'] ?? ''}',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              submission['completed_part']?.toString() ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              submission['description']?.toString() ?? '',
              style: const TextStyle(color: Color(0xFF475569), height: 1.45),
            ),
            const SizedBox(height: 8),
            Text(
              'Work status: ${(submission['work_status'] ?? '').toString().replaceAll('_', ' ')}',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            if (submission['admin_feedback']?.toString().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              _MessageCard(
                message: 'Admin feedback: ${submission['admin_feedback']}',
                color: const Color(0xFFFFF7ED),
              ),
            ],
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final url = photos[index]['url']?.toString();
                    if (url == null || url.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        url,
                        width: 96,
                        height: 86,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 96,
                          height: 86,
                          color: const Color(0xFFF1F5F9),
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
