#!/bin/bash

# ============================================
# إعدادات Telegram
# ============================================
TG_TOKEN="8799513128:AAFF5a0v4-8afMOr4dvRfgnIdPkXCF9UsAI"
TG_CHAT="1286122053"

# ============================================
# قائمة النطاقات - نفس نظام Kangaroo
# الصيغة: "START END"  (hex)
# النطاق الكامل للغز 71:
# 400000000000000000 → 7FFFFFFFFFFFFFFFFF
# ============================================
RANGES=(
    "400000000000000000 400000100000000000"
    "500000100000000000 500000200000000000"
    "600000200000000000 600000300000000000"
    "700000300000000000 700000400000000000"
)

# عنوان لغز 71
TARGET_ADDRESS="1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU"
HASH160_FILE="/opt/puzzle71/puzzle71.bin"

# ============================================
# ملفات حفظ الحالة
# ============================================
RANGE_INDEX_FILE="/workspace/logs/current_range_index.txt"
RANGE_HASH_FILE="/workspace/logs/current_range_hash.txt"

# ============================================
# اكتشاف GPU
# ============================================
GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
[ "$GPU_COUNT" -eq 0 ] && GPU_COUNT=1

case "$GPU_COUNT" in
    1) GPU_IDS="0" ;;
    2) GPU_IDS="0,1" ;;
    3) GPU_IDS="0,1,2" ;;
    *) GPU_IDS="0,1,2,3" ;;
esac

# اكتشاف ccap
CCAP_RAW=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)
MAJOR=$(echo $CCAP_RAW | cut -d'.' -f1)
MINOR=$(echo $CCAP_RAW | cut -d'.' -f2)

if [ -z "$MAJOR" ]; then
    CCAP=86
elif [ "$MAJOR" -ge 12 ]; then
    CCAP=100
elif [ "$MAJOR" -eq 8 ] && [ "$MINOR" -eq 9 ]; then
    CCAP=89
elif [ "$MAJOR" -eq 8 ]; then
    CCAP=86
else
    CCAP="${MAJOR}${MINOR}"
fi

echo "🖥️  GPU: ccap=${CCAP} | IDs=${GPU_IDS}"

# ============================================
# إنشاء المجلدات
# ============================================
mkdir -p /workspace/results /workspace/logs /opt/puzzle71

# توليد hash160 إذا لم يكن موجوداً
if [ ! -f "$HASH160_FILE" ]; then
    python3 /opt/puzzle71/generate_hash160.py
fi

# ============================================
# Smart Range Detection - نفس Kangaroo
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

# التحقق من اكتمال جميع النطاقات
if [ "$CURRENT_RANGE_IDX" -ge "$TOTAL_RANGES" ]; then
    echo "✅ تم الانتهاء من جميع النطاقات!"
    python3 -c "
import urllib.request, urllib.parse
data = urllib.parse.urlencode({'chat_id':'${TG_CHAT}','text':'🏁 اكتملت جميع النطاقات (${TOTAL_RANGES})\nلم يُعثر على المفتاح.'}).encode()
urllib.request.urlopen('https://api.telegram.org/bot${TG_TOKEN}/sendMessage',data,timeout=10)
" 2>/dev/null
    exit 0
fi

# استخراج النطاق الحالي
CURRENT_RANGE="${RANGES[$CURRENT_RANGE_IDX]}"
RANGE_START=$(echo "$CURRENT_RANGE" | awk '{print $1}')
RANGE_END=$(echo "$CURRENT_RANGE" | awk '{print $2}')

echo "📋 النطاق: $((CURRENT_RANGE_IDX + 1))/$TOTAL_RANGES"
echo "   START: $RANGE_START"
echo "   END:   $RANGE_END"

# حفظ الإعدادات للـ monitor
cat > /opt/monitor_config.env << EOF
TG_TOKEN=${TG_TOKEN}
TG_CHAT=${TG_CHAT}
GPU_IDS=${GPU_IDS}
CURRENT_RANGE_IDX=${CURRENT_RANGE_IDX}
TOTAL_RANGES=${TOTAL_RANGES}
RANGE_START=${RANGE_START}
RANGE_END=${RANGE_END}
RANGE_INDEX_FILE=${RANGE_INDEX_FILE}
HASH160_FILE=${HASH160_FILE}
TARGET_ADDRESS=${TARGET_ADDRESS}
EOF

