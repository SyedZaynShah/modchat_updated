import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/firestore_service.dart';
import '../../theme/theme.dart';
import '../../providers/chat_providers.dart';
import '../chat/chat_detail_screen.dart';

class NewContactScreen extends ConsumerStatefulWidget {
  const NewContactScreen({super.key});

  @override
  ConsumerState<NewContactScreen> createState() => _NewContactScreenState();
}

class _NewContactScreenState extends ConsumerState<NewContactScreen> {
  final _emailController = TextEditingController();
  bool _starting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _startChat() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _starting = true);
    try {
      // Keep the logic the same as HomeScreen._startChat – reuse FirestoreService paths
      final fs = FirestoreService();
      final me = FirebaseAuth.instance.currentUser!.uid;
      final qs = await fs.users.where('email', isEqualTo: email).limit(1).get();
      if (qs.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User not found')));
        return;
      }
      final peerId = (qs.docs.first.data())['userId'] as String;
      if (peerId == me) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('That is you')));
        return;
      }
      final chatId = await ref
          .read(chatServiceProvider)
          .startOrOpenChat(peerId);
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        ChatDetailScreen.routeName,
        arguments: {'chatId': chatId, 'peerId': peerId},
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.navy),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            const Text(
              'New Contact',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person, color: AppColors.navy, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.navy, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        labelText: 'Email',
                        hintText: 'Enter email to add contact',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _starting ? null : _startChat,
                child: _starting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add to contact'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
