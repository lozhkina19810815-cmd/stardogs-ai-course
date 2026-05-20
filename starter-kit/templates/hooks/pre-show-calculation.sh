#!/bin/bash
# Хук: не даёт записать/показать расчётный результат без проверки CoVe (скилл /falsify).
# Тип: PreToolUse (Write, Edit, Bash).
#
# Зачем: правило «проверяй расчёты» в CLAUDE.md агент забывает. Хук блокирует ФАКТОМ —
#   расчётный файл/команда не пройдут, пока не пройдена проверка (создан флаг /tmp/falsification-done).
#
# Установка:
#   1. Скопировать в свою папку .claude/hooks/  (chmod +x .claude/hooks/pre-show-calculation.sh)
#   2. Прописать в .claude/settings.json (см. settings.example.json в комплекте)
#   3. Положить скилл /falsify в .claude/skills/falsify/

FALSIFY_FLAG="/tmp/falsification-done"
FALSIFY_TTL=1800  # 30 минут — окно после проверки, в которое запись разрешена

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$FILE_PATH" ] && [ -z "$COMMAND" ] && exit 0

# Флаг существует и не протух?
check_flag() {
  if [ -f "$FALSIFY_FLAG" ]; then
    local created now age
    created=$(stat -f %m "$FALSIFY_FLAG" 2>/dev/null || stat -c %Y "$FALSIFY_FLAG" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$(( now - created ))
    rm -f "$FALSIFY_FLAG"
    [ "$age" -lt "$FALSIFY_TTL" ] && return 0
  fi
  return 1
}

# Признаки расчётного файла (по расширению или имени). Подстройте слова под свою зону.
is_calculation_file() {
  local lower
  lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  echo "$lower" | grep -qE '\.(docx|xlsx)$' && return 0
  echo "$lower" | grep -qiE '(предложени|расч[её]т|смета|отч[её]т|анализ|прогноз|бюджет|коммерч|экономик|romi|roi)' && return 0
  return 1
}

# Признаки расчётной команды (запись в таблицу / сохранение xlsx / расчётный скрипт)
is_calculation_command() {
  local lower
  lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  echo "$1" | grep -qE 'spreadsheets\.(values\.(update|append|clear)|batchUpdate)' && return 0
  echo "$1" | grep -qiE '(wb|workbook)\.save\(.*(xlsx|csv)' && return 0
  echo "$lower" | grep -qE '(node|python3?)[[:space:]].*(forecast|прогноз|расч|анализ|analytics|summary|сводк|report|отч[её]т|romi|roi|бюджет|budget|estimate)' && return 0
  return 1
}

block_msg() {
  cat >&2 <<'EOF'
🛑 Перед показом расчёта пройди проверку CoVe (скилл /falsify):
  1. Допущения — что взято неподтверждённо?
  2. Три причины, почему результат может быть неверен
  3. Альтернативные объяснения цифры
  4. Что не проверено
  5. Где подгонка / смешаны разные сущности

После проверки (вердикт «можно показать») создай маркер:  touch /tmp/falsification-done
Потом повтори действие — хук пропустит.
EOF
}

if { [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ] || [ "$TOOL" = "MultiEdit" ]; } && [ -n "$FILE_PATH" ] && is_calculation_file "$FILE_PATH"; then
  check_flag && exit 0
  block_msg
  exit 2
fi

if [ "$TOOL" = "Bash" ] && [ -n "$COMMAND" ] && is_calculation_command "$COMMAND"; then
  check_flag && exit 0
  block_msg
  exit 2
fi

exit 0
