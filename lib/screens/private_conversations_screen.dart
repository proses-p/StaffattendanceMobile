import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:staff_attendance_mobile/screens/private_chat_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class PrivateConversationsScreen extends StatefulWidget {
  const PrivateConversationsScreen({this.apiService, super.key});

  final ApiService? apiService;

  @override
  State<PrivateConversationsScreen> createState() =>
      _PrivateConversationsScreenState();
}

class _PrivateConversationsScreenState
    extends State<PrivateConversationsScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final conversations = await _api.fetchPrivateConversations();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst(
          RegExp(r'^(Exception|ApiRequestException):\s*'),
          '',
        );
      });
    }
  }

  String _timestamp(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? '' : DateFormat('dd MMM, HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Private Messages')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _loadConversations,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  child: _conversations.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No colleagues found.')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final entry = _conversations[index];
                            final colleague = entry['user'] is Map
                                ? Map<String, dynamic>.from(entry['user'] as Map)
                                : <String, dynamic>{};
                            final unread =
                                (entry['unread_count'] as num?)?.toInt() ?? 0;
                            final colleagueId =
                                (colleague['id'] as num?)?.toInt();
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              leading: CircleAvatar(
                                backgroundColor:
                                    const Color(0xFFFFEDD5),
                                child: Text(
                                  colleague['name']?.toString().isNotEmpty == true
                                      ? colleague['name']
                                          .toString()[0]
                                          .toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Color(0xFFEA580C),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      colleague['name']?.toString() ??
                                          'Colleague',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (unread > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFDC2626),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$unread',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  entry['last_message']?.toString() ??
                                      'Start a private conversation',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: Text(
                                _timestamp(entry['last_message_at']),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              onTap: colleagueId == null
                                  ? null
                                  : () async {
                                      await Navigator.of(context)
                                          .push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) => PrivateChatScreen(
                                            apiService: _api,
                                            colleagueId: colleagueId,
                                            colleagueName: colleague['name']
                                                    ?.toString() ??
                                                'Colleague',
                                            colleagueRole:
                                                colleague['role']?.toString(),
                                          ),
                                        ),
                                      );
                                      await _loadConversations();
                                    },
                            );
                          },
                        ),
                ),
    );
  }
}
