#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
STAGING_ROOT="$(mktemp -d /private/tmp/sa-cook-build.XXXXXX)"
APP="$STAGING_ROOT/Presenter AI.app"
FINAL_APP="$ROOT/dist/Presenter AI.app"
SOURCE_DATA="/Users/trunghuy/sa-cook-study/data"
mkdir -p "$ROOT/build" "$APP/Contents/MacOS" "$APP/Contents/Resources"
clang -fobjc-arc -framework Cocoa -framework AVFoundation -framework Speech -framework PDFKit -framework Security -framework CoreAudio -framework AudioToolbox -framework NaturalLanguage \
  -mmacosx-version-min=13.0 "$ROOT/Sources/main.m" "$ROOT/Sources/SCSpeechTimeline.m" "$ROOT/Sources/SCAutoQuestionDetector.m" "$ROOT/Sources/SCAnswerLane.m" "$ROOT/Sources/SCUntimedTranscriptBuffer.m" "$ROOT/Sources/SCAudioUtteranceBuffer.m" -o "$ROOT/build/PresenterAI"
cp "$ROOT/build/PresenterAI" "$APP/Contents/MacOS/PresenterAI"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Data/internet-qa.json" "$APP/Contents/Resources/internet-qa.json"
cp "$ROOT/Data/speech-hints.txt" "$APP/Contents/Resources/speech-hints.txt"
for shared_resource in answer-policy.txt feature-manifest.json ui-tokens.json; do
  test -s "$ROOT/../Shared/$shared_resource"
  cp "$ROOT/../Shared/$shared_resource" "$APP/Contents/Resources/$shared_resource"
done

if [[ -f "$SOURCE_DATA/questions.json.js" && -f "$SOURCE_DATA/theory.json.js" ]]; then
  sed -E 's/^(var|const) QUESTIONS_DATA = //; s/;$//' "$SOURCE_DATA/questions.json.js" > "$ROOT/build/questions.json"
  sed -E 's/^(var|const) THEORY_DATA = //; s/;$//' "$SOURCE_DATA/theory.json.js" > "$ROOT/build/theory.json"
  {
    jq -r '.categories[] | "# CHỦ ĐỀ: \(.nameVi // .name // "")", (.questions[] | "CÂU HỎI EN: \(.question // "")\nCÂU HỎI VI: \(.questionVi // "")\nTRẢ LỜI EN: \(.answer // "")\nTRẢ LỜI VI: \(.answerVi // "")\nGIẢI THÍCH: \(.explanation.content // "")\n")' "$ROOT/build/questions.json"
    jq -r '.categories[] | "# LÝ THUYẾT: \(.nameVi // .name // "")\nGIỚI THIỆU: \(.intro // "")", (.sections[]? | "MỤC: \(.title // "")\n\(.content // "")\nÝ CHÍNH: \((.keyPoints // []) | join("; "))\n"), "MẸO: \((.examTips // []) | join("; "))\n"' "$ROOT/build/theory.json"
  } > "$APP/Contents/Resources/sa-cook-knowledge.txt"
  if [[ -f "$SOURCE_DATA/export_qa.txt" ]]; then
    python3 "$ROOT/Scripts/build_export_index.py" "$SOURCE_DATA/export_qa.txt" "$SOURCE_DATA/export_handbook.txt" "$APP/Contents/Resources/sa-cook-qa.json"
  else
    jq -c '[.categories[] as $c | $c.questions[] | {category:$c.name, question:.question, answer:.answer}]' "$ROOT/build/questions.json" > "$APP/Contents/Resources/sa-cook-qa.json"
  fi
  [[ -f "$SOURCE_DATA/export_handbook.txt" ]] && cp "$SOURCE_DATA/export_handbook.txt" "$APP/Contents/Resources/sa-cook-handbook.txt"
fi
test -s "$APP/Contents/Resources/sa-cook-qa.json"
test -s "$APP/Contents/Resources/sa-cook-knowledge.txt"
test -s "$APP/Contents/Resources/answer-policy.txt"
test -s "$APP/Contents/Resources/feature-manifest.json"
test -s "$APP/Contents/Resources/ui-tokens.json"
/usr/bin/xattr -r -c "$APP" || true
xattr -dr "com.apple.provenance" "$APP" 2>/dev/null || true
xattr -dr "com.apple.fileprovider.fpfs#P" "$APP" 2>/dev/null || true
xattr -dr "com.apple.FinderInfo" "$APP" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
find "$APP" -name "._*" -delete 2>/dev/null || true
dot_clean "$APP" 2>/dev/null || true
codesign --force --deep --sign - --requirements "$ROOT/PresenterAI.requirements" "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$ROOT/dist"
if [[ -d "$FINAL_APP" ]]; then mv "$FINAL_APP" "$ROOT/dist/Presenter AI.app.backup-$(date +%Y%m%d%H%M%S)"; fi
/usr/bin/ditto --norsrc --noextattr --noqtn "$APP" "$FINAL_APP"
# Documents may be backed by a macOS file provider, which immediately attaches
# provenance metadata to the copied bundle. The staging and packaged bundles
# still receive strict verification; use normal verification for this local copy.
codesign --verify --deep "$FINAL_APP"
echo "$FINAL_APP"
