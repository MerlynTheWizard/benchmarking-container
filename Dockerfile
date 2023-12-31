ARG FROM_IMAGE="gadicc/diffusers-api-base:python3.9-pytorch1.12.1-cuda11.6-xformers"
# You only need the -banana variant if you need banana's optimization
# i.e. not relevant if you're using RUNTIME_DOWNLOADS
# ARG FROM_IMAGE="gadicc/python3.9-pytorch1.12.1-cuda11.6-xformers-banana"
FROM ${FROM_IMAGE} as base
ENV FROM_IMAGE=${FROM_IMAGE}

# Note, docker uses HTTP_PROXY and HTTPS_PROXY (uppercase)
# We purposefully want those managed independently, as we want docker
# to manage its own cache.  This is just for pip, models, etc.
ARG http_proxy
ARG https_proxy
RUN if [ -n "$http_proxy" ] ; then \
    echo quit \
    | openssl s_client -proxy $(echo ${https_proxy} | cut -b 8-) -servername google.com -connect google.com:443 -showcerts \
    | sed 'H;1h;$!d;x; s/^.*\(-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----\)\n---\nServer certificate.*$/\1/' \
    > /usr/local/share/ca-certificates/squid-self-signed.crt ; \
    update-ca-certificates ; \
  fi
ARG REQUESTS_CA_BUNDLE=${http_proxy:+/usr/local/share/ca-certificates/squid-self-signed.crt}

ARG DEBIAN_FRONTEND=noninteractive

FROM base AS patchmatch
ARG USE_PATCHMATCH=0
WORKDIR /tmp
COPY scripts/patchmatch-setup.sh .
RUN sh patchmatch-setup.sh

FROM base as output
RUN mkdir /api
WORKDIR /api

# we use latest pip in base image
# RUN pip3 install --upgrade pip

ADD requirements.txt requirements.txt
RUN pip install -r requirements.txt

# [5e5ce13] adds xformers support to train_unconditional.py (#2520)
# Also includes LoRA safetensors support.
RUN git clone https://github.com/huggingface/diffusers && cd diffusers && git checkout 5e5ce13e2f89ac45a0066cb3f369462a3cf1d9ef
WORKDIR /api
RUN pip install -e diffusers

# Set to true to NOT download model at build time, rather at init / usage.
ARG RUNTIME_DOWNLOADS=0
ENV RUNTIME_DOWNLOADS=${RUNTIME_DOWNLOADS}

# TODO, to dda-bananana
# ARG PIPELINE="StableDiffusionInpaintPipeline"
ARG PIPELINE="ALL"
ENV PIPELINE=${PIPELINE}

# Deps for RUNNING (not building) earlier options
ARG USE_PATCHMATCH=0
RUN if [ "$USE_PATCHMATCH" = "1" ] ; then apt-get install -yqq python3-opencv ; fi
COPY --from=patchmatch /tmp/PyPatchMatch PyPatchMatch

# TODO, just include by default, and handle all deps in OUR requirements.txt
ARG USE_DREAMBOOTH=1
ENV USE_DREAMBOOTH=${USE_DREAMBOOTH}

RUN if [ "$USE_DREAMBOOTH" = "1" ] ; then \
    # By specifying the same torch version as conda, it won't download again.
    # Without this, it will upgrade torch, break xformers, make bigger image.
    pip install -r diffusers/examples/dreambooth/requirements.txt bitsandbytes torch==1.12.1 ; \
  fi
RUN if [ "$USE_DREAMBOOTH" = "1" ] ; then apt-get install git-lfs ; fi

RUN apt update
RUN apt install -y socat
RUN apt install -y libfreetype6
RUN apt install -y libgl1
RUN apt install -y unzip
RUN apt install -y curl
COPY api/download.py .
COPY api/app.py .
COPY api/utils/ ./utils/
COPY api/convert_to_diffusers.py .
COPY api/device.py .
COPY api/download_checkpoint.py .
COPY api/getPipeline.py .
COPY api/getScheduler.py .
COPY api/loadModel.py .
COPY api/precision.py .
COPY api/send.py .
COPY api/server.py .
COPY api/tests.py .
COPY api/train_dreambooth.py .
EXPOSE 50150



ARG MODEL_ID="runwayml/stable-diffusion-v1-5"
ENV MODEL_ID=${MODEL_ID}
ARG HF_MODEL_ID=""
ENV HF_MODEL_ID=${HF_MODEL_ID}
ARG MODEL_PRECISION="fp16"
ENV MODEL_PRECISION=${MODEL_PRECISION}
ARG MODEL_REVISION=""
ENV MODEL_REVISION=${MODEL_REVISION}


ENV RUNTIME_DOWNLOADS=0
RUN python3 download.py


RUN wget https://render.otoy.com/downloads/a/61/2d40eddf-65a5-4c96-bc10-ab527f31dbee/OctaneBench_2020_1_5_linux.zip

RUN unzip OctaneBench_2020_1_5_linux.zip
RUN apt-get install -y sysbench

COPY api/octane.sh .
COPY api/start.sh .
COPY api/smi.sh .
COPY api/utilization.sh .
COPY api/stress.py .
COPY api/plot.py .
COPY api/run.py .


ENV sleep 120
ENV sleep2 0
ENV octane 1
ENV cpu 1
ENV loops 1


ARG SAFETENSORS_FAST_GPU=1
ENV SAFETENSORS_FAST_GPU=${SAFETENSORS_FAST_GPU}

CMD bash start.sh

