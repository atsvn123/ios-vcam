# VCam

Bản dựng lại của tweak VCam. Giai đoạn hiện tại: **khung app**, chưa port chức năng.

- iOS 14 – 17, rootless (Dopamine) & RootHide (`/var/jb`)
- Cài .deb sẽ cài `VCam.app` vào `/var/jb/Applications` và chạy `uicache`

## Cấu trúc

```
Makefile                 aggregate root (Theos)
control                  metadata gói .deb
layout/DEBIAN/           postinst / prerm (uicache)
VCamApp/
  Makefile               application.mk
  Resources/             Info.plist, icon, logo
  Sources/
    main.m, VCAppDelegate
    Core/                VCTheme (màu/font), VCSettingsStore (state, NSUserDefaults)
    Views/               VCCardView, VCLiveButton
    Controllers/         VCTabBarController
                         VCSourceViewController    (tab Nguồn)
                         VCLivenessViewController  (tab Liveness)
                         VCSettingsViewController  (tab Settings)
```

## Build

Windows không có Theos: push lên GitHub, workflow `.github/workflows/build.yml`
build trên macOS runner và đính kèm .deb vào release `latest`.

Trên máy có Theos: `make package FINALPACKAGE=1`.

## Port chức năng (bước sau)

Mọi thay đổi state đi qua `VCSettingsStore`. Khi port, nối store sang bridge
gửi tới tweak dylib, và thay các chỗ `TODO(port)` trong controller.
