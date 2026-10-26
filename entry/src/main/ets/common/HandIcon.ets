import { IconMap } from './HandIcons';

/**
 * 手绘风通用图标组件。
 * name 传规范图标名（'egg'）或旧 emoji 字符（'🥚'），二者均可解析。
 */
@Component
export struct HandIcon {
  @Prop name: string = 'dot';
  @Prop iconSize: number = 18;

  build() {
    Image(IconMap.resolve(this.name))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }
}
