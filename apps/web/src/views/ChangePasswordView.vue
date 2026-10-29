<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import UButton from '../components/ui/UButton.vue';
import UField from '../components/ui/UField.vue';
import { post } from '../lib/api.js';
import { useForm } from '../lib/useForm.js';
import { useSession } from '../stores/session.js';
import { useUi } from '../stores/ui.js';
import AuthFrame from './AuthFrame.vue';

const session = useSession();
const router = useRouter();
const ui = useUi();
const confirmError = ref('');
const { form, errors, saving, submit } = useForm({ current: '', password: '', confirm: '' });

async function save() {
  confirmError.value = form.password !== form.confirm ? 'كلمتا المرور غير متطابقتين' : '';
  if (confirmError.value) return;
  const ok = await submit(() => post('/auth/password', { current: form.current, password: form.password }));
  if (!ok) return;
  await session.load();
  ui.toast('تم تعيين كلمة المرور');
  router.replace('/');
}
</script>

<template>
  <AuthFrame :title="`أهلاً ${session.user?.name || ''}`" subtitle="اختر كلمة مرور خاصة بك قبل البدء">
    <form class="space-y-4" @submit.prevent="save">
      <UField v-slot="{ id }" label="كلمة المرور المؤقتة" :error="errors.current">
        <input :id="id" v-model="form.current" type="password" class="input" dir="ltr" autocomplete="current-password" required />
      </UField>
      <UField v-slot="{ id }" label="كلمة المرور الجديدة" hint="8 أحرف على الأقل" :error="errors.password">
        <input :id="id" v-model="form.password" type="password" class="input" dir="ltr" autocomplete="new-password" minlength="8" required />
      </UField>
      <UField v-slot="{ id }" label="أعد كتابتها" :error="confirmError">
        <input :id="id" v-model="form.confirm" type="password" class="input" dir="ltr" autocomplete="new-password" required />
      </UField>
      <UButton type="submit" block :loading="saving">حفظ والمتابعة</UButton>
    </form>
  </AuthFrame>
</template>
