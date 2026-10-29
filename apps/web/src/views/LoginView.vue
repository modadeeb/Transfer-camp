<script setup>
import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Eye, EyeOff } from 'lucide-vue-next';
import UButton from '../components/ui/UButton.vue';
import UField from '../components/ui/UField.vue';
import { useForm } from '../lib/useForm.js';
import { useSession } from '../stores/session.js';
import AuthFrame from './AuthFrame.vue';

const session = useSession();
const router = useRouter();
const route = useRoute();
const show = ref(false);
const error = ref('');
const { form, saving, submit } = useForm({ username: '', password: '', remember: true });

async function login() {
  error.value = '';
  const ok = await submit(async () => {
    try {
      await session.login(form.username.trim(), form.password, form.remember);
      return true;
    } catch (e) {
      error.value = e.message;
      return null;
    }
  });
  if (ok) router.replace(typeof route.query.next === 'string' && route.query.next.startsWith('/') ? route.query.next : '/');
}
</script>

<template>
  <AuthFrame :title="session.campName" subtitle="سجّل الدخول بالحساب الذي أنشأه لك المدير">
    <form class="space-y-4" @submit.prevent="login">
      <p v-if="error" class="rounded-[10px] bg-danger-soft px-3 py-2 text-[14px] text-danger" role="alert">{{ error }}</p>
      <UField v-slot="{ id }" label="اسم المستخدم">
        <input :id="id" v-model="form.username" class="input" dir="ltr" autocomplete="username" autocapitalize="none" spellcheck="false" required />
      </UField>
      <UField v-slot="{ id }" label="كلمة المرور">
        <div class="relative">
          <input :id="id" v-model="form.password" :type="show ? 'text' : 'password'" class="input pe-11" dir="ltr" autocomplete="current-password" required />
          <button type="button" class="absolute inset-y-0 end-1 grid w-10 place-items-center text-muted" :aria-label="show ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'" @click="show = !show">
            <EyeOff v-if="show" class="size-5" /><Eye v-else class="size-5" />
          </button>
        </div>
      </UField>
      <label class="flex items-center gap-2 text-[14.5px]">
        <input v-model="form.remember" type="checkbox" class="size-4 accent-[#56856A]" />
        تذكرني على هذا الجهاز
      </label>
      <UButton type="submit" block :loading="saving">دخول</UButton>
    </form>
    <template #after>
      <p class="mt-4 text-center text-[13.5px] text-muted">نسيت كلمة المرور؟ اطلب من المدير إعادة تعيينها.</p>
    </template>
  </AuthFrame>
</template>
