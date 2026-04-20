# FaceAccess — Instruções de Build

## 1. Pré-requisitos

| Ferramenta | Versão mínima |
|---|---|
| Flutter SDK | 3.19+ |
| Android SDK | API 34 (compileSdk) / API 24 (minSdk) |
| Java | 17+ |
| Dart | 3.3+ |

---

## 2. Baixar o modelo FaceNet

O modelo **não pode** ser distribuído pelo pub — faça o download manualmente:

### Opção A — repositório de referência (recomendado)
```
https://github.com/shubham0204/FaceRecognition_With_FaceNet_Android/raw/master/app/src/main/assets/facenet.tflite
```

### Opção B — modelo MobileFaceNet menor (mais rápido, menos preciso)
```
https://github.com/simonl91/flutter-tflite-face-recognition/raw/main/assets/facenet.tflite
```

**Coloque o arquivo em:**
```
assets/models/facenet.tflite
```

O modelo deve ser FaceNet com saída de **512 dimensões** e entrada **160×160 RGB**.

---

## 3. Instalar dependências

```bash
flutter pub get
```

Se encontrar erro do tflite_flutter (bibliotecas nativas não encontradas):
```bash
flutter pub run tflite_flutter:setup
```

---

## 4. Verificar conexão com o tablet

```bash
# Ligar USB Debug no tablet, depois:
adb devices
```

---

## 5. Gerar o APK de release

```bash
flutter build apk --release
```

O APK gerado estará em:
```
build/app/outputs/flutter-apk/app-release.apk
```

### Instalar direto no tablet conectado via USB
```bash
flutter install
```

---

## 6. Configurações do ESP32

Grave no ESP32 o seguinte sketch (resumo):

```cpp
#include <WiFi.h>
#include <PubSubClient.h>

const char* ssid = "SUA_REDE";
const char* password = "SUA_SENHA";
const char* mqtt_server = "broker.hivemq.com";
const int relayPin = 26;

void callback(char* topic, byte* payload, unsigned int length) {
  String msg = "";
  for (int i = 0; i < length; i++) msg += (char)payload[i];
  if (msg == "ABRIR") {
    digitalWrite(relayPin, HIGH);
    delay(3000);           // mantém relê ativo por 3 s
    digitalWrite(relayPin, LOW);
  }
}

void setup() {
  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin, LOW);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) delay(500);
  client.setServer(mqtt_server, 1883);
  client.setCallback(callback);
}

void loop() {
  if (!client.connected()) reconnect();
  client.loop();
}
```

Tópico MQTT que o tablet publica: **`porta/abrir`**  
Mensagem: **`ABRIR`**

---

## 7. Parâmetros configuráveis (em código)

| Arquivo | Constante | Valor padrão | Descrição |
|---|---|---|---|
| `evaluate_access_use_case.dart` | `_threshold` | `0.45` | Distância cosine máxima |
| `access_screen.dart` | `_frameSkipCounter % 3` | `3` | Processar 1 de N frames |
| `access_screen.dart` | `inSeconds < 5` | `5` | Cooldown por pessoa (s) |
| `access_screen.dart` | `_graceCyclesWithoutFace >= 3` | `3` | Grace period sem rosto |
| `access_screen.dart` | `inSeconds < 3` | `3` | Bloqueio após sair (s) |
| `access_screen.dart` | `_consecutiveMatches >= 2` | `2` | Frames consecutivos necessários |
| `mqtt_door_controller.dart` | `_broker` | `broker.hivemq.com` | Broker MQTT |
| `mqtt_door_controller.dart` | `_port` | `1883` | Porta MQTT |
| `register_screen.dart` | `_minPhotos` | `10` | Mínimo de fotos no cadastro |
| `register_screen.dart` | `_maxPhotos` | `30` | Máximo de fotos no cadastro |

---

## 8. Estrutura Clean Architecture

```
lib/
├── domain/
│   ├── entities/
│   │   └── access_decision.dart       ← Entidade de negócio
│   └── repositories/
│       ├── face_database_repository.dart
│       └── door_controller_repository.dart
├── application/
│   └── use_cases/
│       └── evaluate_access_use_case.dart  ← Regras de negócio
├── infrastructure/
│   ├── face_recognizer.dart           ← FaceNet via TFLite
│   ├── face_database.dart             ← Hive (embeddings locais)
│   └── mqtt_door_controller.dart      ← Publica MQTT para ESP32
└── presentation/
    ├── access_screen.dart             ← Tela principal (câmera + overlay)
    └── register_screen.dart           ← Cadastro de pessoas
```

---

## 9. Troubleshooting

**"No face model found"** → Verifique se `assets/models/facenet.tflite` existe e está listado no `pubspec.yaml`.

**MQTT não conecta** → Confirme que o tablet tem acesso à internet e que `usesCleartextTraffic="true"` está no `AndroidManifest.xml`.

**Muitos falsos negativos** → Aumente o threshold de `0.45` para `0.50`–`0.55` em `evaluate_access_use_case.dart`.

**Muitos falsos positivos** → Reduza o threshold para `0.38`–`0.42`.

**App lento / camera travando** → Reduza a resolução de `ResolutionPreset.medium` para `ResolutionPreset.low` em `access_screen.dart`.
