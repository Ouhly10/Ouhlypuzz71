#!/bin/bash

# ============================================
# إعدادات Telegram - تُقرأ من متغيرات البيئة
# إذا لم توجد تُستخدم القيم الافتراضية
# ============================================
TG_TOKEN="${TG_TOKEN:-YOUR_TOKEN_HERE}"
TG_CHAT="${TG_CHAT:-YOUR_CHAT_ID_HERE}"

# ============================================
# العنوان المستهدف - لغز 71
# ============================================
TARGET="${TARGET:-1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU}"

# ============================================
# مدة كل نطاق بالثواني
# ============================================
RANGE_DURATION="${RANGE_DURATION:-3600}"

# ============================================
# قائمة النطاقات - تُقرأ من متغير البيئة RANGES
# إذا لم يوجد تُستخدم النطاقات الافتراضية
# ============================================
if [ -n "$RANGES" ]; then
    # قراءة من متغير البيئة - كل سطر نطاق
    mapfile -t RANGES_ARR <<< "$RANGES"
else
    # النطاقات الافتراضية
    RANGES_ARR=(
        "400000000000000000 4FFFFFFFFFFFFFFFFF"
        "500000000000000000 5FFFFFFFFFFFFFFFFF"
        "600000000000000000 6FFFFFFFFFFFFFFFFF"
        "700000000000000000 7FFFFFFFFFFFFFFFFF"
    )
fi

# استخدام RANGES_ARR بدل RANGES
RANGES=("${RANGES_ARR[@]}")

# ============================================
# ملفات حفظ الحالة
# ============================================
RANGE_INDEX_FILE="/workspace/logs/current_range_index.txt"
RANGE_HASH_FILE="/workspace/logs/current_range_hash.txt"
RESULT="/workspace/results/found.txt"
LOG="/workspace/logs/rotor.log"
MLOG="/workspace/logs/monitor.log"

# ============================================
# اكتشاف GPU
# ============================================
GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
[ "$GPU_COUNT" -eq 0 ] && GPU_COUNT=1

case "$GPU_COUNT" in
    1) GPU_IDS="0";   GPUX="256,256" ;;
    2) GPU_IDS="0,1"; GPUX="256,256,256,256" ;;
    3) GPU_IDS="0,1,2"; GPUX="256,256,256,256,256,256" ;;
    *) GPU_IDS="0,1,2,3"; GPUX="256,256,256,256,256,256,256,256" ;;
esac

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
echo "🖥️  GPU: ${GPU_NAME} | IDs: ${GPU_IDS}"

# ============================================
# إنشاء المجلدات
# ============================================
mkdir -p /workspace/logs /workspace/results

# ============================================
# Smart Range Detection
# ============================================
CURRENT_HASH=$(echo "${RANGES[*]}" | md5sum | cut -d' ' -f1)

if [ -f "$RANGE_INDEX_FILE" ] && [ -f "$RANGE_HASH_FILE" ]; then
    SAVED_HASH=$(cat "$RANGE_HASH_FILE")
    if [ "$SAVED_HASH" = "$CURRENT_HASH" ]; then
        CURRENT_RANGE_IDX=$(cat "$RANGE_INDEX_FILE")
        echo "✅ نفس النطاقات → نكمل من النطاق $((CURRENT_RANGE_IDX + 1))"
    else
        CURRENT_RANGE_IDX=0
        echo "$CURRENT_HASH" > "$RANGE_HASH_FILE"
        echo "$CURRENT_RANGE_IDX" > "$RANGE_INDEX_FILE"
        echo "🆕 نطاقات جديدة → نبدأ من النطاق 1"
    fi
else
    CURRENT_RANGE_IDX=0
    echo "$CURRENT_HASH" > "$RANGE_HASH_FILE"
    echo "$CURRENT_RANGE_IDX" > "$RANGE_INDEX_FILE"
    echo "🆕 أول تشغيل → نبدأ من النطاق 1"
fi

