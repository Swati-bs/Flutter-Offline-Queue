# AI Prompt Log

## Summary
This project was built with AI assistance to demonstrate offline-first architecture in Flutter. Below is a log of key prompts, responses, and decisions made.

---

## 1. Initial Architecture Design

**Prompt:**
```
Design a Flutter offline-first sync queue system for a reports app:
- Use Hive for local storage
- Firebase Firestore as backend
- Riverpod for state management
- Support offline writes (create report, mark important)
- Implement retry with backoff
- Add idempotency to prevent duplicates
- Use last-write-wins for conflicts
```

**AI Response Summary:**
- Suggested repository pattern with clear separation of concerns
- Recommended two Hive boxes: one for reports, one for sync queue
- Proposed idempotency key format: `"operation_reportId_timestamp"`
- Suggested SyncManager to process queue sequentially
- Recommended connectivity service to trigger sync

**Decision:** ✅ **Accepted**

**Why:**
- Clean architecture, easy to test
- Separation between data and queue makes sense
- Idempotency strategy is simple and effective

---

## 2. Data Models Design

**Prompt:**
```
Design data models for:
1. Report (id, title, description, isImportant, timestamps, syncStatus)
2. SyncQueueItem (operation type, payload, idempotency key, retry info)
```

**AI Response Summary:**
- Report model with syncStatus enum (pending/synced/failed)
- SyncQueueItem with operationType enum (create/updateImportant)
- Include retry tracking: attempts, nextRetryTime, errorMessage
- Store full report snapshot in queue for reliability

**Decision:** ✅ **Accepted**

**Why:**
- Comprehensive models cover all edge cases
- Retry tracking enables exponential backoff
- Storing snapshot ensures queue is self-contained

---

## 3. Idempotency Implementation

**Prompt:**
```
How to implement idempotency in Firestore to prevent duplicate writes on retry?
```

**AI Response Summary:**
- Store `_idempotencyKey` field in Firestore document
- Use Firestore transaction to check key before writing
- If key exists, skip write (idempotent success)
- If not, execute write and store key

**Decision:** ✅ **Accepted**

**Why:**
- Leverages Firestore's ACID transactions
- Simple to implement
- Handles all retry scenarios correctly

**Code snippet:**
```dart
if (existingIdempotencyKey == queueItem.idempotencyKey) {
  return; // Already synced, skip
}
transaction.set(docRef, {...data, '_idempotencyKey': key});
```

---

## 4. Retry Strategy with Backoff

**Prompt:**
```
Implement retry logic with exponential backoff.
Requirements:
- Max 2 retries (3 total attempts)
- Backoff delays: 1s, 2s
- Keep failed items in queue for manual retry
```

**AI Response Summary:**
- Track syncAttempts in queue item
- Calculate nextRetryTime = now + backoff
- Update queue item status to 'retry'
- After max retries, mark as 'failed' but keep in queue

**Decision:** ✅ **Modified**

**Why:**
- Used fixed delays (1s, 2s) instead of pure exponential
- Simpler and more predictable for demo
- Still demonstrates backoff concept

**Change:**
- Original suggestion: `2^attempt` seconds
- Modified to: Fixed 1s, 2s for first two retries

---

## 5. Conflict Resolution Strategy

**Prompt:**
```
Compare conflict resolution strategies:
1. Last-Write-Wins
2. Operational Transform
3. Three-Way Merge

Which is best for a reports app?
```

**AI Response Summary:**
- **Last-Write-Wins:** Simple, uses timestamps, potential data loss
- **Operational Transform:** Complex, real-time collab, overkill
- **Three-Way Merge:** Needs base version, medium complexity

Recommended: Last-Write-Wins for this use case

**Decision:** ✅ **Accepted**

**Why:**
- Reports app is typically single-user
- Conflicts are rare
- Simplicity > complexity for demo
- Easy to explain in interview

---


## Summary of AI Usage

### What AI Did Well ✅
1. **Architecture design** - Clean, production-like patterns
2. **Edge case identification** - Caught retry, idempotency, persistence issues
3. **Code generation** - Boilerplate code for models, services
4. **Documentation** - Suggested comprehensive README structure

### What I Modified 🔧
1. **Simplified debouncing** - Removed 2s delay for connectivity
2. **Fixed backoff delays** - Used 1s, 2s instead of exponential
3. **Removed some features** - Kept scope manageable for assignment
4. **Improved logging** - Added more detailed console output

### What I Rejected ❌
1. **Complex merge strategies** - Stuck with Last-Write-Wins
2. **Background workers** - Avoided native code complexity
3. **Authentication** - Out of scope for demo

---

## Verification

### How I Validated AI Suggestions
1. **Tested offline scenarios** - Created reports offline, verified persistence
2. **Tested retry logic** - Simulated failures, checked backoff timing
3. **Tested idempotency** - Manually triggered duplicate syncs, verified no duplicates
4. **Checked logs** - Verified all operations produce expected console output
5. **App restart** - Confirmed queue persists across restarts

### Issues Found & Fixed
1. **Initial connectivity API mismatch** - AI used old API, I updated to List<ConnectivityResult>
2. **Missing error handling** - Added try-catch around sync operations
3. **UI refresh** - Added manual refresh after sync completes

---

## Conclusion

**AI was 85% helpful:**
- ✅ Architecture and design decisions
- ✅ Code structure and patterns
- ✅ Edge case thinking
- 🔧 Needed adjustments for current Flutter APIs
- 🔧 Needed simplification for assignment scope

---

**Total time saved by AI: ~6 hours** (would have taken 10-12 hours from scratch)
**Actual implementation time: 4-5 hours** (including this documentation)
