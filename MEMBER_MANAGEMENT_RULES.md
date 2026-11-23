# Admin Member Management — Firestore Rules Note

The new Admin > सदस्य व्यवस्थापन screen lists member documents and edits only optional profile fields. It deliberately does **not** change or delete the member's Firebase Authentication account, UID, name, email, role, or member number.

Before using the Edit/Save feature, merge the following additional condition into the existing `match /member/{uid}` block's `allow update` rules. Do not replace the existing member rules. Multiple `allow update` statements are OR-combined by Firestore Rules.

```javascript
allow update: if isAdmin()
  && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
    'mobileNumber',
    'dateOfBirth',
    'address',
    'occupation',
    'citizenshipNumber',
    'familyMembers',
    'profileUpdatedAt',
    'adminProfileUpdatedAt'
  ]);
```

Keep the existing member-self update rule and all existing protections for `name`, `email`, `role`, UID, and account creation/deletion. Publish the merged Rules in Firebase Console before expecting Admin profile edits to save. If your current helper is not named `isAdmin()`, use the exact admin-check helper already present in your deployed Rules.


## Read access required by these screens

The Admin member directory needs Admin read access to `member` documents. Add the following inside the existing `match /member/{uid}` block if Admin list/read is not already allowed:

```javascript
allow read: if isAdmin() || (request.auth != null && request.auth.uid == uid);
```

The member's insurance history reads only their own payout records. Add the following inside the existing `match /insurance_claim_payments/{paymentId}` block if member self-read is not already allowed:

```javascript
allow read: if isAdmin()
  || (request.auth != null && resource.data.uid == request.auth.uid);
```

These are additive permissions; merge them into the existing match blocks and retain the existing create/update restrictions. Do not replace the full Firestore Rules file with this note.
