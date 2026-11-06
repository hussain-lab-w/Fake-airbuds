# EW27 Player v2

تطبيق iOS أصلي لتشغيل الأغاني المحلية الموجودة داخل مكتبة Apple Music مع EQ حقيقي عبر `AVAudioEngine`.

## المزايا

- هدف البناء iOS 17.
- قراءة **كل الأغاني المحلية** عبر `MPMediaQuery.songs()`، مع استبعاد عناصر iCloud فقط.
- قراءة قوائم التشغيل المحلية عبر `MPMediaQuery.playlists()`.
- عرض رمز قفل للعناصر التي لا تملك `MPMediaItem.assetURL`.
- تشغيل الملفات غير المحمية عبر `AVAudioFile` و`AVAudioEngine`.
- EQ بخمسة نطاقات: 60 Hz و250 Hz و1 kHz و4 kHz و12 kHz.
- 60 Hz يستخدم low-shelf، و12 kHz يستخدم high-shelf، والباقي parametric.
- Preamp محفوظ كـ `AVAudioUnitEQ.globalGain` بالديسيبل.
- Peak limiter بعد EQ لتقليل clipping.
- Presets: Flat وBass Boost وVocal وTreble.
- حفظ EQ لكل اسم output route وإعادة تطبيقه عند تغيّر route.
- Queue مع التالي والسابق والتشغيل العشوائي والتقدم والبحث داخل الأغنية.
- Auto-advance عند انتهاء الأغنية.
- `MPRemoteCommandCenter` للتشغيل والإيقاف والتبديل والتالي والسابق والبحث الزمني.
- `MPNowPlayingInfoCenter` مع elapsed time وduration وplayback rate.
- معالجة تغيّر audio route، وانقطاع المكالمات، و`AVAudioEngineConfigurationChange`.
- لا يوجد BLE أو طلب Bluetooth permission في v2.

## البناء على GitHub Actions

1. ارفع محتويات المجلد إلى GitHub.
2. افتح تبويب **Actions**.
3. شغّل workflow باسم **Build EW27 Player**.
4. نزّل artifact باسم `EW27Player-unsigned-ipa`.
5. وقّع الـ IPA بواسطة AltStore أو Sideloadly.

الـ workflow يعمل على `macos-15`، يثبت XcodeGen، يولّد `EW27Player.xcodeproj`، ثم يبني باستخدام:

```text
-destination 'generic/platform=iOS'
```

ويضع التطبيق داخل `Payload/EW27Player.app` ثم ينشئ `EW27Player-unsigned.ipa`.

## حدود Apple Music

هذا التطبيق لا يتجاوز DRM. يستطيع معالجة الأغنية فقط عندما تكون محلية وغير محمية ويعيد iOS رابطًا صالحًا من `MPMediaItem.assetURL`. العناصر التي لا تملك الرابط تظهر في المكتبة مع رمز القفل ولا يمكن تشغيلها عبر EQ التطبيق.

التطبيق لا يعالج Spotify أو YouTube أو صوت تطبيقات أخرى على مستوى النظام.

## هيكل المشروع

- `project.yml`: إعداد XcodeGen وiOS 17 وInfo.plist.
- `EW27Player/App/EW27PlayerApp.swift`: نقطة دخول التطبيق.
- `EW27Player/Media/MediaLibraryStore.swift`: مكتبة الوسائط وقوائم التشغيل.
- `EW27Player/Audio/AudioPlayer.swift`: AVAudioEngine وEQ والـ queue والـ remote commands.
- `EW27Player/UI/ContentView.swift`: واجهة عربية للمكتبة والمشغل وEQ.
- `EW27Player/Info.plist`: صلاحية مكتبة الوسائط وbackground audio.
