import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/data_models.dart';
import '../services/hive_manager.dart';

/// Repository for managing reports
/// Handles offline-first operations
class ReportsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch reports from Firebase and update local cache
  Future<void> fetchReportsFromFirebase() async {
    try {
      if (kDebugMode) {
        print('[ReportsRepository] 🔄 Starting Firebase fetch...');
        print('[ReportsRepository] 📡 Querying Firestore collection: reports');
      }

      final snapshot = await _firestore
          .collection('reports')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Firebase fetch timed out after 10 seconds');
            },
          );

      if (kDebugMode) {
        print('[ReportsRepository] 📥 Fetched ${snapshot.docs.length} reports from Firebase');
      }

      // Get all Firebase report IDs
      final firebaseReportIds = snapshot.docs.map((doc) => doc.id).toSet();

      // Get all local report IDs
      final localReportIds = HiveManager.reportsBox.keys.cast<String>().toSet();

      // Find reports that exist locally but not in Firebase (deleted reports)
      final deletedReportIds = localReportIds.difference(firebaseReportIds);

      // Remove deleted reports from local cache
      if (deletedReportIds.isNotEmpty) {
        if (kDebugMode) {
          print('[ReportsRepository] 🗑️  Found ${deletedReportIds.length} reports deleted from Firebase');
        }

        for (final deletedId in deletedReportIds) {
          await HiveManager.reportsBox.delete(deletedId);
          if (kDebugMode) {
            print('[ReportsRepository] 🗑️  Removed deleted report from cache: $deletedId');
          }
        }
      }

      if (snapshot.docs.isEmpty) {
        if (kDebugMode) {
          print('[ReportsRepository] ℹ️  No reports found in Firebase');
        }
        return;
      }

      // Update local cache with fetched reports
      int cachedCount = 0;
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();

          // Create Report object from Firebase data
          final report = Report(
            id: doc.id,
            title: data['title'] ?? '',
            description: data['description'] ?? '',
            isImportant: data['isImportant'] ?? false,
            createdAt: data['createdAt'] != null
                ? DateTime.parse(data['createdAt'])
                : DateTime.now(),
            updatedAt: data['updatedAt'] != null
                ? DateTime.parse(data['updatedAt'])
                : DateTime.now(),
            syncStatus: data['syncStatus'] ?? 'synced', // Already in Firebase, so it's synced
          );

          // Save to local Hive cache
          await HiveManager.reportsBox.put(report.id, report.toJson());
          cachedCount++;

          if (kDebugMode) {
            print('[ReportsRepository] 💾 Cached report ${cachedCount}/${snapshot.docs.length}: ${report.title}');
          }
        } catch (docError) {
          if (kDebugMode) {
            print('[ReportsRepository] ⚠️  Error processing document ${doc.id}: $docError');
          }
          // Continue with other documents
        }
      }

      if (kDebugMode) {
        print('[ReportsRepository] ✅ Successfully cached $cachedCount/${snapshot.docs.length} reports');
        print('[ReportsRepository] 📊 Local cache now has ${HiveManager.reportsBox.length} total reports');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ReportsRepository] ❌ Error fetching reports from Firebase: $e');
        print('[ReportsRepository] Stack trace: ${StackTrace.current}');
      }
      // Rethrow to let caller handle
      rethrow;
    }
  }
  /// Get all reports from local cache
  List<Report> getAllReports() {
    final reportsData = HiveManager.getAllReports();
    final reports = reportsData.map((data) => Report.fromJson(data)).toList();

    // Debug: Log sync status of all reports
    if (kDebugMode) {
      for (final report in reports) {
        print('[ReportsRepository] Report ${report.id.substring(0, 8)}: ${report.title} - syncStatus: ${report.syncStatus}');
      }
    }

    return reports;
  }

  /// Create a new report (offline-first)
  Future<Report> createReport({
    required String title,
    required String description,
  }) async {
    final now = DateTime.now();
    final report = Report(
      id: const Uuid().v4(),
      title: title,
      description: description,
      isImportant: false,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );

    // Save to local cache
    await HiveManager.reportsBox.put(report.id, report.toJson());

    // Create queue item for sync
    final idempotencyKey = 'create_${report.id}_${now.millisecondsSinceEpoch}';
    final queueItem = SyncQueueItem(
      id: 'q_${now.millisecondsSinceEpoch}_${report.id.hashCode}',
      reportId: report.id,
      operationType: OperationType.create,
      data: report.toJson(),
      idempotencyKey: idempotencyKey,
      enqueuedAt: now,
      syncAttempts: 0,
      status: 'pending',
    );

    await HiveManager.syncQueueBox.add(queueItem.toJson());

    if (kDebugMode) {
      print('[ReportsRepository] ✓ Created report: ${report.id} (${report.title})');
      print('[ReportsRepository] ✓ Queued for sync: $idempotencyKey');
    }

    return report;
  }

  /// Mark report as important (offline-first)
  Future<Report> markImportant(String reportId, bool important) async {
    final reportData = HiveManager.reportsBox.get(reportId);
    if (reportData == null) {
      throw Exception('Report not found: $reportId');
    }

    final reportMap = Map<String, dynamic>.from(reportData as Map);
    final report = Report.fromJson(reportMap);
    final now = DateTime.now();

    final updatedReport = report.copyWith(
      isImportant: important,
      updatedAt: now,
      syncStatus: 'pending',
    );

    // Save to local cache
    await HiveManager.reportsBox.put(reportId, updatedReport.toJson());

    // Create queue item for sync
    final idempotencyKey = 'update_${reportId}_${now.millisecondsSinceEpoch}';
    final queueItem = SyncQueueItem(
      id: 'q_${now.millisecondsSinceEpoch}_${reportId.hashCode}',
      reportId: reportId,
      operationType: OperationType.updateImportant,
      data: {'isImportant': important, 'updatedAt': now.toIso8601String()},
      idempotencyKey: idempotencyKey,
      enqueuedAt: now,
      syncAttempts: 0,
      status: 'pending',
    );

    await HiveManager.syncQueueBox.add(queueItem.toJson());

    if (kDebugMode) {
      print('[ReportsRepository] ✓ Updated report: $reportId (important=$important)');
      print('[ReportsRepository] ✓ Queued for sync: $idempotencyKey');
    }

    return updatedReport;
  }

  /// Get pending queue size
  int getPendingQueueSize() {
    return HiveManager.getPendingQueueItems().length;
  }

  /// Get all queue items (for debugging)
  List<SyncQueueItem> getAllQueueItems() {
    return HiveManager.syncQueueBox.values
        .map((data) => SyncQueueItem.fromJson(data))
        .toList();
  }
}

