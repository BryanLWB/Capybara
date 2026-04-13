import 'package:flutter/material.dart';

import 'web_shell_section.dart';

enum WebPlanFilter { all, recurring, onetime }

extension WebPlanFilterX on WebPlanFilter {
  String label(bool isChinese) {
    switch (this) {
      case WebPlanFilter.all:
        return isChinese ? '全部套餐' : 'All Plans';
      case WebPlanFilter.recurring:
        return isChinese ? '周期性套餐' : 'Recurring';
      case WebPlanFilter.onetime:
        return isChinese ? '一次性套餐' : 'One-time';
    }
  }
}

class WebMockPlan {
  const WebMockPlan({
    required this.id,
    required this.title,
    required this.summary,
    required this.traffic,
    required this.priceLabel,
    required this.priceValue,
    required this.deviceLimit,
    required this.resetPack,
    required this.filter,
    required this.features,
  });

  final String id;
  final String title;
  final String summary;
  final String traffic;
  final String priceLabel;
  final String priceValue;
  final String deviceLimit;
  final String resetPack;
  final WebPlanFilter filter;
  final List<String> features;
}

class WebClientGroup {
  const WebClientGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<WebClientItem> items;
}

class WebClientItem {
  const WebClientItem({
    required this.platform,
    required this.title,
    required this.updatedAt,
    required this.summary,
    required this.icon,
  });

  final String platform;
  final String title;
  final String updatedAt;
  final String summary;
  final IconData icon;
}

class WebInviteMockData {
  const WebInviteMockData({
    required this.currentCommission,
    required this.totalCommission,
    required this.inviteUrl,
    required this.invitedUsers,
    required this.commissionRate,
  });

  final String currentCommission;
  final String totalCommission;
  final String inviteUrl;
  final int invitedUsers;
  final String commissionRate;
}

class WebAccountMockData {
  const WebAccountMockData({
    required this.balance,
    required this.expireReminder,
    required this.trafficReminder,
  });

  final String balance;
  final bool expireReminder;
  final bool trafficReminder;
}

const webMockPlans = <WebMockPlan>[
  WebMockPlan(
    id: 'micro',
    title: '微量基础节点',
    summary: '包含流量 10 GB',
    traffic: '10 GB',
    priceLabel: '月付',
    priceValue: '¥3.80',
    deviceLimit: '最多支持 3 台设备同时在线使用',
    resetPack: '流量重置包：2.8 元',
    filter: WebPlanFilter.recurring,
    features: <String>[
      '基础系列节点（5 个热门地区）',
      '适合轻量浏览与消息通信',
      '入门价格低，适合首次体验',
    ],
  ),
  WebMockPlan(
    id: 'light',
    title: '轻量基础节点',
    summary: '包含流量 45 GB',
    traffic: '45 GB',
    priceLabel: '月付',
    priceValue: '¥5.80',
    deviceLimit: '最多支持 3 台设备同时在线使用',
    resetPack: '流量重置包：4.8 元',
    filter: WebPlanFilter.recurring,
    features: <String>[
      '基础系列节点（5 个热门地区）',
      '更实惠的流量均价',
      '适合日常上网和媒体访问',
    ],
  ),
  WebMockPlan(
    id: 'medium',
    title: '中量进阶节点',
    summary: '包含流量 95 GB',
    traffic: '95 GB',
    priceLabel: '月付',
    priceValue: '¥8.80',
    deviceLimit: '最多支持 3 台设备同时在线使用',
    resetPack: '流量重置包：7 元',
    filter: WebPlanFilter.recurring,
    features: <String>[
      '额外优化线路与进阶系列节点',
      '更适合跨区服务与热门平台',
      '性价比最高',
    ],
  ),
  WebMockPlan(
    id: 'large',
    title: '宏量进阶节点',
    summary: '包含流量 150 GB',
    traffic: '150 GB',
    priceLabel: '月付',
    priceValue: '¥10.80',
    deviceLimit: '最多支持 3 台设备同时在线使用',
    resetPack: '流量重置包：9 元',
    filter: WebPlanFilter.recurring,
    features: <String>[
      '进阶系列节点（26 个地区）',
      '更宽松的限速和更实惠流量均价',
      '适合长期主力使用',
    ],
  ),
  WebMockPlan(
    id: 'xl',
    title: '巨量进阶节点',
    summary: '包含流量 210 GB',
    traffic: '210 GB',
    priceLabel: '月付',
    priceValue: '¥13.80',
    deviceLimit: '最多支持 3 台设备同时在线使用',
    resetPack: '流量重置包：12 元',
    filter: WebPlanFilter.recurring,
    features: <String>[
      '进阶线路 + 更宽松的速率策略',
      '适合多设备与视频场景',
      '高配日常主力套餐',
    ],
  ),
  WebMockPlan(
    id: 'ultimate',
    title: '终身备用套餐',
    summary: '一次性购买，适合备用与备份场景',
    traffic: '480 GB',
    priceLabel: '一次性',
    priceValue: '¥28.80',
    deviceLimit: '最多支持 3 台设备同时在线使用',
    resetPack: '一次性套餐不支持月度重置',
    filter: WebPlanFilter.onetime,
    features: <String>[
      '一次性可用流量包',
      '适合作为备用订阅或旅行场景',
      '后续可扩展为长期备用节点',
    ],
  ),
];

