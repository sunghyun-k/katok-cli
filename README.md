# katok

macOS 카카오톡 자동화 CLI. 접근성 API를 사용하여 카카오톡의 친구 목록, 채팅방, 메시지를 CLI로 조회하고 메시지를 보낼 수 있습니다.

## 설치

```bash
brew install sunghyun-k/tap/katok
```

## 사전 요구사항

- macOS 13+
- [카카오톡 macOS 앱](https://apps.apple.com/kr/app/kakaotalk/id869223134?mt=12)
- 터미널에 접근성 권한 허용 (시스템 설정 → 개인정보 보호 및 보안 → 접근성)
- 화면보호기 또는 화면 잠김 상태에서는 접근성 API가 작동하지 않아 사용할 수 없습니다

## 사용법

```bash
# 채팅방 목록 (기본 명령)
katok chats
katok chats --limit 10 --offset 20

# 친구 목록
katok friends

# 메시지 읽기
katok messages "홍길동"
katok messages "홍길동" --limit 20

# 메시지 보내기
katok send "홍길동" "안녕하세요"
```

출력은 CSV 형식입니다.

## Claude Code 연동

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 스킬로도 사용할 수 있습니다.

```bash
claude install-skill sunghyun-k/katok-cli
```

## License

MIT
