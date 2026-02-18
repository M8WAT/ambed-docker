# AMBEd Docker Image by Ash, 2E0WAT.
# Last Updated: 2024-06-19
#
# This Docker image is created in three stages.
# 
# The first stage pulls the latest Ubuntu image and applies any required updates
# and installs any common packages used by further stages. This removes the
# duplication of downloading and updating the images in the following stage(s).
#
# The second stage does the crux of the work, downloading and extracting FTDI
# drivers and the S6 Overlays before downloading the AMBEd source code and
# compiling it.
# 
# The third stage then "starts again" with a fresh image and only installs the
# bare minimum packages before pulling the AMBEd Executable, FTDI Drivers and S6
# Overlays from the stage 2 "builder" image.
# 
# Using this technique reduces the final image from ~493MB to ~162MB.
#
# Note - The layout of this file has been kept to 80cols wide wherever possible
# to aid editing on mobile devices.

################################### Stage 1 ####################################

# Select Docker Image to Build On
FROM ubuntu:latest AS start

# Set Environmental Variable
ENV TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

# Install Dependencies - Done first to cache package updates & installs and save
# time incase of mods made between builds later in the stage
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        curl \
        kmod \
        sudo

################################### Stage 2 ####################################

# Using Updated Base Image from Stage 1
FROM start AS builder

# Set Environmental Variable
ENV TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

# Install Dependencies - Done first to cache package updates & installs and save
# time incase of mods made between builds later in the stage
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    apt-get install -y \
        build-essential \
        wget

# Set Build Arguments
ARG AMBED_DIR=/ambed AMBED_SRC=/src/ambed USE_AGC=0
ARG FTDI_VER=1.4.27 FTDI_SRC=/src/ftdi
ARG FTDI_URL=https://ftdichip.com/wp-content/uploads/2022/07/libftd2xx-arm-v8-
ARG S6_VER=3.2.0.0 S6_SRC=/src/S6
ARG S6_URL=https://github.com/just-containers/s6-overlay/releases/download/v

# Create File Structure
RUN mkdir -p \
    ${AMBED_DIR} \
    ${AMBED_SRC} \
    ${FTDI_SRC} \
    ${S6_SRC}

# Fetch and Extract S6 Overlays & FTDI Driver
RUN wget -P /tmp ${S6_URL}${S6_VER}/s6-overlay-noarch.tar.xz && \
    wget -P /tmp ${S6_URL}${S6_VER}/s6-overlay-aarch64.tar.xz && \
    wget -P /tmp ${FTDI_URL}${FTDI_VER}.tgz && \
    tar -C ${S6_SRC}/ -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C ${S6_SRC}/ -Jxpf /tmp/s6-overlay-aarch64.tar.xz && \
    tar -C ${FTDI_SRC}/ -zxvf /tmp/libftd2xx-arm-v8-${FTDI_VER}.tgz

# Install FTDI Driver Ahead of AMBEd Compilation
RUN cd /usr/local/ && \
    cp ${FTDI_SRC}/release/build/libftd2xx.* ./lib/ && \
    chmod 0755 ./lib/libftd2xx.so.${FTDI_VER} && \
    ln -sf ./lib/libftd2xx.so.${FTDI_VER} ./lib/libftd2xx.so && \
    cp ${FTDI_SRC}/release/ftd2xx.h ./include/ && \
    cp ${FTDI_SRC}/release/WinTypes.h ./include/ && \
    ldconfig

# AMBEd Source Code
ADD --keep-git-dir=true https://github.com/LX3JL/xlxd.git#master ${AMBED_SRC}

# Modify AGC Setting, then Compile and Install AMBEd
RUN cd ${AMBED_SRC}${AMBED_DIR} && \
    sed "s/\(USE_AGC[[:space:]]*\)[[:digit:]]/\1${USE_AGC}/g" main.h && \
    make clean && \
    make && \
    make install

################################### Stage 3 ####################################

# Using Updated Base Image from Stage 1
FROM start AS base

# Set Environmental Variable
ENV TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

# Install Dependencies - Done first to cache package updates & installs and save
# time incase of mods made between builds later in the stage
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    apt-get install -y \
        lsof

# Set Build Arguments
ARG AMBED_DIR=/ambed
ARG A=A
ARG FTDI_VER=1.4.27
ARG FTDI_SRC=/src/ftdi
ARG S6_SRC=/src/S6

# Fetch AMBEd from Builder
COPY --from=builder ${AMBED_DIR} ${AMBED_DIR}

# Fetch S6 Overlays from Builder
COPY --from=builder ${S6_SRC}/ /

# Fetch FTDI Drivers from Builder
COPY --from=builder ${FTDI_SRC}/release/build/libftd2xx.* /usr/local/lib/
COPY --from=builder ${FTDI_SRC}/release/ftd2xx.h /usr/local/include/
COPY --from=builder ${FTDI_SRC}/release/WinTypes.h /usr/local/include/

# Install FTDI Drivers
RUN cd /usr/local/ && \
    chmod 0755 ./lib/libftd2xx.so.${FTDI_VER} && \
    ln -sf ./lib/libftd2xx.so.${FTDI_VER} ./lib/libftd2xx.so && \
    ldconfig

# Fetch S6 Scripts & Healthcheck
COPY scripts/ /

# Clean Up Image
RUN apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/* && \
    rm -rf /var/tmp/* && \
    rm -rf /src

# Expose AMBE Controller Port
EXPOSE 10100/udp

# Expose AMBE Transcoding Ports
EXPOSE 10101-10199/udp

# Set Healthcheck Parameters - Checks Container is Listening on UDP Port 10100
HEALTHCHECK --interval=10s --timeout=2s --retries=10 CMD /healthcheck.sh || exit 1

ENTRYPOINT ["/init"]

##################################### End ######################################
