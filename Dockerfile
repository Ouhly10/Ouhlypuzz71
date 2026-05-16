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
# بناء KeyHunt-Cuda (Linux version)
# ============================================
RUN git clone https://github.com/phrutis/KeyHunt-Cuda.git /opt/KeyHunt-Cuda

WORKDIR /opt/KeyHunt-Cuda

# بناء مع ccap 86 - يعمل مع معظم البطاقات
RUN make CCAP=86 -j$(nproc) || \
    make CCAP=75 -j$(nproc) || \
    make -j$(nproc)

# ============================================
# تحضير المجلدات والملفات
# ============================================
RUN mkdir -p /workspace/logs /workspace/results /opt/puzzle71

# ============================================
# نسخ الملفات
# ============================================
COPY generate_hash160.py /opt/puzzle71/generate_hash160.py
COPY start.sh /opt/start.sh
RUN chmod +x /opt/start.sh

CMD ["bash", "/opt/start.sh"]
