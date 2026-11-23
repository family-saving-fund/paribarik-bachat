# Insurance safety update — deployment checklist

The Dart changes now use Firestore transactions for annual claim reservations and the shared insurance-fund balance. **Do not release the APK until the migration and Firestore Rules updates below are completed.** The source ZIP cannot publish Firestore Rules to the Firebase project.

## 1. Back up Firestore first

Create/export a fresh Firestore backup before running the migration.

## 2. Initialize the aggregate documents once

Run in Google Cloud Shell, authenticated to project `paribarik-bachat-kosh`:

```bash
python3 -m pip install --user firebase-admin
gcloud auth application-default login
python3 tools/initialize_insurance_aggregates.py
```

Review every printed annual total and the insurance-fund balance against existing records. The script never overwrites an aggregate document that already exists. If an aggregate exists but is incorrect, stop and reconcile it manually before continuing.

## 3. Add Firestore Rules

Merge these matches inside the existing `match /databases/{database}/documents` block. Keep the project's existing `isAdmin()` and `request.auth != null` helpers. Do not replace the complete Rules file with this fragment.

```javascript
match /insurance_fund_state/{stateId} {
  allow read: if request.auth != null;
  allow create, update: if isAdmin()
    && stateId == 'current'
    && request.resource.data.balance is number
    && request.resource.data.revision is int;
  allow delete: if false;
}

match /insurance_annual_limits/{limitId} {
  allow read: if isAdmin()
    || (request.auth != null && resource.data.uid == request.auth.uid);

  // A first-ever claim in a new BS financial year creates its reservation
  // and claim document in the same transaction.
  allow create: if (isAdmin()
      && request.resource.data.lastAction == 'initialize'
      && request.resource.data.uid is string
      && request.resource.data.reservedAmount is number
      && request.resource.data.reservedAmount >= 0
      && request.resource.data.reservedAmount <= 100000)
    || (request.auth != null
    && request.resource.data.uid == request.auth.uid
    && request.resource.data.reservedAmount is number
    && request.resource.data.reservedAmount > 0
    && request.resource.data.reservedAmount <= 100000
    && request.resource.data.lastAction == 'reserve'
    && request.resource.data.lastClaimId is string
    && getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.uid == request.auth.uid
    && getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.status == 'pending'
    && request.resource.data.reservedAmount == getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.insuranceAmount);

  // Members can only increase their own reservation by the exact amount of
  // the pending claim created in the same transaction. Admin can only release
  // the exact reservation for a claim rejected in the same transaction.
  allow update: if (
      request.auth != null
      && resource.data.uid == request.auth.uid
      && request.resource.data.uid == resource.data.uid
      && request.resource.data.lastAction == 'reserve'
      && request.resource.data.reservedAmount <= 100000
      && request.resource.data.reservedAmount == resource.data.reservedAmount
        + getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.insuranceAmount
      && getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.uid == request.auth.uid
      && getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.status == 'pending'
    ) || (
      isAdmin()
      && request.resource.data.uid == resource.data.uid
      && request.resource.data.lastAction == 'release'
      && request.resource.data.reservedAmount >= 0
      && resource.data.reservedAmount - request.resource.data.reservedAmount
        == getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.insuranceAmount
      && getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.uid == resource.data.uid
      && getAfter(/databases/$(database)/documents/insurance_claims/$(request.resource.data.lastClaimId)).data.status == 'rejected'
    );

  allow delete: if false;
}
```

For legacy approved claims whose annual aggregate was not present, the migration script creates the reservation document before the new app is released. The app's payout transaction can initialize a missing aggregate for an older approved claim, but the preferred path is to run the migration first.

Also strengthen the existing `insurance_claims` create rule so a member can create only their own pending claim, with `expenseAmount > 5000`, `insuranceAmount == expenseAmount * 0.20`, `claimAmount == insuranceAmount`, and `paymentStatus == 'unpaid'`. Keep admin-only update/delete permissions already present. The annual-limit rule above checks that the claim and reservation are committed together.

## 4. Publish and verify

1. Publish the merged Firestore Rules.
2. Verify a member can submit a valid claim and the annual aggregate rises by exactly the claim amount.
3. Verify a second claim that would exceed Rs. 100,000 is rejected.
4. Verify family and self claims use the same UID aggregate.
5. Reject a pending claim and verify the reserved amount falls by exactly that claim amount.
6. Approve a claim and verify the reservation remains unchanged.
7. Approve a monthly payment/donation and verify `insurance_fund_state/current.balance` rises by the insurance portion.
8. Pay an approved claim and verify the balance falls by the payout amount while retaining Rs. 5,000.

## Important limitation

The code and migration script are included in this ZIP, but Firebase Rules are deployed remotely and cannot be published from this source-editing session. A 100% production verification also requires running the app against the project's real Firestore rules and checking the seven cases above. Do not treat the ZIP alone as proof that the remote project has been updated.