# كتابة قائمة النطاقات
RANGES_FILE="/opt/ranges_list.txt"
> "$RANGES_FILE"
for r in "${RANGES[@]}"; do
    echo "$r" >> "$RANGES_FILE"
done

# ============================================
# بناء KeyHunt-Cuda إذا لم يكن مبنياً
# ============================================
if [ ! -f /opt/KeyHunt-Cuda/KeyHunt-Cuda ]; then
    echo "🔨 بناء KeyHunt-Cuda..."
    cd /opt/KeyHunt-Cuda
    make gpu=1 CCAP=${CCAP} -j$(nproc) >> /workspace/logs/build.log 2>&1
    if [ ! -f /opt/KeyHunt-Cuda/KeyHunt-Cuda ]; then
        python3 -c "
import urllib.request, urllib.parse
data = urllib.parse.urlencode({'chat_id':'${TG_CHAT}','text':'❌ فشل بناء KeyHunt-Cuda!'}).encode()
urllib.request.urlopen('https://api.telegram.org/bot${TG_TOKEN}/sendMessage',data,timeout=10)
" 2>/dev/null
        exit 1
    fi
    echo "✅ KeyHunt-Cuda جاهز"
fi

# ============================================
# كتابة monitor.py - نفس منطق Kangaroo
# ============================================
cat > /opt/monitor.py << 'PYEOF'
import time, subprocess, os, re, math, ssl, urllib.request, urllib.parse, threading

cfg = {}
with open('/opt/monitor_config.env') as f:
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            cfg[k] = v

TOKEN            = cfg['TG_TOKEN']
CHAT             = cfg['TG_CHAT']
GPU_IDS          = cfg['GPU_IDS']
CURRENT_IDX      = int(cfg['CURRENT_RANGE_IDX'])
TOTAL_RANGES     = int(cfg['TOTAL_RANGES'])
RANGE_START      = cfg['RANGE_START']
RANGE_END        = cfg['RANGE_END']
RANGE_INDEX_FILE = cfg['RANGE_INDEX_FILE']
HASH160_FILE     = cfg['HASH160_FILE']
TARGET_ADDRESS   = cfg['TARGET_ADDRESS']
LOG              = '/workspace/logs/keyhunt.log'
RESULT           = '/workspace/results/found.txt'
MLOG             = '/workspace/logs/monitor.log'
RANGES_FILE      = '/opt/ranges_list.txt'

# ============================================
# حساب Target Count - نفس Kangaroo
# 98% من النطاق
# ============================================
def calc_target_count(start_hex, end_hex):
    try:
        size = int(end_hex, 16) - int(start_hex, 16)
        if size <= 0:
            return 32.0
        size_bits = size.bit_length()
        target = (size_bits - 1) / 2.0
        target = target - 0.029  # 98%
        return round(target, 2)
    except:
        return 32.0

def load_ranges():
    ranges = []
    try:
        with open(RANGES_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split()
                if len(parts) == 2:
                    ranges.append((parts[0], parts[1]))
    except Exception as e:
        log(f"خطأ تحميل النطاقات: {e}")
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
                f'https://api.telegram.org/bot{TOKEN}/sendMessage',
                data=data
            )
            urllib.request.urlopen(req, timeout=20, context=ctx)
            log(f"إشعار أُرسل: {msg[:60]}")
            return
        except Exception as e:
            log(f"خطأ إشعار {attempt}/3: {e}")
            if attempt < 3:
                time.sleep(5)
    log("فشل الإشعار - متابعة")

def keyhunt_running():
    r = subprocess.run(['pgrep', '-f', 'KeyHunt-Cuda'], capture_output=True)
    return r.returncode == 0

def kill_keyhunt():
    subprocess.run(['pkill', '-9', '-f', 'KeyHunt-Cuda'], capture_output=True)
    time.sleep(2)

