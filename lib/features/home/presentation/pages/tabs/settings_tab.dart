import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/common/widgets/cache_image.dart';
import 'package:JsxposedX/common/widgets/custom_dIalog.dart';
import 'package:JsxposedX/core/constants/assets_constants.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/providers/locale_provider.dart';
import 'package:JsxposedX/core/providers/status_management_provider.dart';
import 'package:JsxposedX/core/providers/theme_provider.dart';
import 'package:JsxposedX/core/utils/procedure_utils.dart';
import 'package:JsxposedX/core/utils/url_helper.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_config_sheet.dart';
import 'package:JsxposedX/features/home/presentation/widgets/settings_community_card.dart';
import 'package:JsxposedX/features/home/presentation/widgets/settings_section.dart';
import 'package:JsxposedX/features/home/presentation/widgets/settings_tile.dart';
import 'package:JsxposedX/features/home/presentation/widgets/theme_color_picker.dart';
import 'package:JsxposedX/core/routes/routes/home_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const String _forumHost = 'muxue.pro';
const String _forumUrl = 'https://muxue.pro';
const String _discordUrl = 'https://discord.gg/sUHbq6jHeZ';
const String _facebookUrl =
    'https://www.facebook.com/share/16nAHDLhAp/?mibextid=wwXIfr';
const String _tiktokUrl =
    'https://www.tiktok.com/@wanfengd?_r=1&_t=ZP-94YMtmcFzAN';
const String _douyinUrl = 'https://v.douyin.com/hgm3ny4eehs/';
const String _bilibiliUrl = 'https://b23.tv/wIvEf06';
const String _youtubeUrl =
    'https://youtube.com/channel/UCXH3m2W67bwMDBsTRibagmw?si=i1kwAbgOMrY3gtKE';
const String _qqGroupUrl =
    'https://qun.qq.com/universal-share/share?ac=1&authKey=CoeFZQRhWhCHjLTPhZC%2BVcCSkHb431ulekylEVq8Cy9g%2FF9nNwzaak3lrpzPmez4&busi_data=eyJncm91cENvZGUiOiIzMzUwNDc4MzQiLCJ0b2tlbiI6IjhkekxXRklPcU9nNCtLbnhQM3FjeWFOT3VnTW5SY2E2ZVNYL25Fdjc5dlI1a1ZVMTlsYUtwbzNRblo2R01xOXMiLCJ1aW4iOiIzMTEzMTQzNjY2In0%3D&data=_T2_0SMUSubLMt0YcN1MGZJF9zB2cR1tByzZ7-nin-3yDQ_QIxc9UfAHGCD4I5pkd1bunaTW6aZqZ3NmHeepJg&svctype=4&tempid=h5_group_info';
const String _targetRangeUrl =
    'https://pan.xunlei.com/s/VOodpELVGUCsmDw41eT_cxBaA1?pwd=2x75';
const String _projectUrl = 'https://jsxposed.org';
const String _repositoryUrl = 'https://github.com/dugongzi/JsxposedX';

const List<_ExternalLinkItem> _creatorLinks = [
  _ExternalLinkItem(
    title: 'Facebook',
    url: _facebookUrl,
    imageAsset: AssetsConstants.facebook,
    color: Color(0xFF1877F2),
  ),
  _ExternalLinkItem(
    title: 'TikTok',
    url: _tiktokUrl,
    imageAsset: AssetsConstants.tiktok,
    color: Color(0xFF111111),
  ),
  _ExternalLinkItem(
    title: '抖音',
    url: _douyinUrl,
    imageAsset: AssetsConstants.tiktok,
    color: Color(0xFF161823),
  ),
  _ExternalLinkItem(
    title: '哔哩哔哩',
    url: _bilibiliUrl,
    imageAsset: AssetsConstants.blbl,
    color: Color(0xFFFB7299),
  ),
  _ExternalLinkItem(
    title: 'YouTube',
    url: _youtubeUrl,
    imageAsset: AssetsConstants.youtube,
    color: Color(0xFFFF0033),
  ),
];

