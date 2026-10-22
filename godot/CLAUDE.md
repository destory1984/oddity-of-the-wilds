# Oddity of the Wilds (Godot 4.7) 작업 안내

## 구성

- 게임 전부를 `main.gd` 가 코드로 짓는다. `main.tscn` 은 거의 비어 있다.
- `minimap.gd` 둥근 미니맵, `sky.gd` 왼쪽 위 해와 달 창, `shaders/` 지형, 풀, 물, 틸트시프트.
- 기획은 `DESIGN.md`. 무엇을 만들지, 밸런스를 정할 때는 기획자 에이전트(`designer`)를 먼저 부른다.
- 웹 사이트 저장소는 `../rpg_demo` (GitHub `destory1984/oddity-of-the-wilds`). 맨 위에 웹 실행 파일, `godot/` 에 이 프로젝트 원본 사본이 들어간다.

## 작업 순서

1. 고친다.
2. `python tools/dev.py check` : 스크립트 문법과 타입 오류를 잡는다. GDScript는 `:=` 로 타입을 추론할 수 없는 값(사전에서 꺼낸 값 등)에서 자주 막힌다. 그런 곳은 `var x: float =` 처럼 타입을 적는다.
3. `python tools/dev.py shot 장면이름` : `shots/장면이름.png` 를 읽어 눈으로 확인한다. 장면은 `python tools/dev.py scenes` (title, start, night, dusk, noon, cottage, shop, boss, bridge, faint). 새 상황을 확인해야 하면 `main.gd` 의 `SCENES` 에 장면을 더한다. `--hour=23 --day=4` 로 시각과 날짜를 덮어쓸 수 있다.
4. `python tools/dev.py test` : 자동 플레이 시험(`tools/autoplay.gd`). 진짜 게임에 클릭과 키를 넣어 결과를 본다. 시작 화면, 다리 4곳 건너기, 상점에서 사기, 발소리, 보스 곁 12초 버티기, 쓰러짐 뒤 되돌림. 사용자가 찾아 준 버그는 고친 뒤 여기에 시험으로 더한다.
5. 소리를 바꿨으면 `python tools/dev.py sound` : 효과음마다 길이, 크기(peak, rms), 쉿 소리 정도(zcr)를 숫자로 보고 `shots/sounds/*.wav` 를 남긴다. zcr이 0.15를 넘으면 쉿 소리가 난다.
6. 화면을 크게 바꾸기 전에 `python tools/dev.py baseline 장면` 으로 기준 사진을 두면, 다음 `shot` 이 기준과 몇 % 다른지 알려 준다. 시간대가 다르면 30% 넘게 다르다. 같은 조건에서 5%를 넘으면 의도한 변화인지 본다.
7. `python tools/dev.py ship -m "메시지"` : 검사와 시험을 돌리고, 하나라도 실패하면 멈춘다. 통과하면 여기 커밋, 웹 내보내기, 사이트 저장소로 복사와 커밋까지 한다. 푸시는 하지 않는다.
8. 푸시는 사용자가 "푸시해"라고 할 때만 사이트 저장소에서 `git push`. 먼저 권하지 않는다.

Godot 창이 멈춰 남으면 다음 실행이 조용히 실패한다. `python tools/dev.py kill` 로 닫는다(다른 명령은 시작할 때 스스로 닫는다).
사이트 폴더를 미리보기 서버가 물고 있으면 `index.wasm` 복사가 막힌다. 서버를 내리고 다시 한다.

## 그림

- 그림은 GPT에 맡긴다: `codex exec --skip-git-repo-check -c 'windows.sandbox="unelevated"' --sandbox workspace-write -i 참고.png - < 주문.txt`. 한 장에 1 → 2분.
- 배경은 순수 자홍 `#FF00FF` 로 그리게 하고 `../rpg_demo/art/cut.py 원본 결과 열 행` 으로 지우고 칸을 맞춘다.
- 소라 그림(`art/sora/`)과 제목 그림(`art/title/`)은 destory1984의 권리 보유 자료다. 다른 게임의 참고 그림(예: Space Oddity 제목)은 저장소에 넣지 않는다.

