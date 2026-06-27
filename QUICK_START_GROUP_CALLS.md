# 🚀 Quick Start: Group Calling

## ⚡ 5-Minute Test Guide

Everything is implemented and ready. Follow these steps to test group calling immediately.

---

## 📱 Prerequisites (2 minutes)

1. **Two Devices/Emulators**
   - Device A with Account 1
   - Device B with Account 2

2. **One Group Chat**
   - Create or use existing group
   - Both accounts must be members
   - Group must have 2-6 total members

3. **Network**
   - Both devices connected to internet
   - WiFi or mobile data (WiFi recommended for testing)

---

## 🧪 Basic Test (3 minutes)

### Step 1: Start Call (Device A)

1. Open the app, login as Account 1
2. Navigate to a group chat
3. Look at top-right corner → **See phone icon** ✓
4. Tap the phone icon
5. **Expected:** Navigate to call screen
6. **Expected:** Status shows "Ringing..." or "Connecting..."
7. **Expected:** Your name shows with "Host" badge

✅ **Success:** Call created without errors

### Step 2: Join Call (Device B)

1. Open the app on Device B, login as Account 2
2. Navigate to the **same group chat**
3. Tap the phone icon (top-right)
4. **Expected:** Navigate to call screen
5. **Expected:** See Account 1 already in call
6. **Expected:** Audio connection establishes

✅ **Success:** Second participant joined

### Step 3: Test Audio

1. **On Device A:** Speak into microphone
2. **On Device B:** Should hear Account 1's voice
3. **On Device B:** Speak into microphone
4. **On Device A:** Should hear Account 2's voice

✅ **Success:** Bidirectional audio working

### Step 4: End Call

1. **Either device:** Tap "End Call" button (red)
2. **Expected:** Return to group chat
3. **Other device:** Should see participant leave
4. **Last person:** Tap "End Call"
5. **Expected:** Call status changes to "ended"

✅ **Success:** Call lifecycle complete

---

## 🎯 What You Just Tested

✅ **Call Button** - Visible in group chat AppBar  
✅ **Call Creation** - No permission errors  
✅ **Participant Invitation** - All members invited  
✅ **Join Existing Call** - No duplicate call created  
✅ **Audio Transmission** - WebRTC mesh working  
✅ **Call Termination** - Clean cleanup  

**Total Test Time:** ~3 minutes  
**Result:** Fully functional group calling system

---

## 🔧 Optional: Advanced Tests (5 minutes)

### Test Mute

1. During call, tap "Mute" button
2. Speak
3. Other participant should NOT hear
4. Tap "Mute" again
5. Speak
6. Other participant SHOULD hear

### Test Speaker

1. Tap "Speaker" button
2. Audio should route to speaker
3. Tap again
4. Audio should route to earpiece

### Test 3+ Participants

1. Start call on Device A
2. Join on Device B
3. Join on Device C (if available)
4. All should see each other
5. All should hear each other

### Test Host Transfer

1. Start call with 3+ participants
2. Original host leaves
3. Check who has "Host" badge now
4. Should be next participant

### Test Privacy Settings (Optional)

1. Go to Group Settings → Permissions
2. Manually add to Firestore: `settings.permissions.membersCanStartCalls = false`
3. Login as regular member
4. Tap call button
5. Should see error: "You do not have permission..."
6. Login as admin/owner
7. Tap call button
8. Should work normally

---

## ❌ Common Issues & Fixes

### Issue: "Permission Denied" Error

**Fix 1:** Verify Firestore rules deployed
```bash
cd /path/to/modchat_updated
firebase deploy --only firestore:rules --project modchat-f6594
```

**Fix 2:** Verify you're a group member
- Open Firebase Console
- Check `dmChats/{groupId}.members` contains your UID

### Issue: Can't Hear Audio

**Fix 1:** Check microphone permissions
- Android: Settings → Apps → ModChat → Permissions → Microphone
- iOS: Settings → ModChat → Microphone

**Fix 2:** Try toggling mute
- Tap mute button twice

**Fix 3:** Check speaker is on
- Tap speaker button to toggle

### Issue: Call Button Not Visible

**Check 1:** Are you in a GROUP chat?
- Call button only appears in group chats (not 1-to-1 DMs)

**Check 2:** Verify group type
- Open Firestore Console
- Check `dmChats/{chatId}.type == 'group'`

### Issue: Can't Join Call

**Check 1:** Is there an active call?
- Open Firestore Console
- Check `groupCalls` collection for document with your groupId
- Verify `status == 'ringing'` or `'active'`

**Check 2:** Are you in participants list?
- In the call document, check `participants` array contains your UID

---

## 🎉 Success! What Next?

If all tests passed, your group calling implementation is working perfectly!

### Next Steps:

1. **Test with Real Users**
   - Have actual users try the feature
   - Gather feedback on audio quality
   - Test on different networks (WiFi, 4G, 5G)

2. **Monitor Performance**
   - Check Firebase usage in console
   - Monitor bandwidth during calls
   - Test with 6 participants (maximum)

3. **Optional Enhancements**
   - Add video support
   - Implement call recording
   - Add screen sharing
   - Show active call indicator in group list
   - Add call history to Calls tab

4. **Production Deployment**
   - Update app version
   - Write release notes mentioning group calling
   - Notify users of new feature

---

## 📊 Expected Results Summary

| Test | Expected Result | Status |
|------|----------------|--------|
| See call button | ✓ Phone icon in AppBar | ⬜ |
| Start call | ✓ Navigate to call screen | ⬜ |
| Join call | ✓ Second user joins | ⬜ |
| Audio works | ✓ Hear each other | ⬜ |
| Mute works | ✓ Silence/resume audio | ⬜ |
| Host badge | ✓ Shows on initiator | ⬜ |
| Host transfer | ✓ New host when original leaves | ⬜ |
| Call ends | ✓ Clean termination | ⬜ |
| No duplicates | ✓ Join existing vs create new | ⬜ |
| Permissions | ✓ No Firebase errors | ⬜ |

**Mark each as you test:** Change ⬜ to ✅

---

## 🆘 Need Help?

### Check Logs

**Android (via ADB):**
```bash
adb logcat | grep -i "GroupCall"
```

**Flutter Console:**
Look for these messages:
```
[GroupCallService] ✅ Call created: <callId>
[GroupCallController] 🎤 Initializing local audio stream
[GroupCallController] ✅ Local stream initialized
[GroupCallController] 🔗 Creating peer connection for <userId>
```

### Check Firebase Console

1. **Firestore Database:**
   - Collections → `groupCalls`
   - Find your call document
   - Verify structure matches expected

2. **Security Rules:**
   - Firestore → Rules tab
   - Verify last deployment timestamp is recent

3. **Usage Statistics:**
   - Check read/write counts
   - Verify no permission-denied errors

### Documentation

- **Full Implementation:** See `PHASE_4.1_COMPLETE.md`
- **Detailed Tests:** See `test_group_calling.md` (12 test scenarios)
- **Verification:** See `IMPLEMENTATION_VERIFICATION.md`

---

## ✅ Ready to Go!

Your group calling feature is **fully implemented** and **ready to test**.

**Time to first call:** < 1 minute  
**Setup complexity:** Zero (already done)  
**Expected errors:** None

**Just open the app and tap the phone icon!** 🎉
