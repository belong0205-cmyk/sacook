#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
RESOURCES="${1:-$ROOT/dist/Presenter AI.app/Contents/Resources}"
TEST_BUILD="$(mktemp -d /private/tmp/sa-cook-tests.XXXXXX)"
FRAMEWORKS=(-framework Cocoa -framework AVFoundation -framework Speech -framework PDFKit -framework Security -framework CoreAudio -framework AudioToolbox -framework NaturalLanguage)
SUPPORT=("$ROOT/Sources/SCSpeechTimeline.m" "$ROOT/Sources/SCAutoQuestionDetector.m" "$ROOT/Sources/SCAnswerLane.m" "$ROOT/Sources/SCUntimedTranscriptBuffer.m" "$ROOT/Sources/SCAudioUtteranceBuffer.m")
for shared_resource in answer-policy.txt feature-manifest.json ui-tokens.json; do
  test -s "$RESOURCES/$shared_resource"
done
clang -fobjc-arc -framework Foundation -framework AVFoundation -Wall -Wextra -Werror "$ROOT/Sources/SCAudioUtteranceBuffer.m" "$ROOT/Tests/audio_utterance_tests.m" -o "$TEST_BUILD/audio_utterance_tests"
"$TEST_BUILD/audio_utterance_tests"
clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror "$ROOT/Sources/SCSpeechTimeline.m" "$ROOT/Tests/timeline_tests.m" -o "$TEST_BUILD/timeline"
"$TEST_BUILD/timeline"
for spec in 'SCAutoQuestionDetector:auto_detector_tests' 'SCAnswerLane:answer_lane_tests' 'SCUntimedTranscriptBuffer:untimed_buffer_tests'; do
  module="${spec%%:*}"; test="${spec##*:}"
  clang -fobjc-arc -framework Foundation -Wall -Wextra -Werror "$ROOT/Sources/$module.m" "$ROOT/Tests/$test.m" -o "$TEST_BUILD/$test"
  "$TEST_BUILD/$test"
done
for test in recognition_tests answer_queue_tests space_integration_tests; do
  clang -fobjc-arc "${FRAMEWORKS[@]}" -mmacosx-version-min=13.0 "$ROOT/Tests/$test.m" "${SUPPORT[@]}" -o "$TEST_BUILD/$test"
  "$TEST_BUILD/$test" "$RESOURCES"
done
clang -fobjc-arc "${FRAMEWORKS[@]}" -mmacosx-version-min=13.0 "$ROOT/Tests/reading_ui_tests.m" "${SUPPORT[@]}" -o "$TEST_BUILD/reading_ui_tests"
"$TEST_BUILD/reading_ui_tests" "$TEST_BUILD/reading-ui.png"
python3 -m unittest discover -s "$ROOT/Tests" -p 'test_data_index.py' -v
