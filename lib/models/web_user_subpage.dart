enum WebUserSubpage { profile, orders, nodes, tickets, traffic }

extension WebUserSubpageX on WebUserSubpage {
  String label(bool isChinese) {
    switch (this) {
      case WebUserSubpage.profile:
        return isChinese ? '个人中心' : 'Profile';
      case WebUserSubpage.orders:
        return isChinese ? '我的订单' : 'My Orders';
      case WebUserSubpage.nodes:
        return isChinese ? '节点状态' : 'Node Status';
      case WebUserSubpage.tickets:
        return isChinese ? '我的工单' : 'My Tickets';
      case WebUserSubpage.traffic:
        return isChinese ? '流量明细' : 'Traffic Logs';
    }
  }
}
