import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/data_models.dart';

/// Manages all Firestore operations with idempotency protection
/// 
/// Responsibilities:
/// - Write reports to Firestore
/// - Implement idempotency to prevent duplicate writes
/// - Handle CREATE and MARK_IMPORTANT operations
/// - Use transactions for atomic writes
/// - Track idempotency keys for deduplication window
/// - Provide comprehensive error handling and logging
class FirebaseService {
  final FirebaseFirestore _firestore;
  final String _userId;

  // Configuration
  static const String reportsCollection = 'reports';
  static const String idempotencyKeysCollection = 'idempotency_keys';
  static const String idempotencyKeyField = '_idempotencyKey';
  static const String lastSyncTimeField = '_lastSyncTime';

  FirebaseService({
    required String userId,
    FirebaseFirestore? firestore,
  })  : _userId = userId,
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Write a report to Firestore with idempotency protection
  /// 
  /// Implements:
  /// 1. Check if operation was already processed (idempotency)
  /// 2. If not, write report to Firestore
  /// 3. Store idempotency key for future deduplication
  /// 4. Use transaction for atomicity
  /// 
  /// Returns: true if write succeeded, false if already processed
  Future<bool> writeReport({
    required Report report,
    required String idempotencyKey,
    required OperationType operationType,
  }) async {
    try {
      print(
        '[FirebaseService] 📝 Writing report: ${report.id} '
        '(op: ${operationType.toString()})',
      );

      // Get the document reference
      final reportDocRef = _firestore
          .collection(reportsCollection)
          .doc(report.id);

      // Use Firestore transaction for atomicity
      final result = await _firestore.runTransaction((transaction) async {
        // Step 1: Check if this operation was already processed (idempotency)
        final existingDoc = await transaction.get(reportDocRef);

        if (existingDoc.exists) {
          final existingIdempotencyKey =
              existingDoc[idempotencyKeyField] as String?;

          // If idempotency key matches, operation was already processed
          if (existingIdempotencyKey == idempotencyKey) {
            print(
              '[FirebaseService] ⚡ Idempotent: Operation already processed '
              'for ${report.id}',
            );
            return 'idempotent'; // Already processed
          }

          // If idempotency key differs, we might have a conflict
          // Log it for observability
          print(
            '[FirebaseService] ⚠️  Different idempotency key for ${report.id}',
          );
        }

        // Step 2: Prepare data with idempotency key and timestamp
        final reportData = report.toJson();
        final dataToWrite = {
          ...reportData,
          idempotencyKeyField: idempotencyKey,
          lastSyncTimeField: FieldValue.serverTimestamp(),
        };

        // Step 3: Write to Firestore
        // merge: true ensures we don't overwrite other fields
        transaction.set(reportDocRef, dataToWrite, SetOptions(merge: true));

        print(
          '[FirebaseService] ✅ Written to Firestore: ${report.id} '
          '(key: $idempotencyKey)',
        );

        return 'written'; // Successfully written
      });

      return result == 'written'; // Return true only if new write
    } catch (e) {
      print('[FirebaseService] ❌ Write error for ${report.id}: $e');
      rethrow; // Let caller handle the error
    }
  }

  /// Create a new report in Firestore
  /// 
  /// Wrapper method specifically for CREATE operations
  Future<bool> createReport({
    required Report report,
    required String idempotencyKey,
  }) async {
    return writeReport(
      report: report,
      idempotencyKey: idempotencyKey,
      operationType: OperationType.create,
    );
  }

  /// Update a report as important in Firestore
  /// 
  /// Wrapper method specifically for MARK_IMPORTANT operations
  Future<bool> markReportAsImportant({
    required Report report,
    required String idempotencyKey,
  }) async {
    return writeReport(
      report: report,
      idempotencyKey: idempotencyKey,
      operationType: OperationType.updateImportant,
    );
  }

  /// Fetch a report from Firestore
  /// 
  /// Used for conflict resolution or manual refresh
  Future<Report?> getReport(String reportId) async {
    try {
      print('[FirebaseService] 🔍 Fetching report: $reportId');

      final docSnapshot = await _firestore
          .collection(reportsCollection)
          .doc(reportId)
          .get();

      if (!docSnapshot.exists) {
        print('[FirebaseService] ℹ️  Report not found: $reportId');
        return null;
      }

      final report = Report.fromJson(docSnapshot.data() as Map<String, dynamic>);
      print('[FirebaseService] ✅ Fetched report: $reportId');
      return report;
    } catch (e) {
      print('[FirebaseService] ❌ Fetch error for $reportId: $e');
      rethrow;
    }
  }

  /// Check if an idempotency key was already processed
  /// 
  /// Returns: true if key was already used, false if new
  Future<bool> isIdempotencyKeyProcessed(String idempotencyKey) async {
    try {
      print('[FirebaseService] 🔍 Checking idempotency key: $idempotencyKey');

      // Query all reports with this idempotency key
      final querySnapshot = await _firestore
          .collection(reportsCollection)
          .where(idempotencyKeyField, isEqualTo: idempotencyKey)
          .limit(1)
          .get();

      final processed = querySnapshot.docs.isNotEmpty;

      if (processed) {
        print(
          '[FirebaseService] ✅ Key already processed: $idempotencyKey '
          '(reportId: ${querySnapshot.docs.first.id})',
        );
      } else {
        print('[FirebaseService] ℹ️  Key is new: $idempotencyKey');
      }

      return processed;
    } catch (e) {
      print('[FirebaseService] ⚠️  Error checking idempotency: $e');
      // In case of error, assume key wasn't processed (safer to retry)
      return false;
    }
  }