const webRecommendedClients = WebClientGroup(
  title: '官方推荐客户端',
  items: <WebClientItem>[
    WebClientItem(
      platform: 'iOS',
      title: 'Capybara for iOS',
      updatedAt: '2026-04-03',
      summary: '适合 iPhone / iPad 的官方推荐接入方式。',
      icon: Icons.phone_iphone_rounded,
    ),
    WebClientItem(
      platform: 'Android',
      title: 'Capybara for Android',
      updatedAt: '2025-11-29',
      summary: '适合 Android 手机和平板的官方客户端。',
      icon: Icons.android_rounded,
    ),
    WebClientItem(
      platform: 'Windows',
      title: 'Capybara for Windows',
      updatedAt: '2026-03-26',
      summary: '适合 Windows 桌面环境的官方客户端。',
      icon: Icons.desktop_windows_rounded,
    ),
    WebClientItem(
      platform: 'macOS',
      title: 'Capybara for macOS',
      updatedAt: '2026-03-17',
      summary: '适合 macOS 桌面环境的官方客户端。',
      icon: Icons.laptop_mac_rounded,
    ),
  ],
);

const webOtherClients = WebClientGroup(
  title: '其他客户端',
  items: <WebClientItem>[
    WebClientItem(
      platform: 'iOS',
      title: 'Shadowrocket',
      updatedAt: '2026-04-03',
      summary: '适合需要手动导入订阅链接的 iOS 用户。',
      icon: Icons.rocket_launch_rounded,
    ),
    WebClientItem(
      platform: 'iOS',
      title: 'Clash Mi',
      updatedAt: '2026-04-03',
      summary: '适合需要更细节点管理能力的用户。',
      icon: Icons.auto_graph_rounded,
    ),
    WebClientItem(
      platform: 'Windows',
      title: 'Clash Verge',
      updatedAt: '2026-03-30',
      summary: '适合桌面端策略组与规则模式用户。',
      icon: Icons.layers_rounded,
    ),
  ],
);

const webInviteMock = WebInviteMockData(
  currentCommission: '¥0.00',
  totalCommission: '¥0.00',
  inviteUrl: 'https://capybara.local/register?code=CAPYBARA-DEMO',
  invitedUsers: 0,
  commissionRate: '10%',
);

const webAccountMock = WebAccountMockData(
  balance: '¥0.00',
  expireReminder: false,
  trafficReminder: false,
);

const webQuickTargets = <WebShellSection>[
  WebShellSection.purchase,
  WebShellSection.help,
  WebShellSection.invite,
  WebShellSection.account,
];
