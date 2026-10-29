<script setup>
import { useRouter } from 'vue-router';
import UButton from '../components/ui/UButton.vue';
import UField from '../components/ui/UField.vue';
import { useForm } from '../lib/useForm.js';
import { useSession } from '../stores/session.js';
import AuthFrame from './AuthFrame.vue';

const session = useSession();
const router = useRouter();
const { form, errors, saving, submit } = useForm({ campName: 'معسكر نقلة', name: '', username: '', password: '' });

async function save() {
  const ok = await submit(async () => {
    await session.setup({ ...form, username: form.username.trim() });
    return true;
  });
  if (ok) router.replace('/');
}
</script>

<template>
  <AuthFrame title="إعداد المعسكر" subtitle="أنشئ حساب المدير. بعدها تضيف بقية الأعضاء من الإعدادات.">
    <form class="space-y-4" @submit.prevent="save">
      <UField v-slot="{ id }" label="اسم المعسكر" :error="errors.campName">
        <input :id="id" v-model="form.campName" class="input" maxlength="60" />
      </UField>
      <UField v-slot="{ id }" label="اسمك" :error="errors.name">
        <input :id="id" v-model="form.name" class="input" maxlength="60" autocomplete="name" required />
      </UField>
      <UField v-slot="{ id }" label="اسم المستخدم" hint="بالأحرف الإنجليزية والأرقام" :error="errors.username">
        <input :id="id" v-model="form.username" class="input" dir="ltr" autocomplete="username" autocapitalize="none" required />
      </UField>
      <UField v-slot="{ id }" label="كلمة المرور" hint="8 أحرف على الأقل" :error="errors.password">
        <input :id="id" v-model="form.password" type="password" class="input" dir="ltr" autocomplete="new-password" minlength="8" required />
      </UField>
      <UButton type="submit" block :loading="saving">إنشاء الحساب والبدء</UButton>
    </form>
  </AuthFrame>
</template>
