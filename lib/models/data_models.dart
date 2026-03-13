enum OperationType { create, updateImportant }

class Report {
  final String id;
  final String title;
  final String description;
  final bool isImportant;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus; // "pending", "synced", "failed"
  final String? errorMessage;

  Report({
    required this.id,
    required this.title,
    required this.description,
    required this.isImportant,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    this.errorMessage,
  });

  Report copyWith({
    bool? isImportant,
    DateTime? updatedAt,
    String? syncStatus,
    String? errorMessage,
  }) {
    return Report(
      id: id,
      title: title,
      description: description,
      isImportant: isImportant ?? this.isImportant,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'isImportant': isImportant,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncStatus': syncStatus,
    'errorMessage': errorMessage,
  };

  factory Report.fromJson(Map<String, dynamic> json) => Report(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    isImportant: json['isImportant'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    syncStatus: json['syncStatus'] as String? ?? 'pending',
    errorMessage: json['errorMessage'] as String?,
  );

  @override
  String toString() => 'Report($id, $title, important=$isImportant, status=$syncStatus)';
}

class SyncQueueItem {
  final String id;
  final String reportId;
  final OperationType operationType;
  final Map<String, dynamic> data;
  final String idempotencyKey;
  final DateTime enqueuedAt;
  final int syncAttempts;
  final String status; // "pending", "retry", "synced", "failed"
  final DateTime? nextRetryTime;
  final String? errorMessage;

  SyncQueueItem({
    required this.id,
    required this.reportId,
    required this.operationType,
    required this.data,
    required this.idempotencyKey,
    required this.enqueuedAt,
    required this.syncAttempts,
    required this.status,
    this.nextRetryTime,
    this.errorMessage,
  });

  bool isReadyForRetry() {
    if (status != 'retry') return false;
    if (nextRetryTime == null) return true;
    return DateTime.now().isAfter(nextRetryTime!);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'reportId': reportId,
    'operationType': operationType.toString(),
    'data': data,
    'idempotencyKey': idempotencyKey,
    'enqueuedAt': enqueuedAt.toIso8601String(),
    'syncAttempts': syncAttempts,
    'status': status,
    'nextRetryTime': nextRetryTime?.toIso8601String(),
    'errorMessage': errorMessage,
  };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    final opTypeStr = json['operationType'] as String;
    final opType = opTypeStr.contains('create')
        ? OperationType.create
        : OperationType.updateImportant;

    return SyncQueueItem(
      id: json['id'] as String,
      reportId: json['reportId'] as String,
      operationType: opType,
      data: json['data'] as Map<String, dynamic>,
      idempotencyKey: json['idempotencyKey'] as String,
      enqueuedAt: DateTime.parse(json['enqueuedAt'] as String),
      syncAttempts: json['syncAttempts'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      nextRetryTime: json['nextRetryTime'] != null
          ? DateTime.parse(json['nextRetryTime'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  @override
  String toString() => 'QueueItem($reportId, $operationType, status=$status, attempts=$syncAttempts)';
}

