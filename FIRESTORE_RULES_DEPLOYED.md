# ✅ Firestore Rules Updated

## Status: RULES UPDATED LOCALLY

The Firestore security rules have been updated to include the `calls` collection rules needed for Phase 1 Voice Call functionality.

---

## 📁 Files Updated

### 1. `firebase/firestore.rules` ✅
- Added complete calls collection security rules
- Location: Line 197-241 (before the "deny everything else" rule)

### 2. `firebase/firebase.rules` ✅
- Added complete calls collection security rules
- Location: Line 147-191 (before the "deny everything else" rule)

---

## 🔐 Rules Added

The following security rules were added for the `calls` collection:

```javascript
// ---------------- VOICE/VIDEO CALLS ----------------
match /calls/{callId} {
  
  function authed() {
    return request.auth != null;
  }
  
  function isCallerOrReceiver() {
    return authed() && (
      resource.data.callerId == request.auth.uid 
      || resource.data.receiverId == request.auth.uid
    );
  }
  
  function isCallerInNew() {
    return authed() && request.resource.data.callerId == request.auth.uid;
  }
  
  function callerIdImmutable() {
    return request.resource.data.callerId == resource.data.callerId;
  }
  
  function receiverIdImmutable() {
    return request.resource.data.receiverId == resource.data.receiverId;
  }
  
  // Allow users to create calls where they are the caller
  // Prevents impersonation and self-calling
  allow create: if authed() 
    && isCallerInNew()
    && request.resource.data.receiverId != request.auth.uid
    && request.resource.data.type in ['voice', 'video']
    && request.resource.data.status == 'ringing'
    && request.resource.data.createdAt is timestamp;
  
  // Allow caller and receiver to read the call
  allow read: if isCallerOrReceiver();
  
  // Allow caller and receiver to update call status
  // Ensure caller and receiver IDs cannot be changed
  allow update: if isCallerOrReceiver()
    && callerIdImmutable()
    && receiverIdImmutable()
    && request.resource.data.type == resource.data.type;
  
  // Prevent deletion to maintain call history/audit trail
  allow delete: if false;
}
```

---

## 🛡️ Security Features

### ✅ What These Rules Protect Against

1. **Impersonation Prevention**
   - Users can only create calls as themselves (callerId must match auth.uid)
   
2. **Self-Calling Prevention**
   - Users cannot call themselves (receiverId != callerId)

3. **Privacy Protection**
   - Only the caller and receiver can read/update call documents
   - Third parties are blocked from accessing calls

4. **Data Integrity**
   - Caller and receiver IDs cannot be changed after creation
   - Call type cannot be changed after creation
   - Calls cannot be deleted (maintains audit trail)

5. **Type Validation**
   - Only 'voice' and 'video' types are allowed
   - Status must be 'ringing' on creation
   - CreatedAt must be a valid timestamp

---

## 🚀 Deployment Steps

### Option 1: Firebase Console (Recommended)

1. **Open Firebase Console**
   ```
   https://console.firebase.google.com/
   ```

2. **Navigate to Firestore Rules**
   - Select your project
   - Go to "Firestore Database"
   - Click "Rules" tab

3. **Deploy Rules**
   - The rules are already in your local files
   - You have two options:

   **A. Use Firebase CLI** (if installed):
   ```bash
   cd modchat_updated
   firebase deploy --only firestore:rules
   ```

   **B. Copy/Paste to Console**:
   - Open `firebase/firestore.rules` in a text editor
   - Copy the entire content
   - Paste into Firebase Console Rules editor
   - Click "Publish"

4. **Wait for Propagation**
   - Rules take 1-2 minutes to propagate globally

---

### Option 2: Firebase CLI

If you have Firebase CLI installed:

```bash
# Navigate to project directory
cd modchat_updated

# Deploy rules
firebase deploy --only firestore:rules

# Or deploy all Firebase configs
firebase deploy
```

---

## ✅ Verification Steps

