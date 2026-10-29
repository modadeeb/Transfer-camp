import { Bath, BedDouble, Brush, Bubbles, ChefHat, Droplets, Flame, Leaf, Recycle, Shirt, ShoppingCart, Sofa, Soup, Sparkles, SprayCan, Trash2, Utensils, Wrench } from 'lucide-vue-next';

export const CHORE_ICONS = {
  'chef-hat': { icon: ChefHat, label: 'طبخ' },
  utensils: { icon: Utensils, label: 'أطباق' },
  soup: { icon: Soup, label: 'وجبة' },
  'trash-2': { icon: Trash2, label: 'قمامة' },
  recycle: { icon: Recycle, label: 'فرز' },
  bath: { icon: Bath, label: 'حمّام' },
  'spray-can': { icon: SprayCan, label: 'تنظيف' },
  brush: { icon: Brush, label: 'كنس' },
  bubbles: { icon: Bubbles, label: 'غسيل' },
  shirt: { icon: Shirt, label: 'ملابس' },
  sofa: { icon: Sofa, label: 'الصالة' },
  'bed-double': { icon: BedDouble, label: 'الغرف' },
  'shopping-cart': { icon: ShoppingCart, label: 'مشتريات' },
  droplets: { icon: Droplets, label: 'ماء' },
  flame: { icon: Flame, label: 'غاز' },
  leaf: { icon: Leaf, label: 'نباتات' },
  wrench: { icon: Wrench, label: 'صيانة' },
  sparkles: { icon: Sparkles, label: 'أخرى' },
};

export const choreIcon = (key) => CHORE_ICONS[key]?.icon || Sparkles;
