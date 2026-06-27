# GROUP AUDIO CALLING - PHASE 3 MIGRATION GUIDE

## 🚀 DEPLOYMENT & ROLLBACK STRATEGY

---

## OVERVIEW

This document provides step-by-step migration instructions for deploying Phase 3 Group Audio Calling feature and procedures for rolling back if critical issues are discovered.

---

## PRE-DEPLOYMENT CHECKLIST

### Code Review:
- [ ] All new files reviewed and approved
- [ ] Security rules changes reviewed
- [ ] No breaking changes to existing 1-to-1 calls
- [ ] Error handling implemented
- [ ] Logging added for debugging

### Testing Complete:
- [ ] Unit tests pass (if applicable)
- [ ] Manual testing completed (see TEST_PLAN.md)
- [ ] Multi-device testing done
- [ ] Network resilience tested
- [ ] Performance benchmarks met

### Infrastructure:
- [ ] Firebase project has sufficient quota
- [ ] Firestore has sufficient capacity
- [ ] STUN servers accessible (stun.l.google.com)
- [ ] Monitoring/alerting configured

### Documentation:
- [ ] Architecture document complete
- [ ] Test plan finalized
- [ ] This migration guide ready
- [ ] User-facing documentation prepared

---

## DEPLOYMENT STEPS

### PHASE 3A: BACKEND (Firestore Schema & Rules)

#### Step 1: Backup Existing Data

```bash
# Backup current Firestore rules
firebase firestore:rules:get --project=your-project-id > firestore.rules.backup

# Export existing group calls (if any)
gcloud firestore export gs://your-backup-bucket/phase3-backup \
  --collection-ids=groupCalls,groupCallInvitations \
  --project=your-project-id
```

#### Step 2: Deploy Updated Security Rules

```bash
# Test rules in Firebase console first (Rules Playground)
# Then deploy:
firebase deploy --only firestore:rules --project=your-project-id
```

**Verification:**
```bash
# Check rules deployed successfully
firebase firestore:rules:get --project=your-project-id

# Test with Firestore Rules Simulator in console
```

#### Step 3: Update Firestore Indexes (if needed)

```bash
# Deploy indexes
firebase deploy --only firestore:indexes --project=your-project-id
```

**Verify:**
- Check Firebase Console → Firestore → Indexes
- Wait for indexes to build (can take minutes to hours)

---

### PHASE 3B: CLIENT APP DEPLOYMENT

#### Step 4: Build and Test Staging Build

```bash
# Flutter build for Android
flutter build apk --release --flavor staging

# Flutter build for iOS
flutter build ios --release --flavor staging

# Flutter build for Web
flutter build web --release
```

**Staging Testing:**
- [ ] Deploy to internal testing track
- [ ] Test with 3+ devices
- [ ] Verify all features work
- [ ] Check error logs (Firebase Crashlytics)

#### Step 5: Gradual Rollout (Recommended)

**Day 1: Internal Team (5%)**
- Deploy to internal testers only
- Monitor for 24 hours
- Check crash reports
- Verify call quality

**Day 2: Beta Users (20%)**
- Deploy to beta testing track
- Monitor for 48 hours
- Collect user feedback
- Watch Firebase metrics

**Day 3: Public (50%)**
- Deploy to 50% of production users
- Monitor for 72 hours
- Compare metrics with control group

**Day 4: Public (100%)**
- Deploy to all users
- Continue monitoring

---

### PHASE 3C: MONITORING

#### Key Metrics to Track:

**Firebase Console:**
1. Firestore → Usage
   - Document reads/writes per minute
   - Active connections
   - Rule denials (should be low)

2. Crashlytics
   - Crash-free users percentage
   - WebRTC-related crashes
   - Call initialization errors

3. Performance Monitoring
   - Call setup duration
   - Screen rendering time
   - Network request duration

**Custom Logging:**
```dart
// Add to GroupCallController
print('[METRICS] Call setup time: ${duration}ms');
print('[METRICS] Peer connections: ${count}');
print('[METRICS] Audio quality: ${quality}');
```

