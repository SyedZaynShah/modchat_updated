import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message_model.dart';
import '../services/firestore_service.dart';
import '../theme/theme.dart';

class _UserMini {
  final String uid;
  final String name;
  final String? avatarUrl;

  const _UserMini({
    required this.uid,
    required this.name,
    required this.avatarUrl,
  });
}

final Map<String, _UserMini> _pollUserCache = <String, _UserMini>{};

class PollMessageCard extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const PollMessageCard({super.key, required this.message, required this.isMe});

  @override
  State<PollMessageCard> createState() => _PollMessageCardState();
}

class _PollMessageCardState extends State<PollMessageCard> {
  Timer? _debounce;
  bool _busy = false;

  Set<String>? _optimisticSelected;
  bool _pendingWrite = false;

  Future<List<_UserMini>> _loadUserMinis(List<String> uids) async {
    final unique = uids.where((e) => e.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return const <_UserMini>[];

    final missing = unique
        .where((id) => !_pollUserCache.containsKey(id))
        .toList();
    if (missing.isNotEmpty) {
      final fs = FirestoreService();
      const chunkSize = 10;
      for (var i = 0; i < missing.length; i += chunkSize) {
        final chunk = missing.sublist(
          i,
          (i + chunkSize) > missing.length ? missing.length : (i + chunkSize),
        );
        final snap = await fs.users
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final name = (data['name'] as String?)?.trim();
          _pollUserCache[doc.id] = _UserMini(
            uid: doc.id,
            name: (name == null || name.isEmpty) ? doc.id : name,
            avatarUrl: (data['profileImageUrl'] as String?)?.trim(),
          );
        }
      }
    }

    return unique
        .map(
          (id) =>
              _pollUserCache[id] ??
              _UserMini(uid: id, name: id, avatarUrl: null),
        )
        .toList(growable: false);
  }

