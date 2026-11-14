import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/screens/private_conversations_screen.dart';
import 'package:staff_attendance_mobile/screens/private_chat_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class TeamChatScreen extends StatefulWidget {
  const TeamChatScreen({this.apiService, super.key});

  final ApiService? apiService;

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  static const _accent = Color(0xFFFB923C);
  late final ApiService _api = widget.apiService ?? ApiService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  Timer? _pollTimer;
  int? _userId;
  int _unreadPrivateCount = 0;
  int _pollCount = 0;
  bool _isRefreshing = false;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollCount++;
      _loadMessages(forceFull: _pollCount % 5 == 0);
    });
  }

  Future<void> _loadUserId() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userId = preferences.getInt('auth_user_id') ??
          int.tryParse(preferences.getString('auth_user_id') ?? '');
    });
    await _loadMessages();
  }

  int get _lastMessageId => _messages.isEmpty
      ? 0
      : (_messages.last['id'] as num?)?.toInt() ?? 0;

  Future<void> _loadMessages({bool forceFull = false}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final response = await _api.fetchGroupChat(
        afterId: _messages.isEmpty || forceFull ? null : _lastMessageId,
      );
      final incoming = response['messages'];
      if (!mounted) return;
      final shouldScroll =
          _messages.isEmpty ||
          (_scrollController.hasClients &&
              _scrollController.position.maxScrollExtent -
                      _scrollController.position.pixels <
                  80);
      setState(() {
        _isLoading = false;
        _error = null;
        _unreadPrivateCount =
            (response['unread_private_count'] as num?)?.toInt() ?? 0;
        if (incoming is List) {
          if (forceFull || _messages.isEmpty) _messages.clear();
          for (final item in incoming.whereType<Map>()) {
            final message = Map<String, dynamic>.from(item);
            final id = (message['id'] as num?)?.toInt();
            if (id != null && !_messages.any((existing) => existing['id'] == id)) {
              _messages.add(message);
            }
          }
          _messages.sort(
            (a, b) => ((a['id'] as num?)?.toInt() ?? 0)
                .compareTo((b['id'] as num?)?.toInt() ?? 0),
          );
        }
      });
      if (shouldScroll) _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst(RegExp(r'^(Exception|ApiRequestException):\s*'), '');
      });
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      final result = await _api.sendGroupChatMessage(message);
      final sent = result['message'];
      if (sent is Map && mounted) {
        setState(() => _messages.add(Map<String, dynamic>.from(sent)));
        _messageController.clear();
        _scrollToBottom();
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _messageActions(Map<String, dynamic> message) async {
    final userValue = message['user'];
    final sender = userValue is Map ? Map<String, dynamic>.from(userValue) : {};
    final senderId = (sender['id'] as num?)?.toInt();
    final isMine = senderId != null && senderId == _userId;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply Privately'),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Message'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Message'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (selected == 'reply' && senderId != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PrivateChatScreen(
            apiService: _api,
            colleagueId: senderId,
            colleagueName: sender['name']?.toString() ?? 'Colleague',
            colleagueRole: sender['role']?.toString(),
            quotedMessage: message['message']?.toString(),
          ),
        ),
      );
      await _loadMessages();
    } else if (selected == 'edit') {
      await _editMessage(message);
    } else if (selected == 'delete') {
      await _deleteMessage(message);
    }
  }

  Future<void> _editMessage(Map<String, dynamic> message) async {
    final controller = TextEditingController(text: message['message']?.toString());
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 2000,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == null || updated.isEmpty) return;
    try {
      final result = await _api.updateGroupChatMessage(
        messageId: (message['id'] as num).toInt(),
        message: updated,
      );
      final updatedMessage = result['message'];
      if (updatedMessage is Map && mounted) {
        setState(() {
          final index = _messages.indexWhere((item) => item['id'] == message['id']);
          if (index >= 0) _messages[index] = Map<String, dynamic>.from(updatedMessage);
        });
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteGroupChatMessage((message['id'] as num).toInt());
      if (mounted) {
        setState(() => _messages.removeWhere((item) => item['id'] == message['id']));
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  void _showError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.replaceFirst(RegExp(r'^(Exception|ApiRequestException):\s*'), ''))),
    );
  }

  String _timeLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '${date.day}/${date.month} $hour:${date.minute.toString().padLeft(2, '0')} '
        '${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Chat'),
        actions: [
          PopupMenuButton<String>(
            icon: Badge(
              isLabelVisible: _unreadPrivateCount > 0,
              label: Text('$_unreadPrivateCount'),
              backgroundColor: Colors.red,
              child: const Icon(Icons.more_vert),
            ),
            onSelected: (value) async {
              if (value != 'private') return;
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PrivateConversationsScreen(apiService: _api),
                ),
              );
              await _loadMessages();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'private',
                child: Text(
                  _unreadPrivateCount > 0
                      ? 'Private Messages ($_unreadPrivateCount)'
                      : 'Private Messages',
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(onPressed: _loadMessages, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet. Say hello!'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(14),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final item = _messages[index];
                          final user = item['user'] is Map
                              ? Map<String, dynamic>.from(item['user'] as Map)
                              : <String, dynamic>{};
                          final own = (user['id'] as num?)?.toInt() == _userId;
                          return GestureDetector(
                            onLongPress: () => _messageActions(item),
                            onTap: () => _messageActions(item),
                            child: Align(
                              alignment: own
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.sizeOf(context).width * .82,
                                ),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: own ? const Color(0xFFFFF1E6) : Colors.white,
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!own)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              user['name']?.toString() ?? 'Colleague',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          if (user['role']?.toString() == 'admin') ...[
                                            const SizedBox(width: 6),
                                            const _AdminRoleBadge(),
                                          ],
                                        ],
                                      ),
                                    if (!own) const SizedBox(height: 5),
                                    Text(item['message']?.toString() ?? ''),
                                    const SizedBox(height: 7),
                                    Text(
                                      '${_timeLabel(item['created_at'])}'
                                      '${item['edited_at'] != null ? ' · (edited)' : ''}',
                                      style: Theme.of(context).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(22)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendMessage,
                    style: IconButton.styleFrom(backgroundColor: _accent),
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminRoleBadge extends StatelessWidget {
  const _AdminRoleBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFDBEAFE),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'ADMIN',
          style: TextStyle(
            color: Color(0xFF1D4ED8),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}
