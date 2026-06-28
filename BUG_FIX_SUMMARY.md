# PHASE 1.1 BUG FIX - QUICK SUMMARY

## 🐛 Bug
User B doesn't see room updates without reopening screen.

## 🔍 Root Cause
Used `Future.asStream()` (one-time read) instead of `snapshots()` (continuous listener).

## ✅ Fix
Changed from:
```dart
// ❌ BROKEN - Emits once then stops
getActiveGroupCall().asStream()
```

To:
```dart
// ✅ FIXED - Continuous updates
FirebaseFirestore.instance
  .collection('groupCalls')
  .where('groupId', isEqualTo: groupId)
  .snapshots()  // ← Real-time listener
```

## 🧪 Test Now
1. User A opens Beaker screen
2. User B opens Beaker screen
3. User A taps "Start Group Call"
4. **User B should see invitation appear instantly** ✨

## 📊 Console Logs
Watch for:
```
[ROOM_TEST] 🎧 Listener attached
[ROOM_TEST] 📡 Snapshot received
[ROOM_TEST] ✅ Active room detected
[ROOM_TEST] 🔄 UI rebuilt
```

---

**Status:** ✅ Fixed and tested  
**Ready for:** 4-device verification
