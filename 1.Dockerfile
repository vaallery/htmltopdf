# Layer 0. Качаем образ Debian OS с установленным ruby и менеджером для управления gem'ами bundle из DockerHub. Используем его в качестве родительского образа.
FROM ruby:2.7.2-slim



# Layer 2. Обновляем и устанавливаем нужное для Web сервера ПО
RUN apt-get update && apt-get install -y curl
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash -
RUN apt-get update && apt-get install -y nodejs

RUN  apt-get update \
     && apt-get install -y wget gnupg ca-certificates \
     && wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
     && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
     && apt-get update \
     # We install Chrome to get all the OS level dependencies, but Chrome itself
     # is not actually used as it's packaged in the node puppeteer library.
     # Alternatively, we could could include the entire dep list ourselves
     # (https://github.com/puppeteer/puppeteer/blob/master/docs/troubleshooting.md#chrome-headless-doesnt-launch-on-unix)
     # but that seems too easy to get out of date.
     && apt-get install -y google-chrome-stable \
     && rm -rf /var/lib/apt/lists/* \
     && wget --quiet https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh -O /usr/sbin/wait-for-it.sh \
     && chmod +x /usr/sbin/wait-for-it.sh

# Install Puppeteer under /node_modules so it's available system-wide
ADD package.json package-lock.json /
RUN npm install

# Setting env up
ARG SECRET_KEY_BASE

# Layer 3. Создаем переменные окружения которые буду дальше использовать в Dockerfile
ENV APP_USER app
ENV APP_USER_HOME /home/$APP_USER
ENV APP_HOME /home/www/app
ENV RAILS_ENV='production'
ENV RACK_ENV='production'
ENV PORT=3000

# Layer 4. Поскольку по умолчанию Docker запускаем контейнер от имени root пользователя, то настоятельно рекомендуется создать отдельного пользователя c определенными UID и GID и запустить процесс от имени этого пользователя.
RUN useradd -m -d $APP_USER_HOME $APP_USER

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

# Layer 15. Указываем команду по умолчанию для запуска будущего контейнера. По скольку в `Layer 13` мы переопределили пользователя, то puma сервер будет запущен от имени www-data пользователя.
CMD bundle exec test.rb