## 이야기 삽화

- 이야기 장면마다 GPT에 삽화를 주문해 `art/story/번호_이름.jpg` (가로 1600)로 넣고 `show_story(경로, [문장, ...])` 로 띄운다. 주문 문구는 같은 이름의 `.txt` 로 남긴다.
- 참고 그림은 소라 설정화(`../../oddity/assets/vroid/ref/sora-outfit-3view.webp`, 저장소에는 넣지 않음)를 `-i` 로 준다.
- 소라는 최대한 예쁘고 아름답고 사랑스럽게 그린다. 주문문에 꼭 넣는다:
  - 팔다리는 정확히 둘씩, 몸에 바르게 붙고, 손가락은 다섯. 꼬이거나 덧붙은 팔다리 없음.
  - 속옷은 어떤 식으로도 보이지 않는다. 치마 속이 보이는 각도와 들린 치맛단은 금지. 무릎을 세우고 앉는 편한 자세는 좋다(사용자가 고른 01_wake). 너무 반듯한 자세보다 자연스러운 자세를 고른다.
- Codex가 그린 원본은 `~/.codex/generated_images/` 에도 남는다. 덮어쓴 그림을 되살릴 때 쓴다.
- 화풍은 1990년대 셀 애니(사용자가 고름). `art/story/order.py` 가 화풍 참고(`style_ref.png`)와 얼굴 참고(`face_ref.png`, 소라 표정 그림)를 함께 넘긴다. 반짝이, 역광, 빛망울은 금지.
- 인물 일관성: 보리 할머니는 주름진 75세 노인(art/portrait/bori.png 기준). 할머니가 나오는 주문에는 그 그림을 넷째 참고로 붙인다(order.py가 자동으로 한다). 손에 든 물건과 시선이 하는 일과 맞는지(차를 따르면 잔을 본다)도 본다.
- 서 있는 그림: 소라는 왼쪽에 서서 오른쪽을 보고, 상대는 오른쪽에 서서 왼쪽(소라 쪽)을 봐야 한다. 받은 그림의 시선이 반대면 좌우로 뒤집는다.
- 확인할 것: 얼굴이 표정 그림과 같은지, 허리와 등이 꺾이지 않았는지, 팔다리 수, 치마. 모음 그림으로 작게 보지 말고 소라 부분을 크게 잘라 본다.
- 받은 그림은 반드시 열어 보고 위 두 가지를 확인한 뒤 쓴다. 어긋나면 다시 주문한다.

## 화면에서 지킬 것

- 글자는 한국어, 글꼴은 `fonts/pretendard/` 조각을 이어 쓴다. 이 글꼴에 없는 기호(이모지, ✦, ◎ 등)는 웹에서 네모로 나온다.
- 스프라이트는 `BILLBOARD_FIXED_Y` 에 세로 `1/cos(카메라 기울기)` 배. 카메라를 정면으로 보게 하면 발이 땅에 묻힌다.
- 효과음은 `sfx()` 로 코드에서 합성한다. 숫자는 `dev.py sound` 로 보지만 듣기 좋은지는 사용자에게 들어 봐 달라고 말한다.
- 시험에서 키를 누른 것처럼 하려면 `Input.is_key_pressed` 대신 `key_down()` 을 쓴다. 그래야 `fake_keys` 로 누를 수 있다.

## Text and languages

- All player-facing text goes through `i18n/text.csv` (columns: keys, ko, en, ja, zh_CN). The key is the Korean text itself.
- After adding or changing Korean text, run `python tools/i18n.py`. `dev.py check` fails while the table is out of date.
- Labels and buttons translate on their own. Strings with `%` need `tr("...") % x`, so the template is looked up before the numbers go in. Text drawn with `draw_string` (hud.gd `text()`) calls `tr()` itself.
- Story lines `"speaker|face|text"` give two keys: speaker and text.
- `python tools/dev.py shot SCENE --pseudo` wraps translated text in [brackets]. Text without brackets skipped the table.
- A language is added to project.godot only once its column has text. Japanese and Chinese also need a font with those glyphs (Pretendard has Korean and Latin only).