TOTAL_RANGES=${#RANGES[@]}

if [ "$CURRENT_RANGE_IDX" -ge "$TOTAL_RANGES" ]; then
    echo "✅ تم الانتهاء من جميع النطاقات!"
    python3 -c "
import urllib.request, urllib.parse, ssl
msg = '🏁 اكتملت جميع النطاقات (${TOTAL_RANGES})\nلم يُعثر على المفتاح.'
data = urllib.parse.urlencode({'chat_id':'${TG_CHAT}','text':msg}).encode()
ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=0
urllib.request.urlopen(urllib.request.Request('https://api.telegram.org/bot${TG_TOKEN}/sendMessage',data),timeout=20,context=ctx)
" 2>/dev/null
    exit 0
fi

CURRENT_RANGE="${RANGES[$CURRENT_RANGE_IDX]}"
RANGE_START=$(echo "$CURRENT_RANGE" | awk '{print $1}')
RANGE_END=$(echo "$CURRENT_RANGE" | awk '{print $2}')

# حفظ الإعدادات
cat > /opt/monitor_config.env << EOF
TG_TOKEN=${TG_TOKEN}
TG_CHAT=${TG_CHAT}
GPU_IDS=${GPU_IDS}
GPUX=${GPUX}
GPU_NAME=${GPU_NAME}
CURRENT_RANGE_IDX=${CURRENT_RANGE_IDX}
TOTAL_RANGES=${TOTAL_RANGES}
RANGE_START=${RANGE_START}
RANGE_END=${RANGE_END}
TARGET=${TARGET}
RANGE_INDEX_FILE=${RANGE_INDEX_FILE}
RANGE_DURATION=${RANGE_DURATION}
EOF

# كتابة قائمة النطاقات
RANGES_FILE="/opt/ranges_list.txt"
> "$RANGES_FILE"
for r in "${RANGES[@]}"; do
    echo "$r" >> "$RANGES_FILE"
done

# ============================================
# كتابة monitor.py
# ============================================
cat > /opt/monitor.py << 'PYEOF'
import time, subprocess, os, re, ssl, urllib.request, urllib.parse, threading

cfg = {}
with open('/opt/monitor_config.env') as f:
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            cfg[k] = v

TOKEN            = cfg['TG_TOKEN']
CHAT             = cfg['TG_CHAT']
GPU_IDS          = cfg['GPU_IDS']
GPUX             = cfg['GPUX']
GPU_NAME         = cfg['GPU_NAME']
CURRENT_IDX      = int(cfg['CURRENT_RANGE_IDX'])
TOTAL_RANGES     = int(cfg['TOTAL_RANGES'])
RANGE_START      = cfg['RANGE_START']
RANGE_END        = cfg['RANGE_END']
TARGET           = cfg['TARGET']
RANGE_INDEX_FILE = cfg['RANGE_INDEX_FILE']
RANGE_DURATION   = int(cfg['RANGE_DURATION'])
RESULT           = '/workspace/results/found.txt'
LOG              = '/workspace/logs/rotor.log'
MLOG             = '/workspace/logs/monitor.log'
RANGES_FILE      = '/opt/ranges_list.txt'
ROTOR            = '/opt/Rotor-Cuda/Rotor-Cuda/Rotor'

def load_ranges():
    ranges = []
    try:
        with open(RANGES_FILE) as f:
            for line in f:
                line = line.strip()
                if not line: continue
                parts = line.split()
                if len(parts) == 2:
                    ranges.append((parts[0], parts[1]))
    except Exception as e:
        log(f"خطأ: {e}")
    return ranges

def log(msg):
    with open(MLOG, 'a') as f:
        f.write(f"[{time.strftime('%H:%M:%S')}] {msg}\n")

def notify(msg):
    for attempt in range(1, 4):
        try:
            data = urllib.parse.urlencode({'chat_id': CHAT, 'text': msg}).encode()
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            req = urllib.request.Request(
                f'https://api.telegram.org/bot{TOKEN}/sendMessage', data=data)
            urllib.request.urlopen(req, timeout=20, context=ctx)
            log(f"إشعار: {msg[:60]}")
            return
        except Exception as e:
            log(f"خطأ إشعار {attempt}/3: {e}")
            if attempt < 3:
                time.sleep(5)
    log("فشل الإشعار - متابعة")

def rotor_running():
    r = subprocess.run(['pgrep', '-f', 'Rotor'], capture_output=True)
    return r.returncode == 0

def kill_rotor():
    subprocess.run(['pkill', '-9', '-f', 'Rotor'], capture_output=True)
    time.sleep(2)

def start_rotor(start, end):
    cmd = (
        f'{ROTOR} -g --gpui {GPU_IDS} --gpux {GPUX} '
        f'-m address --coin BTC '
        f'-r 5 --range {start}:{end} '
        f'-o {RESULT} '
        f'{TARGET} '
        f'>> {LOG} 2>&1'
    )
    subprocess.Popen(cmd, shell=True, start_new_session=True)
    log(f"Rotor بدأ: {start} → {end}")

def get_stats():
    speed, total = 'N/A', 'N/A'
    try:
        with open(LOG) as f:
            lines = f.readlines()
        for line in reversed(lines[-100:]):
            m_speed = re.search(r'GPU:\s*([\d.]+)\s*([MGk])k?/s', line)
            m_total = re.search(r'T:\s*([\d,]+)', line)
            if m_speed:
                speed = f"{m_speed.group(1)} {m_speed.group(2)}k/s"
            if m_total:
                total = m_total.group(1)
            if m_speed and m_total:
                break
    except:
        pass
    return speed, total

def advance_range(active_idx, all_ranges, done_start, done_end, reason="time"):
    log(f"✅ النطاق {active_idx + 1} اكتمل ({reason})")
    notify(
        f"✅ اكتمل النطاق {active_idx + 1}/{TOTAL_RANGES}\n"
        f"▶️ {done_start}\n"
        f"⏹️ {done_end}\n"
        f"🔍 لم يُعثر على المفتاح\n"
        f"🕐 {time.strftime('%H:%M:%S')}"
    )
    kill_rotor()
    next_idx = active_idx + 1

    if next_idx >= len(all_ranges):
        log("🏁 جميع النطاقات اكتملت")
        notify(
            f"🏁 اكتملت جميع النطاقات ({TOTAL_RANGES})\n"
            f"❌ لم يُعثر على المفتاح\n"
            f"🕐 {time.strftime('%H:%M:%S')}"
        )
        with open(RANGE_INDEX_FILE, 'w') as f:
            f.write(str(next_idx))
        return None

    with open(RANGE_INDEX_FILE, 'w') as f:
        f.write(str(next_idx))

    next_start, next_end = all_ranges[next_idx]
    log(f"▶️ بدء النطاق {next_idx + 1}: {next_start}")

    if os.path.exists(RESULT):
        os.remove(RESULT)

    with open(LOG, 'w') as f:
        f.write(f"=== النطاق {next_idx + 1} - {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n")

    start_rotor(next_start, next_end)
    time.sleep(10)

    notify(
        f"🔄 بدأ النطاق {next_idx + 1}/{TOTAL_RANGES}\n"
        f"▶️ {next_start}\n"
        f"⏹️ {next_end}\n"
        f"⏱️ مدة: {RANGE_DURATION // 3600} ساعة\n"
        f"🕐 {time.strftime('%H:%M:%S')}"
    )
    return next_idx

# ============================================
# Thread مراقبة المفتاح
# ============================================
key_found_flag = threading.Event()
active_range_idx_ref = [CURRENT_IDX]

def watch_result():
    while not key_found_flag.is_set():
        if os.path.exists(RESULT) and os.path.getsize(RESULT) > 0:
            key = open(RESULT).read().strip()
            log(f"🎉 المفتاح وُجد: {key}")
            key_found_flag.set()
            msg = (
                f"🎉 المفتاح وُجد! لغز 71\n"
                f"🔑 {key}\n"
                f"📋 النطاق: {active_range_idx_ref[0] + 1}/{TOTAL_RANGES}\n"
                f"🕐 {time.strftime('%H:%M:%S')}"
            )
            for i in range(1, 4):
                notify(msg)
                if i < 3:
                    time.sleep(60)
            kill_rotor()
            notify(f"🏁 انتهى البحث بنجاح!\n🔑 {key}")
            while True:
                time.sleep(3600)
        time.sleep(5)

watcher = threading.Thread(target=watch_result, daemon=True)
watcher.start()

# ============================================
# بداية Monitor
# ============================================
active_idx  = CURRENT_IDX
range_start_time = time.time()
last_report = time.time()
REPORT_INTERVAL = 900

log(f"====== Monitor بدأ - لغز 71 ======")
log(f"النطاق {active_idx + 1}/{TOTAL_RANGES} | مدة: {RANGE_DURATION}s")

notify(
    f"🚀 Rotor-Cuda يعمل - لغز 71\n"
    f"📋 النطاق: {active_idx + 1}/{TOTAL_RANGES}\n"
    f"▶️ {RANGE_START}\n"
    f"⏹️ {RANGE_END}\n"
    f"⏱️ مدة: {RANGE_DURATION // 3600} ساعة\n"
    f"🎮 GPU: {GPU_NAME}\n"
    f"🕐 {time.strftime('%H:%M:%S')}"
)

# ============================================
# الحلقة الرئيسية
# ============================================
while True:
    try:
        time.sleep(30)

        if key_found_flag.is_set():
            while True:
                time.sleep(3600)

        all_ranges = load_ranges()
        elapsed = time.time() - range_start_time

        # الحالة 1: انتهى الوقت المحدد للنطاق
        if elapsed >= RANGE_DURATION:
            log(f"⏰ انتهى وقت النطاق {active_idx + 1} ({elapsed:.0f}s)")
            done = all_ranges[active_idx] if active_idx < len(all_ranges) else (RANGE_START, RANGE_END)
            result = advance_range(active_idx, all_ranges, done[0], done[1], "time")
            if result is None:
                while True:
                    time.sleep(3600)
                    log("انتهت جميع النطاقات")
            active_idx = result
            active_range_idx_ref[0] = active_idx
            range_start_time = time.time()
            last_report = time.time()
            continue

        # الحالة 2: Rotor توقف مبكراً
        if not rotor_running():
            found_empty = (not os.path.exists(RESULT)) or (os.path.getsize(RESULT) == 0)
            if found_empty:
                log(f"⚠️ Rotor توقف مبكراً - إعادة تشغيل")
                if active_idx < len(all_ranges):
                    s, e = all_ranges[active_idx]
                    start_rotor(s, e)
            continue

        # الحالة 3: تقرير كل 15 دقيقة
        if time.time() - last_report >= REPORT_INTERVAL:
            speed, total = get_stats()
            remaining = RANGE_DURATION - elapsed
            log(f"تقرير: {speed} | T={total}")
            notify(
                f"📊 تقرير لغز 71\n"
                f"📋 النطاق: {active_idx + 1}/{TOTAL_RANGES}\n"
                f"⚡ {speed}\n"
                f"🔢 T: {total}\n"
                f"⏳ متبقي: {remaining // 60:.0f} دقيقة\n"
                f"🕐 {time.strftime('%H:%M:%S')}"
            )
            last_report = time.time()

    except Exception as e:
        log(f"⚠️ خطأ: {e} - إعادة بعد دقيقة")
        time.sleep(60)
PYEOF

# ============================================
# إيقاف العمليات القديمة
# ============================================
pkill -9 -f monitor.py 2>/dev/null
pkill -9 -f Rotor 2>/dev/null
sleep 2

# ============================================
# تشغيل Rotor-Cuda
# ============================================
nohup /opt/Rotor-Cuda/Rotor-Cuda/Rotor \
    -g --gpui $GPU_IDS --gpux $GPUX \
    -m address --coin BTC \
    -r 5 --range ${RANGE_START}:${RANGE_END} \
    -o ${RESULT} \
    ${TARGET} \
    >> ${LOG} 2>&1 &
ROTOR_PID=$!
disown $ROTOR_PID

# ============================================
# تشغيل Monitor
# ============================================
nohup python3 /opt/monitor.py > /dev/null 2>&1 &
MONITOR_PID=$!
disown $MONITOR_PID

sleep 5

# ============================================
# التحقق النهائي
# ============================================
echo ""
echo "======= الحالة ======="
echo "🖥️  GPU: ${GPU_NAME}"
echo "📋 النطاق: $((CURRENT_RANGE_IDX + 1)) / $TOTAL_RANGES"
echo "   START: ${RANGE_START}"
echo "   END:   ${RANGE_END}"
echo "   مدة:   $((RANGE_DURATION / 3600)) ساعة"
pgrep -f "monitor.py" > /dev/null && echo "✅ Monitor يعمل" || echo "❌ Monitor فشل!"
pgrep -f "Rotor" > /dev/null && echo "✅ Rotor يعمل" || echo "❌ Rotor لا يعمل!"

# إشعار Telegram
python3 -c "
import urllib.request, urllib.parse, ssl
msg = (
    'Instance جاهز - لغز 71\n'
    'GPU: ${GPU_NAME}\n'
    'النطاق: $((CURRENT_RANGE_IDX + 1))/${TOTAL_RANGES}\n'
    'START: ${RANGE_START}\n'
    'END:   ${RANGE_END}\n'
    'مدة: $((RANGE_DURATION / 3600)) ساعة\n'
    'Rotor PID: ${ROTOR_PID}'
)
data = urllib.parse.urlencode({'chat_id':'${TG_CHAT}','text':msg}).encode()
ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=0
urllib.request.urlopen(urllib.request.Request('https://api.telegram.org/bot${TG_TOKEN}/sendMessage',data),timeout=20,context=ctx)
" 2>/dev/null

echo ""
echo "======= أوامر مفيدة ======="
echo "📺 monitor: tail -f /workspace/logs/monitor.log"
echo "📺 rotor:   tail -f /workspace/logs/rotor.log"
