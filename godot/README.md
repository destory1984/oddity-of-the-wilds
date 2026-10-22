# The Crown Oddity (Godot 4)

브라우저 데모(`oddity-of-the-wilds`, Three.js)를 Godot 4.7로 옮긴 판이다.
씬 파일은 거의 비어 있고, 지형, 풀, 나무, 소라, 괴물, 상태창, 미니맵을 모두 `main.gd` 가 코드로 만든다.

## 실행

Godot 4.7에서 이 폴더를 열고 F5를 누른다. 명령줄로는 다음과 같다.

```
Godot_v4.7.2-stable_win64.exe --path .
```

- `-- --play` 를 붙이면 타이틀 화면을 건너뛴다.
- `-- --shot` 을 붙이면 4초 뒤 `shot.png` 를 저장하고 끝난다. 화면 확인용이다.

웹으로도 내보낼 수 있게 렌더러는 GL Compatibility를 쓴다.

## 파일

| 파일 | 하는 일 |
|---|---|
| `main.gd` | 지도 생성, 지형과 소품, 소라, 괴물, 전투, 스킬, 카메라, 상태창 |
| `minimap.gd` | 카메라 방향으로 돌고 납작하게 눕힌 둥근 양피지 미니맵 |
| `shaders/block.gdshader` | 지형 블록 (윗면 무늬, 옆면 흙색) |
| `shaders/grass.gdshader` | 바람에 흔들리는 풀과 부들 |
| `shaders/water.gdshader` | 흐르는 물 무늬 |
| `shaders/tiltshift.gdshader` | 화면 위아래 흐림, 따뜻한 색보정, 가장자리 어둡게 |

## 웹판과 다른 점

- 글꼴은 파일을 넣지 않고 운영체제 글꼴(SystemFont)을 쓴다. 윈도에서는 맑은 고딕으로 나온다.
- 빛번짐은 Godot의 Glow, 반딧불과 비는 CPUParticles3D로 했다.

## 라이선스

- 코드: MIT 라이선스.
- 소라 캐릭터(`art/sora/` 의 디자인과 모든 그림): destory1984의 것이다(All rights reserved). 허락 없이 복사, 수정, 배포, 다른 작품에 쓰기를 할 수 없다.

전체 문구는 `LICENSE` 에 있다.
