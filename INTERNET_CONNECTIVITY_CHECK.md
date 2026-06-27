# 🌐 INTERNET CONNECTIVITY TROUBLESHOOTING

## ❌ CURRENT ERROR

```
Unable to resolve host "firestore.googleapis.com": No address associated with hostname
```

**Translation:** Your device cannot reach Firebase servers.

---

## ✅ STEP-BY-STEP FIX

### Step 1: Basic Internet Check (2 min)

**On your Android device:**

1. Open Chrome or any browser
2. Go to: `https://www.google.com`
3. Does it load?
   - ✅ YES → Internet works, proceed to Step 2
   - ❌ NO → Fix internet first (see below)

### Step 2: Check Firebase Connectivity (1 min)

**On your Android device:**

1. Open Chrome
2. Go to: `https://firestore.googleapis.com`
3. You should see either:
   - Error 404 (this is GOOD - means you reached Firebase)
   - Or some Google error page (also GOOD)
   - Connection timeout or DNS error (BAD - Firebase is blocked)

### Step 3: Restart Everything (5 min)

1. **Close your app completely**
2. **Restart your Android device**
   - Power off
   - Wait 10 seconds
   - Power on
3. **Reconnect to WiFi**
4. **Test browser again** (Step 1)
5. **Run app again**

---

## 🔧 IF INTERNET DOESN'T WORK

### Option A: WiFi Issues

**If connected to WiFi but no internet:**

1. Go to Settings → WiFi
2. Forget current network
3. Reconnect with password
4. Test browser

**Or try:**
- Restart WiFi router
- Use different WiFi network
- Switch to mobile data instead

### Option B: Mobile Data Issues

**If using mobile data:**

1. Go to Settings → Mobile Network
2. Toggle "Mobile Data" off/on
3. Check if airplane mode is off
4. Test browser

### Option C: Network Restrictions

**Some networks block Firebase:**

- School/University WiFi → often blocks Firebase
- Corporate WiFi → may have firewall rules
- Public WiFi → may have restrictions
- VPN → may interfere

**Solutions:**
- Use your phone's mobile data (4G/5G)
- Use personal hotspot
- Use home WiFi
- Disable VPN if using one

---

## 🔍 VERIFY FIX WORKED

### After restoring internet:

1. Open your app
2. Look for these logs in console:

**GOOD SIGNS:**
```
[SIGNAL] LISTENER_STARTED
[SIGNAL] CURRENT_USER: xxx
```

**NO MORE:**
```
Unable to resolve host "firestore.googleapis.com"
```

3. Try sending a test signal
4. Look for:
```
[SIGNAL] VERIFIED_IN_FIRESTORE
```

**If you see this → Internet is working!**

---

## 🚨 STILL NOT WORKING?

### Check Android Permissions

1. Go to: Settings → Apps → ModChat
2. Check "Network Permissions"
3. Ensure "WiFi" and "Mobile Data" allowed

### Check Firestore Rules

Run this command to verify rules are deployed:

```bash
firebase deploy --only firestore:rules
```

### Check Firebase Project

1. Go to Firebase Console
2. Verify your project exists
3. Check Firestore is enabled
4. Check Authentication is enabled

---

## 📋 CHECKLIST BEFORE TESTING

- [ ] Device has internet connection (browser works)
- [ ] Can reach google.com in browser
- [ ] WiFi/mobile data is on
- [ ] Airplane mode is off
- [ ] VPN is disabled (if any)
- [ ] App has network permissions
- [ ] Device was restarted
- [ ] App was fully closed and reopened

**Once ALL checked → Test signal again**

---

## 💡 QUICK TEST

Want to verify Firebase works before testing signals?

1. Open app
2. Log in
3. Go to any chat
4. Send a message
5. Does it send?
   - ✅ YES → Firebase works, signal test should work
   - ❌ NO → Internet issue, fix connectivity first

---

**Bottom line:** The code is working. Your device just needs internet.
