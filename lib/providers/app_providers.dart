import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/data_models.dart';
import '../repositories/reports_repository.dart';
import '../services/sync_manage.dart';
import '../services/connectivity_service.dart';

/// Repository provider
final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository();
});

/// Reports list provider
final reportsProvider = StateNotifierProvider<ReportsNotifier, List<Report>>((ref) {
  final repository = ref.watch(reportsRepositoryProvider);
  final syncManager = ref.watch(syncManagerProvider);
  return ReportsNotifier(repository, syncManager, ref);
});

class ReportsNotifier extends StateNotifier<List<Report>> {
  final ReportsRepository _repository;
  final SyncManager _syncManager;
  final Ref _ref;
  bool _hasInitialized = false;

  ReportsNotifier(this._repository, this._syncManager, this._ref) : super([]) {
    // Load local cache immediately (might be empty after reinstall)
    _loadReports();

    // Fetch from Firebase on startup - same as pull-to-refresh
    _initialize();
  }

  /// Initialize - fetch from Firebase on first load (like pull-to-refresh)
  Future<void> _initialize() async {
    if (_hasInitialized) return;
    _hasInitialized = true;

    // Check connectivity
    final connectivityState = _ref.read(connectivityProvider);
    final isOnline = connectivityState.value ?? false;

    if (isOnline) {
      if (kDebugMode) {
        print('[ReportsNotifier] 🌐 Online - fetching reports from Firebase on startup');
        print('[ReportsNotifier] 🔄 This is the same as pull-to-refresh');
      }

      // Fetch from Firebase and update UI (same as pull-to-refresh)
      await fetchFromFirebase();

      if (kDebugMode) {
        print('[ReportsNotifier] ✅ Startup fetch completed - reports should appear now!');
      }
    } else {
      if (kDebugMode) {
        print('[ReportsNotifier] 📴 Offline - using local cache only');
      }
    }
  }

  void _loadReports() {
    final reports = _repository.getAllReports();

    // Sort by createdAt date - latest first
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Create new list instance to ensure state change is detected
    state = List.from(reports);
  }

  /// Fetch reports from Firebase and update local cache
  Future<void> fetchFromFirebase() async {
    if (kDebugMode) {
      print('[ReportsNotifier] 📡 Starting Firebase fetch...');
    }

    try {
      await _repository.fetchReportsFromFirebase();

      if (kDebugMode) {
        print('[ReportsNotifier] 📥 Firebase fetch completed, reloading reports...');
      }

      _loadReports(); // Reload to show fetched reports

      if (kDebugMode) {
        print('[ReportsNotifier] ✅ Reports loaded, count: ${state.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ReportsNotifier] ❌ Fetch from Firebase failed: $e');
        print('[ReportsNotifier] Stack trace: ${StackTrace.current}');
      }
      // Don't rethrow - app should continue with local cache
    }
  }

  /// Auto-sync if online after any operation
  Future<void> _autoSyncIfOnline() async {
    final connectivityState = _ref.read(connectivityProvider);
    final isOnline = connectivityState.value ?? false;

    if (isOnline) {
      if (kDebugMode) {
        print('[ReportsNotifier] 🌐 Online detected, triggering auto-sync...');
      }
      try {
        // Sync to Firebase
        await _syncManager.processQueue();

        // Refresh local reports to show updated sync status
        _loadReports();

        if (kDebugMode) {
          print('[ReportsNotifier] ✅ Auto-sync completed');
        }
      } catch (e) {
        if (kDebugMode) {
          print('[ReportsNotifier] ⚠️ Auto-sync failed: $e');
        }
      }
    } else {
      if (kDebugMode) {
        print('[ReportsNotifier] 📴 Offline - sync will happen when online');
      }
    }
  }

  Future<void> createReport({
    required String title,
    required String description,
  }) async {
    // Create report locally
    await _repository.createReport(title: title, description: description);

    // Load reports to show the new one immediately
    _loadReports();

    // Auto-sync if online (this will update sync status)
    await _autoSyncIfOnline();
  }

  Future<void> toggleImportant(String reportId, bool important) async {
    await _repository.markImportant(reportId, important);
    _loadReports();

    // Auto-sync if online
    await _autoSyncIfOnline();
  }

  void refresh() {
    _loadReports();
  }
}

/// Sync manager provider
final syncManagerProvider = Provider<SyncManager>((ref) {
  return SyncManager();
});

/// Connectivity provider
final connectivityProvider = StreamProvider<bool>((ref) {
  return ConnectivityService().connectivityStream;
});

/// Queue size provider
final queueSizeProvider = StateProvider<int>((ref) => 0);

/// Sync stats provider
final syncStatsProvider = StateProvider<SyncStats>((ref) {
  return SyncStats(
    successCount: 0,
    failureCount: 0,
    pendingCount: 0,
    lastSyncTime: null,
  );
});

class SyncStats {
  final int successCount;
  final int failureCount;
  final int pendingCount;
  final DateTime? lastSyncTime;

  SyncStats({
    required this.successCount,
    required this.failureCount,
    required this.pendingCount,
    this.lastSyncTime,
  });

  SyncStats copyWith({
    int? successCount,
    int? failureCount,
    int? pendingCount,
    DateTime? lastSyncTime,
  }) {
    return SyncStats(
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}


