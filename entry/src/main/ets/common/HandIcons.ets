/**
 * 手绘风图标资源映射表。
 * resolve() 支持两种键：
 *   1. 规范图标名（'egg'、'tree'、'star_glow' ...）
 *   2. 旧版 emoji 字符（'🥚'、'🌳' ...）——兼容历史持久化数据，零迁移直接渲染
 * 未命中时返回 hd_dot 兜底小圆点。
 */

export const FONT_HAND: string = 'LXGW WenKai';

export class IconMap {
  private static readonly fallback: Resource = $r('app.media.hd_dot');

  private static readonly icons: Record<string, Resource> = {
    'egg': $r('app.media.hd_egg'),
    'coin': $r('app.media.hd_coin'),
    'chick': $r('app.media.hd_chick'),
    'tree': $r('app.media.hd_tree'),
    'sprout': $r('app.media.hd_sprout'),
    'leaf': $r('app.media.hd_leaf'),
    'nut': $r('app.media.hd_nut'),
    'star': $r('app.media.hd_star'),
    'star_glow': $r('app.media.hd_star_glow'),
    'sparkle': $r('app.media.hd_sparkle'),
    'flame': $r('app.media.hd_flame'),
    'swords': $r('app.media.hd_swords'),
    'calendar': $r('app.media.hd_calendar'),
    'note': $r('app.media.hd_note'),
    'rice': $r('app.media.hd_rice'),
    'pin': $r('app.media.hd_pin'),
    'target': $r('app.media.hd_target'),
    'party': $r('app.media.hd_party'),
    'confetti': $r('app.media.hd_confetti'),
    'ban': $r('app.media.hd_ban'),
    'receipt': $r('app.media.hd_receipt'),
    'pig': $r('app.media.hd_pig'),
    'bolt': $r('app.media.hd_bolt'),
    'lantern': $r('app.media.hd_lantern'),
    'volcano': $r('app.media.hd_volcano'),
    'leaf_wind': $r('app.media.hd_leaf_wind'),
    'clover': $r('app.media.hd_clover'),
    'moneybag': $r('app.media.hd_moneybag'),
    'hourglass': $r('app.media.hd_hourglass'),
    'ice': $r('app.media.hd_ice'),
    'heart': $r('app.media.hd_heart'),
    'mailbox_empty': $r('app.media.hd_mailbox_empty'),
    'moon': $r('app.media.hd_moon'),
    'skull': $r('app.media.hd_skull'),
    'monster': $r('app.media.hd_monster'),
    'plane': $r('app.media.hd_plane'),
    'bamboo': $r('app.media.hd_bamboo'),
    'chart': $r('app.media.hd_chart'),
    'redpacket': $r('app.media.hd_redpacket'),
    'gem': $r('app.media.hd_gem'),
    'jar': $r('app.media.hd_jar'),
    'gift': $r('app.media.hd_gift'),
    'check': $r('app.media.hd_check'),
    'check_green': $r('app.media.hd_check_green'),
    'cross': $r('app.media.hd_cross'),
    'cross_red': $r('app.media.hd_cross_red'),
    'rainbow': $r('app.media.hd_rainbow'),
    'dot': $r('app.media.hd_dot')
  };

  // 旧 emoji 字符 → 规范图标名（历史数据兼容层）
  private static readonly legacy: Record<string, string> = {
    '🥚': 'egg',
    '🪙': 'coin',
    '🐣': 'chick',
    '🐤': 'chick',
    '🌳': 'tree',
    '🌱': 'sprout',
    '🌿': 'leaf',
    '🌰': 'nut',
    '⭐': 'star',
    '🌟': 'star_glow',
    '✨': 'sparkle',
    '🔥': 'flame',
    '⚔': 'swords',
    '⚔️': 'swords',
    '📅': 'calendar',
    '🗓': 'calendar',
    '🗓️': 'calendar',
    '📝': 'note',
    '🌾': 'rice',
    '📌': 'pin',
    '🎯': 'target',
    '🎉': 'party',
    '🎊': 'confetti',
    '🚫': 'ban',
    '🧾': 'receipt',
    '🐷': 'pig',
    '⚡': 'bolt',
    '🏮': 'lantern',
    '🌋': 'volcano',
    '🍃': 'leaf_wind',
    '🍀': 'clover',
    '💰': 'moneybag',
    '⏳': 'hourglass',
    '🧊': 'ice',
    '💗': 'heart',
    '📭': 'mailbox_empty',
    '🌓': 'moon',
    '💀': 'skull',
    '👾': 'monster',
    '✈': 'plane',
    '✈️': 'plane',
    '🎋': 'bamboo',
    '📊': 'chart',
    '🧧': 'redpacket',
    '💎': 'gem',
    '🏺': 'jar',
    '🎁': 'gift',
    '✅': 'check_green',
    '✓': 'check',
    '❌': 'cross_red',
    '✗': 'cross',
    '🌈': 'rainbow'
  };

  public static resolve(name: string): Resource {
    const direct: Resource | undefined = IconMap.icons[name];
    if (direct !== undefined) {
      return direct;
    }
    const mapped: string | undefined = IconMap.legacy[name];
    if (mapped !== undefined) {
      const res: Resource | undefined = IconMap.icons[mapped];
      if (res !== undefined) {
        return res;
      }
    }
    return IconMap.fallback;
  }

  public static has(name: string): boolean {
    return IconMap.icons[name] !== undefined || IconMap.legacy[name] !== undefined;
  }
}
