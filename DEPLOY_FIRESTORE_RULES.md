# DEPLOY FIRESTORE RULES FOR PHASE 1.1

## ✅ Rules Updated

The Firestore rules have been updated to support:
- ✅ `groupCalls/` collection
- ✅ `groupCallInvitations/` collection
- ✅ Create, read, update permissions for group calls
- ✅ 8-participant limit enforcement
- ✅ Group membership verification

## 🚀 How to Deploy

### Option 1: Firebase Console (Recommended)

1. **Open Firebase Console**
   - Go to: https://console.firebase.google.com
   - Select your project

2. **Navigate to Firestore Rules**
   - Click "Firestore Database" in left sidebar
   - Click "Rules" tab at the top

3. **Copy & Paste Rules**
   - Open `firebase/firestore.rules`
   - Copy the entire content
   - Paste into the Firebase Console editor

4. **Publish Rules**
   - Click "Publish" button
   - Wait for confirmation (usually takes 1-2 seconds)

### Option 2: Firebase CLI

If you have Firebase CLI installed:

```bash
# From project root
cd firebase
firebase deploy --only firestore:rules
```

## 📋 New Rules Added

### 1. groupCalls Collection

**Permissions:**
- ✅ Create: Initiator + group member only
- ✅ Read: All group members
- ✅ Update: All group members (for join/leave/decline)
- ❌ Delete: Blocked (maintain history)

**Validations:**
- Maximum 8 joined participants
- Immutable fields: groupId, initiatorId, type
- Status must be: ringing | active | ended
- Type must be: group_audio

### 2. groupCallInvitations Collection

**Permissions:**
- ✅ Create: Inviter only
- ✅ Read: Target user + inviter
- ✅ Update: Target user only (accept/decline)
- ❌ Delete: Blocked

**Validations:**
- Status must be: pending | accepted | declined
- Has expiration timestamp
- Immutable fields: inviterId, targetUserId, callId

## 🧪 Test After Deployment

1. **Test Create Call**
   ```
   Tap science icon → Start Group Call
   Should succeed (no permission error)
   ```

2. **Test Read Call**
   ```
   Other users see the room appear
   Should succeed (real-time updates)
   ```

3. **Test Join Call**
   ```
   User taps "Join"
   Should succeed (no permission error)
   ```

4. **Test Decline Call**
   ```
   User taps "Decline"
   Should succeed (no permission error)
   ```

5. **Test Leave Call**
   ```
   User taps "Leave"
   Should succeed (no permission error)
   ```

## ⚠️ Important Notes

1. **Rules are in `firebase/firestore.rules`**
   - NOT in root directory
   - Path: `firebase/firestore.rules`

2. **Deploy affects PRODUCTION**
   - These rules will apply to live database
   - Test in development first if possible

3. **Rules take effect immediately**
   - No app restart needed
   - Changes apply to all users instantly

4. **Backup old rules**
   - Firebase Console keeps rule history
   - You can rollback if needed

## 🔍 Verify Deployment

After deploying, test with the app:

1. Open group chat
2. Tap science icon 🧪
3. Tap "Start Group Call"
4. Should succeed without permission error

If you still get permission errors:
- Wait 10 seconds (propagation delay)
- Check Firebase Console for any rule syntax errors
- Verify rules were published (look for timestamp)

## 📝 Rule Summary

```
groupCalls/{callId}
  ├─ create: initiator + group member
  ├─ read: all group members
  ├─ update: all group members
  └─ delete: blocked

groupCallInvitations/{invitationId}
  ├─ create: inviter only
  ├─ read: target + inviter
  ├─ update: target only
  └─ delete: blocked
```

## ✅ Success Criteria

After deployment, you should be able to:
- [x] Create group call without permission error
- [x] See call appear on other devices
- [x] Join call without permission error
- [x] Decline call without permission error
- [x] Leave call without permission error
- [x] See real-time participant updates

---

**Status:** 🟢 Rules ready to deploy  
**Action Required:** Deploy rules via Firebase Console or CLI
