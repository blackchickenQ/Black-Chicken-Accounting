import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { Configuration } from '@ohos.app.ability.Configuration';
import dataPreferences from '@ohos.data.preferences';
import { isPinSet } from '../common/PrivacyLock';


export default class EntryAbility extends UIAbility {
  // 平板/折叠屏宽屏断点：窗口宽度 >= 840vp 视为宽屏，全局写入 AppStorage 供各页面响应
  private updateWideScreenState(widthPx: number): void {
    const density = display.getDefaultDisplaySync().densityPixels;
    const widthVp = widthPx / density;
    const isWide = widthVp >= 840;
    AppStorage.setOrCreate('isWideScreen', isWide);
    console.info('📐 宽屏断点检测: widthPx=' + widthPx + ', density=' + density
      + ', widthVp=' + widthVp.toFixed(0) + ', isWideScreen=' + isWide);
  }


  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    // 预置宽屏断点键，确保页面创建时 @StorageProp 能正确建立订阅
    AppStorage.setOrCreate('isWideScreen', false);
  }


  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 首次启动（未看过引导介绍页）先加载引导页，否则直接进入主页
    this.loadEntryPage(windowStage);
  }

  private async loadEntryPage(windowStage: window.WindowStage): Promise<void> {
    let firstPage: string = 'pages/Index';
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'bill_data');
      const introDone = await prefs.get('guide_intro_done', false) as boolean;
      if (!introDone) {
        firstPage = 'pages/GuideIntroPage';
      }
    } catch (e) {
      console.error('读取引导状态失败，默认进入主页: ' + JSON.stringify(e));
    }
    windowStage.loadContent(firstPage, (err) => {
      if (err) {
        console.error('❌ 加载页面失败: ' + JSON.stringify(err));
        return;
      }
      console.info('✅ 页面加载成功');

      try {
        const win = windowStage.getMainWindowSync();
        win.setWindowLayoutFullScreen(true);

        // 宽屏断点检测：初始一次 + 窗口尺寸变化时更新（分屏/折叠/旋转）
        this.updateWideScreenState(win.getWindowProperties().windowRect.width);
        win.on('windowSizeChange', (size: Size) => {
          this.updateWideScreenState(size.width);
        });

        // ✅ 不再主动获取系统颜色模式，由 onConfigurationUpdate 负责更新
        // 首次启动时，systemColorMode 默认为 COLORMODE_LIGHT
        // 但如果系统当前是深色，用户切换到深色时会触发 onConfigurationUpdate

        const colorMode = AppStorage.get('currentColorMode') as ConfigurationConstant.ColorMode;
        const isDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;

        // 窗口背景色与页面 bg_main 保持一致，避免导航条区域露出异色底
        win.setWindowBackgroundColor(isDark ? '#101116' : '#F6F7FB');

        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
          navigationBarColor: isDark ? '#101116' : '#F6F7FB',
          navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
        });
        console.info('✅ 沉浸式设置成功');
      } catch (e) {
        console.error('❌ 设置窗口属性失败: ' + JSON.stringify(e));
      }
    });
  }

  onWindowStageDestroy(): void {}
  onForeground(): void {
    // 从后台回前台：已设隐私锁时，无论当前停在哪个子页面，
    // 都退回主页让锁屏置顶（privacy_should_relock 已在 onBackground 置位）
    if (!this.pendingRelock) {
      return;
    }
    this.pendingRelock = false;
    isPinSet(this.context).then((set: boolean): void => {
      if (!set) {
        return;
      }
      window.getLastWindow(this.context).then((win: window.Window): void => {
        win.getUIContext().getRouter().back({ url: 'pages/Index' });
      }).catch(() => {});
    }).catch(() => {});
  }
  onBackground(): void {
    // 隐私锁：应用真正退到后台时通知首页重新锁定（由 Index.onPageShow 消费）。
    // 不在 onForeground 设置，避免指纹认证弹窗、系统分享面板等临时系统界面结束时误置信号，
    // 导致解锁后在"我的"子页面间切换返回时被误要求重新输入密码。
    this.pendingRelock = true;
    AppStorage.setOrCreate('privacy_should_relock', true);
  }

  // 本次前台期间是否发生过真正的退后台（冷启动为 false，避免误触发重新上锁）
  private pendingRelock: boolean = false;
}