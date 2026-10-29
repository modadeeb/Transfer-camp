<script setup>
import { watch } from 'vue';
import { DAY_NAMES, SLOT_LABELS, WEEK_ORDER } from '@camp/domain';
import { patch, post } from '../../lib/api.js';
import { CHORE_ICONS } from '../../lib/icons.js';
import { useForm } from '../../lib/useForm.js';
import { useUi } from '../../stores/ui.js';
import UButton from '../ui/UButton.vue';
import UDialog from '../ui/UDialog.vue';
import UField from '../ui/UField.vue';
import USegment from '../ui/USegment.vue';

const props = defineProps({ open: Boolean, chore: { type: Object, default: null } });
const emit = defineEmits(['close', 'saved']);
const ui = useUi();
const blank = { name: '', icon: 'spray-can', frequency: 'daily', days: [], weeklyDay: 6, points: 2, peopleCount: 1, slot: 'any', active: true };
const { form, errors, saving, submit, reset } = useForm(blank);
watch(
  () => props.open,
  (open) => {
    if (!open) return;
    const c = props.chore;
    reset(c ? { name: c.name, icon: c.icon || 'sparkles', frequency: c.frequency, days: c.days || [], weeklyDay: c.weeklyDay ?? 6, points: c.points, peopleCount: c.peopleCount, slot: c.slot, active: c.active } : blank);
  },
  { immediate: true },
);
function toggleDay(d) {
  form.days = form.days.includes(d) ? form.days.filter((x) => x !== d) : [...form.days, d];
}
async function save() {
  const body = { ...form, days: form.frequency === 'days' ? form.days : [], weeklyDay: form.frequency === 'weekly' ? form.weeklyDay : null };
  const r = await submit(() => (props.chore ? patch(`/chores/${props.chore.id}`, body) : post('/chores', body)));
  if (!r) return;
  ui.toast(props.chore ? 'حُفظت المهمة المنزلية' : 'أُضيفت المهمة المنزلية · ستدخل في التوزيع القادم');
  ui.bump('housing');
  emit('saved', r);
  emit('close');
}
</script>

<template>
  <UDialog :open="open" :title="chore ? 'تعديل مهمة سكن' : 'مهمة سكن جديدة'" @close="emit('close')">
    <form id="chore-form" class="space-y-4" @submit.prevent="save">
      <UField v-slot="{ id, invalid }" label="الاسم" :error="errors.name">
        <input :id="id" v-model="form.name" class="input" maxlength="60" placeholder="مثال: تنظيف المطبخ" :aria-invalid="invalid || undefined" />
      </UField>
      <UField label="الأيقونة">
        <div class="flex flex-wrap gap-1.5" role="radiogroup" aria-label="الأيقونة">
          <button
            v-for="(v, key) in CHORE_ICONS"
            :key="key"
            type="button"
            role="radio"
            :aria-checked="form.icon === key"
            :aria-label="v.label"
            :title="v.label"
            class="grid size-10 place-items-center rounded-[10px] border"
            :class="form.icon === key ? 'border-sage bg-sage-soft text-forest' : 'border-line text-muted hover:border-sage'"
            @click="form.icon = key"
          >
            <component :is="v.icon" class="size-5" />
          </button>
        </div>
      </UField>
      <UField label="التكرار" :error="errors.days">
        <USegment
          v-model="form.frequency"
          :options="[
            { value: 'daily', label: 'يومياً' },
            { value: 'days', label: 'أيام محددة' },
            { value: 'weekly', label: 'مرة في الأسبوع' },
          ]"
          label="التكرار"
        />
        <div v-if="form.frequency === 'days'" class="mt-2 flex flex-wrap gap-1.5" role="group" aria-label="الأيام">
          <button
            v-for="d in WEEK_ORDER"
            :key="d"
            type="button"
            :aria-pressed="form.days.includes(d)"
            class="h-9 rounded-full border px-3 text-[13.5px]"
            :class="form.days.includes(d) ? 'border-sage bg-sage-soft text-forest' : 'border-line'"
            @click="toggleDay(d)"
          >
            {{ DAY_NAMES[d] }}
          </button>
        </div>
        <select v-if="form.frequency === 'weekly'" v-model.number="form.weeklyDay" class="input mt-2" aria-label="يوم المهمة">
          <option v-for="d in WEEK_ORDER" :key="d" :value="d">{{ DAY_NAMES[d] }}</option>
        </select>
      </UField>
      <UField label="الجهد" hint="1 خفيف (رمي القمامة) — 5 ثقيل (تنظيف الحمّام). التوزيع يساوي مجموع النقاط بين الأفراد." :error="errors.points">
        <USegment v-model="form.points" :options="[1, 2, 3, 4, 5].map((n) => ({ value: n, label: String(n) }))" label="نقاط الجهد" />
      </UField>
      <div class="grid grid-cols-2 gap-4">
        <UField v-slot="{ id }" label="عدد الأفراد" :error="errors.peopleCount">
          <input :id="id" v-model.number="form.peopleCount" type="number" min="1" max="8" class="input num" />
        </UField>
        <UField v-slot="{ id }" label="الوقت">
          <select :id="id" v-model="form.slot" class="input">
            <option v-for="(label, key) in SLOT_LABELS" :key="key" :value="key">{{ label }}</option>
          </select>
        </UField>
      </div>
      <label class="flex items-center justify-between">
        <span>فعّالة (تدخل في التوزيع)</span>
        <input v-model="form.active" type="checkbox" class="size-5 accent-[#56856A]" />
      </label>
    </form>
    <template #footer>
      <UButton type="submit" form="chore-form" :loading="saving" class="flex-1">{{ chore ? 'حفظ' : 'إضافة' }}</UButton>
      <UButton variant="secondary" @click="emit('close')">إلغاء</UButton>
    </template>
  </UDialog>
</template>
