FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release

FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY docker-entrypoint.d/40-maps-api-key.sh /docker-entrypoint.d/40-maps-api-key.sh
RUN chmod +x /docker-entrypoint.d/40-maps-api-key.sh
COPY --from=build /app/build/web /usr/share/nginx/html
RUN cp /usr/share/nginx/html/maps-config.example.js /usr/share/nginx/html/maps-config.js

EXPOSE 8080
