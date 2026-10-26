import { IconMap } from './HandIcons';

/**
 * 手绘风通用图标组件。
 * name 传规范图标名（'egg'）或旧 emoji 字符（'🥚'），二者均可解析。
 */
// V2 状态管理：@Param 父组件传参（单向同步）
@ComponentV2
export struct HandIcon {
  @Param name: string = 'dot';
  @Param iconSize: number = 18;

  build() {
    Image(IconMap.resolve(this.name))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }
}
