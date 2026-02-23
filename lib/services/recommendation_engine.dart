import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:event_collab/services/huggingface_service.dart';

/// Result of the recommendation engine: event ID, combined score, and per-technique breakdown.
class RecommendedEvent {
  final String eventId;
  final Map<String, dynamic> event;
  final double score;
  final double? collaborativeScore;
  final double? contentScore;
  final double? embeddingScore;
  final String? reason;

  RecommendedEvent({
    required this.eventId,
    required this.event,
    required this.score,
    this.collaborativeScore,
    this.contentScore,
    this.embeddingScore,
    this.reason,
  });
}

/// Combines three AI techniques for event recommendations:
/// 1. Collaborative filtering - users who engaged with similar events
/// 2. Content-based similarity - event attributes (type, tags, description)
/// 3. Vector embeddings - semantic similarity via Hugging Face
class RecommendationEngine {
  final FirebaseFirestore firestore;
  final HuggingFaceService? huggingFaceService;

  RecommendationEngine({
    required this.firestore,
    this.huggingFaceService,
  });

  /// Compute cosine similarity between two vectors.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    double dot = 0, normA = 0, normB = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Content-based similarity: Jaccard for tags, type match, location/description overlap.
  double _contentSimilarity(
    Map<String, dynamic> event,
    String? userRole,
    Set<String> userPastEventTags,
  ) {
    double score = 0;
    int factors = 0;

    // Type preference: user role often correlates with event type
    final type = (event['type'] ?? '').toString().toLowerCase();
    if (type.isNotEmpty) {
      factors++;
      score += 0.3; // base for having type
    }

    // LookingFor tags - Jaccard similarity with user's past event tags or role
    final lookingFor = <String>{};
    if (event['lookingFor'] is List) {
      for (var item in event['lookingFor'] as List) {
        if (item != null) lookingFor.add(item.toString().toLowerCase());
      }
    }
    if (userRole != null && userRole.isNotEmpty) {
      final roleLower = userRole.toLowerCase();
      if (lookingFor.contains(roleLower)) {
        score += 0.4; // strong match: event looks for user's role
      }
    }
    if (userPastEventTags.isNotEmpty && lookingFor.isNotEmpty) {
      final intersection = userPastEventTags.intersection(lookingFor).length;
      final union = userPastEventTags.union(lookingFor).length;
      if (union > 0) {
        score += 0.3 * (intersection / union);
      }
      factors++;
    }
    if (lookingFor.isNotEmpty) factors++;

    // Description keywords (simple word overlap)
    final desc = (event['description'] ?? '').toString().toLowerCase();
    if (desc.isNotEmpty && userPastEventTags.isNotEmpty) {
      final descWords = desc.split(RegExp(r'\s+')).toSet();
      final overlap = userPastEventTags.intersection(descWords).length;
      if (userPastEventTags.isNotEmpty) {
        score += 0.2 * (overlap / userPastEventTags.length).clamp(0.0, 1.0);
      }
      factors++;
    }

    if (factors == 0) return 0.5; // neutral when no signals
    return (score / 3).clamp(0.0, 1.0);
  }

  /// Collaborative filtering: item-based - events that share users who engaged.
  /// Uses whereIn for targeted queries (Firestore limit: 30 per whereIn).
  Future<Map<String, double>> _collaborativeScores(
    String? userId,
    List<String> eventIds,
  ) async {
    final scores = <String, double>{};
    for (final id in eventIds) scores[id] = 0;

    if (userId == null || userId.isEmpty) return scores;

    // 1. Get events the current user has engaged with
    final userEventIds = <String>{};
    for (final col in ['event_applications', 'claimed_tickets', 'payments']) {
      try {
        final q = await firestore
            .collection(col)
            .where('userId', isEqualTo: userId)
            .get();
        for (final doc in q.docs) {
          final eid = doc.data()['eventId']?.toString();
          if (eid != null) userEventIds.add(eid);
        }
      } catch (_) {}
    }

    if (userEventIds.isEmpty) return scores;

    // 2. Build eventId -> users who engaged (batch whereIn, max 30 per query)
    final eventToUsers = <String, Set<String>>{};
    for (final eid in eventIds) eventToUsers[eid] = {};

    const batchSize = 30;
    for (var i = 0; i < eventIds.length; i += batchSize) {
      final batch = eventIds.skip(i).take(batchSize).toList();
      for (final col in ['event_applications', 'claimed_tickets', 'payments']) {
        try {
          final q = await firestore
              .collection(col)
              .where('eventId', whereIn: batch)
              .get();
          for (final doc in q.docs) {
            final eid = doc.data()['eventId']?.toString();
            final uid = doc.data()['userId']?.toString();
            if (eid != null && uid != null && uid != userId && eventToUsers.containsKey(eid)) {
              eventToUsers[eid]!.add(uid);
            }
          }
        } catch (_) {}
      }
    }

    final usersToFetch = <String>{};
    for (final users in eventToUsers.values) usersToFetch.addAll(users);
    if (usersToFetch.isEmpty) return scores;

    // 3. Build userId -> events for similar users (batch whereIn)
    final userToEvents = <String, Set<String>>{};
    final userList = usersToFetch.toList();
    for (var i = 0; i < userList.length; i += batchSize) {
      final batch = userList.skip(i).take(batchSize).toList();
      for (final col in ['event_applications', 'claimed_tickets', 'payments']) {
        try {
          final q = await firestore
              .collection(col)
              .where('userId', whereIn: batch)
              .get();
          for (final doc in q.docs) {
            final uid = doc.data()['userId']?.toString();
            final eid = doc.data()['eventId']?.toString();
            if (uid != null && eid != null) {
              userToEvents.putIfAbsent(uid, () => {}).add(eid);
            }
          }
        } catch (_) {}
      }
    }

    // 4. Score: fraction of engagers who also engaged with user's events
    for (final eventId in eventIds) {
      if (userEventIds.contains(eventId)) continue;
      final engagers = eventToUsers[eventId] ?? {};
      if (engagers.isEmpty) continue;

      int overlapCount = 0;
      for (final uid in engagers) {
        final otherEvents = userToEvents[uid] ?? {};
        if (otherEvents.intersection(userEventIds).isNotEmpty) overlapCount++;
      }
      scores[eventId] = (overlapCount / engagers.length).clamp(0.0, 1.0);
    }

    return scores;
  }

