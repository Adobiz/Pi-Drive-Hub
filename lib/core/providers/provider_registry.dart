/// 多网盘注册中心。
///
/// 集中管理所有已注册的网盘 Provider，UI 从这里按 id 取实例。
/// 以后接入阿里云盘/夸克时，只需在 [registered] 里加一个实现。
library;

import '../../providers/baidu_client/baidu_client_provider.dart';
import '../../providers/pan123/pan123_provider.dart';
import '../../providers/quark/quark_provider.dart';
import 'cloud_provider.dart';

class ProviderRegistry {
  ProviderRegistry._();

  static final ProviderRegistry instance = ProviderRegistry._();

  final List<CloudProvider> _providers = [];

  /// 注册一个网盘实现
  void register(CloudProvider provider) {
    _providers.add(provider);
  }

  /// 所有已注册网盘（按注册顺序）
  List<CloudProvider> get all => List.unmodifiable(_providers);

  /// 按 id 查找；未注册返回 null
  CloudProvider? byId(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// 预置注册：百度网盘双通道（官方 OAuth + 客户端协议）+ 夸克网盘（占位）。
/// 夸克接入完成后在 QuarkProvider 中补齐实现即可。
void setupDefaultProviders() {
  final registry = ProviderRegistry.instance;
  if (registry.all.isEmpty) {
    registry.register(BaiduClientProvider()); // 百度网盘（客户端协议，全功能任意目录）
    registry.register(QuarkProvider()); // 夸克网盘
    registry.register(Pan123Provider()); // 123云盘
  }
}
