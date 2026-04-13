import 'package:flutter/material.dart';

import '../models/web_mock_content.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_card.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_page_frame.dart';
import '../widgets/web_page_hero.dart';

class WebPurchasePage extends StatefulWidget {
  const WebPurchasePage({super.key});

  @override
  State<WebPurchasePage> createState() => _WebPurchasePageState();
}

class _WebPurchasePageState extends State<WebPurchasePage> {
  WebPlanFilter _filter = WebPlanFilter.all;
  WebMockPlan? _selectedPlan;

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  List<WebMockPlan> _plans() {
    if (_filter == WebPlanFilter.all) return webMockPlans;
    return webMockPlans.where((plan) => plan.filter == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);

    return WebPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebPageHero(
            title: isChinese ? '选择更适合你的套餐' : 'Choose a plan that fits you',
            subtitle: isChinese
                ? '先把购买页壳子铺出来。当前只做本地筛选和套餐预览，真实下单流程下一轮接入。'
                : 'This page is scaffolded first. Filtering and selection are local-only for now, while real checkout comes next.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: WebPlanFilter.values
                  .map(
                    (filter) => _FilterPill(
                      label: filter.label(isChinese),
                      selected: _filter == filter,
                      onTap: () => setState(() => _filter = filter),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (_selectedPlan != null) ...[
            const SizedBox(height: 16),
            GradientCard(
              borderRadius: 28,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: AppColors.accent.withValues(alpha: 0.14),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isChinese ? '已选套餐预览' : 'Selected plan preview',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isChinese
                              ? '${_selectedPlan!.title}，当前只做本地选中预览，真实下单流程下一轮接入。'
                              : '${_selectedPlan!.title} is selected locally. Real checkout will be connected in the next round.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _selectedPlan!.priceValue,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 26,
                        ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 1320
                  ? 3
                  : width >= 860
                      ? 2
                      : 1;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 380,
                ),
                itemCount: _plans().length,
                itemBuilder: (context, index) {
                  final plan = _plans()[index];
                  return _PlanCard(
                    plan: plan,
                    selected: _selectedPlan?.id == plan.id,
                    isChinese: isChinese,
                    onTap: () => setState(() => _selectedPlan = plan),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : AppColors.surfaceAlt.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.isChinese,
    required this.onTap,
  });

  final WebMockPlan plan;
  final bool selected;
  final bool isChinese;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      enableBreathing: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: 26,
                                height: 1.05,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      plan.summary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 16,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppColors.accent.withValues(alpha: 0.14),
                ),
                child: Text(
                  plan.traffic,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...plan.features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.brightness_1_rounded,
                      size: 6,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                            height: 1.45,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            plan.deviceLimit,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            plan.resetPack,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                plan.priceLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                    ),
              ),
              const Spacer(),
              Text(
                plan.priceValue,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 34,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(
                  color: selected ? AppColors.accent : AppColors.border,
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                backgroundColor: selected
                    ? AppColors.accent.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
              child: Text(
                isChinese ? '立即购买' : 'Purchase Now',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