def start_keyhunt(start, end):
    # بناء GPU IDs للـ KeyHunt (--gpui 0,1,...)
    cmd = (
    f'/opt/KeyHunt-Cuda/keyhunt '
    f'-m bsgs '
    f'-f {HASH160_FILE} '
    f'-r {start}:{end} '
    f'-R -q '
    f'-o {RESULT} '
    f'>> {LOG} 2>&1'
)
    )
    subprocess.Popen(cmd, shell=True, start_new_session=True)
    log(f"KeyHunt بدأ: {start} → {end}")

def get_current_count():
    """يقرأ Mkeys من log ويحوله لـ count بصيغة log2"""
    try:
        with open(LOG) as f:
            lines = f.readlines()
        for line in reversed(lines[-200:]):
            # KeyHunt يطبع: [GPU: 363.60 Gkeys/s] [T: 242,432,650,248,192]
            m = re.search(r'\[T:\s*([\d,]+)\]', line)
            if m:
                total = int(m.group(1).replace(',', ''))
                if total > 0:
                    return math.log2(total)
    except:
        pass
    return 0.0

def get_stats():
    speed, total = 'N/A', 'N/A'
    try:
        with open(LOG) as f:
            lines = f.readlines()
        for line in reversed(lines[-200:]):
            m_speed = re.search(r'\[GPU:\s*([\d.]+)\s*([MG])keys/s\]', line)
            m_total = re.search(r'\[T:\s*([\d,]+)\]', line)
            if m_speed:
                val = float(m_speed.group(1))
                unit = m_speed.group(2)
                speed = f"{val} {unit}keys/s"
            if m_total:
                total = m_total.group(1)
            if m_speed and m_total:
                break
    except:
        pass
    return speed, total

def advance_range(active_idx, all_ranges, done_start, done_end, reason="count"):
    log(f"✅ النطاق {active_idx + 1} اكتمل ({reason})")
    notify(
        f"✅ اكتمل النطاق {active_idx + 1}/{TOTAL_RANGES}\n"
        f"▶️ {done_start}\n"
        f"⏹️ {done_end}\n"
        f"🔍 لم يُعثر على المفتاح\n"
        f"🕐 {time.strftime('%H:%M:%S')}"
    )
    kill_keyhunt()
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

    start_keyhunt(next_start, next_end)
    time.sleep(10)

    target = calc_target_count(next_start, next_end)
    notify(
        f"🔄 بدأ النطاق {next_idx + 1}/{TOTAL_RANGES}\n"
        f"▶️ {next_start}\n"
        f"⏹️ {next_end}\n"
        f"🎯 Target: 2^{target}\n"
        f"🕐 {time.strftime('%H:%M:%S')}"
    )
    return next_idx, target

# ============================================
# Thread مراقبة المفتاح فوراً
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
            kill_keyhunt()
            notify(
                f"🏁 انتهى البحث بنجاح!\n"
                f"🔑 {key}\n"
                f"🕐 {time.strftime('%H:%M:%S')}"
            )
            while True:
                time.sleep(3600)
        time.sleep(5)

watcher = threading.Thread(target=watch_result, daemon=True)
watcher.start()

# ============================================
# بداية Monitor
# ============================================
active_idx   = CURRENT_IDX
target_count = calc_target_count(RANGE_START, RANGE_END)
last_report  = time.time()
REPORT_INTERVAL = 900

log(f"====== Monitor بدأ - لغز 71 ======")
log(f"النطاق {active_idx + 1}/{TOTAL_RANGES} | Target = 2^{target_count}")

notify(
    f"🚀 KeyHunt يعمل - لغز 71\n"
    f"📋 النطاق: {active_idx + 1}/{TOTAL_RANGES}\n"
    f"▶️ {RANGE_START}\n"
    f"⏹️ {RANGE_END}\n"
    f"🎯 Target: 2^{target_count}\n"
    f"🎮 GPU:{GPU_IDS} | 🕐 {time.strftime('%H:%M:%S')}"
)

