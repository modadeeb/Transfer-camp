<script setup>
defineProps({ size: { type: Number, default: 36 } });
</script>
<template>
  <svg :width="size" :height="size" viewBox="0 0 100 100" aria-hidden="true">
    <rect width="100" height="100" rx="22" fill="#243F35" />
    <path d="M18 42 a32 26 0 0 0 64 0" fill="none" stroke="#F7F6F1" stroke-width="10" stroke-linecap="round" />
    <circle cx="50" cy="45" r="8" fill="#B68A47" />
  </svg>
</template>