After deploying the rules:

### 1. Check Rules in Console
- Go to Firebase Console → Firestore → Rules
- Verify you see the "VOICE/VIDEO CALLS" section
- Check that it's before the "deny everything else" rule

### 2. Test Rules with Simulator
In Firebase Console:
1. Click "Rules" tab
2. Click "Rules Playground" (top right)
3. Test these scenarios:

**Test 1: Create Call (Should ALLOW)**
```
Operation: create
Location: /calls/testCallId
Authenticated: Yes (uid: user123)
Document data:
{
  "callerId": "user123",
  "receiverId": "user456",
  "type": "voice",
  "status": "ringing",
  "createdAt": [current timestamp]
}
```
Expected: ✅ ALLOW

**Test 2: Read Own Call (Should ALLOW)**
```
Operation: get
Location: /calls/testCallId
Authenticated: Yes (uid: user123)
Existing document:
{
  "callerId": "user123",
  "receiverId": "user456",
  ...
}
```
Expected: ✅ ALLOW

**Test 3: Read Others' Call (Should DENY)**
```
Operation: get
Location: /calls/testCallId
Authenticated: Yes (uid: user789)
Existing document:
{
  "callerId": "user123",
  "receiverId": "user456",
  ...
}
```
Expected: ❌ DENY

**Test 4: Create Call as Someone Else (Should DENY)**
```
Operation: create
Location: /calls/testCallId
Authenticated: Yes (uid: user123)
Document data:
{
  "callerId": "user456",  // Not the authenticated user!
  "receiverId": "user789",
  ...
}
```
Expected: ❌ DENY

### 3. Test with Real App
1. Run the app on two devices
2. Try to initiate a call
3. Check if incoming call appears
4. Verify status updates work

If any step fails, check:
- Rules are published
- 1-2 minutes have passed for propagation
- Firebase project is correct

---

## 🔍 Troubleshooting

### Issue: "Permission denied" when creating call

**Possible Causes:**
1. Rules not deployed yet
2. User not authenticated
3. CallerId doesn't match auth.uid
4. Missing required fields

**Solution:**
```javascript
// Check in your Flutter app:
final user = FirebaseAuth.instance.currentUser;
print('User: ${user?.uid}'); // Should not be null

// Check call document structure:
{
  "callerId": user.uid,  // Must match authenticated user
  "receiverId": "other_user_id",
  "type": "voice",  // Must be 'voice' or 'video'
  "status": "ringing",  // Must be 'ringing' on create
  "createdAt": FieldValue.serverTimestamp()  // Must be timestamp
}
```

### Issue: "Permission denied" when reading call

**Solution:**
- Verify the authenticated user is either the caller or receiver
- Check that the call document exists
- Ensure rules are deployed

### Issue: "Permission denied" when updating call

**Solution:**
- Don't try to change callerId or receiverId
- Don't try to change type
- Only update status, answeredAt, endedAt fields

---

## 📊 Rules Summary

| Operation | Who Can Do It | Conditions |
|-----------|---------------|------------|
| Create | Authenticated user | Must be caller, can't call self, valid fields |
| Read | Caller or Receiver | Must be participant in the call |
| Update | Caller or Receiver | Can't change IDs or type |
| Delete | No one | Prevented for audit trail |

---

## 📝 Next Steps

1. ✅ Rules updated locally (DONE)
2. ⏳ Deploy rules to Firebase (PENDING - Use steps above)
3. ⏳ Test with simulator (PENDING)
4. ⏳ Test with real app (PENDING)

---

## 📞 Support

If you encounter issues:
1. Check Firebase Console for error messages
2. Use Rules Playground to test specific scenarios
3. Verify user authentication state
4. Check document structure matches requirements

---

**Status**: ✅ Rules updated in local files  
**Action Required**: Deploy to Firebase Console or use Firebase CLI  
**Time to Deploy**: ~2 minutes  
**Time to Propagate**: ~1-2 minutes after deployment
