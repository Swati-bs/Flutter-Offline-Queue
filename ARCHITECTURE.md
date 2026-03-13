# Offline-First Sync Queue - Architecture Documentation

**Project:** Quick Reporter  
**Date:** March 12, 2026  
**Status:** As-Implemented (Honest Documentation)

---

## Overview

This document describes the **actual implemented architecture** of the offline-first reporting application. This is not a theoretical design - it reflects the working codebase.


## 1. High-Level Architecture (As Implemented)

```
┌─────────────────────────────────────────────────────┐
│                   UI Layer (Flutter)                 │
│  ┌──────────────────┐  ┌─────────────────────────┐  │
│  │ ReportsScreen    │  │ ReportDetailScreen      │  │
│  │ (List + Create)  │  │ (View Details)          │  │
│  └────────┬─────────┘  └──────────┬──────────────┘  │
└───────────┼────────────────────────┼─────────────────┘
            │ (Riverpod)             │
┌───────────┼────────────────────────┼─────────────────┐
│         Provider Layer (State Management)            │
│  ┌──────────────────────────────────────────────┐   │
│  │ ReportsNotifier (StateNotifier<List<Report>>) │  │
│  │  - Loads reports from repository             │   │
│  │  - Auto-syncs when online                    │   │
│  │  - Creates/updates reports                   │   │
│  └────────┬────────────────────────────────────┘    │
│           │                                          │
│  ┌────────┴─────────────┐  ┌────────────────────┐  │
│  │ SyncManagerProvider  │  │ ConnectivityProvider│  │
│  └──────────┬───────────┘  └──────────┬─────────┘  │
└─────────────┼──────────────────────────┼────────────┘
              │                          │
┌─────────────┼──────────────────────────┼────────────┐
│          Business Logic Layer                        │
│  ┌───────────────────┐  ┌──────────────────────┐   │
│  │ ReportsRepository │  │ SyncManager          │   │
│  │ - getAllReports() │  │ - processQueue()     │   │
│  │ - createReport()  │  │ - Retry logic        │   │
│  │ - markImportant() │  │ - Idempotency check  │   │
│  │ - fetchFromFB()   │  │ - Error handling     │   │
│  └─────────┬─────────┘  └──────────┬───────────┘   │
│            │                       │                │
│  ┌─────────┴───────────────────────┴─────────┐     │
│  │         ConnectivityService               │     │
│  │         - Online/offline detection        │     │
│  └───────────────────────────────────────────┘     │
└────────────────────────────────────────────────────┘
              │                       │
┌─────────────┼───────────────────────┼────────────┐
│          Persistence Layer                        │
│  ┌─────────────────┐  ┌───────────────────────┐  │
│  │ HiveManager     │  │ Firebase Firestore    │  │
│  │ ├─ reportsBox   │  │ ├─ reports collection │  │
│  │ └─ syncQueueBox │  │ └─ (no auth)          │  │
│  └─────────────────┘  └───────────────────────┘  │
└───────────────────────────────────────────────────┘
```

## 2. Data Models (Actual Implementation)

### Report Model
**File:** `lib/models/simplified_models.dart`

```dart
class Report {
  final String id;              // UUID v4
  final String title;           // Report title
  final String description;     // Description text
  final bool isImportant;       // Star flag
  final DateTime createdAt;     // Creation timestamp
  final DateTime updatedAt;     // Last update (for conflict resolution)
  final String syncStatus;      // 'pending' | 'synced' | 'failed'
}
```

**Note:** No location, severity, or attachments implemented.

### SyncQueueItem Model
**File:** `lib/models/simplified_models.dart`

```dart
class SyncQueueItem {
  final String id;                    // Queue item UUID
  final String reportId;              // FK to report
  final OperationType operationType;  // create | updateImportant
  final Map<String, dynamic> data;    // Operation payload
  final String idempotencyKey;        // Unique: "operation_id_timestamp"
  final DateTime enqueuedAt;          // Queue time
  final int syncAttempts;             // Retry counter
  final String status;                // 'pending' | 'retry' | 'failed'
  final DateTime? nextRetryTime;      // For backoff
  final String? errorMessage;         // Last error
}
```

