FROM nats:2.15.3-alpine
COPY nats.conf /etc/nats/nats.conf
CMD ["-c", "/etc/nats/nats.conf"]
