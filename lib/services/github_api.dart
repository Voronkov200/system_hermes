// GitHub API: проверка коммитов (верификация работы над кодом).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';

class GithubApi {
  final http.Client _client = http.Client();

  /// Список коммитов в репозитории owner/repo с даты since (YYYY-MM-DD).
  Future<Map<String, dynamic>> getCommits({
    required String owner,
    required String repo,
    required String since,
    String? token,
  }) async {
    final uri = Uri.parse(
        '${AppConstants.githubApiUrl}/repos/$owner/$repo/commits?since=${since}T00:00:00Z&per_page=100');
    final headers = <String, String>{'Accept': 'application/vnd.github+json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final res = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('GitHub API: HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    final messages = <String>[];
    for (final item in data) {
      final commit = item['commit'] as Map<String, dynamic>?;
      final msg = (commit?['message'] as String?) ?? '';
      final line = msg.split('\n').first;
      if (line.isNotEmpty) messages.add(line);
    }
    return {
      'count': messages.length,
      'messages': messages,
      'since': since,
    };
  }
}

final githubApiProvider = Provider<GithubApi>((ref) => GithubApi());
