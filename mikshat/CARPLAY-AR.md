# تجربة CarPlay في مكشات

المشروع يتضمن CarPlay. إصدار 4.6.22 يربط إعداد Release بالملف iphone/Maps/Mikshat-CarPlay.entitlements، الذي يطلب com.apple.developer.carplay-maps. إعداد Codemagic يختار الملف mikshat_carplay_appstore للتطبيق والملف mikshat_widget_appstore للودجت صراحةً.

مرجع شهادة التوزيع في Codemagic هو Mikshat-Codemagic، كما حدده صاحب الحساب. يجلبه مسار البناء صراحةً مع الملفين، وتظل مطابقة الشهادة الفعلية جزءًا من خطوة إعداد التوقيع في Codemagic.

تم فحص ملف Mikshat AppStore المجدد: معرّف التطبيق 6W3WJ7KLLY.com.mikshat.maps، وصلاحية CarPlay للملاحة مفعّلة، وينتهي في 29 أكتوبر 2027. يتحقق البناء من الملف المختار قبل الاختبارات، ومن صلاحية CarPlay في التطبيق الموقّع وملفه المضمّن قبل السماح برفع IPA إلى TestFlight. ملف provisioning نفسه لا يُحفظ في المستودع.

لتجربة شاشة سيارة فعلية:

1. من https://developer.apple.com/carplay/ اطلب صلاحية CarPlay لتطبيق ملاحة، باستخدام حساب الفريق 6W3WJ7KLLY ومعرّف التطبيق com.mikshat.maps.
2. بعد موافقة Apple فعّل الصلاحية للمعرّف وفق تعليمات Apple، وأعد إنشاء ملف App Store provisioning للتطبيق. يجب أن يتضمن ملف التوقيع com.apple.developer.carplay-maps=true. امتداد الودجت لا يحتاج هذه الصلاحية.
3. بعد رفع الملف الجديد إلى Codemagic، استخدم مسار Mikshat iOS - signed TestFlight build. إعداد Release واسمَا ملفّي التطبيق والودجت مربوطان في المشروع، ويبقى التحقق من التوقيع الفعلي جزءًا من البناء.
4. جرّب على iPhone وشاشة تدعم CarPlay. وجود شفرة CarPlay لا يثبت عملها مع هوية مكشات؛ اختبر ظهور التطبيق والبحث وحساب المسار والإرشاد الصوتي والاتصال والانفصال والخلفية.

حساب Apple Developer أو مفتاح API لا يمنح صلاحية CarPlay تلقائيًا. لا يمكن إصلاح غياب موافقة Apple بمجرد إضافة مفتاح الاستحقاق إلى المصدر. اختبار المحاكي مختلف عن اعتماد الصلاحية لجهاز حقيقي، وملف المحاكي الناتج من CI لا يعمل على الآيفون أو شاشة السيارة.
