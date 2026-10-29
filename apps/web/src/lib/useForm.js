import { reactive, ref } from 'vue';
import { ApiError } from './api.js';
import { useUi } from '../stores/ui.js';

/** Form state + server-side field errors (422) shown under each field. */
export function useForm(initial) {
  const ui = useUi();
  const form = reactive(JSON.parse(JSON.stringify(initial)));
  const errors = ref({});
  const saving = ref(false);

  async function submit(fn) {
    if (saving.value) return null;
    errors.value = {};
    saving.value = true;
    try {
      return await fn();
    } catch (e) {
      if (e instanceof ApiError && e.fields && Object.keys(e.fields).length) errors.value = e.fields;
      else ui.error(e);
      return null;
    } finally {
      saving.value = false;
    }
  }

  function reset(values = initial) {
    Object.assign(form, JSON.parse(JSON.stringify(values)));
    errors.value = {};
  }

  return { form, errors, saving, submit, reset };
}