  /// Vector embeddings: semantic similarity between event text and user preference.
  Future<Map<String, double>> _embeddingScores(
    List<Map<String, dynamic>> events,
    List<String> eventIds,
    String? userRole,
    Set<String> userPastEventTags,
  ) async {
    final scores = <String, double>{};
    for (var i = 0; i < eventIds.length; i++) scores[eventIds[i]] = 0;

    if (huggingFaceService == null) return scores;

    final queryParts = <String>[];
    if (userRole != null && userRole.isNotEmpty) queryParts.add(userRole);
    queryParts.addAll(userPastEventTags);
    final queryText = queryParts.isEmpty ? 'events' : queryParts.join(' ');

    final eventTexts = events.map((e) {
      final name = e['name'] ?? '';
      final desc = (e['description'] ?? '').toString();
      final type = e['type'] ?? '';
      final loc = e['location'] ?? '';
      final lookingFor = (e['lookingFor'] as List?)?.map((x) => x.toString()).join(' ') ?? '';
      return '$name $desc $type $loc $lookingFor'.trim();
    }).toList();

    final queryEmb = await huggingFaceService!.getEmbedding(queryText);
    if (queryEmb == null) return scores;

    final eventEmbs = await huggingFaceService!.getEmbeddings(eventTexts);
    for (var i = 0; i < eventIds.length && i < eventEmbs.length; i++) {
      final emb = eventEmbs[i];
      if (emb != null) {
        final sim = cosineSimilarity(queryEmb, emb);
        scores[eventIds[i]] = (sim + 1) / 2; // map [-1,1] to [0,1]
      }
    }

    return scores;
  }

  /// Get recommended events using all three techniques.
  Future<List<RecommendedEvent>> getRecommendations({
    required List<Map<String, dynamic>> events,
    required List<String> eventIds,
    String? userId,
    String? userRole,
    int topK = 5,
    double weightCollaborative = 0.35,
    double weightContent = 0.35,
    double weightEmbedding = 0.30,
  }) async {
    if (events.isEmpty || eventIds.isEmpty) return [];

    // Build user's past event tags from their applications
    final userPastEventTags = <String>{};
    if (userId != null) {
      try {
        final apps = await firestore
            .collection('event_applications')
            .where('userId', isEqualTo: userId)
            .get();
        for (final doc in apps.docs) {
          final role = doc.data()['role']?.toString();
          if (role != null) userPastEventTags.add(role.toLowerCase());
        }
        if (userRole != null) userPastEventTags.add(userRole.toLowerCase());
      } catch (_) {}
    }

    // 1. Collaborative filtering scores
    final cfScores = await _collaborativeScores(userId, eventIds);

    // 2. Content-based scores (local, no API)
    final contentScores = <String, double>{};
    for (var i = 0; i < eventIds.length; i++) {
      contentScores[eventIds[i]] = _contentSimilarity(
        events[i],
        userRole,
        userPastEventTags,
      );
    }

    // 3. Embedding scores (Hugging Face API)
    Map<String, double> embScores = {};
    if (huggingFaceService != null) {
      embScores = await _embeddingScores(
        events,
        eventIds,
        userRole,
        userPastEventTags,
      );
    }

    // Normalize and combine
    final combined = <String, double>{};
    for (final id in eventIds) {
      final cf = cfScores[id] ?? 0;
      final cb = contentScores[id] ?? 0;
      final emb = embScores[id] ?? 0;

      double total = 0;
      double denom = 0;
      if (weightCollaborative > 0) {
        total += cf * weightCollaborative;
        denom += weightCollaborative;
      }
      if (weightContent > 0) {
        total += cb * weightContent;
        denom += weightContent;
      }
      if (weightEmbedding > 0 && embScores.containsKey(id)) {
        total += emb * weightEmbedding;
        denom += weightEmbedding;
      }
      if (denom > 0) {
        combined[id] = total / denom;
      } else {
        combined[id] = (cb + cf) / 2;
      }
    }

    // Sort and take top K
    final sorted = combined.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final results = <RecommendedEvent>[];
    for (var i = 0; i < topK && i < sorted.length; i++) {
      final entry = sorted[i];
      final idx = eventIds.indexOf(entry.key);
      if (idx < 0) continue;
      final event = events[idx];
      final name = event['name'] ?? 'Event';

      String? reason;
      if (cfScores[entry.key] != null && (cfScores[entry.key] ?? 0) > 0.1) {
        reason = 'Users with similar interests engaged with this';
      } else if ((contentScores[entry.key] ?? 0) > 0.5) {
        reason = 'Matches your role and preferences';
      } else if ((embScores[entry.key] ?? 0) > 0.5) {
        reason = 'Semantically relevant to your interests';
      } else {
        reason = 'Recommended for you';
      }

      results.add(RecommendedEvent(
        eventId: entry.key,
        event: event,
        score: entry.value,
        collaborativeScore: cfScores[entry.key],
        contentScore: contentScores[entry.key],
        embeddingScore: embScores[entry.key],
        reason: reason,
      ));
    }

    return results;
  }
}
