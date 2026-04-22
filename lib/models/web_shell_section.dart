import 'package:flutter/material.dart';

enum WebShellSection { home, purchase, help, invite, account }

extension WebShellSectionX on WebShellSection {
  IconData get icon {
    switch (this) {
      case WebShellSection.home:
        return Icons.home_rounded;
      case WebShellSection.purchase:
        return Icons.shopping_bag_outlined;
      case WebShellSection.help:
        return Icons.help_outline_rounded;
      case WebShellSection.invite:
        return Icons.redeem_outlined;
      case WebShellSection.account:
        return Icons.person_outline_rounded;
    }
  }

  String label(bool isChinese) {
    switch (this) {
      case WebShellSection.home:
        return isChinese ? '主页' : 'Home';
      case WebShellSection.purchase:
        return isChinese ? '购买' : 'Purchase';
      case WebShellSection.help:
        return isChinese ? '帮助' : 'Help';
      case WebShellSection.invite:
        return isChinese ? '邀请' : 'Invite';
      case WebShellSection.account:
        return isChinese ? '用户' : 'User';
    }
  }
}
