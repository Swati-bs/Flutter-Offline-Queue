import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/data_models.dart';
import 'hive_manager.dart';

/// Manages sync operations between local Hive and Firebase Firestore
///
/// Responsibilities:
/// - Process sync queue sequentially
/// - Handle CREATE_REPORT and MARK_IMPORTANT operations
/// - Implement idempotency to prevent duplicate writes
/// - Retry failed operations with exponential backoff
/// - Log all operations for observability
class SyncManager {
  final FirebaseFirestore _firestore;
  bool _isSyncing = false;

  // Configuration
  static const int maxRetries = 2;
  static const Duration backoffDuration1 = Duration(seconds: 1);
  static const Duration backoffDuration2 = Duration(seconds: 2);

  SyncManager({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Process all pending queue items
  ///
  /// Logs:
  /// - Queue size before processing
  /// - Each item being processed
  /// - Sync success/failure
  /// - Retry attempts
  Future<void> processQueue() async {
    // Prevent concurrent sync operations
    if (_isSyncing) {
      print('[SyncManager] Already syncing, skipping duplicate call');
      return;
    }

    _isSyncing = true;

    try {
      // Get all pending queue items from Hive
      final queueItems = HiveManager.getPendingQueueItems();

      print('[SyncManager] ▶️  Starting sync process');
      print('[SyncManager] 📊 Queue size: ${queueItems.length}');

      if (queueItems.isEmpty) {
        print('[SyncManager] ✅ Queue empty, nothing to sync');
        return;
      }

      int successCount = 0;
      int failureCount = 0;

      // Process each queue item sequentially
      for (final queueItemData in queueItems) {
        final queueItem = SyncQueueItem.fromJson(queueItemData);

        print(
          '[SyncManager] 🔄 Processing: ${queueItem.operationType.toString()} '
          'for report ${queueItem.reportId}',
        );

        try {
          // Attempt to sync this item
          await _syncItemToFirestore(queueItem);

          // Update report sync status in Hive to 'synced'
          await _updateReportSyncStatus(queueItem.reportId, 'synced');

          // Remove from queue on success
          await HiveManager.removeQueueItem(queueItem.id);

          print(
            '[SyncManager] ✅ Synced: ${queueItem.operationType.toString()} '
            'for ${queueItem.reportId}',
          );

          successCount++;
        } catch (e) {
          // Handle sync failure with retry logic
          await _handleSyncFailure(queueItem, e);

          // Update report sync status in Hive to 'failed'
          await _updateReportSyncStatus(queueItem.reportId, 'failed');

          failureCount++;
        }
      }

      // Log final results
      print('[SyncManager] ✅ Sync completed');
      print(
          '[SyncManager] 📈 Results: $successCount succeeded, $failureCount retried/failed');
      print(
          '[SyncManager] 📊 Remaining queue: ${HiveManager.syncQueueBox.length} items');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync a single queue item to Firestore
  ///
  /// Implements:
  /// - Idempotency check (via custom document field)
  /// - CREATE and MARK_IMPORTANT operations
  /// - Atomic write via Firestore transaction
  Future<void> _syncItemToFirestore(SyncQueueItem queueItem) async {
    final reportId = queueItem.reportId;
    final docRef = _firestore.collection('reports').doc(reportId);

    try {
      // Use Firestore transaction for atomic writes
      await _firestore.runTransaction((transaction) async {
        // For idempotency, check if we've already written this operation
        // by storing the idempotency key with the document
        final snapshot = await transaction.get(docRef);

        if (snapshot.exists) {
          final existingData = snapshot.data() as Map<String, dynamic>;
          final existingIdempotencyKey = existingData['_idempotencyKey'];

          // If idempotency key matches, operation was already processed
          if (existingIdempotencyKey == queueItem.idempotencyKey) {
            print(
              '[SyncManager] ⚡ Idempotent: Operation already synced for $reportId '
              '(key: ${queueItem.idempotencyKey})',
            );
            return; // Idempotent success - don't rewrite
          }
        }

        // Prepare data with idempotency key
        // Note: We update syncStatus to 'synced' here since we're successfully syncing
        final dataToWrite = {
          ...queueItem.data,
          'syncStatus': 'synced', // Override to synced since we're successfully writing
          '_idempotencyKey': queueItem.idempotencyKey,
          '_lastSyncTime': FieldValue.serverTimestamp(),
        };

        // Write to Firestore (merge: true to preserve other fields)
        transaction.set(docRef, dataToWrite, SetOptions(merge: true));

        print(
          '[SyncManager] 💾 Written to Firestore: $reportId '
          '(operation: ${queueItem.operationType.toString()})',
        );
      });
    } catch (e) {
      print('[SyncManager] ❌ Firestore write error: $e');
      rethrow;
    }
  }

  /// Update report sync status in Hive
  Future<void> _updateReportSyncStatus(String reportId, String status) async {
    final reportData = HiveManager.reportsBox.get(reportId);
    if (reportData != null) {
      final updatedData = Map<String, dynamic>.from(reportData as Map);
      final oldStatus = updatedData['syncStatus'];
      updatedData['syncStatus'] = status;
      await HiveManager.reportsBox.put(reportId, updatedData);
      print('[SyncManager] 📝 Updated report $reportId sync status: $oldStatus → $status');
    } else {
      print('[SyncManager] ⚠️  Report $reportId not found in Hive for status update');
    }
  }

  /// Handle sync failure with retry logic
  ///
  /// Retry logic:
  /// - 1st attempt fails → Retry after 1 second
  /// - 2nd attempt fails → Retry after 2 seconds
  /// - 3rd attempt fails → Mark as failed, keep in queue
  Future<void> _handleSyncFailure(
      SyncQueueItem queueItem, dynamic error) async {
    final reportId = queueItem.reportId;
    final currentAttempts = queueItem.syncAttempts;

    print(
      '[SyncManager] ⚠️  Sync failed for $reportId '
      '(attempt ${currentAttempts + 1}/$maxRetries): $error',
    );

    if (currentAttempts < maxRetries) {
      // Schedule retry with exponential backoff
      final backoffDuration =
          currentAttempts == 0 ? backoffDuration1 : backoffDuration2;

      final nextRetryTime = DateTime.now().add(backoffDuration);

      // Update queue item with retry info
      final updatedQueueItem = SyncQueueItem(
        id: queueItem.id,
        reportId: queueItem.reportId,
        operationType: queueItem.operationType,
        data: queueItem.data,
        idempotencyKey: queueItem.idempotencyKey,
        enqueuedAt: queueItem.enqueuedAt,
        syncAttempts: currentAttempts + 1,
        status: 'retry',
        nextRetryTime: nextRetryTime,
        errorMessage: error.toString(),
      );

      // Update in Hive
      await HiveManager.updateQueueItem(updatedQueueItem);

      print(
        '[SyncManager] 🔄 Retry scheduled: $reportId '
        'in ${backoffDuration.inSeconds}s (attempt ${currentAttempts + 1}/$maxRetries)',
      );
    } else {
      // Max retries exceeded - mark as failed
      final failedQueueItem = SyncQueueItem(
        id: queueItem.id,
        reportId: queueItem.reportId,
        operationType: queueItem.operationType,
        data: queueItem.data,
        idempotencyKey: queueItem.idempotencyKey,
        enqueuedAt: queueItem.enqueuedAt,
        syncAttempts: currentAttempts + 1,
        status: 'failed',
        nextRetryTime: null,
        errorMessage: error.toString(),
      );

      // Update in Hive
      await HiveManager.updateQueueItem(failedQueueItem);

      print(
        '[SyncManager] ❌ Max retries exceeded: $reportId '
        '(${currentAttempts + 1} attempts). Marked as failed.',
      );
    }
  }

  /// Check if there are retry items ready to sync
  ///
  /// Used by caller to periodically retry failed items
  /// Items with status='retry' and nextRetryTime <= now are ready
  Future<bool> hasReadyRetryItems() async {
    final retryItems = HiveManager.getRetryReadyQueueItems();
    return retryItems.isNotEmpty;
  }

  /// Process only retry items that are ready
  ///
  /// Call this periodically (e.g., every 5 seconds) to retry failed items
  /// whose backoff period has expired
  Future<void> processRetryQueue() async {
    final retryItems = HiveManager.getRetryReadyQueueItems();

    if (retryItems.isEmpty) {
      return;
    }

    print('[SyncManager] 🔄 Processing ${retryItems.length} retry item(s)');

    for (final queueItemData in retryItems) {
      final queueItem = SyncQueueItem.fromJson(queueItemData);

      print(
        '[SyncManager] Retrying: ${queueItem.operationType.toString()} '
        'for ${queueItem.reportId}',
      );

      try {
        await _syncItemToFirestore(queueItem);
        await _updateReportSyncStatus(queueItem.reportId, 'synced');
        await HiveManager.removeQueueItem(queueItem.id);
        print('[SyncManager] ✅ Retry succeeded: ${queueItem.reportId}');
      } catch (e) {
        print(
          '[SyncManager] ⚠️  Retry failed: ${queueItem.reportId} - $e',
        );
        await _handleSyncFailure(queueItem, e);
        await _updateReportSyncStatus(queueItem.reportId, 'failed');
      }
    }
  }

  /// Force process a specific queue item (manual retry)
  ///
  /// Useful for user-initiated sync after addressing an issue
  Future<void> retryQueueItem(String queueItemId) async {
    final queueItemData = HiveManager.getQueueItemById(queueItemId);

    if (queueItemData == null) {
      print('[SyncManager] ❌ Queue item not found: $queueItemId');
      return;
    }

    final queueItem = SyncQueueItem.fromJson(queueItemData);

    print(
      '[SyncManager] 🔄 Manual retry initiated: ${queueItem.reportId}',
    );

    try {
      await _syncItemToFirestore(queueItem);
      await _updateReportSyncStatus(queueItem.reportId, 'synced');
      await HiveManager.removeQueueItem(queueItem.id);
      print('[SyncManager] ✅ Manual retry succeeded: ${queueItem.reportId}');
    } catch (e) {
      print(
        '[SyncManager] ⚠️  Manual retry failed: ${queueItem.reportId} - $e',
      );
      await _handleSyncFailure(queueItem, e);
      await _updateReportSyncStatus(queueItem.reportId, 'failed');
    }
  }

  /// Get current queue statistics
  ///
  /// Useful for UI display and monitoring
  Map<String, dynamic> getQueueStats() {
    final allItems = HiveManager.syncQueueBox.values.toList();
    final pendingItems = HiveManager.getPendingQueueItems();
    final retryItems = HiveManager.syncQueueBox.values
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) => item['status'] == 'retry')
        .toList();
    final failedItems = HiveManager.syncQueueBox.values
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) => item['status'] == 'failed')
        .toList();

    return {
      'total': allItems.length,
      'pending': pendingItems.length,
      'retry': retryItems.length,
      'failed': failedItems.length,
      'isSyncing': _isSyncing,
    };
  }

  /// Log current queue status
  ///
  /// Useful for debugging and observability
  void logQueueStatus() {
    final stats = getQueueStats();
    print('[SyncManager] 📊 Queue Status:');
    print('    Total: ${stats['total']}');
    print('    Pending: ${stats['pending']}');
    print('    Retry: ${stats['retry']}');
    print('    Failed: ${stats['failed']}');
    print('    Syncing: ${stats['isSyncing']}');
  }
}
