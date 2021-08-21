FROM rclone/rclone:1.56.0

LABEL "repository"="https://github.com/ttionya/vaultwarden-backup" \
  "homepage"="https://github.com/ttionya/vaultwarden-backup" \
  "maintainer"="ttionya <git@ttionya.com>"

COPY scripts/*.sh /app/

RUN chmod +x /app/*.sh \
  && apk add --no-cache bash sqlite p7zip tzdata curl

ENTRYPOINT ["/app/entrypoint.sh"]
