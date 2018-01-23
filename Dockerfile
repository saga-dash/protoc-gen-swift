FROM alpine:3.7 as protoc_builder
RUN apk add --no-cache build-base curl automake autoconf libtool git zlib-dev

ENV GRPC_VERSION=1.8.4 \
    PROTOBUF_VERSION=3.5.1 \
    OUTDIR=/out
RUN mkdir -p /protobuf && \
    curl -L https://github.com/google/protobuf/archive/v${PROTOBUF_VERSION}.tar.gz | tar xvz --strip-components=1 -C /protobuf
RUN git clone --depth 1 --recursive -b v${GRPC_VERSION} https://github.com/grpc/grpc.git /grpc && \
    rm -rf grpc/third_party/protobuf && \
    ln -s /protobuf /grpc/third_party/protobuf
RUN cd /protobuf && \
    autoreconf -f -i -Wall,no-obsolete && \
    ./configure --prefix=/usr --enable-static=no && \
    make -j2 && make install
RUN cd grpc && \
    make -j2 plugins
RUN cd /protobuf && \
    make install DESTDIR=${OUTDIR}
RUN cd /grpc && \
    make install-plugins prefix=${OUTDIR}/usr
RUN find ${OUTDIR} -name "*.a" -delete -or -name "*.la" -delete


FROM ubuntu:16.04 as swift_builder
RUN apt-get update && \
    apt-get install -y build-essential make tar xz-utils bzip2 gzip sed \
    libz-dev unzip patchelf curl libedit-dev python2.7 python2.7-dev libxml2 \
    git libxml2-dev uuid-dev libssl-dev bash patch
ENV SWIFT_VERSION=4.0.3 \
    LLVM_VERSION=5.0.1
RUN curl -L http://releases.llvm.org/${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-16.04.tar.xz | tar --strip-components 1 -C /usr/local/ -xJv
RUN curl -L https://swift.org/builds/swift-${SWIFT_VERSION}-release/ubuntu1604/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu16.04.tar.gz | tar --strip-components 1 -C / -xz

# Add MariaDB repository
RUN apt-get install -y software-properties-common && \
    apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8 && \
    add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://ftp.yz.yamagata-u.ac.jp/pub/dbms/mariadb/repo/10.1/ubuntu xenial main'

# 
RUN ln -fs /usr/share/zoneinfo/Etc/GMT /etc/localtime

# Install dependency library
RUN apt-get install -y automake libtool autoconf tzdata curl libcurl4-openssl-dev && \
    apt-get clean

ENV SWIFT_PROTOBUF_VERSION=0.3.2
# Build and install the swiftgrpc plugin
RUN git clone -b ${SWIFT_PROTOBUF_VERSION} https://github.com/saga-dash/grpc-swift && \
    cd grpc-swift/Plugin && \
    make && \
    cp protoc-gen-swift /usr/bin && \
    cp protoc-gen-swiftgrpc /usr/bin

RUN mkdir -p /protoc-gen-swift && \
    cp /grpc-swift/Plugin/.build/x86_64-unknown-linux/debug/protoc-gen-swift /protoc-gen-swift/ && \
    cp /grpc-swift/Plugin/.build/x86_64-unknown-linux/debug/protoc-gen-swiftgrpc /protoc-gen-swift/ 
RUN cp /lib64/ld-linux-x86-64.so.2 \
        $(ldd /protoc-gen-swift/protoc-gen-swift | awk '{print $3}' | grep /lib | sort | uniq) \
        /protoc-gen-swift/
RUN find /protoc-gen-swift/ -name 'lib*.so*' -exec patchelf --set-rpath /protoc-gen-swift {} \; && \
    for p in protoc-gen-swift protoc-gen-swiftgrpc; do \
        patchelf --set-interpreter /protoc-gen-swift/ld-linux-x86-64.so.2 /protoc-gen-swift/${p}; \
    done


FROM znly/upx as packer
COPY --from=protoc_builder /out/ /out/
RUN upx --lzma \
        /out/usr/bin/protoc


FROM alpine:3.7
RUN apk add --no-cache libstdc++
COPY --from=packer /out/ /
COPY --from=swift_builder /protoc-gen-swift /protoc-gen-swift
RUN for p in protoc-gen-swift protoc-gen-swiftgrpc; do \
        ln -s /protoc-gen-swift/${p} /usr/bin/${p}; \
    done

RUN apk add --no-cache curl && \
    mkdir -p /protobuf/google/protobuf && \
        for f in any duration descriptor empty struct timestamp wrappers; do \
            curl -L -o /protobuf/google/protobuf/${f}.proto https://raw.githubusercontent.com/google/protobuf/master/src/google/protobuf/${f}.proto; \
        done && \
    mkdir -p /protobuf/google/api && \
        for f in annotations http; do \
            curl -L -o /protobuf/google/api/${f}.proto https://raw.githubusercontent.com/grpc-ecosystem/grpc-gateway/master/third_party/googleapis/google/api/${f}.proto; \
        done && \
    apk del curl

ENTRYPOINT ["/usr/bin/protoc", "-I/protobuf"]
