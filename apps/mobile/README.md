# تطبيق الجوال — معسكر نقلة (Flutter)

تطبيق Flutter أصلي يتصل بنفس خادم Cloudflare (`/api`)، بنفس الحسابات والصلاحيات والبيانات.

## المتطلبات
- Flutter 3.27 أو أحدث (`flutter doctor` بلا أخطاء لأندرويد)
- Android Studio + Android SDK (للبناء والمحاكي)

## أول تشغيل
مجلدات المنصات (android/ios) لا تُحفظ في المستودع، تُولَّد مرة واحدة:

```bash
cd apps/mobile
flutter create --platforms=android,ios --org com.naqla --project-name transfer_camp .
flutter pub get
flutter test
flutter run
```

ثم أضف إلى `android/app/src/main/AndroidManifest.xml` داخل `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

## عنوان الخادم
الافتراضي `https://transfer-camp.moadeebprog.workers.dev`. لتغييره عند البناء:
```bash
flutter build apk --release --dart-define=API_BASE=https://camp.example.com
```
أو من شاشة الدخول ← «الخادم».

## الإشعارات
لا يحتاج التطبيق `google-services.json`؛ يأخذ إعداد Firebase من الخادم. أضف في Firebase تطبيق **Android** باسم الحزمة `com.naqla.transfer_camp`، ثم ضع على Cloudflare سراً باسم `FIREBASE_ANDROID_CONFIG`:
```json
{"apiKey":"…","appId":"1:…:android:…","messagingSenderId":"…","projectId":"transfer-camp"}
```
(مع `FCM_SERVICE_ACCOUNT` الموجود أصلاً لإرسال الإشعارات.)

## البناء للتوزيع
```bash
flutter build apk --release
```
الملف: `build/app/outputs/flutter-apk/app-release.apk`