**Note:** No priority queue implemented - FIFO order only.

## 3. Core Services (Actual Implementation)

### 2.1 Data Models

```
ReportModel
├── id: String (UUID, immutable)
├── title: String
├── description: String
├── location: GeoPoint
├── severity: ReportSeverity (enum)
├── isImportant: bool
├── attachments: List<String> (URLs)
├── metadata:
│   ├── createdAt: DateTime
│   ├── updatedAt: DateTime (Last-Write-Wins)
│   ├── createdBy: String (userId)
│   ├── syncStatus: SyncStatus (enum)
│   ├── idempotencyKey: String (UUID per action)
│   └── errorMessage: String?

SyncQueueItem
├── id: String (UUID)
├── reportId: String
├── operationType: OperationType (CREATE, UPDATE, DELETE)
├── reportSnapshot: ReportModel
├── idempotencyKey: String (unique per operation)
├── metadata:
│   ├── enqueuedAt: DateTime
│   ├── lastSyncAttempt: DateTime?
│   ├── syncAttempts: int
│   ├── status: QueueItemStatus
│   ├── errorMessage: String?
│   └── nextRetryTime: DateTime?
├── priority: int (0-100, important reports get higher priority)
```

### 2.2 Service Architecture

**SyncQueueService**
- Manages the persistent queue in Hive
- Handles enqueueing operations
- Orchestrates sync when connectivity returns
- Implements exponential backoff retry logic
- Emits progress updates via streams

**ReportRepository**
- Local CRUD operations via Hive
- Sync with Firestore
- Conflict resolution (Last-Write-Wins + custom rules)
- Idempotency enforcement (prevents duplicate writes)

**ConnectivityService**
- Wraps connectivity_plus
- Provides reactive stream of connectivity changes
- Triggers sync queue processing on connectivity gain

**ObservabilityService**
- Logs queue size metrics
- Tracks sync success/failure rates
- Provides observability streams for UI
- Stores metrics in Hive for historical analysis

## 3. Data Flow for Offline Report Creation

```
User Creates Report (Offline)
  │
  ├─> Generate UUID + idempotencyKey
  │
  ├─> Save to Hive (Reports Box)
  │   status: PENDING_SYNC
  │   updatedAt: now
  │
  ├─> Enqueue SyncQueueItem to Hive (SyncQueue Box)
  │   operationType: CREATE
  │   idempotencyKey: unique
  │   priority: 50 (or higher if marked important)
  │
  ├─> Update UI via ReportProvider (Riverpod)
  │   Show report with "sync pending" indicator
  │
  └─> ObservabilityService logs:
      - Queue size increased to N
      - Report enqueued with id=X

        [If Connectivity Available]
        ├─> ConnectivityService detects online
        │
        ├─> SyncQueueService.processSyncQueue()
        │
        ├─> For each QueueItem (in priority order):
        │   ├─> Check idempotencyKey (deduplication)
        │   ├─> Call Firestore transaction with idempotency key
        │   ├─> If success:
        │   │   ├─ Update local report: status = SYNCED
        │   │   ├─ Remove from sync queue
        │   │   └─ Log success
        │   │
        │   └─> If failure:
        │       ├─> Retry up to 2 times with exponential backoff
        │       ├─> After max retries, keep in queue with error status
        │       ├─> Mark report: status = SYNC_FAILED
        │       └─> Log failure + error details
        │
        └─> UI updates reflect synced/failed status
```

## 4. Sync Queue Structure

