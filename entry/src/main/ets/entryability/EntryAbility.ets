import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam) {}

  onWindowStageCreate(windowStage: window.WindowStage) {
    windowStage.loadContent('pages/Index', (err: Error | null) => {
      if (err) {
        console.error('Failed to load content: ' + JSON.stringify(err));
      }
    });

    try {
      const win = windowStage.getMainWindowSync();
      win.setWindowSystemBarProperties({
        statusBarColor: 'rgba(0,0,0,0)',      // 顶部透明
        statusBarContentColor: '#000000',
        navigationBarColor: 'rgba(0,0,0,0)',  // 底部透明
        navigationBarContentColor: '#000000'
      });
    } catch (e) {
      console.error('设置系统栏失败: ' + JSON.stringify(e));
    }
  }

  onWindowStageDestroy() {}
  onForeground() {}
  onBackground() {}
}