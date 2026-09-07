FROM debian:trixie

RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates curl git unzip xz-utils \
	clang lld llvm g++ make \
	libsdl3-dev \
	neko \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://github.com/HaxeFoundation/haxe/releases/download/4.3.7/haxe-4.3.7-linux64.tar.gz \
	-o /tmp/haxe.tar.gz \
	&& mkdir -p /opt/haxe && tar -xzf /tmp/haxe.tar.gz -C /opt/haxe --strip-components=1 \
	&& ln -s /opt/haxe/haxe /usr/local/bin/haxe \
	&& ln -s /opt/haxe/haxelib /usr/local/bin/haxelib \
	&& rm /tmp/haxe.tar.gz

ENV HAXE_STD_PATH=/opt/haxe/std

RUN mkdir -p /haxelib && haxelib setup /haxelib && haxelib install hxcpp --quiet --always

WORKDIR /work

# Build:  docker build -t mdd-linux tools/docker
# Gate:   docker run --rm -e SDL_VIDEODRIVER=dummy -e SDL_AUDIODRIVER=dummy \
#           -v "$PWD:/work:ro" mdd-linux sh -c \
#           "cp -r /work/src /work/test /work/tools /work/assets /work/vendor \
#            /work/mdd /work/mdd.xml /src/ && chmod +x /src/mdd && cd /src && \
#            ./mdd build && ./mdd build gate && ./mdd gate"