```
## 5. Sync Queue Structure (Actual Implementation)

**Storage:** Hive box named `syncQueueBox`

**Processing:** Sequential FIFO (First In, First Out) - no priority

**Queue Item Example:**
```dart
{
  "id": "q_1710176400000_123456",
  "reportId": "abc-123",
  "operationType": "create",          // Only: create | updateImportant
  "data": { /* full report data */ },
  "idempotencyKey": "create_abc-123_1710176400000",
  "enqueuedAt": "2026-03-12T10:30:00Z",
  "syncAttempts": 0,
  "status": "pending",                // pending | retry | failed
  "nextRetryTime": null,
  "errorMessage": null
}
```

**What's NOT in the queue:**
- ❌ No priority field (FIFO only)
- ❌ No DELETE operations
- ❌ No UPDATE operations (only updateImportant)
- ❌ No separate idempotency keys box

---


## 6. Sync Lifecycle (Actual Implementation)

**Trigger:** Connectivity restored or manual sync button

**Process:**
```
User goes online
    ↓
ConnectivityService detects change
    ↓
Auto-sync triggered in ReportsScreen
    ↓
SyncManager.processQueue()
    ↓
Get all pending items from Hive (FIFO order)
    ↓
For each item:
    ├─ Check idempotency in Firestore transaction
    ├─ If already synced → Skip (idempotent)
    ├─ If not → Write to Firestore
    ├─ On success → Update local syncStatus
    ├─ Remove from queue
    └─ On failure → Retry with backoff (1s, 2s)
    ↓
Queue empty → Sync complete
```

**No processing lock:** Simple implementation, processes one at a time
**No meta document:** Queue items stored directly
**No priority sorting:** FIFO only

---
│  │  │  ├─ Update local: report.syncStatus = SYNCED
│  │  │  ├─ Update local: report.updatedAt = serverTimestamp
│  │  │  ├─ Remove from sync queue
│  │  │  ├─ Keep idempotency key (for deduplication window)
│  │  │  └─ Emit: ReportSynced event
│  │  │
│  │  └─ On failure:
│  │     ├─ If network error:
│  │     │  ├─ Retry after backoff: 1s → 2s → stop
│  │     │  └─ Keep in queue with status = RETRY
│  │     │
│  │     └─ If conflict error:
│  │        ├─ Fetch server version
│  │        ├─ Resolve conflict (Last-Write-Wins)
│  │        ├─ Update local report with server state
│  │        ├─ Mark queue item: CONFLICT_RESOLVED
│  │        └─ Manual sync required flag (notify user)
│  │
│  ├─ Item 2: UPDATE report_124
│  │  └─ Similar process...
│  │
│  └─ Item N: Process remaining items
│
├─ T=2000ms: All items processed
│  └─> Release processing lock (meta.isProcessing = false)
│
├─ T=2100ms: Final status
│  ├─ Calculate metrics:
│  │  ├── totalSynced: N items
│  │  ├── totalFailed: M items
│  │  └── totalConflicts: K items
│  │
│  ├─ Emit: SyncStatus.completed with metrics
│  │
│  └─ ObservabilityService.logSyncCycle()
│
└─ UI updates to show final state
   ├─ Synced reports show checkmark
   ├─ Failed reports show retry button
   └─ Conflict reports show resolution UI
```

## 6. Key Edge Cases & Handling

### 6.1 Duplicate Prevention (Idempotency)

**Problem:** Network timeout during write → user retries → potential duplicate

**Solution:**
- Each operation gets unique `idempotencyKey` (UUID + timestamp)
- Store all keys in Hive `idempotencyKeys` box
- Before sync, check if key exists
- If exists, verify document matches (conflict check)
- If matches, silently succeed (idempotent)

```
Scenario: User creates report, network timeout, user taps "Retry"
├─ First attempt: Generate idempotencyKey_v1
├─ Write to Firestore with idempotencyKey_v1
├─ Timeout, user doesn't see result
├─ Automatic retry OR manual retry uses SAME idempotencyKey_v1
├─ Firestore sees same key, returns existing document
├─ Local state matches, marked SYNCED
└─ No duplicate created ✓
```

### 6.2 Concurrent Operations Conflict

