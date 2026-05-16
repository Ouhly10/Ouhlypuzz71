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

RUN git clone https://github.com/Mehdi256/Rotor-Cuda.git /opt/Rotor-Cuda

WORKDIR /opt/Rotor-Cuda/Rotor-Cuda

RUN make gpu=1 CCAP=86 all -j$(nproc)

RUN mkdir -p /workspace/logs /workspace/results /opt/puzzle71

COPY start.sh /opt/start.sh
RUN chmod +x /opt/start.sh

CMD ["bash", "/opt/start.sh"]
