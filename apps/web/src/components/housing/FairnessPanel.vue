<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { formatDate } from '@camp/domain';
import { get } from '../../lib/api.js';
import { useUi } from '../../stores/ui.js';
import UAvatar from '../ui/UAvatar.vue';
import USegment from '../ui/USegment.vue';
import USkeleton from '../ui/USkeleton.vue';

const ui = useUi();
const period = ref('week');
const data = ref(null);
async function load() {
  try {
    data.value = await get('/fairness', { period: period.value });
  } catch (e) {
    ui.error(e);
  }
}
onMounted(load);
watch(period, load);
watch(() => ui.versions.tasks, load);

// rows stay in member order (no ranking)
const maxHouse = computed(() => Math.max(1, ...(data.value?.rows || []).map((r) => r.housePoints)));
const maxHours = computed(() => Math.max(1, ...(data.value?.rows || []).map((r) => r.companyHours)));
const maxBalance = computed(() => Math.max(1, ...(data.value?.rows || []).map((r) => Math.abs(r.balance))));
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <USegment
        v-model="period"
        :options="[
          { value: 'week', label: 'هذا الأسبوع' },
          { value: 'month', label: 'هذا الشهر' },
        ]"
        label="الفترة"
      />
      <p v-if="data" class="num text-[13.5px] text-muted">{{ formatDate(data.from) }} – {{ formatDate(data.to) }}</p>
    </div>
    <USkeleton v-if="!data" :lines="4" />
    <div v-else class="section overflow-x-auto">
      <table class="w-full min-w-[640px] text-[14px]">
        <caption class="sr-only">توزيع العمل بين الأعضاء</caption>
        <thead>
          <tr class="border-b border-line text-start text-[13px] text-muted">
            <th scope="col" class="px-4 py-3 text-start font-medium">العضو</th>
            <th scope="col" class="px-3 py-3 text-start font-medium">نقاط السكن (أُنجز / مسند)</th>
            <th scope="col" class="px-3 py-3 text-start font-medium">ساعات الشركة</th>
            <th scope="col" class="px-3 py-3 text-start font-medium">الإنجاز</th>
            <th scope="col" class="px-4 py-3 text-start font-medium">الرصيد المرحّل</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in data.rows" :key="r.userId" class="border-b border-line last:border-0">
            <th scope="row" class="px-4 py-3 text-start font-medium">
              <span class="flex items-center gap-2"><UAvatar :name="r.name" :color="r.color" size="sm" />{{ r.name }}</span>
            </th>
            <td class="px-3 py-3">
              <div class="flex items-center gap-2">
                <span class="relative h-2 w-28 overflow-hidden rounded-full bg-sunken">
                  <span class="absolute inset-y-0 start-0 rounded-full bg-sage-soft" :style="{ width: `${(r.housePoints / maxHouse) * 100}%` }" />
                  <span class="absolute inset-y-0 start-0 rounded-full bg-sage" :style="{ width: `${(r.houseDonePoints / maxHouse) * 100}%` }" />
                </span>
                <span class="num">{{ r.houseDonePoints }} / {{ r.housePoints }}</span>
              </div>
            </td>
            <td class="px-3 py-3">
              <div class="flex items-center gap-2">
                <span class="relative h-2 w-24 overflow-hidden rounded-full bg-sunken">
                  <span class="absolute inset-y-0 start-0 rounded-full bg-brass/40" :style="{ width: `${(r.companyHours / maxHours) * 100}%` }" />
                  <span class="absolute inset-y-0 start-0 rounded-full bg-brass" :style="{ width: `${(r.companyDoneHours / maxHours) * 100}%` }" />
                </span>
                <span class="num">{{ r.companyDoneHours }} / {{ r.companyHours }} س</span>
              </div>
            </td>
            <td class="num px-3 py-3">{{ r.completion === null ? '—' : `${r.completion}%` }}</td>
            <td class="px-4 py-3">
              <!-- centred bar: below zero = will receive more later -->
              <div class="flex items-center gap-2" :title="r.balance < 0 ? 'سيأخذ مهاماً أكثر قليلاً لاحقاً' : r.balance > 0 ? 'سيأخذ مهاماً أقل قليلاً لاحقاً' : 'متوازن'">
                <span class="relative h-2 w-24 rounded-full bg-sunken">
                  <span class="absolute inset-y-0 start-1/2 w-px bg-line" />
                  <span
                    class="absolute inset-y-0 rounded-full"
                    :class="r.balance < 0 ? 'end-1/2 bg-brass' : 'start-1/2 bg-sage'"
                    :style="{ width: `${(Math.abs(r.balance) / maxBalance) * 50}%` }"
                  />
                </span>
                <span class="num" dir="ltr">{{ r.balance > 0 ? '+' : '' }}{{ Number(r.balance.toFixed(1)) }}</span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
      <p class="border-t border-line px-4 py-3 text-[13px] text-muted">الرصيد المرحّل يوازن الأسابيع: من أخذ أكثر هذا الأسبوع يُخفَّف عنه لاحقاً، ومن غاب يُعوِّض بعد عودته.</p>
    </div>
  </div>
</template>
