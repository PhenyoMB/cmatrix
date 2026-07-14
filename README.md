<img width="977" height="309" alt="image" src="https://github.com/user-attachments/assets/83cd7709-45f7-4231-bdec-d3ebd47b13fc" /># Dockerized cmatrix — Multi-Stage, Multi-Arch Container Build

A hands-on lab containerizing [cmatrix](https://github.com/abishekvashok/cmatrix), a terminal-based "Matrix digital rain" animation, using a multi-stage Dockerfile, a non-root runtime user, and a multi-architecture image pushed to Docker Hub.

---

## Objective

This lab teaches how to take a C program with build-time dependencies (compilers, dev headers, autotools) and package it into a small, secure, production-style container image — without shipping the build toolchain in the final image. It also covers building and publishing that image for multiple CPU architectures (`amd64` and `arm64`) using `docker buildx`.

---

## Skills Practiced

- Docker (multi-stage builds, image tagging, `buildx`)
- Linux (Alpine package management, compiling from source)
- Bash (command history, flag usage, git clone/build workflow)
- Git (cloning and building an upstream open-source project)
- Container security fundamentals (non-root users, minimal base images)
- Docker Hub (image publishing, multi-arch manifests)

---

## Prerequisites

- Docker Desktop (or Docker Engine) installed and running
- A [Docker Hub](https://hub.docker.com/) account (for pushing images)
- Basic familiarity with the command line
- `docker buildx` available (bundled with recent Docker Desktop versions)

---

## Task Overview

The goal was to build a Docker image that runs `cmatrix` inside a container. This is a good beginner-to-intermediate lab because it forces you to deal with a real-world packaging problem: `cmatrix` needs to be **compiled from source** (it depends on `ncurses` and autotools), but you don't want your final, shippable image to contain an entire build toolchain — that would make the image large and expose unnecessary attack surface.

The solution is a **multi-stage build**: one stage compiles the binary, and a second, clean stage copies *only the compiled binary* into a minimal image. The image is then further hardened by running the program as a non-root user, and finally built for multiple CPU architectures so it works on both typical amd64 machines and ARM-based systems (e.g., Apple Silicon, AWS Graviton).

---

## Step-by-Step Walkthrough

### Step 1 — Set up the project folder

```powershell
mkdir cmatrix
cd .\cmatrix\
```

**What/why:** Every Docker image should live in its own directory containing the `Dockerfile` and any related build context. Keeping it isolated avoids accidentally sending unrelated files into the Docker build context.

---

### Step 2 — Write the multi-stage Dockerfile

```dockerfile
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
```

**Breaking it down, stage by stage:**

**Stage 1 — `cmatrixbuilder` (the "build" stage)**
- `FROM alpine AS cmatrixbuilder` — starts from the tiny Alpine Linux base image and names this stage so it can be referenced later. Naming a stage is what makes multi-stage builds possible.
- `WORKDIR /cmatrix` — sets the working directory inside the image; all following commands run from here.
- `apk --no-cache update` — refreshes Alpine's package index without caching it to disk, keeping the intermediate layer smaller.
- `apk add git autoconf automake alpine-sdk ncurses-dev ncurses-static` — installs everything needed to *compile* cmatrix: `git` to fetch the source, `autoconf`/`automake` to generate the build scripts, `alpine-sdk` for `gcc`/`make`/core build tools, and the `ncurses` dev + static libraries because cmatrix relies on `ncurses` for terminal rendering.
- `git clone https://github.com/spurin/cmatrix .` — clones the source directly into the current working directory (the trailing `.` is important — it puts the repo contents into `/cmatrix` rather than creating a nested folder).
- `autoreconf -i` — regenerates the `configure` script from the project's `configure.ac`/`Makefile.am` files (common for projects that don't ship a pre-built `configure`).
- `mkdir -p /usr/share/consolefonts /usr/lib/kbd/consolefonts` — pre-creates directories cmatrix expects at runtime for console font handling, avoiding errors later.
- `./configure LDFLAGS="-static"` — configures the build and statically links dependencies, so the resulting binary doesn't rely on shared libraries being present at runtime. This is *why* the final stage can be so minimal.
- `make` — compiles the actual `cmatrix` binary.

**Stage 2 — final runtime image**
- `FROM alpine` — starts a **fresh**, clean Alpine image. None of stage 1's build tools exist here — this is the core of what makes multi-stage builds valuable.
- `LABEL` — adds OCI-standard metadata (author, description) to the image, which is good practice for any image you publish publicly.
- `apk add ncurses-terminfo-base` — installs only the small runtime piece of `ncurses` needed to correctly render terminal output — not the full dev package.
- `adduser -g "John Doe" -s /usr/sbin/nologin -D -h t john` — creates a non-root user (`john`) with no login shell (`nologin`) and no password (`-D`). Running containers as root is a common security anti-pattern; this avoids it.
- `COPY --from=cmatrixbuilder /cmatrix/cmatrix /cmatrix` — this is the key multi-stage instruction: it copies **only the compiled binary** from the first stage into this clean image, leaving all build tools and source code behind.
- `USER john` — switches the container's runtime user from root to `john` for every subsequent instruction and at container runtime.
- `ENTRYPOINT ["./cmatrix"]` + `CMD ["-b"]` — `ENTRYPOINT` fixes the container's main executable so it always runs `cmatrix`; `CMD` supplies a *default* argument (`-b`, bold mode) that can be overridden at `docker run` time without overriding the entrypoint itself.

**Common mistakes seen in this exact lab's history:**
- Editing the file as `Dockerfile.txt` in Notepad (Docker requires the exact filename `Dockerfile`, no extension).
- Typos like `docker imaage ls`, `docker imgages`, `docekr image run` — Docker's CLI doesn't autocorrect subcommands.
- Confusing `docker image run` (not a valid command) with the correct `docker container run` / `docker run`.

---

### Step 3 — Build the image

```powershell
docker build . -t weebpotato/cmatrix
```

**What/why:** `docker build .` tells Docker to build using the current directory as build context (this is where it looks for the `Dockerfile` and any files referenced by `COPY`). `-t weebpotato/cmatrix` tags the resulting image with a name in `<dockerhub-username>/<repo>` format, which is required if you intend to push it to Docker Hub later.

**Expected output:** A series of build steps (`[1/2]`, `[2/2]`, etc.) for each stage, ending in `Successfully tagged weebpotato/cmatrix:latest` (or an equivalent "writing image" confirmation on newer Docker versions using BuildKit).

**Common mistake:** Running `docker build -t weebpotato/cmatrix` **without** the trailing `.` — the build context path is mandatory; Docker doesn't know where to look for the Dockerfile without it.

---

### Step 4 — Run the container

```powershell
docker container run -it --rm weebpotato/cmatrix
```

**What/why:**
- `docker container run` — the explicit, modern form of `docker run` (both work identically; `docker run` is a shorthand). Using the explicit `container` form is considered clearer/more self-documenting in scripts and documentation.
- `-it` — combines `-i` (interactive, keeps STDIN open) and `-t` (allocates a pseudo-TTY). Both are required for `cmatrix`'s animated terminal output to render correctly — without a TTY, the ncurses-based output would fail or render incorrectly.
- `--rm` — automatically removes the container once it exits, preventing a pile-up of stopped containers from repeated test runs (this directly explains the earlier `docker ps -a` / `docker stop` cleanup steps in the history).
- No arguments after the image name — since `CMD ["-b"]` supplies a default, the container runs `cmatrix -b` (bold mode) unless overridden, e.g.:

```powershell
docker container run -it --rm weebpotato/cmatrix -a -u 1 -c green
```

Any flags placed after the image name **override** the Dockerfile's `CMD`, but not the `ENTRYPOINT` — this is exactly the mechanic being explored in the history's trial-and-error with `-ab`, `-u 1`, `-c Red`, etc.

**Expected output:** An animated, colored "digital rain" effect filling the terminal. Press `Ctrl+C` to exit.

**Common mistake:** Running without `-it`, which either errors out or produces no visible animation since there's no interactive terminal for `ncurses` to draw into.

---

### Step 5 — Multi-architecture build and push

```powershell
docker buildx create --name buildx-multi-arch
docker buildx use buildx-multi-arch
docker buildx build --platform linux/amd64,linux/arm64/v8 . -t weebpotato/cmatrix --push
```

**What/why:**
- `docker buildx create --name buildx-multi-arch` — creates a new **builder instance** capable of building for architectures other than your host machine's, using QEMU emulation under the hood.
- `docker buildx use buildx-multi-arch` — switches the active builder to the one just created.
- `docker buildx build --platform linux/amd64,linux/arm64/v8 . -t weebpotato/cmatrix --push` — builds the image for **both** Intel/AMD (`amd64`) and ARM (`arm64/v8`) architectures in a single command, then pushes a combined multi-arch **manifest** to Docker Hub. This means the same tag (`weebpotato/cmatrix`) works correctly whether someone pulls it on a typical laptop, a cloud VM, or an Apple Silicon Mac / Raspberry Pi.

**Common mistake (seen directly in this history):** A typo — `linux/arm74/v8` instead of `linux/arm64/v8`. Buildx will reject or fail on an invalid platform string, so this had to be corrected before the build/push succeeded.

**Note:** A regular `docker build` (Step 3) only builds for your local machine's architecture and doesn't produce a multi-arch manifest — `buildx` with `--platform` is the production-recommended approach when you want an image to be portable across architectures.

---

## Verification

- `docker images` / `docker image ls` shows `weebpotato/cmatrix` listed locally after a successful build.
- Running `docker container run -it --rm weebpotato/cmatrix` displays the animated cmatrix effect in the terminal — this is the clearest sign the binary built and executed correctly.
- After the `buildx --push`, visiting the repository on Docker Hub (`https://hub.docker.com/r/weebpotato/cmatrix`) shows the image with **both** `linux/amd64` and `linux/arm64` listed under supported architectures/manifests.

---

## Key Concepts Learned

**Multi-stage builds**
Rather than one Dockerfile stage doing everything, you split the build environment from the runtime environment. Engineers use this constantly in production because it shrinks final image size dramatically and removes compilers/dev tools that would otherwise increase the attack surface of a running container.

**Non-root container users**
By default, containers run as root unless told otherwise. If an attacker compromises a process running as root inside a container, they have a much easier path to escalate or affect the host. Creating and switching to an unprivileged user (`adduser` + `USER john`) is a baseline security practice expected in most real-world container images.

**ENTRYPOINT vs CMD**
`ENTRYPOINT` defines the fixed command a container always runs; `CMD` defines default *arguments* to that command, which callers can override at runtime. This pattern lets you ship a single image that behaves like a CLI tool with sensible defaults but full flexibility — used heavily in real CLI-style container images (e.g., `kubectl`, `terraform` images).

**Multi-architecture images (buildx)**
Modern infrastructure isn't just x86 anymore — ARM is common in cloud (AWS Graviton) and edge/dev environments (Apple Silicon, Raspberry Pi). Publishing a multi-arch manifest means one tag works everywhere, which is standard practice for any image intended for public or team-wide use.

**Static linking (`LDFLAGS="-static"`)**
Statically linking the binary at build time means the final runtime image doesn't need matching shared libraries installed, which is part of why the final stage can be nearly bare Alpine plus one small package.

---

## Troubleshooting

This lab's command history is a realistic record of common Docker learning-curve issues:

- **Command typos** (`docekr`, `imgages`, `imaage`) — Docker's CLI has no autocorrect; these simply return "command not found" or "unknown command" errors. Careful, consistent typing (or shell aliases/tab-completion) helps.
- **Invalid subcommand combinations** — `docker image run` is not valid; the correct forms are `docker run` or the more explicit `docker container run`. `image` subcommands manage image objects (`ls`, `build`, `rm`); `container`/no-prefix subcommands manage running containers.
- **Editing files as `Dockerfile.txt`** — Windows text editors like Notepad often append `.txt` automatically. Docker requires the literal filename `Dockerfile` (no extension) unless you explicitly pass `-f <filename>` to `docker build`.
- **Repeated identical `docker build` commands** — often a sign of debugging a Dockerfile line-by-line; each rebuild after an edit is expected and normal during iterative development.
- **Invalid `--platform` string** (`linux/arm74/v8`) — buildx validates platform strings against known GOOS/GOARCH pairs; a typo here causes the multi-arch build to fail until corrected to `linux/arm64/v8`.
- **Stale/duplicate containers** — earlier runs without `--rm` left containers behind, requiring manual `docker ps -a` + `docker stop <id>` cleanup. Using `--rm` for short-lived/test containers avoids this entirely.

---

## Takeaways

- Multi-stage builds are the standard way to keep production images small and secure without sacrificing build tooling during development.
- Running as a non-root user is a simple, high-value security practice that costs almost nothing to implement.
- `ENTRYPOINT`/`CMD` together give a container both a fixed identity and runtime flexibility.
- `buildx` with `--platform` is the production-recommended way to publish images that work across CPU architectures, not just your local machine's.
- Debugging Docker CLI typos and subcommand confusion is a normal, expected part of learning — and documenting that journey honestly is itself useful evidence of a real troubleshooting process.

---

## Repository Structure

```
.
├── README.md
├── Dockerfile

```

---
## Reflection

> Through this lab I learned how to structure a Dockerfile using multi-stage builds to separate compiling a C program from running it, which taught me why production images should never ship build toolchains they don't need at runtime. I also got hands-on with container security basics by creating and switching to a non-root user, and I built real confidence working through Docker CLI mistakes — mixing up `image` and `container` subcommands, fixing typos, and cleaning up stale containers with `docker ps -a`. Finally, using `docker buildx` to build and push a true multi-architecture image gave me a concrete understanding of why architecture portability matters in real cloud and edge environments, not just as a checkbox but as something I had to debug (a single typo in a platform string) to get working.
