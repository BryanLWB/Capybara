import '../services/app_api.dart';
import '../services/panel_api.dart';

enum WebErrorContext {
  authLogin,
  authForm,
  pageLoad,
  quickAction,
  general,
}

String webErrorText(
  Object error, {
  required bool isChinese,
  WebErrorContext context = WebErrorContext.general,
}) {
  if (error is PanelApiException) {
    return _fromError(
      statusCode: error.statusCode,
      code: error.code,
      message: error.message,
      isChinese: isChinese,
      context: context,
    );
  }

  if (error is AppApiException) {
    return _fromError(
      statusCode: error.statusCode,
      code: error.code,
      message: error.message,
      isChinese: isChinese,
      context: context,
    );
  }

  return _genericMessage(isChinese, context);
}

String _fromError({
  required int statusCode,
  required String? code,
  required String message,
  required bool isChinese,
  required WebErrorContext context,
}) {
  if (code == 'auth.required' || statusCode == 403) {
    return isChinese
        ? '登录状态已失效，请重新登录后再试。'
        : 'Your session has expired. Please sign in again.';
  }

  if (context == WebErrorContext.authLogin &&
      (code == 'auth.invalid' ||
          statusCode == 401 ||
          statusCode == 400 ||
          message == 'Request failed')) {
    return isChinese
        ? '邮箱或密码不正确，请重新输入。'
        : 'Incorrect email or password. Please try again.';
  }

  if (context == WebErrorContext.authForm &&
      (code == 'request.invalid' || statusCode == 400)) {
    return isChinese
        ? '请检查填写的信息后再试。'
        : 'Please check your details and try again.';
  }

  if (code == 'subscription.required') {
    return isChinese
        ? '开通套餐后即可使用订阅链接。'
        : 'A subscription is required before using this link.';
  }

  if (code == 'subscription.unavailable') {
    return isChinese
        ? '当前订阅内容暂时不可用，请稍后再试或联系在线客服。'
        : 'Subscription content is temporarily unavailable.';
  }

  if (code == 'commerce.coupon_invalid') {
    return isChinese
        ? '优惠券不可用或不适用于当前套餐。'
        : 'This coupon is not valid for the selected plan.';
  }

  if (code == 'commerce.payment_method_unavailable' ||
      code == 'commerce.no_payment_methods') {
    return isChinese
        ? '当前暂无可用支付方式，请稍后再试或联系在线客服。'
        : 'No payment methods are available right now.';
  }

  if (code == 'commerce.pending_order_exists') {
    return isChinese
        ? '检测到已有待支付订单，请前往我的订单继续处理。'
        : 'You already have a pending order.';
  }

  if (code == 'referrals.no_withdrawable_commission') {
    return isChinese
        ? '当前没有可操作的佣金。'
        : 'There is no commission available right now.';
  }

  if (code == 'referrals.transfer_amount_invalid') {
    return isChinese
        ? '输入金额超出可转范围，请重新检查后再试。'
        : 'The amount is outside the transferable range.';
  }

  if (code == 'referrals.withdrawal_unavailable') {
    return isChinese
        ? '当前暂时无法申请提现，请确认佣金余额或联系在线客服。'
        : 'Withdrawals are unavailable right now.';
  }

  if (code == 'rewards.redeem_failed') {
    return isChinese
        ? '兑换失败，请检查兑换码后重试。'
        : 'Redemption failed. Please check the code and try again.';
  }

  if (code == 'support.ticket_invalid') {
    return isChinese
        ? '请完善工单标题和问题描述后再提交。'
        : 'Please complete the ticket subject and message before submitting.';
  }

  if (code == 'support.ticket_reply_unavailable') {
    return isChinese
        ? '当前暂时无法回复这张工单，请稍后再试。'
        : 'This ticket cannot be replied to right now.';
  }

  if (code == 'support.ticket_close_unavailable') {
    return isChinese
        ? '当前暂时无法关闭这张工单，请稍后再试。'
        : 'This ticket cannot be closed right now.';
  }

  if (code == 'support.ticket_not_found') {
    return isChinese
        ? '这张工单暂时无法查看，请刷新后重试。'
        : 'This ticket is not available right now.';
  }

  return _genericMessage(isChinese, context);
}

String _genericMessage(bool isChinese, WebErrorContext context) {
  switch (context) {
    case WebErrorContext.pageLoad:
      return isChinese
          ? '当前内容暂时无法加载，请稍后刷新重试。'
          : 'This content is not available right now. Please refresh and try again.';
    case WebErrorContext.quickAction:
      return isChinese
          ? '暂时无法完成这个操作，请稍后再试。'
          : 'This action is not available right now. Please try again later.';
    case WebErrorContext.authLogin:
    case WebErrorContext.authForm:
    case WebErrorContext.general:
      return isChinese
          ? '暂时无法完成操作，请稍后再试。'
          : 'We could not complete that action right now. Please try again later.';
  }
}
