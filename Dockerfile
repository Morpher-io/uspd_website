FROM node:alpine
WORKDIR /app
RUN npm install -g serve
COPY package*.json ./
RUN npm install
COPY . .
RUN npm ci
ENTRYPOINT [""]
RUN rm node_modules/abstractionkit
RUN cp -R ./abstractionkit ./node_modules/
RUN npm run build
CMD npm run start
