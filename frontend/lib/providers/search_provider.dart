import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/search_result.dart';

enum SearchState { idle, loading, done, error }

class SearchProvider extends ChangeNotifier {
  final _dio = Dio();

  List<SearchResult> _results = [];
  SearchState _state = SearchState.idle;
  String _error = '';
  CancelToken? _cancelToken;

  List<SearchResult> get results => _results;
  SearchState get state => _state;
  String get error => _error;

  Future<void> search(String query, String serverUrl) async {
    if (query.trim().isEmpty) return;

    // Cancel any in-flight request
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    _state = SearchState.loading;
    _results = [];
    notifyListeners();

    try {
      final res = await _dio.get(
        '$serverUrl/search',
        queryParameters: {'q': query.trim(), 'limit': 15},
        cancelToken: _cancelToken,
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );

      final list = (res.data['results'] as List? ?? []);
      _results = list
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
      _state = SearchState.done;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return; // user typed again — ignore
      _error = e.response?.data?['detail'] ?? 'Search failed';
      _state = SearchState.error;
    } catch (e) {
      _error = e.toString();
      _state = SearchState.error;
    }

    notifyListeners();
  }

  void clear() {
    _cancelToken?.cancel();
    _results = [];
    _state = SearchState.idle;
    notifyListeners();
  }
}
