// ---------- 共享 UI 常量（调色板 / 图表配色） ----------
import { BrandSignals } from './V2Signals';

// 6 位品牌色叠加透明度：'#RRGGBB' + 'AA' → '#AARRGGBB'（ArkUI 8 位 hex 为 AARRGGBB）
export function withAlpha(hex: string, alpha: string): string {
  if (hex.length !== 7 || hex.charAt(0) !== '#') {
    return hex;
  }
  return '#' + alpha + hex.substring(1);
}

// 资产/账单列表项色点调色板（15 色，按索引轮转）
export const ASSET_PALETTE: string[] = [
  '#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA94D', '#A29BFE',
  '#FD79A8', '#00B894', '#E17055', '#6C5CE7', '#FDCB6E',
  '#00CEC9', '#D63031', '#0984E3', '#F368E0', '#FF9FF3'
];

// 图表配色（Canvas 无法使用 $r 资源，按颜色模式选取 hex 常量）
export interface ChartPalette {
  grid: string;
  text: string;
  textLight: string;
  cardBg: string;
  track: string;
}

export function getChartPalette(isDark: boolean): ChartPalette {
  if (isDark) {
    return {
      grid: '#2A2A2A',
      text: '#888888',
      textLight: '#777777',
      cardBg: '#1A1A1A',
      track: '#2A2A2A'
    };
  }
  return {
    grid: '#EEF0F4',
    text: '#666666',
    textLight: '#999999',
    cardBg: '#FFFFFF',
    track: '#E8ECF0'
  };
}

// ---------- 自定义主题颜色（品牌色） ----------

// 单个主题在浅色/深色模式下的四档品牌色
export interface BrandColorSet {
  main: string;
  light: string;
  deep: string;
  tint: string;
}

export interface BrandThemePreset {
  name: string;
  light: BrandColorSet;
  dark: BrandColorSet;
}

// AppStorage 键：applyBrandTheme 写入，各组件通过 @StorageProp 读取实现全局联动
export const BRAND_THEME_INDEX_KEY: string = 'brand_theme_index';

export const BRAND_THEMES: BrandThemePreset[] = [
  {
    name: '静谧蓝',
    light: { main: '#4E6EF2', light: '#7B93FF', deep: '#3A55E0', tint: '#EEF1FE' },
    dark: { main: '#6E87FF', light: '#3D55CC', deep: '#2E40A8', tint: '#232A45' }
  },
  {
    name: '青碧色',
    light: { main: '#00A8BD', light: '#3FC9DB', deep: '#008DA1', tint: '#E0F7FA' },
    dark: { main: '#2EC4D8', light: '#00829A', deep: '#006475', tint: '#12333B' }
  },
  {
    name: '薄荷绿',
    light: { main: '#12B886', light: '#4DD4AC', deep: '#0CA678', tint: '#E6FAF3' },
    dark: { main: '#38D9A9', light: '#0C8F6C', deep: '#087150', tint: '#0F3A2D' }
  },
  {
    name: '活力橙',
    light: { main: '#FF8A3D', light: '#FFAD70', deep: '#F2711C', tint: '#FFF3EA' },
    dark: { main: '#FF9F5A', light: '#C05A15', deep: '#8F4210', tint: '#3D2818' }
  },
  {
    name: '樱花粉',
    light: { main: '#EC6FA0', light: '#F49BC0', deep: '#D5568A', tint: '#FDEEF5' },
    dark: { main: '#FF9CC4', light: '#B84B7C', deep: '#8A3760', tint: '#3A1E2C' }
  },
  {
    name: '葡萄紫',
    light: { main: '#9C6BF2', light: '#BC94FF', deep: '#8452E0', tint: '#F3EDFE' },
    dark: { main: '#B48CFF', light: '#7447C4', deep: '#5A36A0', tint: '#2A1D45' }
  },
  {
    name: '汽水蓝',
    light: { main: '#2EB8F0', light: '#6FD3FF', deep: '#0E9BD8', tint: '#E5F8FF' },
    dark: { main: '#54C7F5', light: '#0B7FB0', deep: '#0A6288', tint: '#123A4D' }
  },
  {
    name: '青柠苏打',
    light: { main: '#84CC16', light: '#B5E85C', deep: '#65A30D', tint: '#F2FCE3' },
    dark: { main: '#A3D94E', light: '#4E7A0B', deep: '#3C5F09', tint: '#1E2E10' }
  },
  {
    name: '蜜桃气泡',
    light: { main: '#FB7185', light: '#FDA4AF', deep: '#E11D48', tint: '#FFF1F2' },
    dark: { main: '#FB8FA3', light: '#BE3D55', deep: '#8F2A3D', tint: '#3B1A20' }
  }
];

// 将指定主题的品牌色写入 AppStorage（全局组件通过 @StorageProp 响应刷新）；
// 同时双写 AppStorageV2 包装类（BrandSignals），供已迁移 @ComponentV2 的组件响应刷新
export function applyBrandTheme(index: number, isDark: boolean): void {
  const safeIndex: number = Math.max(0, Math.min(BRAND_THEMES.length - 1, index));
  const preset: BrandThemePreset = BRAND_THEMES[safeIndex];
  const set: BrandColorSet = isDark ? preset.dark : preset.light;
  AppStorage.setOrCreate('brand_main', set.main);
  AppStorage.setOrCreate('brand_light', set.light);
  AppStorage.setOrCreate('brand_deep', set.deep);
  AppStorage.setOrCreate('brand_tint', set.tint);
  const brandV2 = BrandSignals.connect();
  brandV2.main = set.main;
  brandV2.light = set.light;
  brandV2.deep = set.deep;
  brandV2.tint = set.tint;
}
