# ./hooks/build dev
# ./hooks/build dfw
# ./hooks/build nux
# ./hooks/build nux --no-cache

ARG BASETAG=latest

FROM accetto/ubuntu-vnc-xfce:${BASETAG} as stage-install

### Be sure to use root user
USER 0

### 'apt-get clean' runs automatically
RUN apt-get update -y
RUN apt-get upgrade -y
RUN apt-get install -y firefox
RUN apt-get install -y ttf-wqy-microhei ttf-wqy-microhei ttf-wqy-zenhei kde-l10n-zhcn xfonts-wqy
RUN rm -rf /var/lib/apt/lists/*

### Alternatively install an explicit Firefox version
### http://releases.mozilla.org/pub/firefox/releases/67.0.4/linux-x86_64/en-US/firefox-67.0.4.tar.bz2
# ENV \
#     FIREFOX_VERSION=67.0.4 \
#     FIREFOX_DISTRO=linux-x86_64 \
#     FIREFOX_PATH=/usr/lib/firefox
# RUN mkdir -p ${FIREFOX_PATH} \
#     && wget -qO- http://releases.mozilla.org/pub/firefox/releases/${FIREFOX_VERSION}/${FIREFOX_DISTRO}/en-US/firefox-${FIREFOX_VERSION}.tar.bz2 \
#         | tar xvj -C /usr/lib/ \
#     && ln -s ${FIREFOX_PATH}/firefox /usr/bin/firefox

FROM stage-install as stage-config

### Arguments can be provided during build
ARG ARG_VNC_USER

ENV VNC_USER=${ARG_VNC_USER:-headless:headless}

ENV TZ=Asia/Shanghai
ENV LANG=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh:en_US:en
ENV LC_ALL=zh_CN.UTF-8

WORKDIR ${HOME}
SHELL ["/bin/bash", "-c"]

### Create the default profile folder and put the file with default preferences there.
### The preferences will be forced for each session, but only in the profile containing the file.
### The VNC user ('headles:headless' by default) will get permissions to modify or delete the file.
### There will be also a backup copy of the proto-profile.
RUN mkdir \
    ./.mozilla \
    ./.mozilla/firefox \
    ./.mozilla/firefox/profile0.default \
    ./firefox.plus

COPY [ "./src/firefox/profiles.ini", "./.mozilla/firefox/" ]
COPY [ "./src/firefox.plus/user.js", "./.mozilla/firefox/profile0.default/" ]
COPY [ "./src/create_user_and_fix_permissions.sh", "./src/patch_vnc_startup.*", "./" ]
COPY [ "./src/firefox.plus/*.js", "./src/firefox.plus/*.sh", "./firefox.plus/"]
COPY [ "./src/firefox.plus/*.svg", "/usr/share/icons/hicolor/scalable/apps/"]

### 'sync' mitigates automated build failures
RUN \
    chmod +x \
        ./create_user_and_fix_permissions.sh \
        ./patch_vnc_startup.sh \
        ./firefox.plus/*.sh \
    && sync \
    && ./patch_vnc_startup.sh \
    && ./create_user_and_fix_permissions.sh $STARTUPDIR $HOME \
    && rm \
        ./*.sh \
        ./patch_vnc_startup.txt \
    && gtk-update-icon-cache -f /usr/share/icons/hicolor

FROM stage-config as stage-final

### Arguments can be provided during build
ARG ARG_MOZ_FORCE_DISABLE_E10S
ARG ARG_REFRESHED_AT
ARG ARG_VCS_REF
ARG ARG_VERSION_STICKER
ARG ARG_VNC_BLACKLIST_THRESHOLD
ARG ARG_VNC_BLACKLIST_TIMEOUT
ARG ARG_VNC_RESOLUTION

LABEL \
    any.accetto.description="Headless Ubuntu VNC/noVNC container with Xfce desktop and customizable Firefox" \
    any.accetto.display-name="Headless Ubuntu/Xfce VNC/noVNC container with customizable Firefox" \
    any.accetto.tags="ubuntu, xfce, vnc, novnc, firefox" \
    version-sticker="${ARG_VERSION_STICKER}" \
    org.label-schema.vcs-ref="${ARG_VCS_REF}" \
    org.label-schema.vcs-url="https://github.com/accetto/ubuntu-vnc-xfce-firefox-plus"

ENV \
  MOZ_FORCE_DISABLE_E10S=${ARG_MOZ_FORCE_DISABLE_E10S:+1} \
  REFRESHED_AT=${ARG_REFRESHED_AT} \
  VERSION_STICKER=${ARG_VERSION_STICKER} \
  VNC_BLACKLIST_THRESHOLD=${ARG_VNC_BLACKLIST_THRESHOLD:-20} \
  VNC_BLACKLIST_TIMEOUT=${ARG_VNC_BLACKLIST_TIMEOUT:-0} \
  VNC_RESOLUTION=${ARG_VNC_RESOLUTION:-1024x768}

### Preconfigure Xfce
COPY [ "./src/home/Desktop", "./Desktop/" ]
COPY [ "./src/home/config/xfce4/panel", "./.config/xfce4/panel/" ]
COPY [ "./src/home/config/xfce4/xfconf/xfce-perchannel-xml", "./.config/xfce4/xfconf/xfce-perchannel-xml/" ]
COPY [ "./src/startup/version_sticker.sh", "${STARTUPDIR}/" ]

### Fix permissions
RUN \
    chmod a+wx "${STARTUPDIR}"/version_sticker.sh \
    && "${STARTUPDIR}"/set_user_permissions.sh "${STARTUPDIR}" "${HOME}"

### Switch to non-root user
USER ${VNC_USER}

### Issue #7 (base): Mitigating problems with foreground mode
WORKDIR ${STARTUPDIR}
