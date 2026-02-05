FROM node:18

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm install

COPY . .

RUN npm run build && ls -la dist

EXPOSE 5000

CMD ["npm", "run", "start:prod"]