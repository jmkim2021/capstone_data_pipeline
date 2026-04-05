# macOS launchd 예시 (로컬 전용)

실제 사용 중인 plist는 **본인 Mac 경로**(`com.jaemin.*`, `Library/Application Support/...`)가 들어가므로 Git에는 올리지 않습니다 (`.gitignore`의 `launchd/`).

팀원이 비슷하게 스케줄하려면 아래를 참고해 **경로와 Label** 만 본인 환경에 맞게 바꿉니다.

## 단일 수집기 plist 템플릿

- `Label`: 역전 충돌을 피하려면 `com.yourname.kma.ultra_now` 처럼 고유하게.
- `ProgramArguments`: 프로젝트의 `./scripts/run_collector.sh` 와 수집기 이름.
- `WorkingDirectory`: **저장소 루트** (`.env`가 있는 곳).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.kma.ultra_now</string>
    <key>ProgramArguments</key>
    <array>
        <string>/ABS/PATH/TO/repo/scripts/run_collector.sh</string>
        <string>ultra_now</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/ABS/PATH/TO/repo</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Minute</key>
        <integer>5</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/ABS/PATH/TO/repo/logs/ultra_now.log</string>
    <key>StandardErrorPath</key>
    <string>/ABS/PATH/TO/repo/logs/ultra_now.err.log</string>
</dict>
</plist>
```

`logs/` 디렉터리를 만든 뒤 `launchctl load` 로 등록합니다. Linux 팀원은 **cron** 또는 **systemd timer** 로 동일한 커맨드를 호출하면 됩니다.