/// 设置 Tab
class SettingsTab extends HookConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomBarSpacing = 60.h + 10.h + bottomInset + 24.h;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 20.h)),
        SliverToBoxAdapter(
          child: SettingsCommunityCard(
            forumHost: _forumHost,
            onVisitForum: () => UrlHelper.openUrlInBrowser(url: _forumUrl),
            onJoinDiscord: () => UrlHelper.openUrlInBrowser(url: _discordUrl),
            onJoinQQGroup: () => UrlHelper.openUrlInBrowser(url: _qqGroupUrl),
            onOpenTargetRange: () =>
                UrlHelper.openUrlInBrowser(url: _targetRangeUrl),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20.h)),
        SliverToBoxAdapter(
          child: SettingsSection(
            title: context.l10n.settings,
            items: [
              SettingsTile(
                icon: Icons.translate,
                title: context.l10n.language,
                subtitle: context.isChinese
                    ? context.l10n.chinese
                    : context.l10n.english,
                onTap: () {
                  if (context.isChinese) {
                    ref.read(localeProvider.notifier).setEn();
                    return;
                  }
                  ref.read(localeProvider.notifier).setZh();
                },
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.palette_rounded,
                title: context.l10n.theme,
                subtitle: context.theme.brightness == Brightness.dark
                    ? context.l10n.darkTheme
                    : context.l10n.lightTheme,
                onTap: () {
                  ref.read(themeProvider.notifier).toggleTheme();
                },
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.color_lens_rounded,
                title: context.l10n.themeColor,
                onTap: () => ThemeColorPicker.show(context),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.smart_toy_rounded,
                title: context.l10n.aiConfig,
                onTap: () {
                  final isHook = ref.read(isHookProvider).value ?? false;
                  if (!isHook) {
                    ToastMessage.show(context.l10n.pleaseActivateXposed);
                    return;
                  }
                  AIConfigSheet.show(context);
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20.h)),
        SliverToBoxAdapter(
          child: SettingsSection(
            title: context.l10n.followAuthor,
            items: [
              SettingsTile(
                icon: Icons.emoji_people_rounded,
                title: context.l10n.creatorPlatforms,
                subtitle: context.l10n.morePlatforms,
                onTap: () => _showCreatorLinksDialog(context),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.qr_code_rounded,
                title: context.isZh ? '微信公众号' : 'WeChat Channel',
                onTap: () => _showWechatDialog(context),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20.h)),
        SliverToBoxAdapter(
          child: SettingsSection(
            title: context.isZh ? '桌面连接' : 'Desktop connection',
            items: [
              SettingsTile(
                icon: Icons.wifi_tethering_rounded,
                title: context.isZh ? '局域网直连' : 'Wi-Fi direct',
                subtitle: context.isZh
                    ? '不插线，在电脑上操作；需要同一 Wi-Fi'
                    : 'Use the desktop app without a cable',
                onTap: () => context.push(HomeRoute.lanBridge),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20.h)),
        SliverToBoxAdapter(
          child: SettingsSection(
            title: context.l10n.about,
            items: [
              const _AboutSummaryTile(),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.policy_rounded,
                title: context.l10n.disclaimer,
                onTap: () => _showDisclaimerDialog(context),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.public_rounded,
                title: context.isChinese ? "官网" : "Site",
                subtitle: context.isZh ? '获取最新教程' : 'tutorials',
                onTap: () => UrlHelper.openUrlInBrowser(url: _projectUrl),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.code_rounded,
                title: context.l10n.repository,
                subtitle: 'GitHub',
                onTap: () => UrlHelper.openUrlInBrowser(url: _repositoryUrl),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: bottomBarSpacing)),
      ],
    );
  }

  Future<void> _showCreatorLinksDialog(BuildContext context) {
    final colorScheme = context.colorScheme;

    return CustomDialog.show<void>(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, color: colorScheme.primary),
          SizedBox(width: 8.w),
          Text(context.l10n.creatorPlatforms),
        ],
      ),
      hasClose: true,
      width: 0.9.sw,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 0.58.sh),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.isZh
                    ? '选择一个平台，继续关注作者的最新内容与动态。'
                    : 'Choose a platform to keep up with the latest creator updates.',
                style: context.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 16.h),
              LayoutBuilder(
                builder: (context, constraints) {
                  final spacing = 12.w;
                  final runSpacing = 12.h;
                  final isTwoColumns = constraints.maxWidth >= 280;
                  final itemWidth = isTwoColumns
                      ? (constraints.maxWidth - spacing) / 2
                      : constraints.maxWidth;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: runSpacing,
                    children: _creatorLinks
                        .map(
                          (item) => SizedBox(
                            width: itemWidth,
                            child: _CreatorLinkCard(item: item),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actionButtons: [
        TextButton(
          onPressed: () => SmartDialog.dismiss(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }

  Future<void> _showWechatDialog(BuildContext context) {
    return CustomDialog.show<void>(
      title: Text(context.isZh ? '微信公众号' : 'WeChat Channel'),
      hasClose: true,
      width: 0.88.sw,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: AspectRatio(
              aspectRatio: 1885 / 624,
              child: Image.asset(
                AssetsConstants.wx,
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            ),
          ),
        ],
      ),
      actionButtons: [
        TextButton(
          onPressed: () => SmartDialog.dismiss(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }

  Future<void> _showDisclaimerDialog(BuildContext context) {
    final colorScheme = context.colorScheme;
    final items = [
      _DisclaimerItem(
        icon: Icons.verified_user_rounded,
        title: context.l10n.disclaimerLegalTitle,
        body: context.l10n.disclaimerLegalBody,
      ),
      _DisclaimerItem(
        icon: Icons.block_rounded,
        title: context.l10n.disclaimerProhibitedTitle,
        body: context.l10n.disclaimerProhibitedBody,
      ),
      _DisclaimerItem(
        icon: Icons.assignment_turned_in_rounded,
        title: context.l10n.disclaimerResponsibilityTitle,
        body: context.l10n.disclaimerResponsibilityBody,
      ),
      _DisclaimerItem(
        icon: Icons.smart_toy_rounded,
        title: context.l10n.disclaimerAiTitle,
        body: context.l10n.disclaimerAiBody,
      ),
    ];

    return CustomDialog.show<void>(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.policy_rounded, color: colorScheme.primary),
          SizedBox(width: 8.w),
          Text(context.l10n.disclaimer),
        ],
      ),
      hasClose: true,
      width: 0.9.sw,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 0.68.sh),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.disclaimerDialogIntro,
                style: context.textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 14.h),
              ...items.map(
                (item) => Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: _DisclaimerBlock(item: item),
                ),
              ),
            ],
          ),
        ),
      ),
      actionButtons: [
        TextButton(
          onPressed: () => SmartDialog.dismiss(),
          child: Text(context.l10n.confirm),
        ),
      ],
    );
  }
}

