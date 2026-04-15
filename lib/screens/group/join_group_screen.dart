import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_providers.dart';
import '../../theme/theme.dart';
import '../chat/group_chat_detail_screen.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  static const routeName = '/join-group';
  final String? inviteCode;

  const JoinGroupScreen({super.key, this.inviteCode});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _codeCtrl = TextEditingController();
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    final initial = (widget.inviteCode ?? '').trim();
    if (initial.isNotEmpty) {
      _codeCtrl.text = initial;
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = (data?.text ?? '').trim();
    if (!mounted) return;
    if (text.isEmpty) return;

    final maybe = _tryExtractCode(text) ?? text;
    setState(() => _codeCtrl.text = maybe);
  }

  String? _tryExtractCode(String text) {
    try {
      final uri = Uri.tryParse(text);
      if (uri == null) return null;
      final segs = uri.pathSegments;
      if (segs.length >= 2 && segs[0] == 'join') {
        final code = segs[1].trim();
        return code.isEmpty ? null : code;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _join() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to join.')),
      );
      return;
    }

    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an invite code')),
      );
      return;
    }

    setState(() => _joining = true);
    try {
      final chatId = await ref
          .read(groupModerationServiceProvider)
          .joinByInviteCode(inviteCode: code);
      if (!mounted) return;

      if (chatId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid invite code')),
        );
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        GroupChatDetailScreen.routeName,
        arguments: {'chatId': chatId},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Join failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Join group'),
        actions: [
          TextButton(
            onPressed: _joining ? null : _paste,
            child: const Text('Paste'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.outline, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invite code',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _codeCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _joining ? null : _join(),
                  decoration: const InputDecoration(
                    hintText: 'e.g. AbC123xYz...',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _joining ? null : _join,
                    child: _joining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Join'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'You can paste either the invite code or a full invite link.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