  void _openVotersSheet({
    required String optionLabel,
    required List<String> uids,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF0F0F0F) : Colors.white;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Voters',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  optionLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<_UserMini>>(
                  future: _loadUserMinis(uids),
                  builder: (context, snap) {
                    final items = snap.data ?? const <_UserMini>[];
                    final height = MediaQuery.of(ctx).size.height * 0.55;
                    return SizedBox(
                      height: height,
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                        itemBuilder: (context, i) {
                          final u = items[i];
                          final initial = u.name.isNotEmpty
                              ? u.name[0].toUpperCase()
                              : '?';
                          final img =
                              (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
                              ? NetworkImage(u.avatarUrl!)
                              : null;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(
                                0xFF5865F2,
                              ).withOpacity(0.18),
                              backgroundImage: img,
                              child: img == null
                                  ? Text(
                                      initial,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              u.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Set<String> _applyOptimisticOverlay({
    required List<Map<String, dynamic>> options,
    required Set<String> selectedFromFirestore,
    required String uid,
  }) {
    if (!_pendingWrite || uid.isEmpty) return selectedFromFirestore;
    final optimistic = _optimisticSelected;
    if (optimistic == null) return selectedFromFirestore;
    return optimistic;
  }

  int _voteCountWithOverlay({
    required Map<String, dynamic> option,
    required String optionId,
    required Set<String> selectedFromFirestore,
    required Set<String> selectedForUi,
    required String uid,
  }) {
    final base = (option['voteCount'] as num?)?.toInt();
    final votes = (option['votes'] as List?)?.cast<dynamic>() ?? const [];
    var count = base ?? votes.length;
    if (!_pendingWrite || uid.isEmpty) return count;

    final hadUid = selectedFromFirestore.contains(optionId);
    final hasUid = selectedForUi.contains(optionId);
    if (hadUid == hasUid) return count;
    return hasUid ? count + 1 : (count - 1).clamp(0, 1 << 30);
  }

  int _totalVotersWithOverlay({
    required Set<String> allVotersFromFirestore,
    required Set<String> selectedFromFirestore,
    required Set<String> selectedForUi,
    required String uid,
  }) {
    var total = allVotersFromFirestore.length;
    if (!_pendingWrite || uid.isEmpty) return total;

    final hadAny = selectedFromFirestore.isNotEmpty;
    final hasAny = selectedForUi.isNotEmpty;
    if (hadAny == hasAny) return total;
    return hasAny ? total + 1 : (total - 1).clamp(0, 1 << 30);
  }

  Set<String> _nextSelection({
    required Set<String> current,
    required String optionId,
    required bool allowMultipleVotes,
    required bool allowVoteChange,
  }) {
    if (optionId.isEmpty) return current;
    if (!allowVoteChange && current.isNotEmpty) return current;

    final next = {...current};
    final isSelected = next.contains(optionId);

    if (allowMultipleVotes) {
      if (isSelected) {
        next.remove(optionId);
      } else {
        next.add(optionId);
      }
      return next;
    }

    if (isSelected) {
      next.remove(optionId);
      return next;
    }

    next
      ..clear()
      ..add(optionId);
    return next;
  }

  void _optimisticallySelect(Set<String> desired) {
    setState(() {
      _optimisticSelected = desired;
      _pendingWrite = true;
    });
  }

  void _clearOptimisticIfSafe({required Set<String> selectedFromFirestore}) {
    if (!_pendingWrite) return;
    final optimistic = _optimisticSelected;
    if (optimistic == null) return;

    if (setEquals(optimistic, selectedFromFirestore)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_pendingWrite) return;
        final opt = _optimisticSelected;
        if (opt == null) return;
        if (!setEquals(opt, selectedFromFirestore)) return;
        setState(() {
          _pendingWrite = false;
          _optimisticSelected = null;
        });
      });
    }
  }

  void _showVoteFailed() {
    if (!mounted) return;
    // Intentionally silent (no snackbar spam). Retries handle transient failures.
  }

  void _scheduleCommit({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Set<String> desired,
    required bool allowMultipleVotes,
    required bool allowVoteChange,
  }) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        await _commitVoteSet(
          docRef: docRef,
          desiredSelected: desired,
          allowMultipleVotes: allowMultipleVotes,
          allowVoteChange: allowVoteChange,
        );
      } catch (_) {
        // Silent retry once after a short delay.
        try {
          await Future<void>.delayed(const Duration(seconds: 2));
          await _commitVoteSet(
            docRef: docRef,
            desiredSelected: desired,
            allowMultipleVotes: allowMultipleVotes,
            allowVoteChange: allowVoteChange,
          );
        } catch (_) {
          // If it's a permissions issue, retry won't help. Keep UI optimistic and stop pending.
          if (mounted) {
            setState(() {
              _pendingWrite = false;
            });
          }
        }
        _showVoteFailed();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  Future<void> _commitVoteSet({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Set<String> desiredSelected,
    required bool allowMultipleVotes,
    required bool allowVoteChange,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data();
      final poll =
          (data?['poll'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final optionsRaw = (poll['options'] as List?) ?? const [];

      final options = optionsRaw
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList(growable: false);

      final selectedFromFirestore = <String>{};
      for (final o in options) {
        final id = (o['id'] as String?) ?? '';
        final votes = (o['votes'] as List?)?.cast<dynamic>() ?? const [];
        if (id.isNotEmpty && votes.any((v) => v.toString() == uid)) {
          selectedFromFirestore.add(id);
        }
      }

      if (!allowVoteChange && selectedFromFirestore.isNotEmpty) {
        return;
      }

      final target = allowMultipleVotes
          ? desiredSelected
          : (desiredSelected.isEmpty ? <String>{} : {desiredSelected.first});

      final updatedOptions = options
          .map((o) {
            final id = (o['id'] as String?) ?? '';
            final votes =
                (o['votes'] as List?)?.map((e) => e.toString()).toList() ??
                <String>[];

            if (id.isEmpty) return o;

            final hasUid = votes.contains(uid);
            final shouldHave = target.contains(id);
            if (hasUid == shouldHave) return o;

            final nextVotes = [...votes];
            if (shouldHave) {
              nextVotes.add(uid);
            } else {
              nextVotes.removeWhere((v) => v == uid);
            }
            return {...o, 'votes': nextVotes, 'voteCount': nextVotes.length};
          })
          .toList(growable: false);

      final voterUnion = <String>{};
      for (final o in updatedOptions) {
        final votes =
            (o['votes'] as List?)?.map((e) => e.toString()).toList() ??
            <String>[];
        voterUnion.addAll(votes.where((e) => e.isNotEmpty));
      }

      final nextPoll = <String, dynamic>{
        ...poll,
        'options': updatedOptions,
        'totalVotes': voterUnion.length,
      };
      tx.update(docRef, {'poll': nextPoll});
    });
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();
    final ref = fs.messages(widget.message.chatId).doc(widget.message.id);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final poll =
            (data?['poll'] as Map?)?.cast<String, dynamic>() ??
            (widget.message.poll ?? const <String, dynamic>{});

        final question = (poll['question'] as String?)?.trim() ?? '';
        final optionsRaw = (poll['options'] as List?) ?? const [];
        final allowMultipleVotes =
            (poll['allowMultipleVotes'] as bool?) ?? false;
        final allowVoteChange = (poll['allowVoteChange'] as bool?) ?? true;
        final isAnonymous = (poll['isAnonymous'] as bool?) ?? false;

        final options = optionsRaw
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList(growable: false);

        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final selectedFromFirestore = <String>{};
        final allVoters = <String>{};

        for (final o in options) {
          final id = (o['id'] as String?) ?? '';
          final votes = (o['votes'] as List?)?.cast<dynamic>() ?? const [];
          for (final v in votes) {
            final s = v.toString();
            if (s.isNotEmpty) allVoters.add(s);
          }
          if (uid.isNotEmpty && votes.any((v) => v.toString() == uid)) {
            if (id.isNotEmpty) selectedFromFirestore.add(id);
          }
        }

        final selectedForUi = _applyOptimisticOverlay(
          options: options,
          selectedFromFirestore: selectedFromFirestore,
          uid: uid,
        );

        _clearOptimisticIfSafe(selectedFromFirestore: selectedFromFirestore);

        final totalVoters = _totalVotersWithOverlay(
          allVotersFromFirestore: allVoters,
          selectedFromFirestore: selectedFromFirestore,
          selectedForUi: selectedForUi,
          uid: uid,
        );

        int maxVotes = 0;
        String leadingId = '';
        for (final o in options) {
          final id = (o['id'] as String?) ?? '';
          final votes = _voteCountWithOverlay(
            option: o,
            optionId: id,
            selectedFromFirestore: selectedFromFirestore,
            selectedForUi: selectedForUi,
            uid: uid,
          );
          if (votes > maxVotes) {
            maxVotes = votes;
            leadingId = id;
          }
        }

        String? insight;
        if (totalVoters > 0 && maxVotes / totalVoters > 0.60) {
          final lead = options.firstWhere(
            (e) => (e['id'] as String?) == leadingId,
            orElse: () => const <String, dynamic>{},
          );
          final t = (lead['text'] as String?)?.trim();
          if (t != null && t.isNotEmpty) {
            insight = 'Most people chose $t';
          }
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final bg = widget.isMe
            ? (isDark
                  ? AppColors.primary.withOpacity(0.18)
                  : AppColors.outgoingBubbleLight)
            : (isDark ? AppColors.darkCard : AppColors.incomingBubbleLight);
        final border = widget.isMe
            ? null
            : Border.all(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.bubbleBorderLight,
                width: 1,
              );

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: border,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAnonymous ? '🔒 Anonymous Poll' : '👁 Public Poll',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? Colors.white.withOpacity(0.65)
                      : Colors.black.withOpacity(0.55),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                question.isEmpty ? 'Poll' : question,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.textDarkPrimary
                      : AppColors.textLightPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ...options.map((o) {
                final id = (o['id'] as String?) ?? '';
                final text = (o['text'] as String?)?.trim() ?? '';
                final voterUids =
                    ((o['votes'] as List?)?.cast<dynamic>() ?? const [])
                        .map((e) => e.toString())
                        .where((e) => e.isNotEmpty)
                        .toList(growable: false);
                final voteCount = _voteCountWithOverlay(
                  option: o,
                  optionId: id,
                  selectedFromFirestore: selectedFromFirestore,
                  selectedForUi: selectedForUi,
                  uid: uid,
                );
                final pct = totalVoters == 0
                    ? 0.0
                    : (voteCount / totalVoters).clamp(0.0, 1.0);
                final isSelected = id.isNotEmpty && selectedForUi.contains(id);
                final isLeading =
                    id.isNotEmpty && id == leadingId && maxVotes > 0;

                return _PollOptionTile(
                  label: text,
                  percent: pct,
                  voteCount: voteCount,
                  selected: isSelected,
                  leading: isLeading,
                  disabled: uid.isEmpty || _busy,
                  voters: isAnonymous
                      ? null
                      : _VoterStack(
                          uids: voterUids,
                          onTap: voterUids.isEmpty
                              ? null
                              : () => _openVotersSheet(
                                  optionLabel: text.isEmpty ? 'Option' : text,
                                  uids: voterUids,
                                ),
                        ),
                  onTap: () {
                    if (uid.isEmpty) return;

                    HapticFeedback.selectionClick();

                    final current = selectedForUi;
                    final desired = _nextSelection(
                      current: current,
                      optionId: id,
                      allowMultipleVotes: allowMultipleVotes,
                      allowVoteChange: allowVoteChange,
                    );

                    _optimisticallySelect(desired);

                    Future.microtask(() {
                      _scheduleCommit(
                        docRef: ref,
                        desired: desired,
                        allowMultipleVotes: allowMultipleVotes,
                        allowVoteChange: allowVoteChange,
                      );
                    });
                  },
                );
              }),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  '$totalVoters votes${uid.isEmpty ? '' : ' • Tap to vote'}',
                  key: ValueKey<int>(totalVoters),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textDarkSecondary
                        : AppColors.textLightSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (insight != null) ...[
                const SizedBox(height: 6),
                Text(
                  insight,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PollOptionTile extends StatelessWidget {
  final String label;
  final double percent;
  final int voteCount;
  final bool selected;
  final bool leading;
  final bool disabled;
  final VoidCallback onTap;
  final Widget? voters;

  const _PollOptionTile({
    required this.label,
    required this.percent,
    required this.voteCount,
    required this.selected,
    required this.leading,
    required this.disabled,
    required this.onTap,
    this.voters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final accent = const Color(0xFF5865F2);
    final baseBorder = isDark ? Colors.white12 : Colors.black12;
    final highlightBorder = selected ? accent.withOpacity(0.85) : baseBorder;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: highlightBorder,
                width: selected ? 1.2 : 1,
              ),
              boxShadow: leading
                  ? [
                      BoxShadow(
                        color: accent.withOpacity(isDark ? 0.25 : 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final barW = c.maxWidth * percent;
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 34,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white10
                                : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          height: 34,
                          width: barW,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accent.withOpacity(0.35),
                                accent.withOpacity(0.18),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              if (selected)
                                const Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: Color(0xFF5865F2),
                                )
                              else
                                Icon(
                                  Icons.radio_button_unchecked,
                                  size: 18,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black38,
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.textDarkPrimary
                                        : AppColors.textLightPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${(percent * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (voters != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: voters!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoterStack extends StatelessWidget {
  final List<String> uids;
  final VoidCallback? onTap;

  const _VoterStack({required this.uids, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (uids.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final max = uids.length > 3 ? 3 : uids.length;
    final extra = uids.length - max;
    final shown = uids.take(max).toList(growable: false);

    Widget avatarFor(String uid) {
      final cached = _pollUserCache[uid];
      final label = (cached?.name ?? uid).trim();
      final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
      final url = cached?.avatarUrl;
      final img = (url != null && url.isNotEmpty) ? NetworkImage(url) : null;
      return CircleAvatar(
        radius: 11,
        backgroundColor: const Color(0xFF5865F2).withOpacity(0.18),
        backgroundImage: img,
        child: img == null
            ? Text(
                initial,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              )
            : null,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 11 * 2 + (max - 1) * 14,
            height: 22,
            child: Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(left: i * 14.0, child: avatarFor(shown[i])),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            extra > 0 ? '+$extra' : '${uids.length}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
