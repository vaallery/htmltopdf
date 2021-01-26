# Layer 0. Качаем образ Debian OS с установленным ruby и менеджером для управления gem'ами bundle из DockerHub. Используем его в качестве родительского образа.
FROM ruby:2.7.2-slim

# Layer 1. Задаем пользователя, от чьего имени будут выполняться последующие команды RUN, ENTRYPOINT, CMD и т.д.
USER root

# Layer 2. Обновляем и устанавливаем нужное для Web сервера ПО
RUN apt-get update && apt-get install -y curl
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash -
RUN apt-get update && apt-get install -y nodejs

RUN apt-get update && \
    apt-get -y install xvfb gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 \
      libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 \
      libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 \
      libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 \
      libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget && \
    rm -rf /var/lib/apt/lists/*

# Add user so we don't need --no-sandbox.
RUN groupadd -r pptruser && useradd -r -g pptruser -G audio,video pptruser \
    && mkdir -p /home/pptruser/Downloads \
    && chown -R pptruser:pptruser /home/pptruser

# Install Puppeteer under /node_modules so it's available system-wide
ADD package.json package-lock.json /
RUN npm install

RUN apt-get update -qq && apt-get install -y \
 build-essential libpq-dev

# Setting env up
ARG SECRET_KEY_BASE

# Layer 3. Создаем переменные окружения которые буду дальше использовать в Dockerfile
ENV APP_USER pptruser
ENV APP_USER_HOME /home/$APP_USER
ENV APP_HOME /home/www/app
ENV RAILS_ENV='production'
ENV RACK_ENV='production'
ENV PORT=3000

# Layer 4. Поскольку по умолчанию Docker запускаем контейнер от имени root пользователя, то настоятельно рекомендуется создать отдельного пользователя c определенными UID и GID и запустить процесс от имени этого пользователя.
#RUN useradd -m -d $APP_USER_HOME $APP_USER


# Layer 5. Даем root пользователем пользователю app права owner'а на необходимые директории
RUN mkdir /var/www && \
 chown -R $APP_USER:$APP_USER /var/www && \
 chown -R $APP_USER $APP_USER_HOME

# Layer 6. Создаем и указываем директорию в которую будет помещено приложение. Так же теперь команды RUN, ENTRYPOINT, CMD будут запускаться с этой директории.
WORKDIR $APP_HOME

# Layer 7. Указываем все команды, которые будут выполняться от имени app пользователя
USER $APP_USER



# Layer 8. Добавляем файлы Gemfile и Gemfile.lock из директории, где лежит Dockerfile (root директория приложения на HostOS) в root директорию WORKDIR
COPY Gemfile* ./

# Layer 9. Вызываем команду по установке gem-зависимостей. Рекомендуется запускать эту команду от имени пользователя от которого будет запускаться само приложение
RUN bundle config set without 'development test'
RUN bundle install --jobs 20 --retry 5

# Layer 10. Копируем все содержимое директории приложения в root-директорию WORKDIR
COPY . .

# Layer 11. Указываем все команды, которые будут выполняться от имени root пользователя
USER root

# Layer 12. Даем root пользователем пользователю app права owner'а на WORKDIR
RUN chown -R $APP_USER:$APP_USER "$APP_HOME/."

# Layer 13. Указываем все команды, которые будут выполняться от имени app пользователя
USER $APP_USER

# Layer 14. Запускаем команду для компиляции статических (JS и CSS) файлов
# RUN bin/rails assets:precompile

RUN mkdir -p mkdir $APP_HOME/tmp/pids

RUN build/update-linux-sandbox.sh

# Layer 15. Указываем команду по умолчанию для запуска будущего контейнера. По скольку в `Layer 13` мы переопределили пользователя, то puma сервер будет запущен от имени www-data пользователя.
CMD bundle exec test.rb