# ============================================
# الحلقة الرئيسية - فحص كل 30 ثانية
# ============================================
while True:
    try:
        time.sleep(30)

        if key_found_flag.is_set():
            while True:
                time.sleep(3600)

        all_ranges = load_ranges()
        current_count = get_current_count()

        # الحالة 1: وصل Count للهدف
        if current_count >= target_count:
            log(f"🎯 Count 2^{current_count} وصل الهدف 2^{target_count}")
            done = all_ranges[active_idx] if active_idx < len(all_ranges) else (RANGE_START, RANGE_END)
            result = advance_range(active_idx, all_ranges, done[0], done[1], f"count 2^{current_count}")
            if result is None:
                while True:
                    time.sleep(3600)
                    log("انتهت جميع النطاقات")
            active_idx, target_count = result
            active_range_idx_ref[0] = active_idx
            last_report = time.time()
            continue

        # الحالة 2: KeyHunt توقف مبكراً
        if not keyhunt_running():
            found_empty = (not os.path.exists(RESULT)) or (os.path.getsize(RESULT) == 0)
            if found_empty:
                log(f"⚠️ KeyHunt توقف مبكراً عند 2^{current_count}")
                done = all_ranges[active_idx] if active_idx < len(all_ranges) else (RANGE_START, RANGE_END)
                result = advance_range(active_idx, all_ranges, done[0], done[1], "توقف مبكر")
                if result is None:
                    while True:
                        time.sleep(3600)
                active_idx, target_count = result
                active_range_idx_ref[0] = active_idx
                last_report = time.time()
            continue

        # الحالة 3: يعمل → تقرير كل 15 دقيقة
        if time.time() - last_report >= REPORT_INTERVAL:
            speed, total = get_stats()
            progress = round((current_count / target_count) * 100, 1) if target_count > 0 else 0
            log(f"تقرير: {speed} | Total={total} ({progress}%)")
            notify(
                f"📊 تقرير لغز 71\n"
                f"📋 النطاق: {active_idx + 1}/{TOTAL_RANGES}\n"
                f"⚡ {speed}\n"
                f"🔢 Total: {total}\n"
                f"📈 تقدم: {progress}%\n"
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
pkill -9 -f KeyHunt-Cuda 2>/dev/null
sleep 2

# ============================================
# تشغيل KeyHunt-Cuda
# ============================================
nohup /opt/KeyHunt-Cuda/keyhunt \
    -m bsgs \
    -f ${HASH160_FILE} \
    -r ${RANGE_START}:${RANGE_END} \
    -R -q \
    -o /workspace/results/found.txt \
    >> /workspace/logs/keyhunt.log 2>&1 &
KEYHUNT_PID=$!
disown $KEYHUNT_PID

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
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)

echo ""
echo "======= الحالة ======="
echo "🖥️  GPU: ${GPU_NAME} | ccap: ${CCAP}"
echo "📋 النطاق: $((CURRENT_RANGE_IDX + 1)) / $TOTAL_RANGES"
echo "   START: ${RANGE_START}"
echo "   END:   ${RANGE_END}"
pgrep -f "monitor.py"    > /dev/null && echo "✅ Monitor يعمل"    || echo "❌ Monitor فشل!"
pgrep -f "KeyHunt-Cuda"  > /dev/null && echo "✅ KeyHunt يعمل"    || echo "❌ KeyHunt لا يعمل!"

# إشعار Telegram
python3 -c "
import urllib.request, urllib.parse, ssl
msg = (
    'Instance جاهز - لغز 71\n'
    'GPU: ${GPU_NAME}\n'
    'النطاق: $((CURRENT_RANGE_IDX + 1))/${TOTAL_RANGES}\n'
    'START: ${RANGE_START}\n'
    'END:   ${RANGE_END}\n'
    'KeyHunt PID: ${KEYHUNT_PID}\n'
    'Monitor PID: ${MONITOR_PID}'
)
data = urllib.parse.urlencode({'chat_id':'${TG_CHAT}','text':msg}).encode()
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request('https://api.telegram.org/bot${TG_TOKEN}/sendMessage', data=data)
urllib.request.urlopen(req, timeout=20, context=ctx)
" 2>/dev/null

echo ""
echo "======= أوامر مفيدة ======="
echo "📺 monitor:  tail -f /workspace/logs/monitor.log"
echo "📺 keyhunt:  tail -f /workspace/logs/keyhunt.log"
echo "📋 النطاق:   cat /workspace/logs/current_range_index.txt"
