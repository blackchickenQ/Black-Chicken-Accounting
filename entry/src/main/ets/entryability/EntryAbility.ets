import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { Configuration } from '@ohos.app.ability.Configuration';


export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {}


  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err) {
        console.error('❌ 加载页面失败: ' + JSON.stringify(err));
        return;
      }
      console.info('✅ 页面加载成功');

      try {
        const win = windowStage.getMainWindowSync();
        win.setWindowLayoutFullScreen(true);

        // ✅ 不再主动获取系统颜色模式，由 onConfigurationUpdate 负责更新
        // 首次启动时，systemColorMode 默认为 COLORMODE_LIGHT
        // 但如果系统当前是深色，用户切换到深色时会触发 onConfigurationUpdate

        const colorMode = AppStorage.get('currentColorMode') as ConfigurationConstant.ColorMode;
        const isDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;

        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
          navigationBarColor: isDark ? '#0D0D0D' : '#F2F4F8',
          navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
        });
        console.info('✅ 沉浸式设置成功');
      } catch (e) {
        console.error('❌ 设置窗口属性失败: ' + JSON.stringify(e));
      }
    });
  }

  onWindowStageDestroy(): void {}
  onForeground(): void {}
  onBackground(): void {}
}