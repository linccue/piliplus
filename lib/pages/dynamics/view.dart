import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/common/widgets/pendant_avatar.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;

class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key});

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends CommonPageState<DynamicsPage>
    with AutomaticKeepAliveClientMixin {
  final _dynamicsController = Get.putOrFind(DynamicsController.new);
  UpPanelPosition get upPanelPosition => _dynamicsController.upPanelPosition;
  late final MainController _mainController = Get.find<MainController>();

  bool _hideAppBar = false;
  // 新增：用于记录向上滑动的距离，防止微小滑动就唤醒顶栏
  double _scrollUpDistance = 0.0;

  @override
  bool get wantKeepAlive => true;

  Widget _createAvatarBtn({bool isRight = true}) =>
      Container(
        width: 34,
        height: 34,
        margin: isRight ? const .only(right: 16) : const .only(left: 16),
        child: GestureDetector(
          onTap: () {
            _mainController.toMinePage();
          },
          behavior: HitTestBehavior.opaque,
          child: PendantAvatar(
            Pref.userInfoCache?.face ??
                'https://i0.hdslb.com/bfs/face/member/noface.jpg',
            size: 34,
          ),
        ),
      );

  Widget upPanelPart(ColorScheme colorScheme) {
    final isTop = upPanelPosition == .top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? .canvas : .transparency,
      color: needBg ? colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 64,
        height: isTop ? 76 : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 300) {
              _dynamicsController.onLoadMore();
            }
            return false;
          },
          child: Obx(
            () => _buildUpPanel(_dynamicsController.loadingState.value),
          ),
        ),
      ),
    );
  }

  Widget _buildUpPanel(LoadingState<FollowUpModel> upState) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => UpPanel(
        upData: response,
        dynamicsController: _dynamicsController,
      ),
      Error() => Center(
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _dynamicsController.onReload,
        ),
      ),
    };
  }

  bool get checkPage =>
      _mainController.navigationBars[0] != .dynamics &&
      _mainController.selectedIndex.value == 0;

  @override
  bool onNotificationType1(UserScrollNotification notification) {
    if (checkPage) return false;
    return super.onNotificationType1(notification);
  }

  @override
  bool onNotificationType2(ScrollNotification notification) {
    if (checkPage) return false;
    return super.onNotificationType2(notification);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);

    Widget? drawer;
    Widget? endDrawer;

    Widget? leading;
    Widget actions;

    final tabTypes = Pref.dynamicsTabs;

    Widget child = tabBarView(
      controller: _dynamicsController.tabController,
      children: tabTypes
          .map((e) => DynamicsTabPage(dynamicsType: e))
          .toList(),
    );

    switch (upPanelPosition) {
      case .top:
        child = Column(
          children: [upPanelPart(colorScheme), Expanded(child: child)],
        );
        actions = _createAvatarBtn();
      case .leftFixed:
        child = Row(
          children: [upPanelPart(colorScheme), Expanded(child: child)],
        );
        actions = _createAvatarBtn();
      case .rightFixed:
        child = Row(
          children: [Expanded(child: child), upPanelPart(colorScheme)],
        );
        actions = _createAvatarBtn();
      case .leftDrawer:
        drawer = upPanelPart(colorScheme);
        leading = const DrawerButton();
        actions = _createAvatarBtn();
      case .rightDrawer:
        endDrawer = upPanelPart(colorScheme);
        leading = _createAvatarBtn(isRight: false);
        actions = const EndDrawerButton();
    }

    // ===== 插入无痕模式图标 =====
    if (Pref.showIncognitoInDynamics) {
      final incognitoBtn = Obx(() {
        final anonymity = MineController.anonymity.value;
        return IconButton(
          iconSize: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tooltip: "${anonymity ? '退出' : '进入'}无痕模式",
          onPressed: MineController.onChangeAnonymity,
          icon: anonymity
              ? const Icon(MdiIcons.incognito)
              : const Icon(MdiIcons.incognitoOff),
        );
      });

      if (Pref.incognitoOnLeft) {
        if (leading != null) {
          leading = Row(
            mainAxisSize: MainAxisSize.min,
            children: [leading!, incognitoBtn],
          );
        } else {
          leading = incognitoBtn;
        }
      } else {
        actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [incognitoBtn, actions],
        );
      }
    }

    return Scaffold(
      primary: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      drawer: drawer,
      endDrawer: endDrawer,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (checkPage) return false;
          
          if (notification is ScrollUpdateNotification) {
            final delta = notification.scrollDelta ?? 0;
            
            if (_hideAppBar) {
              // 如果当前是隐藏状态
              if (delta < 0) {
                // 向上滑动（看历史），累积滑动距离
                _scrollUpDistance += -delta;
                // 只有当累积向上的滑动超过 60 像素时，才显示顶栏
                if (_scrollUpDistance > 60.0) {
                  setState(() => _hideAppBar = false);
                  _scrollUpDistance = 0.0;
                }
              } else if (delta > 0) {
                // 如果中途又向下滑了，重置累积距离
                _scrollUpDistance = 0.0;
              }
            } else {
              // 如果当前是显示状态
              if (delta > 0 && notification.metrics.pixels > 0) {
                // 只要向下滑动（看新内容）且不在最顶部，立刻隐藏
                setState(() => _hideAppBar = true);
                _scrollUpDistance = 0.0;
              }
            }
          }
          return false;
        },
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              height: _hideAppBar ? 0 : 50,
              child: ClipRect(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _hideAppBar ? 0.0 : 1.0,
                  child: OverflowBox(
                    minHeight: 50,
                    maxHeight: 50,
                    alignment: Alignment.bottomCenter,
                    child: Row(
                      children: [
                        ?leading,
                        Expanded(
                          child: TabBar(
                            dividerHeight: 0,
                            isScrollable: true,
                            tabAlignment: TabAlignment.center,
                            dividerColor: Colors.transparent,
                            labelColor: colorScheme.primary,
                            indicatorColor: colorScheme.primary,
                            controller: _dynamicsController.tabController,
                            unselectedLabelColor: colorScheme.onSurface,
                            labelStyle:
                                TabBarTheme.of(context).labelStyle?.copyWith(
                                      fontSize: 13,
                                    ) ??
                                    const TextStyle(fontSize: 13),
                            tabs: tabTypes
                                .map((e) => Tab(text: e.label))
                                .toList(),
                            onTap: (index) {
                              if (!_dynamicsController
                                  .tabController.indexIsChanging) {
                                _dynamicsController.animateToTop();
                              }
                            },
                          ),
                        ),
                        actions,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: onBuild(child),
            ),
          ],
        ),
      ),
    );
  }
}
