# بناء iOS عبر GitHub Actions

يستخدم النموذج Flutter 3.47.9 ومحرك Organic Maps بالإصدار المثبت 2026.09.29-32-android.
تُبنى مكتبات C++ على macOS، ويستخدم عرض الخريطة Metal داخل Flutter PlatformView.
واجهة Flutter وملفات MWM والخط والألوان مشتركة مع نموذج Android.

ملف العمل `prototype-ios.yml` يبني تطبيق محاكي iOS بمعمارية arm64 دون شهادات توقيع.
هذا الناتج ليس IPA قابلًا للتثبيت على iPhone. بناء الجهاز الفعلي يحتاج تشغيل `build_ios_core.sh iphoneos`
ثم توقيع تطبيق Runner بحساب Apple Developer وملف provisioning في إعدادات GitHub السرية.
لا تُرفع مفاتيح التوقيع إلى ملفات المشروع.

لإعادة البناء محليًا على Mac:

```sh
flutter pub get
python3 scripts/prepare_native.py
bash scripts/build_ios_core.sh iphonesimulator
(cd ios && pod install)
flutter build ios --simulator --debug --no-codesign
```

الخرائط تعمل من ملفات MWM محلية بعد تجهيز أول مرة؛ تنزيل أدوات البناء ليس جزءًا من تشغيل التطبيق.
التسجيل يستخدم Core Location مع `UIBackgroundModes=location` وسجل نقاط محفوظ على القرص.
تفعيل التسجيل يبدأ من واجهة التطبيق، ويستمر عند القفل حتى الإيقاف.
اختبار المحاكي لا يثبت سلوك GPS أو استهلاك البطارية أو استمرار التسجيل على iPhone فعلي.
