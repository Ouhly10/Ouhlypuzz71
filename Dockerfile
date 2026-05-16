FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

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

RUN git clone https://github.com/manyunya/KeyHunt-Cuda.git /opt/KeyHunt-Cuda

RUN mkdir -p /workspace/logs /workspace/results /opt/puzzle71

COPY generate_hash160.py /opt/puzzle71/generate_hash160.py
COPY start.sh /opt/start.sh
RUN chmod +x /opt/start.sh

CMD ["bash", "/opt/start.sh"]
