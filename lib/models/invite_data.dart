class InviteFetchData {
  final List<InviteCode> codes;
  final InviteStat stat;

  InviteFetchData({
    required this.codes,
    required this.stat,
  });

  factory InviteFetchData.fromJson(Map<String, dynamic> json) {
    return InviteFetchData(
      codes: (json['codes'] as List<dynamic>?)
              ?.map((e) => InviteCode.fromJson(e))
              .toList() ??
          [],
      stat: InviteStat.fromList(json['stat'] as List<dynamic>? ?? []),
    );
  }
}

class InviteStat {
  final int registeredUsers;
  final num validCommission;
  final num pendingCommission;
  final num commissionRate;
  final num availableCommission;

  InviteStat({
    required this.registeredUsers,
    required this.validCommission,
    required this.pendingCommission,
    required this.commissionRate,
    required this.availableCommission,
  });

  factory InviteStat.fromList(List<dynamic> list) {
    if (list.length < 5) {
      return InviteStat(
        registeredUsers: 0,
        validCommission: 0,
        pendingCommission: 0,
        commissionRate: 0,
        availableCommission: 0,
      );
    }
    return InviteStat(
      registeredUsers: list[0] as int? ?? 0,
      validCommission: list[1] as num? ?? 0,
      pendingCommission: list[2] as num? ?? 0,
      commissionRate: list[3] as num? ?? 0,
      availableCommission: list[4] as num? ?? 0,
    );
  }
}

class InviteCode {
  final int id;
  final int userId;
  final String code;
  final int status;
  final int pv;
  final int createdAt;
  final int updatedAt;

  InviteCode({
    required this.id,
    required this.userId,
    required this.code,
    required this.status,
    required this.pv,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InviteCode.fromJson(Map<String, dynamic> json) {
    return InviteCode(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      code: json['code'] as String? ?? '',
      status: json['status'] as int? ?? 0,
      pv: json['pv'] as int? ?? 0,
      createdAt: json['created_at'] as int? ?? 0,
      updatedAt: json['updated_at'] as int? ?? 0,
    );
  }
}

class InviteDetail {
  final int id;
  final num amount;
  final String? tradeNo;
  final num? orderAmount;
  final String? statusText;
  final int createdAt;

  InviteDetail({
    required this.id,
    required this.amount,
    this.tradeNo,
    this.orderAmount,
    this.statusText,
    required this.createdAt,
  });

  factory InviteDetail.fromJson(Map<String, dynamic> json) {
    return InviteDetail(
      id: json['id'] as int? ?? 0,
      amount: json['amount'] as num? ?? 0,
      tradeNo: json['trade_no'] as String?,
      orderAmount: json['order_amount'] as num?,
      statusText: json['status_text'] as String?,
      createdAt: json['created_at'] as int? ?? 0,
    );
  }
}
