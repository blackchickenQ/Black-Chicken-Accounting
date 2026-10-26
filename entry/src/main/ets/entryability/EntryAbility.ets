import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
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

  // ARGB 数值转 '#AARRGGBB' 十六进制字符串（供窗口系统条接口使用）
  private colorToHex(argb: number): string {
    const seg = (v: number): string => (v < 16 ? '0' : '') + v.toString(16).toUpperCase();
    return '#'
      + seg((argb >>> 24) & 0xFF)
      + seg((argb >>> 16) & 0xFF)
      + seg((argb >>> 8) & 0xFF)
      + seg(argb & 0xFF);
  }

  // 系统条着色（全屏沉浸式布局下）：状态栏背景透明由页面内容延伸衬底；
  // 底部导航条着色为页面背景色 bg_main（随深浅色自动取值），小横杠（内容色）按背景亮度取黑/白
  private applyBottomBarColor(win: window.Window): void {
    try {
      const bg = this.context.resourceManager.getColorSync($r('app.color.bg_main').id);
      const lum = 0.299 * ((bg >>> 16) & 0xFF) + 0.587 * ((bg >>> 8) & 0xFF) + 0.114 * (bg & 0xFF);
      // 窗口背景色与页面 bg_main 一致：页面布局未覆盖到的区域由窗口背景兜底
      win.setWindowBackgroundColor(this.colorToHex(bg));
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: lum < 128 ? '#FFFFFF' : '#000000',
        navigationBarColor: this.colorToHex(bg),
        navigationBarContentColor: lum < 128 ? '#FFFFFF' : '#000000'
      });
      console.info('✅ 系统条着色完成: ' + this.colorToHex(bg));
    } catch (e) {
      console.error('❌ 系统条着色失败: ' + JSON.stringify(e));
    }
  }

  // 发布全屏沉浸式布局的安全区高度：状态栏/手势条避让高度换算为 vp 后写入 AppStorage，
  // 各页面通过 @StorageProp('statusBarVp'/'navBarVp') 订阅并做上下留白
  private publishSafeAreaInsets(win: window.Window): void {
    try {
      const density = display.getDefaultDisplaySync().densityPixels;
      const statusBarVp = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height / density;
      const navBarVp = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height / density;
      AppStorage.setOrCreate('statusBarVp', statusBarVp);
      AppStorage.setOrCreate('navBarVp', navBarVp);
      console.info('✅ 安全区高度发布: statusBar=' + statusBarVp.toFixed(1)
        + 'vp, navBar=' + navBarVp.toFixed(1) + 'vp');
    } catch (e) {
      console.error('❌ 安全区高度发布失败: ' + JSON.stringify(e));
    }
  }

  // 全屏沉浸式布局：窗口延伸覆盖状态栏与底部手势条区域，小横杠以透明浮层叠加在页面背景上；
  // 必须在页面加载前开启，避免首帧非全屏闪变
  private enterImmersiveMode(windowStage: window.WindowStage): Promise<void> {
    try {
      const win = windowStage.getMainWindowSync();
      return win.setWindowLayoutFullScreen(true).then(() => {
        console.info('✅ 全屏沉浸式布局已开启');
        // 全屏生效后发布安全区高度（各页面 @StorageProp 订阅）
        this.publishSafeAreaInsets(win);
        // 系统条着色：全屏切换过渡期窗口状态可能异常（1300002），延迟执行规避启动竞态
        setTimeout(() => {
          this.applyBottomBarColor(win);
        }, 500);
      }).catch((e: BusinessError) => {
        console.error('❌ 全屏布局设置失败: ' + JSON.stringify(e));
      });
    } catch (e) {
      console.error('❌ 全屏布局设置异常: ' + JSON.stringify(e));
      return Promise.resolve();
    }
  }



  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    // 预置宽屏断点键，确保页面创建时 @StorageProp 能正确建立订阅
    AppStorage.setOrCreate('isWideScreen', false);
    // 全屏沉浸式布局的安全区高度兜底值（真实值由 publishSafeAreaInsets 在窗口就绪后发布）
    AppStorage.setOrCreate('statusBarVp', 46);
    AppStorage.setOrCreate('navBarVp', 28);
  }


  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 先开启全屏沉浸式布局（页面加载前生效，避免首帧非全屏闪变），再加载入口页
    this.enterImmersiveMode(windowStage).then((): void => {
      this.loadEntryPage(windowStage);
    });
  }

  private async loadEntryPage(windowStage: window.WindowStage): Promise<void> {
    // 统一加载主页（router→Navigation 重构后引导页/子页面均为主页导航栈内的 NavDestination，
    // 首启引导由 Index.aboutToAppear 检测 guide_intro_done 后入栈）
    windowStage.loadContent('pages/Index', (err) => {
      // 注意：API 26+ 成功回调也携带 err 对象（code 为 0），必须判断 err.code 而非 err 本身
      if (err && err.code) {
        console.error('❌ 加载页面失败: ' + JSON.stringify(err));
        return;
      }
      console.info('✅ 页面加载成功');

      // 全局手写字体：注册霞鹜文楷（GB2312 子集，生僻字自动回退系统字体）
      try {
        const win0 = windowStage.getMainWindowSync();
        win0.getUIContext().getFont().registerFont({
          familyName: 'LXGW WenKai',
          familySrc: $rawfile('font/LXGWWenKai-Regular.ttf')
        });
        this.context.getApplicationContext().setFont('LXGW WenKai');
        console.info('✅ 手写字体注册成功');
        // registerFont 为异步接口：延迟重设一次，确保首帧渲染时未就绪的文本重新解析字体族
        setTimeout(() => {
          this.context.getApplicationContext().setFont('LXGW WenKai');
        }, 600);
      } catch (e) {
        console.error('❌ 手写字体注册失败: ' + JSON.stringify(e));
      }

      try {
        const win = windowStage.getMainWindowSync();

        // 宽屏断点检测：初始一次 + 窗口尺寸变化时更新（分屏/折叠/旋转）
        this.updateWideScreenState(win.getWindowProperties().windowRect.width);
        win.on('windowSizeChange', (size: Size) => {
          this.updateWideScreenState(size.width);
        });
        console.info('✅ 窗口属性设置成功');
      } catch (e) {
        console.error('❌ 设置窗口属性失败: ' + JSON.stringify(e));
      }
    });
  }

  onWindowStageDestroy(): void {}

  onConfigurationUpdate(_newConfig: Configuration): void {
    // 深浅色切换时重刷底部导航条着色（bg_main 资源随模式自动取值）
    window.getLastWindow(this.context).then((win: window.Window): void => {
      this.applyBottomBarColor(win);
    }).catch(() => {});
  }
  onForeground(): void {
    // 从后台回前台：已设隐私锁时，清空主页导航栈回到主页，
    // 由 Index.onPageShow 消费 privacy_should_relock 信号重新上锁（信号已在 onBackground 置位）
    if (!this.pendingRelock) {
      return;
    }
    this.pendingRelock = false;
    isPinSet(this.context).then((set: boolean): void => {
      if (!set) {
        return;
      }
      const stack = AppStorage.get<NavPathStack>('navPathStack');
      if (stack !== undefined) {
        stack.clear();
      }
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