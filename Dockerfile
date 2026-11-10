# The same Node environment as the current Forgejo worker. All upstream
# image references are pinned to digests; update the versions together.
FROM python:3.13.7-slim-bookworm@sha256:adafcc17694d715c905b4c7bebd96907a1fd5cf183395f0ebc4d3428bd22d92d AS python
FROM golang:1.24.11-bookworm@sha256:656be510c8b4d33acf4eac8575b7f04a3e30b705c152dc6bde112dbe1a87b602 AS go
FROM prom/prometheus:v3.2.1@sha256:6927e0919a144aa7616fd0137d4816816d42f6b816de3af269ab065250859a62 AS prometheus
FROM data.forgejo.org/oci/node:24-bookworm@sha256:8fa96264f302f58bbb13aa7339c541547b56975766ce956c875da149452a3e40

LABEL org.opencontainers.image.source="https://github.com/larstobi/runner-images" \
      org.opencontainers.image.description="Unprivileged Forgejo worker tools for k8s-relatime"

# Bookworm's systemd 252 lacks the offline repart mode exercised by the
# storage test. The backports package supplies systemd 254 and that mode.
RUN printf '%s\n' 'deb http://deb.debian.org/debian bookworm-backports main' > /etc/apt/sources.list.d/bookworm-backports.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       bash btrfs-progs ca-certificates curl fdisk git make perl rsync systemd util-linux \
    && apt-get install -y --no-install-recommends -t bookworm-backports systemd

COPY --from=python /usr/local/ /usr/local/
COPY --from=go /usr/local/go/ /usr/local/go/
COPY --from=prometheus /bin/promtool /usr/local/bin/promtool

ENV PATH="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

COPY requirements.txt /tmp/runner-requirements.txt
RUN python -m pip install --no-cache-dir -r /tmp/runner-requirements.txt \
    && python -m pip check

# The workflows use linux/amd64 binaries. Verify each download against a
# committed checksum before it enters the image.
RUN test -d /tmp && test ! -L /tmp && test "$(readlink -f /tmp)" = /tmp \
    && test ! -e /tmp/runner-downloads && test ! -L /tmp/runner-downloads \
    && mkdir /tmp/runner-downloads \
    && curl -fsSL https://dl.k8s.io/release/v1.34.1/bin/linux/amd64/kubectl -o /tmp/runner-downloads/kubectl \
    && printf '%s  %s\n' 7721f265e18709862655affba5343e85e1980639395d5754473dafaadcaa69e3 /tmp/runner-downloads/kubectl | sha256sum --check \
    && install -m 0755 /tmp/runner-downloads/kubectl /usr/local/bin/kubectl \
    && curl -fsSL https://github.com/siderolabs/talos/releases/download/v1.14.2/talosctl-linux-amd64 -o /tmp/runner-downloads/talosctl \
    && printf '%s  %s\n' c6c9552b0e5f767352c595fa1c0af4f186f697488646872955057d23990a66c4 /tmp/runner-downloads/talosctl | sha256sum --check \
    && install -m 0755 /tmp/runner-downloads/talosctl /usr/local/bin/talosctl \
    && curl -fsSL https://get.helm.sh/helm-v3.18.6-linux-amd64.tar.gz -o /tmp/runner-downloads/helm.tar.gz \
    && printf '%s  %s\n' 3f43c0aa57243852dd542493a0f54f1396c0bc8ec7296bbb2c01e802010819ce /tmp/runner-downloads/helm.tar.gz | sha256sum --check \
    && tar -xzf /tmp/runner-downloads/helm.tar.gz -C /tmp/runner-downloads linux-amd64/helm \
    && install -m 0755 /tmp/runner-downloads/linux-amd64/helm /usr/local/bin/helm \
    && test ! -L /tmp/runner-downloads/linux-amd64 \
    && test -f /tmp/runner-downloads/linux-amd64/helm && test ! -L /tmp/runner-downloads/linux-amd64/helm \
    && test -f /tmp/runner-downloads/kubectl && test ! -L /tmp/runner-downloads/kubectl \
    && test -f /tmp/runner-downloads/talosctl && test ! -L /tmp/runner-downloads/talosctl \
    && test -f /tmp/runner-downloads/helm.tar.gz && test ! -L /tmp/runner-downloads/helm.tar.gz \
    && rm -- /tmp/runner-downloads/kubectl /tmp/runner-downloads/talosctl /tmp/runner-downloads/helm.tar.gz /tmp/runner-downloads/linux-amd64/helm \
    && rmdir /tmp/runner-downloads/linux-amd64 /tmp/runner-downloads \
    && install -d -o 1000 -g 1000 /work

USER 1000:1000
WORKDIR /work
CMD ["bash"]
