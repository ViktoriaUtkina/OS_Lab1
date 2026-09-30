#!/bin/bash
# log_archiver.sh
# Использование: ./log_archiver.sh <путь_к_log> <порог_в_%> <кол-во_файлов_M>
#
# Логика:
#   1. Считаем процент, который папка занимает от своей файловой системы.
#   2. Если процент > порога - архивируем M самых старых файлов в tar.gz.
#   3. Архив кладём в /backup.


#1. Проверка аргументов
if [ "$#" -ne 3 ]; then
    echo "Использование: $0 <путь_к_log> <порог_в_процентах_N> <кол_во_файлов_M>"
    exit 1
fi

LOG_DIR="$1"
THRESHOLD="$2"
FILES_COUNT="$3"
BACKUP_DIR="/backup"

#2. Проверка, что папка существует
if [ ! -d "$LOG_DIR" ]; then
    echo "Ошибка: Папка '$LOG_DIR' не найдена."
    exit 1
fi

#3. Проверка, что порог и количество - числа
if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || ! [[ "$FILES_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Ошибка: порог и количество файлов должны быть целыми числами."
    exit 1
fi

#4. Честный расчёт процента
# df --output=size берёт только колонку размера ФС в КБ
TOTAL_KB=$(df -k --output=size "$LOG_DIR" | tail -1)
# du -sk считает занятые блоки папки в КБ
DIR_KB=$(du -sk "$LOG_DIR" | awk '{print $1}')

if [ -z "$TOTAL_KB" ] || [ "$TOTAL_KB" -eq 0 ]; then
    echo "Ошибка: не удалось определить размер файловой системы."
    exit 1
fi

USAGE=$(( DIR_KB * 100 / TOTAL_KB ))
echo "Папка '$LOG_DIR': ${DIR_KB} KB из ${TOTAL_KB} KB - это ${USAGE}%."

#5. Проверка порога
if [ "$USAGE" -le "$THRESHOLD" ]; then
    echo "Порог ${THRESHOLD}% не превышен. Архивация не требуется."
    exit 0
fi

echo "Превышен порог ${THRESHOLD}%. Архивируем ${FILES_COUNT} самых старых файлов..."

#6. Готовим папку для бэкапов
mkdir -p "$BACKUP_DIR"

#7. Фильтрация: находим M самых старых файлов
# find -printf '%T@\t%p\n' - время модификации в секундах + путь, разделитель - таб
# sort -n - сортировка по времени (старые первыми)
# head -n M - берём первые M
# cut -f2- - отрезаем время, оставляем путь
# tr '\n' '\0' - превращаем переводы строк в нуль-байты
# tar --null -T - - читает список файлов, разделённых \0
ARCHIVE_NAME="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

# Оборачиваем пайп в { ...; } || true, чтобы SIGPIPE от head не ронял скрипт
{
    find "$LOG_DIR" -type f -printf '%T@\t%p\n' \
        | sort -n \
        | head -n "$FILES_COUNT" \
        | cut -f2- \
        | tr '\n' '\0' \
        | tar -czf "$ARCHIVE_PATH" --null -T -
} || true

#8. Проверяем результат
if [ -f "$ARCHIVE_PATH" ]; then
    SIZE=$(du -h "$ARCHIVE_PATH" | awk '{print $1}')
    echo "Архив создан: $ARCHIVE_PATH ($SIZE)"
    echo "Содержимое архива:"
    tar -tzf "$ARCHIVE_PATH"
else
    echo "Ошибка: архив не был создан."
    exit 1
fi


