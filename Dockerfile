# ============================================
# Base: CUDA 11.8 + Ubuntu 22.04 (الأسرع للبناء)
# ============================================
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ============================================
# تثبيت المتطلبات
# ============================================
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    python3 \
    python3-pip \
    libgmp-dev \
    libssl-dev \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# بناء KeyHunt-Cuda
# ============================================
WORKDIR /opt
RUN git clone https://github.com/Qalander/KeyHunt-Cuda.git

WORKDIR /opt/KeyHunt-Cuda

# تعديل Makefile لدعم ccap تلقائي
RUN sed -i 's/CCAP ?= 75/CCAP ?= 86/' Makefile || true

# بناء مع دعم GPU
RUN make gpu=1 CCAP=86 -j$(nproc) || \
    make CCAP=86 -j$(nproc) || \
    make -j$(nproc)

# ============================================
# تحضير ملف hash160 للغز 71
# ============================================
RUN mkdir -p /opt/puzzle71

# hash160 لعنوان لغز 71: 1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU
# سيتم توليده عند التشغيل الأول
COPY generate_hash160.py /opt/puzzle71/generate_hash160.py

# ============================================
# نسخ السكريبت الرئيسي
# ============================================
COPY start.sh /opt/start.sh
RUN chmod +x /opt/start.sh

# ============================================
# مجلدات العمل
# ============================================
RUN mkdir -p /workspace/logs /workspace/results

CMD ["bash", "/opt/start.sh"]
