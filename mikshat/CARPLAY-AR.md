# تجربة CarPlay في مكشات

المشروع الأصلي يتضمن CarPlay. الملف iphone/Maps/Mikshat-CarPlay.entitlements يطلب com.apple.developer.carplay-maps، لكنه غير مفعّل في مسار TestFlight الحالي إلى حين تأكيد موافقة Apple.

لتجربة شاشة سيارة فعلية:

1. من https://developer.apple.com/carplay/ اطلب صلاحية CarPlay لتطبيق ملاحة، باستخدام حساب الفريق 6W3WJ7KLLY ومعرّف التطبيق com.mikshat.maps.
2. بعد موافقة Apple فعّل الصلاحية للمعرّف وفق تعليمات Apple، وأعد إنشاء ملف App Store provisioning للتطبيق. يجب أن يتضمن ملف التوقيع com.apple.developer.carplay-maps=true. امتداد الودجت لا يحتاج هذه الصلاحية.
3. بعد التحقق غيّر CODE_SIGN_ENTITLEMENTS لإعداد Release إلى Mikshat-CarPlay.entitlements، واستخدم ملف التوقيع الجديد في Codemagic ثم ابنِ وارفع إلى TestFlight.
4. جرّب على iPhone وشاشة تدعم CarPlay. وجود شفرة CarPlay لا يثبت عملها مع هوية مكشات؛ اختبر ظهور التطبيق والبحث وحساب المسار والإرشاد الصوتي والاتصال والانفصال والخلفية.

حساب Apple Developer أو مفتاح API لا يمنح صلاحية CarPlay تلقائيًا. لا يمكن إصلاح غياب موافقة Apple بمجرد إضافة مفتاح الاستحقاق إلى المصدر. اختبار المحاكي مختلف عن اعتماد الصلاحية لجهاز حقيقي، وملف المحاكي الناتج من CI لا يعمل على الآيفون أو شاشة السيارة.
