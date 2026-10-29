# معسكر نقلة — دليل العمل على الكود

## البنية
- `packages/domain`: قواعد JS خالصة يستوردها الـweb والـapi (`@camp/domain`). أي قاعدة عمل (التوزيع، انتقالات حالة المهمة، المال، الميزانية، التواريخ، صيغ العدد العربية `count()`) تُكتب هنا مع اختبار.
- `apps/api`: Cloudflare Worker واحد (Hono، `basePath('/api')`) يخدم الـAPI وملفات `apps/web/dist` (`run_worker_first` + SPA fallback). قاعدة D1 بـSQL مباشر عبر `src/lib/db.js` (بلا ORM). التحقق بمُدقّق داخلي `src/lib/validate.js` برسائل عربية (بلا zod). الـcron في `src/cron.js` كل 15 دقيقة، وكل مهمة فيه محمية من التكرار.
- `apps/web`: Vue 3 + Pinia + vue-router + Tailwind 4 (ألوان CSS variables في `style.css`)، PWA بـ`injectManifest` و`src/sw.js` يعرض إشعارات FCM.

## قواعد ثابتة
- التوقيت: دوال `dates.js` فقط (توقيت عدن، الأسبوع يبدأ السبت). لا تستخدم `new Date().toISOString().slice(0,10)`.
- الخصوصية: موارد الأفراد (budget، prayers، sleep، workouts، goals، habits، المهام الشخصية) تُقيَّد بـ`user_id = me` في الخادم، حتى للمدير.
- كل كيان قابل للحذف فيه `deleted_at` (حذف مؤقت + سلة 30 يوماً)، ومعظمها فيه `archived_at` و`position` (الترتيب عبر `POST /api/reorder`).
- كل طلب يغيّر البيانات يحتاج الترويسة `X-Requested-With: camp` (مضافة في `apps/web/src/lib/api.js`).
- Vue يحذف المسافة البادئة داخل `<template v-if>`؛ استخدم `&nbsp;` أو تعبيراً نصياً.
- العدد مع المعدود: `count(n, TASKS|ITEMS|POINTS|HOURS)`.
- المخطط في `apps/api/migrations/`؛ أي تغيير = ملف migration جديد، ولا تعديل لملف منشور.

## الأوامر
- `npm test` — اختبارات الـdomain والـapi (Miniflare D1).
- `npm run dev` — بناء الواجهة + `wrangler dev` على 8787.
- `npm run deploy` — بناء + `wrangler deploy` (يحتاج موافقة صريحة من صاحب المشروع).

## ممنوع
- رفع `.dev.vars` أو أي سر أو ملف service account.
- `git push` أو `deploy` دون موافقة صريحة.
