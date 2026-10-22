FROM nginx:1.28-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY game/ /usr/share/nginx/html/game/
RUN test -s /usr/share/nginx/html/game/index.html && test -s /usr/share/nginx/html/game/index.wasm
EXPOSE 80
