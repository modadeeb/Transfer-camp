# معسكر نقلة

نظام لإدارة سكن مشترك لثمانية أعضاء يعملون معاً في شركة تصميم وبناء أنظمة:
- توزيع عادل لمهام السكن والشركة، مع اعتماد المدير.
- جدول للمجموعة وجدول لكل عضو.
- صندوق مشترك وميزانية شخصية وديون بين الأعضاء.
- صلوات ونوم ورياضة وأهداف وعادات.
- إشعارات عبر Firebase.

يعمل كله على **Cloudflare** (Worker واحد + قاعدة D1) ضمن الخطة المجانية.

## البنية

```
packages/domain   قواعد مشتركة (توزيع، دورة حياة المهمة، المال، التواريخ) — JavaScript خالص مع اختبارات
apps/api          Cloudflare Worker (Hono) + D1 — يخدم /api/* والملفات الثابتة معاً + cron كل 15 دقيقة
apps/web          Vue 3 + Vite + Tailwind 4 + PWA — يُبنى إلى apps/web/dist ويرفعه الـWorker نفسه
```

- التوقيت كله بتوقيت عدن (UTC+3)، والأسبوع يبدأ السبت.
- البيانات الشخصية (الميزانية، الصلوات، النوم…) لا يراها إلا صاحبها، حتى المدير. هذا مفروض في الخادم نفسه.
- الحذف مؤقت: يمكن التراجع خلال 5 ثوانٍ، ويبقى المحذوف في سلة المحذوفات 30 يوماً.

## التشغيل محلياً

المتطلبات: Node 20 أو أحدث.

```bash
npm install
cp apps/api/.dev.vars.example apps/api/.dev.vars   # ثم ضع JWT_SECRET طويلاً عشوائياً
npm run db:migrate:local
npm run dev            # يبني الواجهة ثم يشغّل الـWorker على http://127.0.0.1:8787
```

افتح الرابط وستظهر صفحة **الإعداد الأول** لإنشاء حساب المدير، ثم أضف الأعضاء من **الإعدادات ← الأعضاء**. يأخذ كل عضو كلمة مرور مؤقتة ويُطلب منه تغييرها عند أول دخول.

لتطوير الواجهة مع إعادة التحميل الفوري: شغّل `npm run dev:api` في نافذة و`npm run dev:web` في أخرى (يمرّر Vite طلبات `/api` إلى 8787).

الاختبارات:

```bash
npm test               # قواعد الـdomain + اختبارات الـAPI على D1 محلية (Miniflare)
```

## النشر على Cloudflare

```bash
npx wrangler login
npx wrangler d1 create camp
```

انسخ `database_id` الذي يظهر وضعه في `apps/api/wrangler.jsonc` مكان `00000000-0000-0000-0000-000000000000`. بعدها:

```bash
npm run db:migrate:remote -w apps/api
cd apps/api
openssl rand -base64 48 | npx wrangler secret put JWT_SECRET
cd ../..
npm run deploy
```

سيظهر رابط مثل `https://transfer-camp.<حسابك>.workers.dev`. افتحه وأكمل الإعداد الأول. يعمل الـcron تلقائياً، وهو المسؤول عن:
- التذكير قبل موعد المهمة بساعتين.
- تنبيه التأخير.
- ملخص الصباح عند السابعة.
- تذكير المساهمات كل سبت.
- مسودة توزيع الأسبوع القادم يوم الخميس.

لربط نطاق خاص: **Workers & Pages ← transfer-camp ← Settings ← Domains & Routes**.

عند أي تحديث لاحق:

```bash
npm run db:migrate:remote -w apps/api   # إن أُضيفت migrations جديدة
npm run deploy
```

## الإشعارات (Firebase)

التطبيق يعمل كاملاً بدونها: تبقى الإشعارات داخل التطبيق عند الجرس. لتفعيل إشعارات الهاتف:

1. أنشئ مشروعاً في [Firebase Console](https://console.firebase.google.com)، ثم أضف إليه تطبيق **Web**.
2. انسخ كائن `firebaseConfig`، وفيه apiKey وauthDomain وprojectId وmessagingSenderId وappId.
3. من **Project settings ← Cloud Messaging ← Web Push certificates**، أنشئ زوج مفاتيح وانسخ المفتاح العام (VAPID).
4. من **Project settings ← Service accounts ← Generate new private key**، نزّل ملف JSON.
5. أضف الأسرار من داخل `apps/api`:

```bash
npx wrangler secret put FIREBASE_WEB_CONFIG     # الصق كائن firebaseConfig بصيغة JSON في سطر واحد
npx wrangler secret put FIREBASE_VAPID_KEY      # المفتاح العام
npx wrangler secret put FCM_SERVICE_ACCOUNT < service-account.json
```

بعدها يفعّل كل عضو الإشعارات من **الإعدادات ← الإشعارات**. على iPhone يجب أولاً إضافة التطبيق إلى الشاشة الرئيسية (iOS 16.4 أو أحدث).

> لا تضع ملف الـservice account ولا `.dev.vars` في المستودع؛ كلاهما مُستثنى في `.gitignore`.

## الأمان باختصار

- كلمات المرور مشفّرة بـPBKDF2 (100 ألف دورة).
- الجلسة في كوكي `httpOnly` و`SameSite=Lax` (و`Secure` على https)، ويمكن إلغاؤها بتغيير كلمة المرور.
- حماية من CSRF عبر الترويسة `X-Requested-With`.
- قفل الدخول بعد 5 محاولات خاطئة للمستخدم أو 30 للعنوان الواحد خلال 15 دقيقة.
- تصدير بياناتك الشخصية من **الإعدادات ← البيانات**.

## النشر التلقائي (Cloudflare Workers Builds)

المستودع مربوط بـCloudflare، وكل دفع إلى `main` يُبنى ويُنشر تلقائياً بهذه الإعدادات:
- **Build command:** `npm run build`
- **Deploy command:** `npx wrangler deploy --config apps/api/wrangler.jsonc`
- **Path:** `/`

الأسرار (`JWT_SECRET` وأسرار Firebase) تُضاف من **إعدادات ← متغيرات وقت التشغيل والأسرار**، وليس من متغيرات البناء.
أي migration جديد يُطبَّق يدوياً: `npm run db:migrate:remote -w apps/api`.
