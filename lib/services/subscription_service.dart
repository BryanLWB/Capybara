import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_node.dart';
import 'app_api.dart';

/// 订阅服务
class SubscriptionService {
  final AppApi _api = AppApi();

  /// 获取订阅内容（由中间层代理）
  Future<String> getSubscriptionContent({String? flag}) async {
    try {
      return await _api.getSubscriptionContent(flag: flag);
    } catch (e) {
      print('[SubscriptionService] Error fetching subscription content: $e');
      rethrow;
    }
  }

  /// 检测订阅格式并解析
  /// 支持 Clash YAML 格式，以及使用 ServerNode.parseFromContent 通用解析器
  List<ServerNode> parseNodes(String subscriptionContent) {
    if (subscriptionContent.trim().isEmpty) return [];

    // 优先尝试 Clash YAML 格式
    if (subscriptionContent.trim().startsWith('#') ||
        subscriptionContent.contains('proxies:') ||
        subscriptionContent.contains('port:')) {
      final nodes = _parseClashYaml(subscriptionContent);
      if (nodes.isNotEmpty)
        return nodes.where((node) => !_isInfoNode(node)).toList();
    }

    // 使用通用解析器 (支持 Base64 递归, Hysteria2, VLESS, VMess, SS, Trojan, WireGuard)
    final nodes = ServerNode.parseFromContent(subscriptionContent);

    // 过滤掉非节点信息
    return nodes.where((node) => !_isInfoNode(node)).toList();
  }

  /// 判断是否为信息展示节点（非真实代理节点）
  bool _isInfoNode(ServerNode node) {
    final name = node.name.toLowerCase();
    return name.contains('剩余流量') ||
        name.contains('套餐到期') ||
        name.contains('期至') ||
        name.contains('重置') ||
        name.contains('官网') ||
        name.contains('traffic') ||
        name.contains('expire') ||
        name.contains('reset') ||
        name.contains('website') ||
        name.contains('距离下次') ||
        name.contains('防止失联');
  }

  /// 解析 Clash YAML 格式
  List<ServerNode> _parseClashYaml(String yamlContent) {
    final nodes = <ServerNode>[];

    try {
      final yaml = loadYaml(yamlContent);
      if (yaml is! Map) return nodes;

      final proxies = yaml['proxies'];
      if (proxies == null || proxies is! List) return nodes;

      for (var proxy in proxies) {
        try {
          Map<String, dynamic>? proxyMap;

          // Clash 配置中的 proxies 可能是 JSON 字符串格式
          if (proxy is String) {
            // 尝试解析 JSON 字符串
            try {
              proxyMap = jsonDecode(proxy) as Map<String, dynamic>?;
            } catch (e) {
              // 如果不是 JSON，跳过
              continue;
            }
          } else if (proxy is Map) {
            // 如果是 Map，需要转换为 Map<String, dynamic>
            proxyMap = Map<String, dynamic>.from(proxy);
          }

          if (proxyMap != null) {
            final node = ServerNode.fromClashConfig(proxyMap);
            nodes.add(node);
          }
        } catch (_) {}
      }
    } catch (_) {}

    return nodes;
  }

  /// 获取并解析订阅节点
  /// [forceRefresh] 是否强制刷新，默认为 false
  Future<List<ServerNode>> fetchNodes({bool forceRefresh = false}) async {
    try {
      // 1. 检查缓存 (默认优先使用缓存)
      if (!forceRefresh) {
        final cached = await _getCachedNodes();
        if (cached != null && cached.isNotEmpty) {
          return cached;
        }
      }

      // 2. 从中间层直接获取订阅内容
      final subscriptionContent = await getSubscriptionContent();

      // 3. 解析节点列表（自动检测格式）
      final nodes = parseNodes(subscriptionContent);

      // 4. 保存缓存
      if (nodes.isNotEmpty) {
        await _saveSubscriptionCache(subscriptionContent);
      }

      return nodes;
    } catch (e) {
      // 如果获取失败且不是强制刷新，尝试返回过期缓存
      if (forceRefresh) {
        final cached = await _getCachedNodes(ignoreExpiration: true);
        if (cached != null) return cached;
      }
      throw Exception('Failed to fetch nodes: $e');
    }
  }

  Future<List<ServerNode>?> _getCachedNodes({
    bool ignoreExpiration = false,
  }) async {
    try {
      // final prefs = await SharedPreferences.getInstance();
      // final lastUpdate = prefs.getInt('nodes_last_update');

      // // 如果没有记录或已过期（超过24小时）且不忽略过期
      // if (!ignoreExpiration) {
      //   if (lastUpdate == null) return null;
      //   final lastTime = DateTime.fromMillisecondsSinceEpoch(lastUpdate);
      //   if (DateTime.now().difference(lastTime).inHours >= 24) {
      //     return null;
      //   }
      // }

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/subscription.txt');
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      if (content.isEmpty) return null;

      return parseNodes(content);
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveSubscriptionCache(String content) async {
    try {
      // 保存内容
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/subscription.txt');
      await file.writeAsString(content);

      // 保存时间戳
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'nodes_last_update',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // ignore
    }
  }

  /// 保存订阅内容到本地
  Future<void> saveSubscriptionLocally(String content) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/subscription.txt');
      await file.writeAsString(content);
    } catch (_) {}
  }
}