**Analytics Events:**
```dart
// Track key events
analytics.logEvent(
  name: 'group_call_started',
  parameters: {'participant_count': count},
);

analytics.logEvent(
  name: 'group_call_ended',
  parameters: {
    'duration_seconds': duration,
    'participant_count': count,
  },
);
```

---

## POST-DEPLOYMENT VERIFICATION

### Immediate (First Hour):

- [ ] Monitor Crashlytics for spikes
- [ ] Check Firestore error logs
- [ ] Verify users can start calls
- [ ] Test 1-to-1 calls still work (regression)
- [ ] Check security rule denials

### First 24 Hours:

- [ ] Review call completion rate
- [ ] Check average call duration
- [ ] Monitor memory usage
- [ ] Verify speaking detection works
- [ ] Check participant limit enforcement

### First Week:

- [ ] Analyze user feedback
- [ ] Review call quality metrics
- [ ] Check for edge cases
- [ ] Monitor server costs (Firestore usage)
- [ ] Verify no regression in existing features

---

## ROLLBACK STRATEGY

### SCENARIO 1: Critical Bug Found (High Severity)

**Examples:**
- App crashes when joining call
- No audio transmission
- Security vulnerability
- Complete feature failure

**Immediate Actions:**

#### Option A: Kill Switch (Fastest)

```dart
// Add to RemoteConfig or feature_flags.dart
const bool enableGroupAudio = false; // Disable feature

// In app code:
if (!FeatureFlags.enableGroupAudio) {
  // Hide group call button
  return SizedBox.shrink();
}
```

Deploy new app version with kill switch:
```bash
# Emergency build
flutter build apk --release
firebase appdistribution:distribute app-release.apk \
  --project=your-project-id \
  --groups=all-users
```

#### Option B: Revert to Previous Version

```bash
# Rollback to previous APK in Play Console
# Or redeploy previous version

# For iOS, submit emergency update to App Store
```

---

### SCENARIO 2: Firestore Rules Issue

**Examples:**
- Users can't join calls
- Wrong users can access calls
- Participant limit not enforced

**Immediate Actions:**

```bash
# Restore backup rules
firebase deploy --only firestore:rules \
  --file=firestore.rules.backup \
  --project=your-project-id
```

**Verify:**
```bash
# Test in Rules Playground
# Confirm 1-to-1 calls still work
```

---

### SCENARIO 3: Partial Failure (Medium Severity)

**Examples:**
- Speaking detection not working
- Mute button issues
- UI glitches

**Recommended Actions:**

1. **Disable Affected Features Only**
   ```dart
   // Disable speaking detection
   const bool enableSpeakingDetection = false;
   ```

2. **Deploy Hotfix**
   - Create fix branch
   - Test thoroughly
   - Deploy gradual rollout

3. **Keep Core Functionality**
   - Audio transport still works
   - Basic join/leave works
   - Users can complete calls

---

### SCENARIO 4: Database Cleanup Needed

**Examples:**
- Stuck calls in Firestore
- Orphaned peer connections
- Corrupted call documents

**Cleanup Script:**

```javascript
// Run in Firebase Functions or Admin SDK
const admin = require('firebase-admin');
const db = admin.firestore();

async function cleanupStuckCalls() {
  const cutoff = Date.now() - (60 * 60 * 1000); // 1 hour ago
  
  const stuckCalls = await db.collection('groupCalls')
    .where('status', 'in', ['ringing', 'active'])
    .where('createdAt', '<', new Date(cutoff))
    .get();
  
  console.log(`Found ${stuckCalls.size} stuck calls`);
  
  const batch = db.batch();
  stuckCalls.forEach(doc => {
    batch.update(doc.ref, {
      status: 'ended',
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  
  await batch.commit();
  console.log('Cleanup complete');
}

cleanupStuckCalls();
```

---

## DATA MIGRATION (If Needed)

### Migrate Existing Group Call Documents

If you have Phase 1 group calls in Firestore without Phase 3 fields:

