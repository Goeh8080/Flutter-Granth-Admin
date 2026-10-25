// Matches CONTRACT §4.3/§4.4 (admin_tab_server_contract.md): KB and Q item shapes, counts, limits.
import 'parse.dart';

/// One "if the question is X, the answer is Y" key point (`/admin/api/ai/knowledge`).
class AiKnowledge {
  const AiKnowledge({
    required this.id,
    required this.question,
    required this.answer,
    this.tags = const [],
    this.visible = true,
    this.updatedAt = '',
  });
  final int id;
  final String question, answer, updatedAt;
  final List<String> tags;
  final bool visible;
  factory AiKnowledge.fromJson(Map<String, dynamic> j) => AiKnowledge(
    id: asInt(j['id']),
    question: asStr(j['question']),
    answer: asStr(j['answer']),
    tags: [for (final t in (j['tags'] as List? ?? const [])) '$t'],
    visible: j['visible'] != false,
    updatedAt: asStr(j['updated_at']),
  );
}

class AiKnowledgeList {
  const AiKnowledgeList({
    this.items = const [],
    this.total = 0,
    this.maxItems = 500,
    this.questionMin = 5,
    this.questionMax = 500,
    this.answerMin = 50,
    this.answerMax = 2000,
  });
  final List<AiKnowledge> items;
  final int total, maxItems, questionMin, questionMax, answerMin, answerMax;
  factory AiKnowledgeList.fromJson(Map<String, dynamic> j) {
    final lim = asMap(j['limits']);
    int at(String k, int i, int d) {
      final l = lim[k];
      return l is List && l.length > i ? asInt(l[i], d) : d;
    }

    return AiKnowledgeList(
      items: [for (final m in asMapList(j['items'])) AiKnowledge.fromJson(m)],
      total: asInt(j['total']),
      maxItems: asInt(j['max_items'], 500),
      questionMin: at('question', 0, 5),
      questionMax: at('question', 1, 500),
      answerMin: at('answer', 0, 50),
      answerMax: at('answer', 1, 2000),
    );
  }
}

/// A question a reader sent from the app (`/admin/api/ai/questions`).
class AiQuestion {
  const AiQuestion({
    required this.id,
    required this.question,
    this.status = 'new',
    this.answer = '',
    this.context = '',
    this.read = false,
    this.verified = false,
    this.createdAt = '',
    this.answeredAt = '',
    this.answeredBy = '',
    this.seenByUser = false,
    this.who = '',
  });
  final int id;
  final String question,
      status,
      answer,
      context,
      createdAt,
      answeredAt,
      answeredBy,
      who;
  final bool read, verified, seenByUser;
  bool get isNew => status == 'new';
  bool get isAnswered => status == 'answered';
  bool get isRejected => status == 'rejected';
  factory AiQuestion.fromJson(Map<String, dynamic> j) => AiQuestion(
    id: asInt(j['id']),
    question: asStr(j['question']),
    status: asStr(j['status']).isEmpty ? 'new' : asStr(j['status']),
    answer: asStr(j['answer']),
    context: asStr(j['context']),
    read: j['read'] == true,
    verified: j['verified'] == true,
    createdAt: asStr(j['created_at']),
    answeredAt: asStr(j['answered_at']),
    answeredBy: asStr(j['answered_by']),
    seenByUser: j['seen_by_user'] == true,
    who: asStr(j['iid_tag']),
  );
}

class AiQuestionCounts {
  const AiQuestionCounts({
    this.newCount = 0,
    this.unread = 0,
    this.answered = 0,
    this.rejected = 0,
    this.total = 0,
  });
  final int newCount, unread, answered, rejected, total;
  factory AiQuestionCounts.fromJson(Map<String, dynamic> j) => AiQuestionCounts(
    newCount: asInt(j['new']),
    unread: asInt(j['unread']),
    answered: asInt(j['answered']),
    rejected: asInt(j['rejected']),
    total: asInt(j['total']),
  );
}

class AiQuestionList {
  const AiQuestionList({
    this.items = const [],
    this.total = 0,
    this.hasMore = false,
    this.counts = const AiQuestionCounts(),
  });
  final List<AiQuestion> items;
  final int total;
  final bool hasMore;
  final AiQuestionCounts counts;
  factory AiQuestionList.fromJson(Map<String, dynamic> j) => AiQuestionList(
    items: [for (final m in asMapList(j['items'])) AiQuestion.fromJson(m)],
    total: asInt(j['total']),
    hasMore: j['has_more'] == true,
    counts: AiQuestionCounts.fromJson(asMap(j['counts'])),
  );
}

/// `GET /ai/summary` (contract §4.4): cheap counters for the badge.
class AiSummary {
  const AiSummary({
    this.unread = 0,
    this.newCount = 0,
    this.answered = 0,
    this.rejected = 0,
    this.total = 0,
    this.kbTotal = 0,
    this.kbVisible = 0,
    this.kbMax = 500,
    this.ready = true,
  });
  final int unread,
      newCount,
      answered,
      rejected,
      total,
      kbTotal,
      kbVisible,
      kbMax;
  final bool ready;
  factory AiSummary.fromJson(Map<String, dynamic> j) {
    final q = asMap(j['questions']), k = asMap(j['knowledge']);
    return AiSummary(
      unread: asInt(q['unread']),
      newCount: asInt(q['new']),
      answered: asInt(q['answered']),
      rejected: asInt(q['rejected']),
      total: asInt(q['total']),
      kbTotal: asInt(k['total']),
      kbVisible: asInt(k['visible']),
      kbMax: asInt(k['max'], 500),
      ready: j['ready'] != false,
    );
  }
}
