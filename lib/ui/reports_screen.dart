import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/hive_manager.dart';
import 'report_detail_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with TickerProviderStateMixin {
  bool _isSyncing = false;
  late AnimationController _dialogAnimationController;

  @override
  void initState() {
    super.initState();
    _dialogAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
     ref.read(reportsProvider.notifier).fetchFromFirebase();
  }

  @override
  void dispose() {
    _dialogAnimationController.dispose();
    super.dispose();
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      final syncManager = ref.read(syncManagerProvider);
      await syncManager.processQueue();

      // Refresh reports after sync
      ref.read(reportsProvider.notifier).refresh();

      // Update queue size (log in debug mode)
      final queueSize = HiveManager.syncQueueBox.length;
      ref.read(queueSizeProvider.notifier).state = queueSize;

      if (kDebugMode) {
        print('[UI] 📊 Queue size after sync: $queueSize');
        print('[UI] 📊 Total reports: ${HiveManager.reportsBox.length}');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Sync completed successfully'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[UI] ❌ Sync error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Sync failed: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _showAddReportDialog() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    _dialogAnimationController.forward(from: 0.0);

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Add Report',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          ),
          child: FadeTransition(
            opacity: animation,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB0E0E6).withValues(alpha: 0.2), // Powder blue
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.add_circle_outline,
                      color: Color(0xFF87CEEB), // Powder blue
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Create Report',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      color: Colors.brown
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      hintText: 'Enter Title of the Report',
                      // prefixIcon: const Icon(Icons.title, color: Color(0xFF87CEEB)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF87CEEB), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      hintText: 'Enter Description',
                      // prefixIcon: const Icon(Icons.description, color: Color(0xFF87CEEB)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF87CEEB), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF87CEEB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) return;

                    await ref.read(reportsProvider.notifier).createReport(
                          title: titleController.text.trim(),
                          description: descController.text.trim(),
                        );

                    // Update queue size
                    final queueSize = HiveManager.syncQueueBox.length;
                    ref.read(queueSizeProvider.notifier).state = queueSize;

                    if (kDebugMode) {
                      print('[UI] 📊 Queue size after create: $queueSize');
                    }

                    if (context.mounted) {
                      Navigator.pop(context);

                      // Check if online to show appropriate message
                      final connectivityState = ref.read(connectivityProvider);
                      final isOnline = connectivityState.value ?? false;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(
                                isOnline ? Icons.cloud_upload : Icons.cloud_off,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isOnline
                                    ? 'Report added and syncing...'
                                    : 'Report added (will sync when online)',
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: isOnline ? Colors.green.shade600 : Colors.orange.shade600,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 20),
                      SizedBox(width: 4),
                      Text('Add Report'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportsProvider);
    final connectivityAsync = ref.watch(connectivityProvider);
    final queueSize = ref.watch(queueSizeProvider);

    // Log debug info instead of showing in UI
    if (kDebugMode) {
      print('[UI] 📊 Current queue size: $queueSize');
      print('[UI] 📊 Total reports: ${reports.length}');
    }

    // Listen to connectivity changes and trigger sync when online
    ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      next.whenData((isOnline) {
        if (isOnline && previous?.value == false) {
          // Switched from offline to online
          if (kDebugMode) {
            print('[UI] 🌐 Connectivity restored, triggering auto-sync');
          }
          _triggerSync();
        }
      });
    });

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.file_copy_outlined, size: 28),
            SizedBox(width: 12),
            Text(
              'Reports',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF87CEEB), // Powder blue
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Connectivity indicator
          connectivityAsync.when(
            data: (isOnline) => Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.greenAccent : Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isOnline ? Colors.greenAccent : Colors.redAccent,
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
            error: (_, __) => const SizedBox(),
          ),
          // Manual sync button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync),
              onPressed: _isSyncing ? null : _triggerSync,
              tooltip: 'Sync Now',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF87CEEB),
        onRefresh: () async {
          if (kDebugMode) {
            print('[UI] 🔄 Pull to refresh - fetching from Firebase');
          }

          // Fetch from Firebase and refresh
          await ref.read(reportsProvider.notifier).fetchFromFirebase();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Reports refreshed'),
                  ],
                ),
                backgroundColor: Colors.green.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        child: reports.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB0E0E6).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.inbox_outlined,
                            size: 80,
                            color: const Color(0xFF87CEEB),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'No reports yet',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF87CEEB),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to create your first report',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Pull down to refresh from cloud',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: reports.length,
                itemBuilder: (context, index) {
                  final report = reports[index];
                  return _buildReportCard(report);
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddReportDialog,
        icon: const Icon(Icons.add),
        label: const Text(
          'New Report',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: const Color(0xFF87CEEB),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }

  Widget _buildReportCard(report) {
    final statusColor = report.syncStatus == 'synced'
        ? Colors.green.shade600
        : report.syncStatus == 'failed'
            ? Colors.red.shade600
            : Colors.orange.shade600;

    final statusIcon = report.syncStatus == 'synced'
        ? Icons.check_circle
        : report.syncStatus == 'failed'
            ? Icons.error
            : Icons.sync;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: const Color(0xFF87CEEB).withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFFB0E0E6).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (kDebugMode) {
            print('[UI] 📄 Tapped report: ${report.id}');
            print('[UI] 📄 Opening detail view');
          }

          // Navigate to detail screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportDetailScreen(report: report),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: report.isImportant
                      ? Colors.amber.withValues(alpha: 0.1)
                      : const Color(0xFFB0E0E6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  report.isImportant ? Icons.priority_high : Icons.description,
                  color: report.isImportant ? Colors.amber.shade700 : const Color(0xFF87CEEB),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (report.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        report.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 6),
                          Text(
                            report.syncStatus,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Star button
              IconButton(
                icon: Icon(
                  report.isImportant ? Icons.star : Icons.star_outline,
                  color: report.isImportant ? Colors.amber.shade600 : Colors.grey.shade400,
                  size: 28,
                ),
                onPressed: () async {
                  final newImportantValue = !report.isImportant;

                  await ref.read(reportsProvider.notifier).toggleImportant(
                    report.id,
                    newImportantValue,
                  );
                  // Update queue size
                  final queueSize = HiveManager.syncQueueBox.length;
                  ref.read(queueSizeProvider.notifier).state = queueSize;

                  if (kDebugMode) {
                    print('[UI] ⭐ Toggled important for: ${report.id}');
                    print('[UI] 📊 Queue size: $queueSize');
                  }

                  if (mounted) {
                    final connectivityState = ref.read(connectivityProvider);
                    final isOnline = connectivityState.value ?? false;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            Icon(
                              newImportantValue ? Icons.star : Icons.star_outline,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                newImportantValue
                                    ? (isOnline
                                    ? 'Marked as important and syncing...'
                                    : 'Marked as important (will sync when online)')
                                    : (isOnline
                                    ? 'Unmarked as important and syncing...'
                                    : 'Unmarked as important (will sync when online)')
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: isOnline ? Colors.green.shade600 : Colors.orange.shade600,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                tooltip: report.isImportant ? 'Unmark as important' : 'Mark as important',
              ),
            ],
          ),
        ),
      ),
    );
  }
}




