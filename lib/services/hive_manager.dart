import 'package:hive_flutter/hive_flutter.dart';

/// Simple Hive initialization
/// 2 boxes: reports and sync_queue
class HiveManager {
  static late Box reportsBox;
  static late Box syncQueueBox;

  static Future<void> initialize() async {
    await Hive.initFlutter();

    reportsBox = await Hive.openBox('reports');
    syncQueueBox = await Hive.openBox('sync_queue');

    print('[HiveManager] ✓ Initialized');
    print('[HiveManager] Reports: ${reportsBox.length} items');
    print('[HiveManager] SyncQueue: ${syncQueueBox.length} items');
  }

  static Future<void> close() async {
    await Hive.close();
  }

  /// Get all reports from Hive
  static List<Map<String, dynamic>> getAllReports() {
    return reportsBox.values
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  /// Get queue items that need syncing
  static List<Map<String, dynamic>> getPendingQueueItems() {
    return syncQueueBox.values
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) {
          final status = item['status'] as String?;
          return status == 'pending';
        })
        .toList();
  }

  /// Get queue items that are ready for retry
  static List<Map<String, dynamic>> getRetryQueueItems() {
    return syncQueueBox.values
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) {
          final status = item['status'] as String?;
          if (status != 'retry') return false;

          // Check if ready for retry (nextRetryTime passed)
          final nextRetryStr = item['nextRetryTime'] as String?;
          if (nextRetryStr == null) return true; // No time set, ready now

          final nextRetryTime = DateTime.parse(nextRetryStr);
          return DateTime.now().isAfter(nextRetryTime);
        })
        .toList();
  }

  /// Get retry items that are ready to sync now
  static List<Map<String, dynamic>> getRetryReadyQueueItems() {
    return getRetryQueueItems();
  }

  /// Remove a queue item after successful sync
  static Future<void> removeQueueItem(String queueItemId) async {
    // Find the index of the item with matching id
    final keys = syncQueueBox.keys.toList();
    for (final key in keys) {
      final item = syncQueueBox.get(key);
      if (item != null && item['id'] == queueItemId) {
        await syncQueueBox.delete(key);
        return;
      }
    }
  }

  /// Update a queue item (for retries, failures)
  static Future<void> updateQueueItem(dynamic queueItem) async {
    final queueItemId = queueItem.id;
    
    // Find the index of the item with matching id
    final keys = syncQueueBox.keys.toList();
    for (final key in keys) {
      final item = syncQueueBox.get(key);
      if (item != null && item['id'] == queueItemId) {
        await syncQueueBox.put(key, queueItem.toJson());
        return;
      }
    }
    
    // If not found, add as new item
    await syncQueueBox.add(queueItem.toJson());
  }

  /// Get a specific queue item by id
  static Map<String, dynamic>? getQueueItemById(String queueItemId) {
    final keys = syncQueueBox.keys.toList();
    for (final key in keys) {
      final item = syncQueueBox.get(key);
      if (item != null) {
        final itemMap = Map<String, dynamic>.from(item as Map);
        if (itemMap['id'] == queueItemId) {
          return itemMap;
        }
      }
    }
    return null;
  }

  /// Clear all data (useful for logout)
  static Future<void> clearAll() async {
    await reportsBox.clear();
    await syncQueueBox.clear();
    print('[HiveManager] ✓ Cleared all data');
  }
}

/*
HIVE BOX STRUCTURE:

📦 reports (Box<Map<String, dynamic>>)
   Key: report.id (UUID string)
   Value: {
     'id': '550e8400-e29b...',
     'title': 'Pothole detected',
     'description': 'Large hole in road...',
     'isImportant': false,
     'createdAt': '2026-03-11T14:30:00.000Z',
     'updatedAt': '2026-03-11T14:30:00.000Z',
     'syncStatus': 'pending',  // pending | synced | failed
     'errorMessage': null
   }

📦 sync_queue (Box<Map<String, dynamic>>)
   Key: queue_item.id (UUID string)
   Value: {
     'id': 'abc123...',
     'reportId': '550e8400-e29b...',
     'operationType': 'OperationType.create',
     'data': {...full report JSON...},
     'idempotencyKey': 'create_550e8400_1710176400000',
     'enqueuedAt': '2026-03-11T14:30:00.000Z',
     'syncAttempts': 0,
     'status': 'pending',  // pending | retry | synced | failed
     'nextRetryTime': null,
     'errorMessage': null
   }

IDEMPOTENCY STRATEGY:
  - Each operation gets unique idempotencyKey
  - Format: "create_reportId_timestamp" or "update_reportId_timestamp"
  - On sync: Check if key exists in Firestore
  - If exists: Idempotent success (no rewrite)
  - If not: Execute write and store key

LAST-WRITE-WINS:
  - Compare updatedAt timestamps
  - Newer timestamp is authoritative
  - Automatic resolution during sync
*/