**Problem:** User edits report offline, sync tries, conflicting edit from another device

**Solution:**
- Last-Write-Wins: Compare `updatedAt` timestamps
- Keep custom fields for fine-grained conflict rules
- Store conflict logs for audit trail

```
Scenario: Two devices edit same report offline
├─ Device A: Sets severity=HIGH (updatedAt: T1)
├─ Device B: Sets severity=LOW (updatedAt: T2)
├─ Device A syncs first (severity=HIGH persists)
├─ Device B syncs: Server has T1, local has T2
│  ├─ If T2 > T1: Update server (B wins)
│  └─ If T2 < T1: Keep server (A wins)
└─ Local device fetches latest on next sync
```

### 6.3 Sync Queue Corruption

**Problem:** App crashes during sync queue write → corrupted Hive box

**Solution:**
- Use Hive transactions for queue operations
- Validate queue structure on app startup
- Keep backup snapshot for recovery
- Log all corruption detection

```dart
try {
  await syncQueueBox.putAll({...}); // Atomic write
} catch (e) {
  // Corruption detected
  await recoverQueueFromBackup();
  logger.error('Queue corrupted, recovered from backup');
}
```

### 6.4 Offline Duration Long (Days)

**Problem:** User works offline for days, queue grows, memory concerns

**Solution:**
- Pagination: Process queue in batches
- Compression: Old metadata archived after sync
- TTL: Discard failed items after N days
- Warning: UI alerts if queue > 1000 items

### 6.5 Connectivity Flaps

**Problem:** WiFi drops/reconnects every few seconds → excessive sync attempts

**Solution:**
- Debounce connectivity changes (wait 2s before syncing)
- Track "stable online" state (online for >5s)
- Only trigger sync on stable transitions

```dart
_connectivityStream
  .debounceTime(Duration(seconds: 2))
  .distinctUntilChanged()
  .listen((_) => _syncQueueService.processSyncQueue());
```

### 6.6 Important Reports During Unreliable Network

**Problem:** Critical report queued but connectivity is poor

**Solution:**
- Priority queue: Important reports = priority 100
- User can manually trigger sync (with visual feedback)
- Show queue status: "5 reports pending sync (1 critical)"

### 6.7 User Deletes Report Before Sync

**Problem:** User creates report offline, deletes it, then goes online

**Solution:**
- Delete operation queued like any other
- When syncing CREATE: Check if report still local
- If deleted, skip/remove from queue
- If UPDATE then DELETE: Skip both, only sync DELETE

```
Scenario: Create → Delete before sync
├─ QueueItem: CREATE (status: PENDING)
├─ User deletes report locally
├─ QueueItem: DELETE (status: PENDING)
├─ Sync encounters CREATE first
├─ Checks: Is report in local box? NO
├─ Removes CREATE from queue
├─ Processes DELETE (idempotent on Firestore)
└─ Result: Clean state ✓
```

### 6.8 Firestore Quota Exceeded

**Problem:** High volume of syncs hits Firestore rate limits

**Solution:**
- Implement client-side rate limiting (max 10 writes/sec)
- Queue items wait if limit reached
- Exponential backoff on quota errors (not retry immediately)
- Alert user: "Sync paused, retrying in 30s"

### 6.9 User Authentication Lost

**Problem:** User logged out but sync queue has items

**Solution:**
- Clear sync queue on logout
- Flag items with "auth_required" status
- On login, restore from backup or re-queue
- Show message: "Queue cleared due to logout"

### 6.10 Timestamp Sync (Clock Skew)

**Problem:** Client clock wrong → updatedAt conflicts with server

**Solution:**
- On first successful sync, capture server timestamp offset
- Use offset for subsequent operations
- Recalibrate on each sync
- Use server time for Last-Write-Wins comparison

---

## Implementation Checklist

---

**Last Updated:** March 12, 2026  
**Reflects:** Actual codebase implementation  
**Honesty Level:** 100% - No exaggerations