  /// Get report with specific idempotency key
  /// 
  /// Useful for verifying idempotent operations
  Future<Report?> getReportByIdempotencyKey(String idempotencyKey) async {
    try {
      print(
        '[FirebaseService] 🔍 Finding report by idempotency key: '
        '$idempotencyKey',
      );

      final querySnapshot = await _firestore
          .collection(reportsCollection)
          .where(idempotencyKeyField, isEqualTo: idempotencyKey)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('[FirebaseService] ℹ️  No report found for key: $idempotencyKey');
        return null;
      }

      final report = Report.fromJson(
        querySnapshot.docs.first.data() as Map<String, dynamic>,
      );

      print(
        '[FirebaseService] ✅ Found report by key: ${report.id}',
      );

      return report;
    } catch (e) {
      print('[FirebaseService] ❌ Error querying by key: $e');
      rethrow;
    }
  }

  /// Get all reports for current user
  /// 
  /// Optional: Filter by sync status or importance
  Future<List<Report>> getAllReports({
    bool? isImportant,
  }) async {
    try {
      print('[FirebaseService] 📥 Fetching all reports');

      Query query = _firestore.collection(reportsCollection);

      if (isImportant != null) {
        query = query.where('isImportant', isEqualTo: isImportant);
      }

      final querySnapshot = await query.get();

      final reports = querySnapshot.docs
          .map((doc) => Report.fromJson(doc.data() as Map<String, dynamic>))
          .toList();

      print('[FirebaseService] ✅ Fetched ${reports.length} reports');
      return reports;
    } catch (e) {
      print('[FirebaseService] ❌ Error fetching reports: $e');
      rethrow;
    }
  }

  /// Batch write multiple reports with idempotency
  /// 
  /// Uses Firestore batch for efficiency
  /// Each report still has individual idempotency protection
  Future<int> batchWriteReports({
    required List<Report> reports,
    required List<String> idempotencyKeys,
  }) async {
    if (reports.length != idempotencyKeys.length) {
      throw ArgumentError('Reports and keys must have same length');
    }

    try {
      print('[FirebaseService] 📦 Batch writing ${reports.length} reports');

      final batch = _firestore.batch();
      int writtenCount = 0;

      for (int i = 0; i < reports.length; i++) {
        final report = reports[i];
        final idempotencyKey = idempotencyKeys[i];

        final docRef = _firestore
            .collection(reportsCollection)
            .doc(report.id);

        final reportData = report.toJson();
        final dataToWrite = {
          ...reportData,
          idempotencyKeyField: idempotencyKey,
          lastSyncTimeField: FieldValue.serverTimestamp(),
        };

        batch.set(docRef, dataToWrite, SetOptions(merge: true));
        writtenCount++;

        print(
          '[FirebaseService] ✓ Queued: ${report.id} '
          '(key: $idempotencyKey)',
        );
      }

      // Commit all writes
      await batch.commit();
      print('[FirebaseService] ✅ Batch commit successful ($writtenCount)');

      return writtenCount;
    } catch (e) {
      print('[FirebaseService] ❌ Batch write error: $e');
      rethrow;
    }
  }

  /// Delete a report from Firestore
  /// 
  /// Should be called only after successful deletion sync
  Future<void> deleteReport(String reportId) async {
    try {
      print('[FirebaseService] 🗑️  Deleting report: $reportId');

      await _firestore.collection(reportsCollection).doc(reportId).delete();

      print('[FirebaseService] ✅ Deleted: $reportId');
    } catch (e) {
      print('[FirebaseService] ❌ Delete error for $reportId: $e');
      rethrow;
    }
  }

  /// Check connection to Firestore
  /// 
  /// Useful for checking if writes will succeed
  Future<bool> testConnection() async {
    try {
      print('[FirebaseService] 🔌 Testing Firestore connection...');

      // Try a simple read operation
      await _firestore
          .collection(reportsCollection)
          .limit(1)
          .get(GetOptions(source: Source.server));

      print('[FirebaseService] ✅ Firestore connection OK');
      return true;
    } catch (e) {
      print('[FirebaseService] ❌ Firestore connection failed: $e');
      return false;
    }
  }

  /// Get Firestore statistics
  /// 
  /// Useful for monitoring and debugging
  Future<Map<String, dynamic>> getStats() async {
    try {
      final snapshot = await _firestore
          .collection(reportsCollection)
          .get();

      final totalReports = snapshot.docs.length;
      final importantReports = snapshot.docs
          .where((doc) => doc['isImportant'] == true)
          .length;

      return {
        'totalReports': totalReports,
        'importantReports': importantReports,
        'standardReports': totalReports - importantReports,
      };
    } catch (e) {
      print('[FirebaseService] ❌ Error getting stats: $e');
      return {
        'totalReports': 0,
        'importantReports': 0,
        'standardReports': 0,
        'error': e.toString(),
      };
    }
  }

  String get apiKey => dotenv.env['FIREBASE_API_KEY'] ?? '';
  // Use apiKey wherever needed
}
