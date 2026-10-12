echo " ТЕСТИРОВАНИЕ log_archiver.sh"

PASS=0
FAIL=0

cleanup() {
    rm -rf /log/* 2>/dev/null
    rm -rf /backup/* 2>/dev/null
}

#ТЕСТ 1: Порог не превышен
echo ""
echo "--- ТЕСТ 1: Порог 99% (архивация НЕ должна произойти) ---"
cleanup
echo "small file" > /log/file1.log
./log_archiver.sh /log 99 1 > /tmp/test1.out 2>&1
ARCH_COUNT=$(ls -1 /backup/*.tar.gz 2>/dev/null | wc -l)
if [ "$ARCH_COUNT" -eq 0 ]; then
    echo "[PASS] Архив не создан (порог не превышен)."
    PASS=$((PASS+1))
else
    echo "[FAIL] Архив создан, хотя не должен был."
    cat /tmp/test1.out
    FAIL=$((FAIL+1))
fi

#ТЕСТ 2: Порог превышен, архив создаётся с нужным кол-вом файлов
echo ""
echo "--- ТЕСТ 2: Порог 0%, M=3 (архив с 3 файлами) ---"
cleanup
touch -d "2023-01-01 10:00:00" /log/old1.log
touch -d "2023-02-01 10:00:00" /log/old2.log
touch -d "2023-03-01 10:00:00" /log/old3.log
touch -d "2023-04-01 10:00:00" /log/new1.log
touch -d "2023-05-01 10:00:00" /log/new2.log
dd if=/dev/zero of=/log/dummy.bin bs=1M count=4 status=none

./log_archiver.sh /log 0 3 > /tmp/test2.out 2>&1

ARCH_COUNT=$(ls -1 /backup/*.tar.gz 2>/dev/null | wc -l)
if [ "$ARCH_COUNT" -eq 1 ]; then
    echo "[PASS] Архив создан."
    ARCHIVE=$(ls -1 /backup/*.tar.gz | head -1)
    FILES_IN_ARCH=$(tar -tzf "$ARCHIVE" | wc -l)
    if [ "$FILES_IN_ARCH" -eq 3 ]; then
        echo "[PASS] В архиве ровно 3 файла."
        echo "       Содержимое:"
        tar -tzf "$ARCHIVE" | sed 's/^/         /'
        PASS=$((PASS+1))
    else
        echo "[FAIL] В архиве $FILES_IN_ARCH файлов, ожидалось 3."
        FAIL=$((FAIL+1))
    fi
else
    echo "[FAIL] Архив не создан."
    cat /tmp/test2.out
    FAIL=$((FAIL+1))
fi

#ТЕСТ 3: Проверка, что архивируются именно САМЫЕ СТАРЫЕ файлы
echo ""
echo "--- ТЕСТ 3: Проверка, что попали именно старые файлы ---"
cleanup
touch -d "2020-01-01" /log/oldest.log
touch -d "2021-01-01" /log/middle.log
touch -d "2022-01-01" /log/newest.log
dd if=/dev/zero of=/log/dummy.bin bs=1M count=4 status=none

./log_archiver.sh /log 0 2 > /tmp/test3.out 2>&1
ARCHIVE=$(ls -1 /backup/*.tar.gz 2>/dev/null | head -1)

if [ -n "$ARCHIVE" ]; then
    CONTENTS=$(tar -tzf "$ARCHIVE")
    if echo "$CONTENTS" | grep -q "oldest.log" && \
       echo "$CONTENTS" | grep -q "middle.log" && \
       ! echo "$CONTENTS" | grep -q "newest.log"; then
        echo "[PASS] В архив попали 2 самых старых файла."
        PASS=$((PASS+1))
    else
        echo "[FAIL] В архив попали не те файлы:"
        echo "$CONTENTS" | sed 's/^/       /'
        FAIL=$((FAIL+1))
    fi
else
    echo "[FAIL] Архив не создан."
    cat /tmp/test3.out
    FAIL=$((FAIL+1))
fi

#ТЕСТ 4: Неверные аргументы
echo ""
echo "--- ТЕСТ 4: Неверное кол-во аргументов ---"
./log_archiver.sh /log > /tmp/test4.out 2>&1
if [ $? -ne 0 ]; then
    echo "[PASS] Скрипт вернул ошибку при неверных аргументах."
    PASS=$((PASS+1))
else
    echo "[FAIL] Скрипт не отреагировал на неверные аргументы."
    FAIL=$((FAIL+1))
fi

#ТЕСТ 5: Несуществующая папка
echo ""
echo "--- ТЕСТ 5: Несуществующая папка ---"
./log_archiver.sh /no_such_dir 50 1 > /tmp/test5.out 2>&1
if [ $? -ne 0 ]; then
    echo "[PASS] Скрипт вернул ошибку для несуществующей папки."
    PASS=$((PASS+1))
else
    echo "[FAIL] Скрипт не отреагировал на несуществующую папку."
    FAIL=$((FAIL+1))
fi

#ИТОГИ
cleanup
echo ""
echo " ИТОГИ: PASS=$PASS  FAIL=$FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
