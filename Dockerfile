FROM rclone/rclone:1.57.0

LABEL "repository"="https://github.com/srgsf/vaultwarden-backup" \
  "homepage"="https://github.com/srgsf/vaultwarden-backup" \
  "maintainer"="srgsf <srgsf.github@gmail.com>"

COPY scripts/*.sh /app/

RUN chmod +x /app/*.sh \
  && apk add --no-cache bash sqlite p7zip tzdata curl

ENTRYPOINT ["/app/entrypoint.sh"]
