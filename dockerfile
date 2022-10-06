FROM ubuntu:20.04
LABEL maintainer="jklin" \
      version="0.6.0" \
      description="HDU computer system integrated design platform"

SHELL ["/bin/bash", "-c"]

# 换 apt源
RUN rm /etc/apt/sources.list
COPY sources.list /etc/apt/sources.list

# 新建用户
RUN useradd -d /home/hdu -s /bin/bash -m hdu

# 安装相关依赖和软件
RUN set -x \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget autoconf automake autotools-dev libmpc-dev libmpfr-dev libgmp-dev \
              gawk build-essential bison flex texinfo gperf libtool patchutils bc xz-utils \
              zlib1g-dev libexpat-dev pkg-config libglib2.0-dev libpixman-1-dev git tmux python3 \
              vim gdb-multiarch qemu-system-misc gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu pip sudo g++ make
# 安装 rust
USER hdu
RUN set -x; \
    RUSTUP='/home/hdu/rustup.sh' \
    && cd $HOME \
    && curl https://sh.rustup.rs -sSf > $RUSTUP && chmod +x $RUSTUP \
    && $RUSTUP -y --default-toolchain nightly --profile minimal \
    && rm /home/hdu/rustup.sh 

# 安装 qemu
USER root
COPY qemu/qemu-5.0.0.tar.xz /root
WORKDIR /root
RUN tar xvJf qemu-5.0.0.tar.xz \
    && cd qemu-5.0.0 \
    && ./configure --target-list=riscv64-softmmu,riscv64-linux-user \
    && make -j$(nproc) install \
    && cd $HOME && rm -rf qemu-5.0.0 qemu-5.0.0.tar.xz

# rust换源
USER hdu
WORKDIR /home/hdu
RUN set -x; \
    CARGO_CONF='/home/hdu/.cargo/config'; \
    BASHRC='/home/hdu/.bashrc' \
    && echo 'export RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static' >> $BASHRC \
    && echo 'export RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup' >> $BASHRC \
    && echo 'export PATH=$PATH:$HOME/.cargo/bin' >> $BASHRC \
    && touch $CARGO_CONF \
    && echo '[source.crates-io]' > $CARGO_CONF \
    && echo "replace-with = 'ustc'" >> $CARGO_CONF \
    && echo '[source.ustc]' >> $CARGO_CONF \
    && echo 'registry = "git://mirrors.ustc.edu.cn/crates.io-index"' >> $CARGO_CONF 

# 安装 rust包 
RUN /home/hdu/.cargo/bin/rustup target add riscv64gc-unknown-none-elf \
    && /home/hdu/.cargo/bin/cargo install cargo-binutils --vers =0.3.3 \
    && /home/hdu/.cargo/bin/rustup component add llvm-tools-preview \
    && /home/hdu/.cargo/bin/rustup component add rust-src 

# 安装 code-server
COPY --chown=hdu code-server/code-server-4.2.0-linux-amd64.tar.gz /home/hdu/.local/
COPY --chown=hdu code-server/config.yaml /home/hdu/.config/code-server/config.yaml
RUN cd /home/hdu/.local/ \
    && tar -xvf code-server-4.2.0-linux-amd64.tar.gz \
    && rm code-server-4.2.0-linux-amd64.tar.gz
USER root
RUN  ln -s /home/hdu/.local/code-server-4.2.0-linux-amd64/code-server /usr/bin/code-server 
RUN  ln -s /home/hdu/.local/code-server-4.2.0-linux-amd64/code-server /usr/bin/code

# 安装 rust语言支持
COPY --chown=hdu rust-analyzer/ /home/hdu
USER hdu
WORKDIR /home/hdu
RUN tar -xvf node-v14.17.1-linux-x64.tar.gz 
USER root
RUN ln -s /home/hdu/node-v14.17.1-linux-x64/bin/node /usr/bin/node \
    && ln -s /home/hdu/node-v14.17.1-linux-x64/bin/npm /usr/bin/npm
USER hdu
RUN tar -xvf rust-analyzer-2022-01-24.tar.gz \
    && cd rust-analyzer-2022-01-24 \
    && /home/hdu/.cargo/bin/cargo xtask install \
    && rm /home/hdu/rust-analyzer-2022-01-24.tar.gz \
    && rm -rf /home/hdu/rust-analyzer-2022-01-24/ \
    && rm /home/hdu/node-v14.17.1-linux-x64.tar.gz \
    && rm -rf /home/hdu/node-v14.17.1-linux-x64/

# 安装 gdb-dashboard
RUN wget -P ~ https://gitee.com/scolin19/gdb-dashboard/raw/master/.gdbinit | pip install pygments -i https://pypi.mirrors.ustc.edu.cn/simple/

# 安装 vscode 插件
COPY --chown=hdu vscode_extensions/ /home/hdu/.local/vscode_extensions
RUN code-server --install-extension  /home/hdu/.local/vscode_extensions/cpptools-linux.vsix \
    && code-server --install-extension  /home/hdu/.local/vscode_extensions/vscode-language-pack-zh-hans-v1.64.2.vsix \ 
    && code-server --install-extension  /home/hdu/.local/vscode_extensions/tomoki1207.pdf-1.1.0.vsix \
    && rm -rf  /home/hdu/.local/vscode_extensions

USER hdu
WORKDIR /home/hdu

# 修改 bash
RUN echo 'PROMPT_COMMAND="history -a"' >> /home/hdu/.bashrc \
    && sed -i 's/^HISTSIZE=1000/HISTSIZE=5000/' ~/.bashrc \
    && sed -i 's/^HISTFILESIZE=2000/HISTSIZE=10000/' ~/.bashrc
    
# 导入实验内容
RUN mkdir experiments
WORKDIR /home/hdu/experiments

# 1、c语言测试程序
COPY --chown=hdu hellohdu.c /home/hdu/experiments/c_test/

# 2、编译器
RUN mkdir tm && cd tm && git clone https://gitee.com/Pentium-Wu/tmc.git

# 3、os
RUN git clone -b 2022spring https://gitee.com/scolin19/rCore.git

EXPOSE 8080
COPY --chown=hdu init.sh /home/hdu/.local/init.sh

CMD [ "code-server"]