#!/bin/bash
# Хук: не даёт утверждать факты по «вашим» темам, не открыв источник в этой сессии.
# Тип: Stop hook (срабатывает, когда агент закончил ответ).
#
# Зачем: правило «бери факт из источника» агент забывает. Хук проверяет ФАКТОМ —
#   если в ответе агент упомянул вашу чувствительную тему (например, цены),
#   но в этой сессии не было Read файла-источника или вызова коннектора → блокирует,
#   пока агент не свериться.
#
# ⚠️ Это УПРОЩЁННАЯ версия (наш рабочий хук сложнее: парсит больше, ведёт реестр тем).
#    Для старта достаточно. Добавляйте свои темы в массив RULES ниже.
#
# Установка:
#   1. Скопировать в .claude/hooks/ (chmod +x)
#   2. Прописать в .claude/settings.json как Stop hook (см. settings.example.json)
#   3. Под себя: в RULES задать пары «тема → как выглядит путь к источнику».

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Защита от зацикливания + нет транскрипта = выходим
[ "$STOP_ACTIVE" = "true" ] && exit 0
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# === ВАШИ ТЕМЫ ===
# Формат строки: имя<TAB>regex_упоминания_темы<TAB>regex_пути_к_источнику<TAB>подсказка
# Пример: тема «цены» — если в ответе есть «прайс/цена/стоимость», должен быть
#         открыт файл, в пути которого есть «price» или «прайс».
RULES=$(printf '%s\n' \
'prices	прайс|цен[аые]|стоимост|наценк	price|прайс|tariff	открой актуальный прайс (Read файла с ценами) перед утверждением о цене' \
'menu	меню|блюд|состав|калори	menu|меню|recipe|рецепт	открой файл меню/рецептур перед утверждением о составе/блюде' \
)
# Добавьте свои строки по образцу выше.

# Последнее реальное сообщение пользователя (без tool_result и системных)
LAST_USER_LINE=$(grep -n '"type":"user"' "$TRANSCRIPT" | grep -v 'tool_result' | grep -v 'hook feedback' | tail -1 | cut -d: -f1)
[ -z "$LAST_USER_LINE" ] && exit 0

TURN=$(awk -v s="$LAST_USER_LINE" 'NR > s' "$TRANSCRIPT")

# Текст ответов агента в этом turn'е
TURN_TEXT=$(echo "$TURN" | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null)
[ -z "$TURN_TEXT" ] && exit 0

# Все обращения к источникам за СЕССИЮ (Read file_path + Bash command)
SOURCES=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | "\(.input.file_path // "") \(.input.command // "")"' "$TRANSCRIPT" 2>/dev/null)

VIOLATIONS=""
while IFS=$'\t' read -r name mention src hint; do
  [ -z "$name" ] && continue
  # Тема упомянута в ответе?
  echo "$TURN_TEXT" | grep -qiE "$mention" || continue
  # Источник по теме открыт в сессии?
  echo "$SOURCES" | grep -qiE "$src" && continue
  VIOLATIONS="$VIOLATIONS\n  • [$name] $hint"
done <<< "$RULES"

if [ -n "$VIOLATIONS" ]; then
  printf '🛑 Сверься с источником перед утверждением:%b\n\nОткрой нужный файл (Read) или вызови коннектор, потом заверши ответ.\n' "$VIOLATIONS" >&2
  exit 2
fi

exit 0
