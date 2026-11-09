import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class OnFieldScreen extends StatefulWidget {
  const OnFieldScreen({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<OnFieldScreen> createState() => _OnFieldScreenState();
}

class _OnFieldScreenState extends State<OnFieldScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  List<Map<String, dynamic>> _rows = const [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.fetchOnField();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openMap(Map<String, dynamic> row) async {
    final latitude = row['latitude'];
    final longitude = row['longitude'];
    if (latitude == null || longitude == null) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open the map.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text('Currently on field'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _rows.isEmpty
          ? Center(child: Text('Unable to load on-field staff: $_error'))
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No staff are currently on field.')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return Card(
                          color: Colors.white,
                          child: ListTile(
                            onTap: () => _openMap(row),
                            leading: Icon(
                              row['is_flagged'] == true
                                  ? Icons.flag
                                  : Icons.person_pin_circle_outlined,
                              color: row['is_flagged'] == true
                                  ? Colors.red
                                  : const Color(0xFFFB923C),
                            ),
                            title: Text(row['name']?.toString() ?? 'Staff'),
                            subtitle: Text(
                              '${row['task_type']} · ${row['last_seen_at'] ?? 'Location unavailable'}\n'
                              '${row['latitude'] ?? '-'}, ${row['longitude'] ?? '-'}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.map_outlined),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
