# MGL03 openmiio/MQTT 런타임

[English](OPENMIIO-RUNTIME.en.md)

BLE 장치를 사용하는 경우 이 Edge Driver에는 `miio/report`와
`central/report`를 제공하는 MQTT 런타임이 필요합니다. MGL03 설치·업데이트,
부팅 자동 시작, 무결성 확인과 진단 도구는
[`mgl03-homekit-bridge`](https://github.com/leathersocks/mgl03-homekit-bridge)에서
통합 관리합니다. 이 저장소에는 게이트웨이를 직접 변경하는 설치기를 중복
보관하지 않습니다.

## Telnet 없이 openmiio만 설치

같은 LAN의 Windows PC에서 다음을 실행합니다.

```powershell
Set-Location C:\Git\mgl03-homekit-bridge
py -m pip install -r .\requirements-installer.txt
py .\scripts\install_no_telnet.py `
  --gateway-ip 192.168.10.41 `
  --mode openmiio
```

숨김 프롬프트에는 해당 MGL03의 32자리 miIO 토큰을 입력합니다. 지원 대상은
`lumi.gateway.mgl03` 펌웨어 `1.5.0`부터 `1.5.4`까지입니다. 설치기는 Telnet
포트 23을 열지 않으며, SHA-256 검증과 실패 시 롤백을 수행한 뒤 MQTT TCP
`1883` 준비 상태를 확인합니다.

`openmiio` 모드는 HomeKit 브리지 바이너리나 TCP `51826`을 요구하지 않습니다.
이미 전체 `mgl03-homekit-bridge`가 정상 실행 중이라면 같은 Mosquitto/openmiio
연결을 Edge Driver와 공유할 수 있으므로 다시 설치할 필요가 없습니다.

## Edge Driver 설정

SmartThings 앱의 Gateway 설정에서 다음 값을 사용합니다.

```text
BLE via MQTT       = On
BLE MQTT broker IP = MGL03 IP 주소
BLE MQTT port      = 1883
```

드라이버는 와일드카드 `#` 대신 `miio/report`와 `central/report`만 구독합니다.
MQTT 이벤트를 PC에서 확인하려면 런타임 저장소의 진단 도구를 실행합니다.

```powershell
py .\scripts\mqtt_ble_probe.py --host 192.168.10.41
```

인증 없는 MQTT 1883 포트를 인터넷에 노출하지 말고 신뢰할 수 있는 LAN/VLAN
안에서만 사용하십시오.
