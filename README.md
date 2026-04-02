# only_head

이미지에서 머리(얼굴 + 머리카락) 영역을 감지하여 배경이 투명한 PNG 이미지로 추출해주는 Flutter 애플리케이션입니다.

## ✨ 주요 기능

- **자동 머리 영역 세그먼테이션**: Google ML Kit의 Selfie Segmentation을 활용하여 인물을 배경으로부터 분리합니다.
- **자동 얼굴 감지 및 크롭**: ML Kit Face Detection을 사용하여 인물의 머리 부분을 정확하게 인식하고 최적의 크기로 크롭합니다.
- **정밀 편집 도구**:
  - **마스크 브러시**: 지우고 싶은 부분을 부드러운 경계로 지울 수 있습니다.
  - **복원 브러시**: 잘못 지워진 부분을 원본 이미지에서 다시 복원할 수 있습니다.
  - **브러시 크기 조절**: 필요에 따라 브러시의 크기를 세밀하게 조정 가능합니다.
  - **실행 취소/재실행 (Undo/Redo)**: 편집 과정을 자유롭게 뒤로 가거나 다시 실행할 수 있습니다.
- **고품질 내보내기**: 투명 배경을 유지한 채 PNG 형식으로 갤러리에 저장하거나 외부로 공유할 수 있습니다.

## 🛠 기술 스택

- **Framework**: Flutter
- **State Management**: Riverpod (`flutter_riverpod`)
- **AI/ML**: Google ML Kit (`selfie_segmentation`, `face_detection`)
- **Image Processing**: `image`, `path_provider`
- **Sharing & Saving**: `share_plus`, `gal`

## 🚀 시작하기

### 사전 준비

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 설치 (3.x 버전 이상 권장)
- Android 또는 iOS 개발 환경 설정

### 설치 및 실행

```bash
# 의존성 패키지 설치
flutter pub get

# 앱 실행
flutter run
```