```javascript
// Migration script
async function migrateToPhase3() {
  const calls = await db.collection('groupCalls').get();
  
  const batch = db.batch();
  calls.forEach(doc => {
    const data = doc.data();
    
    // Add Phase 3 fields if missing
    const updates = {};
    
    if (!data.type) {
      updates.type = 'group_audio';
    }
    
    if (!data.speakingParticipants) {
      updates.speakingParticipants = [];
    }
    
    if (!data.maxParticipants) {
      updates.maxParticipants = 8;
    }
    
    if (Object.keys(updates).length > 0) {
      batch.update(doc.ref, updates);
    }
  });
  
  await batch.commit();
  console.log('Migration complete');
}

migrateToPhase3();
```

---

## COMMUNICATION PLAN

### Internal Team:

**Pre-Deployment:**
- [ ] Engineering team briefed
- [ ] QA team knows what to test
- [ ] Support team has FAQ document
- [ ] Monitoring on-call schedule set

**During Deployment:**
- [ ] Slack channel for real-time updates
- [ ] Status dashboard accessible
- [ ] Escalation path defined

**Post-Deployment:**
- [ ] Results summary shared
- [ ] Lessons learned documented
- [ ] Metrics report generated

### Users:

**Announcement:**
```
🎉 New Feature: Group Audio Calls!

Now you can start voice calls with your entire group.
Just tap the call button in any group chat!

Features:
✓ Crystal clear audio
✓ Up to 8 participants
✓ Simple controls
✓ Join anytime during call

Try it out and let us know what you think!
```

**Support Resources:**
- [ ] Help center article
- [ ] In-app tutorial (optional)
- [ ] FAQ document
- [ ] Support ticket category

---

## EMERGENCY CONTACTS

### On-Call Engineers:
- **Primary:** [Name] - [Phone] - [Email]
- **Secondary:** [Name] - [Phone] - [Email]

### Key Personnel:
- **Engineering Lead:** [Name] - [Contact]
- **Product Manager:** [Name] - [Contact]
- **DevOps:** [Name] - [Contact]

### Escalation Path:
1. On-call engineer (< 15 min)
2. Engineering lead (< 30 min)
3. CTO/VP Engineering (< 1 hour)

---

## SUCCESS CRITERIA

### Week 1:
- [ ] < 1% crash rate
- [ ] > 80% call completion rate
- [ ] < 5 critical bugs reported
- [ ] No security incidents
- [ ] Positive user feedback

### Week 2:
- [ ] Metrics stable
- [ ] All critical bugs fixed
- [ ] User adoption increasing
- [ ] Server costs within budget

### Week 4:
- [ ] Feature considered stable
- [ ] Documentation complete
- [ ] Team trained
- [ ] Ready for next phase

---

## LESSONS LEARNED TEMPLATE

### What Went Well:
- _______________
- _______________
- _______________

### What Could Be Improved:
- _______________
- _______________
- _______________

### Action Items:
- [ ] _______________
- [ ] _______________
- [ ] _______________

---

## APPENDIX: FILE CHANGES SUMMARY

### New Files Created:
```
lib/services/group_call_controller.dart (Phase 3 WebRTC)
lib/models/group_call_participant.dart
GROUP_AUDIO_PHASE_3_ARCHITECTURE.md
GROUP_AUDIO_PHASE_3_TEST_PLAN.md
GROUP_AUDIO_PHASE_3_MIGRATION.md
```

### Files Modified:
```
lib/services/group_call_service.dart (added type field, max limit)
lib/screens/calls/group_audio_call_screen.dart (full UI rebuild)
lib/providers/group_call_providers.dart (speaking state)
firebase/firestore.rules (max 8 participants, type validation)
```

### Files NOT Changed (Preserved):
```
lib/services/call_controller.dart (1-to-1 calls)
lib/services/call_service.dart (1-to-1 calls)
lib/screens/chat/call_screen.dart (1-to-1 voice)
lib/screens/chat/video_call_screen.dart (1-to-1 video)
lib/screens/chat/incoming_call_screen.dart (1-to-1)
```

---

**Migration Guide Version:** 1.0  
**Last Updated:** [Date]  
**Next Review:** [Date]
