// FILE: lib/models/message.dart

enum MessageType {
  data,       // normal encrypted chat message
  ack,        // delivery acknowledgement
  handshake,  // key exchange immediately after a new peer connection
}

enum MessageStatus {
  pending,    // created locally, not yet handed to any peer
  sent,       // transmitted to at least one peer (in-flight, awaiting ACK)
  delivered,  // ACK received from the final destination
  failed,     // max retries exceeded, no ACK received
}

class MeshMessage {
  final String id;
  final String senderId;    
  final String recipientId; 
  final String payload;     
  final int ttl;
  final int hopCount;
  final DateTime timestamp;
  final DateTime? sentTime;
  final MessageType type;
  final String? ackForId;
  final MessageStatus status;
  final DateTime? localReceivedTime; 

  const MeshMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.payload,
    required this.ttl,
    this.hopCount = 0,
    required this.timestamp,
    this.sentTime,
    this.type = MessageType.data,
    this.ackForId,
    this.status = MessageStatus.pending,
    this.localReceivedTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': senderId,
        'recipient': recipientId,
        'payload': payload,
        'ttl': ttl,
        'hops': hopCount,
        'ts': timestamp.toIso8601String(),
        'sent_time': sentTime?.toIso8601String(),
        'type': type.index,
        if (ackForId != null) 'ack_id': ackForId,
        'status': status.index,
        if (localReceivedTime != null) 'local_ts': localReceivedTime!.toIso8601String(),
      };

  factory MeshMessage.fromJson(Map<String, dynamic> json) {
    final typeIdx   = (json['type']   as int?) ?? 0;
    final statusIdx = (json['status'] as int?) ?? 0;
    return MeshMessage(
      id:          json['id']        as String,
      senderId:    json['sender']    as String,
      recipientId: json['recipient'] as String,
      payload:     json['payload']   as String,
      ttl:         json['ttl']       as int,
      hopCount:    (json['hops']     as int?) ?? 0,
      timestamp:   DateTime.parse(json['ts'] as String),
      sentTime:    json['sent_time'] != null
          ? DateTime.parse(json['sent_time'] as String)
          : null,
      type: typeIdx < MessageType.values.length
          ? MessageType.values[typeIdx]
          : MessageType.data,
      ackForId: json['ack_id'] as String?,
      status: statusIdx < MessageStatus.values.length
          ? MessageStatus.values[statusIdx]
          : MessageStatus.pending,
      localReceivedTime: json['local_ts'] != null
          ? DateTime.parse(json['local_ts'] as String)
          : null,
    );
  }

  MeshMessage copyWith({
    String? id,
    String? senderId,
    String? recipientId,
    String? payload,
    int? ttl,
    int? hopCount,
    DateTime? timestamp,
    DateTime? sentTime,
    MessageType? type,
    String? ackForId,
    MessageStatus? status,
    DateTime? localReceivedTime,
  }) {
    return MeshMessage(
      id:                id                ?? this.id,
      senderId:          senderId          ?? this.senderId,
      recipientId:       recipientId       ?? this.recipientId,
      payload:           payload           ?? this.payload,
      ttl:               ttl               ?? this.ttl,
      hopCount:          hopCount          ?? this.hopCount,
      timestamp:         timestamp         ?? this.timestamp,
      sentTime:          sentTime          ?? this.sentTime,
      type:              type              ?? this.type,
      ackForId:          ackForId          ?? this.ackForId,
      status:            status            ?? this.status,
      localReceivedTime: localReceivedTime ?? this.localReceivedTime,
    );
  }
}
