import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';

class ModerationDashboardScreen extends ConsumerStatefulWidget {
  static const routeName = '/moderation-dashboard';
  final String chatId;

  const ModerationDashboardScreen({super.key, required this.chatId});

  @override
  ConsumerState<ModerationDashboardScreen> createState() =>
      _ModerationDashboardScreenState();
}

class _ModerationDashboardScreenState
    extends ConsumerState<ModerationDashboardScreen> {
  final ValueNotifier<DateTime> _now = ValueNotifier<DateTime>(DateTime.now());
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _now.value = DateTime.now();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final fs = FirestoreService();
    final meMemberStream = fs.dmChats
        .doc(widget.chatId)
        .collection('members')
        .doc(myUid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: meMemberStream,
      builder: (context, mySnap) {
        final role = (mySnap.data?.data()?['role'] as String?) ?? 'member';
        final isAdmin = role == 'owner' || role == 'admin';

        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Moderation Dashboard')),
            body: const Center(child: Text('You are not allowed to view this')),
          );
        }

        final bannedStream = fs.dmChats
            .doc(widget.chatId)
            .collection('members')
            .where('bannedUntil', isGreaterThan: Timestamp.now())
            .orderBy('bannedUntil')
            .snapshots();

        final logsStream = fs.dmChats
            .doc(widget.chatId)
            .collection('moderationLogs')
            .orderBy('timestamp', descending: true)
            .limit(50)
            .snapshots();

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Moderation Dashboard'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const _DashboardHeader(title: 'Live Banned Users'),
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: bannedStream,
                  builder: (context, snap) {
                    final docs = snap.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return const _EmptyGlassCard(
                        text: 'No active bans right now',
                      );
                    }

                    return Column(
                      children: [
                        for (final d in docs)
                          _BannedUserCard(
                            chatId: widget.chatId,
                            memberId: d.id,
                            data: d.data(),
                            now: _now,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                const _DashboardHeader(title: 'Moderation History'),
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: logsStream,
                  builder: (context, snap) {
                    final docs = snap.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return const _EmptyGlassCard(
                        text: 'No moderation events yet',
                      );
                    }

                    return Column(
                      children: [
                        for (final d in docs) _ModerationLogRow(data: d.data()),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final String title;
  const _DashboardHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyGlassCard extends StatelessWidget {
  final String text;
  const _EmptyGlassCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.7),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BannedUserCard extends ConsumerWidget {
  final String chatId;
  final String memberId;
  final Map<String, dynamic> data;
  final ValueNotifier<DateTime> now;

  const _BannedUserCard({
    required this.chatId,
    required this.memberId,
    required this.data,
    required this.now,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannedUntilTs = data['bannedUntil'];
    final bannedUntil = bannedUntilTs is Timestamp
        ? bannedUntilTs.toDate()
        : null;
    if (bannedUntil == null) return const SizedBox.shrink();

    final role = (data['role'] as String?) ?? 'member';
    final isProtected = role == 'owner' || role == 'admin';
    final reason = (data['banReason'] as String?)?.trim();

    final startTs = data['lastBanStart'];
    final start = startTs is Timestamp ? startTs.toDate() : null;

    return ValueListenableBuilder<DateTime>(
      valueListenable: now,
      builder: (context, nowValue, _) {
        final remaining = bannedUntil.difference(nowValue);
        final remSec = remaining.inSeconds;
        if (remSec <= 0) return const SizedBox.shrink();

        final total = (start == null)
            ? Duration(seconds: remSec)
            : bannedUntil.difference(start);
        final totalSec = total.inSeconds <= 0 ? 1 : total.inSeconds;
        final ratio = (remSec / totalSec).clamp(0.0, 1.0);

        String fmt(int total) {
          final h = (total ~/ 3600).toString().padLeft(2, '0');
          final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
          final s = (total % 60).toString().padLeft(2, '0');
          return '$h:$m:$s';
        }

        final fade = (ratio < 0.12) ? (0.65 + (ratio / 0.12) * 0.35) : 1.0;

        Future<void> adjust(Duration delta) async {
          final messenger = ScaffoldMessenger.of(context);
          if (isProtected) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Cannot modify admin/owner')),
            );
            return;
          }

          try {
            await ref
                .read(groupModerationServiceProvider)
                .adjustBan(chatId: chatId, userId: memberId, delta: delta);
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Action failed: $e')),
            );
          }
        }

        Future<void> unban() async {
          final messenger = ScaffoldMessenger.of(context);
          if (isProtected) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Cannot modify admin/owner')),
            );
            return;
          }

          try {
            await ref
                .read(groupModerationServiceProvider)
                .unbanUser(chatId: chatId, userId: memberId);
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Action failed: $e')),
            );
          }
        }

        final name = ref
            .watch(userDocProvider(memberId))
            .maybeWhen(
              data: (u) => (u?.name ?? memberId).trim(),
              orElse: () => memberId,
            );

        Color barColor(double r) {
          if (r > 0.55) return const Color(0xFF2ECC71);
          if (r > 0.25) return const Color(0xFFFFA726);
          return const Color(0xFFE24C4C);
        }

        return Opacity(
          opacity: fade,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE24C4C).withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFE24C4C).withOpacity(0.28),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'BANNED',
                        style: TextStyle(
                          color: Color(0xFFE24C4C),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Remaining: ${fmt(remSec)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Reason: $reason',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 6,
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        barColor(ratio),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _PillButton(
                      label: '+10m',
                      color: const Color(0xFFFFA726),
                      onTap: () => adjust(const Duration(minutes: 10)),
                    ),
                    _PillButton(
                      label: '+1h',
                      color: const Color(0xFFFFA726),
                      onTap: () => adjust(const Duration(hours: 1)),
                    ),
                    _PillButton(
                      label: '-10m',
                      color: const Color(0xFFE24C4C),
                      onTap: () => adjust(const Duration(minutes: -10)),
                    ),
                    _PillButton(
                      label: 'UNBAN',
                      color: const Color(0xFF2ECC71),
                      onTap: unban,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(0.35), width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModerationLogRow extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _ModerationLogRow({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = (data['uid'] as String?) ?? '';
    final action = (data['action'] as String?) ?? '';
    final reason = (data['reason'] as String?)?.trim();
    final performedBy = (data['performedBy'] as String?) ?? '';

    final userName = uid.isEmpty
        ? ''
        : ref
              .watch(userDocProvider(uid))
              .maybeWhen(
                data: (u) => (u?.name ?? uid).trim(),
                orElse: () => uid,
              );

    final actorName = performedBy.isEmpty
        ? ''
        : ref
              .watch(userDocProvider(performedBy))
              .maybeWhen(
                data: (u) {
                  final n = (u?.name ?? performedBy).trim();
                  return n.isEmpty ? performedBy : n;
                },
                orElse: () => performedBy,
              );

    final base = uid.isEmpty ? action : '$userName — $action';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            base,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (reason != null && reason.isNotEmpty) 'Reason: $reason',
              if (actorName.isNotEmpty) 'By: $actorName',
            ].join('   '),
            style: TextStyle(
              color: Colors.white.withOpacity(0.68),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
