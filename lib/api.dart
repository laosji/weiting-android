import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const apiBase = 'https://fm.showmyapps.cc';
const _userAgent = 'WeitingAndroid/1.0 (Flutter)';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.retryable = false});

  final String message;
  final int? statusCode;
  final bool retryable;

  @override
  String toString() => message;
}

class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => '已取消';
}

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const CancelledException();
  }
}

class WeitingApi {
  WeitingApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  /// 解析单个微博/小红书链接，返回服务端 JSON。
  /// 自动重试 2 次（共最多 3 次尝试），指数退避。
  Future<Map<String, Object?>> resolveTrack(
    String url, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    const maxAttempts = 3;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      cancelToken?.check();
      try {
        final uri = Uri.parse(
          '$apiBase/api/resolve?url=${Uri.encodeComponent(url)}',
        );
        final response = await _client
            .get(uri, headers: const {'User-Agent': _userAgent})
            .timeout(timeout);

        Map<String, Object?>? body;
        try {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map) body = decoded.cast<String, Object?>();
        } catch (_) {
          // 服务端返回了非 JSON
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (body == null) {
            throw ApiException('解析返回格式异常', statusCode: response.statusCode);
          }
          return body;
        }

        final retryable =
            response.statusCode >= 500 || response.statusCode == 429;
        final msg = body?['error']?.toString() ??
            '解析失败（${response.statusCode}）';
        if (!retryable || attempt == maxAttempts) {
          throw ApiException(msg, statusCode: response.statusCode);
        }
        lastError = ApiException(msg, statusCode: response.statusCode, retryable: true);
      } on CancelledException {
        rethrow;
      } on TimeoutException {
        lastError = ApiException('网络超时', retryable: true);
        if (attempt == maxAttempts) throw lastError;
      } on ApiException catch (e) {
        if (!e.retryable || attempt == maxAttempts) rethrow;
        lastError = e;
      } catch (e) {
        lastError = ApiException('网络异常：$e', retryable: true);
        if (attempt == maxAttempts) throw lastError;
      }
      // 指数退避 400ms / 1200ms
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt * attempt));
    }
    throw lastError ?? ApiException('解析失败');
  }

  /// 健康检查。任何 2xx 都视作正常。
  Future<bool> healthCheck({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final uri = Uri.parse('$apiBase/api/health');
      final response = await _client
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// 给定 resolve 返回值，构造可直接交给 just_audio 的播放地址。
  String mediaUrlFor(Map<String, Object?> track) {
    final formats = track['formats'];
    Map<String, Object?>? format;
    if (formats is List && formats.isNotEmpty && formats.first is Map) {
      format = (formats.first as Map).cast<String, Object?>();
    }
    final mediaUrl =
        format?['url'] as String? ?? track['mediaUrl'] as String? ?? '';
    if (format?['requiresProxy'] == true) {
      final params = <String, String>{'url': mediaUrl};
      final platform = track['platform'] as String?;
      if (platform != null && platform.isNotEmpty) {
        params['platform'] = platform;
      }
      final mid = track['id'] as String? ?? track['videoId'] as String?;
      if (mid != null && mid.isNotEmpty) params['mid'] = mid;
      final streamAuth = track['streamAuth'];
      if (streamAuth is Map) {
        final exp = streamAuth['exp'];
        final sig = streamAuth['sig'];
        if (exp != null) params['exp'] = '$exp';
        if (sig != null) params['sig'] = '$sig';
      }
      return Uri.parse('$apiBase/api/stream')
          .replace(queryParameters: params)
          .toString();
    }
    return mediaUrl;
  }
}

/// 并发执行 [items] 的 [op]，最多 [concurrency] 个并发；
/// 通过 [onProgress] 回调当前完成数 / 总数；
/// 通过 [cancelToken] 取消整体任务。
/// 返回值与输入顺序对应。
Future<List<R>> runBoundedConcurrent<T, R>(
  List<T> items, {
  required Future<R> Function(T item) op,
  int concurrency = 4,
  void Function(int done, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  final total = items.length;
  final results = List<R?>.filled(total, null);
  var nextIndex = 0;
  var done = 0;

  Future<void> worker() async {
    while (true) {
      if (cancelToken?.isCancelled == true) return;
      final i = nextIndex;
      if (i >= total) return;
      nextIndex = i + 1;
      results[i] = await op(items[i]);
      done++;
      onProgress?.call(done, total);
    }
  }

  final workers = List.generate(
    concurrency.clamp(1, total == 0 ? 1 : total),
    (_) => worker(),
  );
  await Future.wait(workers);
  cancelToken?.check();
  return results.cast<R>();
}