class _DisclaimerBlock extends StatelessWidget {
  const _DisclaimerBlock({required this.item});

  final _DisclaimerItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, size: 18.sp, color: colorScheme.primary),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  item.title,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            item.body,
            style: context.textTheme.bodySmall?.copyWith(
              height: 1.55,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerItem {
  const _DisclaimerItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _AboutSummaryTile extends StatelessWidget {
  const _AboutSummaryTile();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return FutureBuilder<String>(
      future: _buildVersionText(),
      builder: (context, snapshot) {
        final versionText = snapshot.data ?? '...';

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5.r),
                    child: CacheImage(
                      imageUrl: AssetsConstants.logo,
                      size: 40.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.appName,
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          context.l10n.appSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall?.copyWith(
                            height: 1.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  _AboutInfoPill(
                    icon: Icons.new_releases_rounded,
                    label: versionText,
                  ),
                  _AboutInfoPill(
                    icon: Icons.verified_rounded,
                    label: 'Xposed · Frida',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _buildVersionText() async {
    final version = await ProcedureUtils.getVersionName();
    final build = await ProcedureUtils.getBuildNumber();
    return 'v$version+$build';
  }
}

class _AboutInfoPill extends StatelessWidget {
  const _AboutInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.sp, color: colorScheme.primary),
          SizedBox(width: 6.w),
          Text(
            label,
            style: context.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatorLinkCard extends StatelessWidget {
  const _CreatorLinkCard({required this.item});

  final _ExternalLinkItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final baseColor = item.color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await SmartDialog.dismiss();
          await UrlHelper.openUrlInBrowser(url: item.url);
        },
        borderRadius: BorderRadius.circular(18.r),
        child: Container(
          constraints: const BoxConstraints(minHeight: 118),
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: baseColor.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: context.isDark ? 0.12 : 0.04,
                ),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: baseColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: item.imageAsset != null
                        ? Padding(
                            padding: EdgeInsets.all(9.w),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10.r),
                              child: CacheImage(
                                imageUrl: item.imageAsset!,
                                width: 22.w,
                                height: 22.w,
                                fit: BoxFit.contain,
                              ),
                            ),
                          )
                        : Icon(
                            item.fallbackIcon,
                            color: baseColor,
                            size: 22.sp,
                          ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 18.sp,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                context.isZh ? '点击打开' : 'Tap to open',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExternalLinkItem {
  const _ExternalLinkItem({
    required this.title,
    required this.url,
    this.imageAsset,
    this.fallbackIcon,
    required this.color,
  }) : assert(imageAsset != null || fallbackIcon != null);

  final String title;
  final String url;
  final String? imageAsset;
  final IconData? fallbackIcon;
  final Color color;
}
