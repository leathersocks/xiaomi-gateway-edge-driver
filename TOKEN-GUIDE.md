# TOKEN 안내

[English](TOKEN-GUIDE.en.md)

SmartThings 설정에서 사용하는 항목 이름은 다음과 같습니다.

```text
TOKEN
```

이 값에는 **Xiaomi Gateway 자체의 miIO TOKEN**을 입력합니다.

형식은 다음과 같습니다.

```text
16바이트 / 32자리 16진수 문자열
```

예를 들면 다음과 같은 형식입니다.

```text
00112233445566778899aabbccddeeff
```

> 위 값은 형식 설명을 위한 예시이며 실제 TOKEN이 아닙니다.

## TOKEN의 용도

이 TOKEN은 다음 기능에서만 사용됩니다.

- 인증이 필요한 로컬 Xiaomi 자식 장치 검색
- Zigbee 장치 상태 polling

드라이버는 Xiaomi Gateway의 로컬 miIO API에 인증 요청을 보낼 때 이 값을 사용합니다.

## TOKEN과 다른 키의 차이

이 문서에서 설명하는 `TOKEN`은 다음 값들과 서로 다른 정보입니다.

- BLE 센서 TOKEN
- BLE Bind Key / BLE KEY
- mgl001 Gateway Key

따라서 위 값들을 SmartThings의 `TOKEN` 설정에 입력하면 안 됩니다.

## BLE over MQTT와 TOKEN

BLE 데이터를 MQTT로 전달받는 경로에서는 이 TOKEN이 필요하지 않습니다.

```text
Xiaomi BLE 장치
    ↓
Gateway / openmiio
    ↓
MQTT
    ↓
SmartThings Edge Driver
```

이 경로에서는 Gateway가 이미 BLE 이벤트를 MQTT로 전달하므로 Edge Driver가 BLE 센서 인증을 직접 수행하지 않습니다.

## 보안 주의사항

SmartThings Device Profile의 preference는 설정 값을 저장하기 위한 공간이며, 별도의 전용 Secret Vault는 아닙니다.

따라서 TOKEN은 다음과 같이 관리하는 것을 권장합니다.

- GitHub 저장소에 TOKEN을 기록하지 않습니다.
- README, CHANGELOG, 로그 파일 등에 실제 TOKEN을 넣지 않습니다.
- 다른 사용자에게 TOKEN을 공유하지 않습니다.
- 공개된 스크린샷이나 로그에 TOKEN이 포함되지 않았는지 확인합니다.

이 드라이버는 설정된 TOKEN 값을 `logcat`에 출력하지 않습니다.

## 요약

```text
SmartThings 설정명 : TOKEN
값                  : Xiaomi Gateway miIO TOKEN
길이                : 16바이트
표현 형식           : 32자리 16진수 문자열
사용 목적           : 인증 자식 검색 / Zigbee 상태 polling
BLE MQTT 사용 시    : 불필요
BLE KEY와 동일 여부 : 아님
Gateway Key와 동일  : 아님
```
