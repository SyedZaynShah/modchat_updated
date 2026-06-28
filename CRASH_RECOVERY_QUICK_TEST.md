# CRASH RECOVERY - QUICK TEST

**Time**: 10 minutes  
**Goal**: Prove crash recovery works

---

## THE BUG (Before Fix)

1. Call someone, accept
2. Force stop app during call
3. Reopen app
4. Try to call again
5. **ERROR**: "Finish call first" 🚨

---

## THE FIX (After Implementation)

Same steps, but now:
- Cleanup runs automatically on login
- Stale call marked as 'ended'
- New call works ✅

---

## QUICK TEST

### Step 1: Create Stale Call (2 min)

**Device A**:
1. Call Device B (voice call)
2. Device B accepts
3. Talk for 10 seconds
4. **Force stop app** (Settings → Apps → ModChat → Force Stop)

**Result**: Call document stuck with status='accepted'

---

### Step 2: Verify Cleanup (2 min)

**Device A**:
1. **Reopen app**
2. **Watch console** immediately
3. Should see:
   ```
   [AuthGate] User logged in, running stale call cleanup...
   [CallRecovery] Starting stale call cleanup...
   [CallRecovery] 🚨 Found 1 stale accepted call(s)
   [CallRecovery] ✅ Cleaned up 1 stale accepted call(s)
   ```

---

### Step 3: Verify Recovery (1 min)

**Device A**:
1. Try to call Device B again
2. **Expected**: ✅ Call goes through (NO ERROR)

**If you see "Finish call first"**: Cleanup didn't work 🚨

---

### Step 4: Check Debug Screen (2 min)

**Device A**:
1. Open Settings
2. Scroll down
3. Tap "Call Debug (Dev)"
4. **Expected**: "No active calls found 🎉"

**If you see active calls**: Cleanup missed some 🚨

---

## WHAT TO CHECK

### ✅ Success Indicators
- Console shows cleanup logs
- New calls work after crash
- Debug screen shows clean state
- No "Finish call first" errors

### 🚨 Failure Indicators
- No console logs
- Still getting "Finish call first"
- Debug screen shows stale calls
- Calls still blocked

---

## OPTIONAL: Test Debug Screen Features

### Force End Test (2 min)
1. Start call (don't accept, leave ringing)
2. Open Call Debug screen
3. See active call listed
4. Tap "Force End"
5. Confirm
6. **Expected**: Call ends, screen refreshes

### Stale Detection Test (5 min)
1. Create stale call (force stop during call)
2. **Immediately** open debug screen
3. See call (green background)
4. Wait 5+ minutes
5. Refresh
6. **Expected**: Call now RED with "STALE" warning

---

## CONSOLE LOGS YOU SHOULD SEE

### On Login (Every Time)
```
[AuthGate] User logged in, running stale call cleanup...
[CallRecovery] Starting stale call cleanup for user: ...
[CallRecovery] Checking for stale ACCEPTED calls...
[CallRecovery] Checking for stale CALLING/RINGING calls...
[CallRecovery] ✅ Cleanup complete
```

### With Stale Calls Found
```
[CallRecovery] 🚨 Found 2 stale accepted call(s)
[CallRecovery] 📞 Call abc123:
[CallRecovery]    Status: accepted
[CallRecovery]    Age: 120 minutes
[CallRecovery]    🧹 Cleaning up...
[CallRecovery]    ✅ Marked as ended
[CallRecovery] ✅ Cleaned up 2 stale accepted call(s)
```

---

## QUICK TROUBLESHOOTING

### "I don't see console logs"
- Rebuild app: `flutter clean && flutter run`
- Check you're watching correct device
- Make sure you're logged in

### "Cleanup runs but calls still blocked"
- Check Firestore Console directly
- Verify documents have status='ended'
- Try manual "Force End" in debug screen

### "Debug screen shows empty but still blocked"
- Check if you're looking at correct user
- Verify Firebase Auth user matches
- Check Firestore rules (should allow read)

---

## SUCCESS = MOVE FORWARD

**If all tests pass**:
- ✅ Crash recovery works
- ✅ 1-to-1 system is stable
- ✅ Ready to investigate echo
- ✅ Ready to verify incoming calls
- ✅ Ready to build group calling (after other fixes)

**If any test fails**:
- 🚨 Fix this FIRST
- Don't proceed to group calls
- Share logs for diagnosis

---

## THE GOAL

**Prove your 1-to-1 call system can recover from crashes.**

That's it. Simple goal. Critical requirement.

Once this works, we can tackle:
1. Echo investigation
2. Incoming call reliability
3. Group calling

But THIS must work first.

---

**Ready to test? Let's go! 🚀**
