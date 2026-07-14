# Build Container Image 
FROM alpine AS cmatrixbuilder

WORKDIR /cmatrix 

RUN apk --no-cache update && \
    apk add git autoconf automake alpine-sdk ncurses-dev ncurses-static && \
    git clone https://github.com/spurin/cmatrix . && \
    autoreconf -i && \
    mkdir -p /usr/share/consolefonts /usr/lib/kbd/consolefonts && \
    ./configure LDFLAGS="-static" && \
    make

# Container Image cmatrix
FROM alpine

LABEL org.opencontainers.image.authors="Phenyo Bareki" \
    org.opencontainers.image.description="https://github.com/abishekvashok/cmatrix"

RUN apk --no-cache update && \
    apk add ncurses-terminfo-base && \
    adduser -g "John Doe" -s /usr/sbin/nologin -D -h t john

COPY --from=cmatrixbuilder /cmatrix/cmatrix /cmatrix

USER john

ENTRYPOINT ["./cmatrix"]
CMD ["-b"]