# 🔬 MINIMAL SIGNAL TEST

## 🎯 OBJECTIVE

**Prove signal delivery works between two devices.**

Nothing else. No features. No complexity.

---

## 📱 WHAT YOU NEED

- **2 Devices** (Device A and Device B)
- **2 Accounts** (already logged in)

---

## ⚡ 3-MINUTE TEST

### Step 1: Open Signal Test on Both Devices (1 min)

**Device A:**
1. Open app
2. Tap menu (⋮) in top right
3. Tap "🔧 Signal Test"
4. You'll see your User ID

**Device B:**
1. Open app
2. Tap menu (⋮) in top right  
3. Tap "🔧 Signal Test"
4. You'll see your User ID

### Step 2: Copy User ID from Device B (30 sec)

**On Device B:**
1. Tap the copy icon next to your User ID
2. User ID copied to clipboard

### Step 3: Send Signal from Device A (30 sec)

**On Device A:**
1. Paste Device B's User ID into the text field
2. Press "SEND TEST SIGNAL" button
3. You should see "Signal sent: xxx"

### Step 4: Check Device B (1 min)

**On Device B:**
- ✅ Dialog should appear automatically
- ✅ Dialog shows "TEST SIGNAL RECEIVED"
- ✅ Shows Signal ID
- ✅ Shows sender info

**Tap OK to dismiss**

---

## ✅ SUCCESS CRITERIA

**If dialog appeared on Device B:** ✅ **SIGNAL DELIVERY WORKS**

**If NO dialog:** ❌ **SIGNAL DELIVERY BROKEN** - See troubleshooting

---

## 🔍 CONSOLE LOGS

### Device A (Sender):
```
[SIGNAL] =================================
[SIGNAL] SENDING TEST SIGNAL
[SIGNAL] =================================
[SIGNAL] CREATED
[SIGNAL] SENDER: {userA}
[SIGNAL] TARGET_USER: {userB}
[SIGNAL] SIGNAL_ID: {signalId}
[SIGNAL] VERIFIED_IN_FIRESTORE
```

### Device B (Receiver):
```
[SIGNAL] LISTENER_STARTED
[SIGNAL] CURRENT_USER: {userB}
[SIGNAL] SNAPSHOT_TRIGGERED
[SIGNAL] Document count: 1
[SIGNAL] DOC_FOUND
[SIGNAL] signalId={signalId}
[SIGNAL] targetUserId={userB}
[SIGNAL] received=false
[SIGNAL] SHOWING_DIALOG for {signalId}
```

### After tapping OK:
```
[SIGNAL] ACK_SENT for {signalId}
[SIGNAL] ACK_UPDATED
[SIGNAL] ACK_VERIFIED: received=true
```

---

## 🐛 TROUBLESHOOTING

### Problem: No dialog on Device B

**Check Console on Device B:**

1. **Is listener started?**
   - Look for `[SIGNAL] LISTENER_STARTED`
   - If missing → listener not starting

2. **What's the current user?**
   - Look for `[SIGNAL] CURRENT_USER: xxx`
   - Copy this ID

3. **Did snapshot trigger?**
   - Look for `[SIGNAL] SNAPSHOT_TRIGGERED`
   - If missing → Firestore listener not working

4. **Document count?**
   - Look for `Document count: X`
   - If 0 → Signal not reaching device

5. **targetUserId matches?**
   - Look for `[SIGNAL] targetUserId=xxx`
   - Must match CURRENT_USER

**Check Console on Device A:**

1. **Was signal created?**
   - Look for `[SIGNAL] CREATED`
   - Look for `[SIGNAL] VERIFIED_IN_FIRESTORE`
   - If missing → Signal not created

2. **Copy the SIGNAL_ID**
   - Look for `[SIGNAL] SIGNAL_ID: xxx`

3. **Check Firebase Console**
   - Go to Firestore
   - Look for collection: `groupCallSignals`
   - Find document with that SIGNAL_ID
   - Verify `targetUserId` matches Device B

### Problem: Listener Error

**Check Console on Device B:**
- Look for `[SIGNAL] ❌ LISTENER_ERROR:`
- This means query failed
- Check Firestore rules deployed

### Problem: Create Failed

**Check Console on Device A:**
- Look for `[SIGNAL] ❌ CREATE_FAILED:`
- Check Firestore rules
- Check internet connection

---

## 🔥 FIREBASE CONSOLE

### Check Signal Document

1. Go to Firebase Console
2. Firestore → groupCallSignals
3. Find your signal document

**Should look like:**
```javascript
{
  senderId: "userA",
  targetUserId: "userB",
  createdAt: Timestamp,
  received: false  // or true after acknowledged
}
```

**Verify:**
- `targetUserId` matches Device B's User ID
- `senderId` matches Device A's User ID
- `received` is false (before OK) or true (after OK)

---

## 🎯 REPEAT TEST

**Run this test 10 times in a row.**

If it works all 10 times: ✅ Signal delivery is reliable

If it fails even once: ❌ Not reliable - debug first

---

## 📊 TEST LOG

Date: ___________

| Attempt | Worked? | Notes |
|---------|---------|-------|
| 1       | ☐ Yes ☐ No | |
| 2       | ☐ Yes ☐ No | |
| 3       | ☐ Yes ☐ No | |
| 4       | ☐ Yes ☐ No | |
| 5       | ☐ Yes ☐ No | |
| 6       | ☐ Yes ☐ No | |
| 7       | ☐ Yes ☐ No | |
| 8       | ☐ Yes ☐ No | |
| 9       | ☐ Yes ☐ No | |
| 10      | ☐ Yes ☐ No | |

**Result:** _____ / 10 successful

---

## ✅ NEXT STEP

**If 10/10 successful:**
- Signal delivery is proven
- Can proceed to build invitation system
- Foundation is solid

**If < 10/10:**
- DO NOT proceed
- Find exact failure point
- Fix before building on top

---

## 🚫 WHAT THIS DOES NOT TEST

- Group calls
- Multiple participants
- Acceptance/decline logic
- Call screens
- WebRTC
- Audio
- Video

**This only tests:** ONE signal from A to B

**That's the point.** Prove the simplest case first.

---

**Start testing. Prove signal delivery. Then build on top.**
